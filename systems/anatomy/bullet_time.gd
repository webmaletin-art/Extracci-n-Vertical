class_name BulletTime
extends Node
## Qué se muestra de las heridas:
##  * MUERTES (del enemigo por el jugador, o del jugador): cámara lenta + cámara que se acerca a la herida que mató
##    (tiro en la cabeza, explosión, caída, cuchillo). Se ven SÓLO las partes dañadas (todas las heridas acumuladas:
##    huesos quebrados, músculos, órganos y vasos perforados, esquirlas), el cuerpo como rayos X alrededor.
##    Si el disparo va a matar (se predice la trayectoria), antes la cámara sigue a la bala.
##  * RESTO DE HERIDAS GRAVES (fracturas, órganos, vasos): en pleno juego, un destello rápido de las partes dañadas a
##    través del cuerpo. Sin cámara lenta. Los puñetazos no muestran nada (sólo quitan vida).
## Tocar la pantalla salta la toma.

signal injury_report(victim: Actor, lines: Array)

const KILL_SECONDS := 1.6        ## toma de muerte BREVE (plan maestro §18): informativa y compatible con el ritmo online
## Tomas de cerca: comienzo del nombre del grupo → [radio de la ventana de rayos X (m), distancia final de la cámara (m), ángulo final (rad, 0 = de costado)]
const CLOSEUPS := {}               ## (sin acercamientos extremos: todas las muertes usan el mismo encuadre moderado)

var camera: SideCamera
var player: Actor
static var closeup_active := false     ## durante la toma de rayos X no se dibujan los láseres
var phase := ""              ## "" | "bullet" | "kill"
var _proj := -1
var _victim: Actor
var _until := 0.0
var _t0 := 0.0
var _focus := Vector3.ZERO
var _main := ""                  ## grupo anatómico de la herida que mató (la cámara la sigue mientras cae el cuerpo)
var _main_pos := Vector3.ZERO
var _kind := ""
var focus_label := ""            ## (práctica) comienzo del nombre del grupo que la cámara debe enfocar
var flash_wounds := false
## En la partida: sin cámara que sigue a la bala ni repetición de la bala por dentro (sólo sangre en los impactos y
## rayos X + cámara lenta al morir). El modo práctica las activa para probar.
var follow_bullet := false        ## (desarrollo) cámara que sigue a la bala: apagada (plan maestro §18)
var bullet_replay := false
var debug_u := -1.0               ## (capturas) fija el avance de la repetición 0..1
const HOLD_SECONDS := 1.6         ## después de atravesar el cuerpo, la toma queda quieta y termina
const REPLAY_SECONDS := 4.0       ## (tiempo real) la bala atravesando el cuerpo, muy lenta
var _replay: Array = []
var _rp_t0 := 0.0
var _rp_anat: AnatomyBody
var _rp_bullet: MeshInstance3D
var _rp_seen := -1
var _rp_spin := 0.0
var _rp_tumble := false
var _rp_flat := false
var _drip_node := ""             ## orificio que chorrea sangre al piso durante la toma
var _drip_p := Vector3.ZERO
var _drip_t := 0.0
var _dist0 := 2.0
var _dist1 := 0.8
var _ang1 := 0.25
var _side := 1.0
var _connected := false

func setup(cam: SideCamera, p: Actor) -> void:
	camera = cam
	player = p
	player.shot_fired.connect(_on_shot)
	player.damaged.connect(func(info): _on_damage(player, info))
	for a in get_tree().get_nodes_in_group("enemies"):
		watch(a as Actor)

## Vigila a un personaje que aparece después (maniquíes del modo práctica).
func watch(ac: Actor) -> void:
	ac.damaged.connect(func(info): _on_damage(ac, info))

func _now() -> float:
	return TimeFx.now()

## Disparo del jugador: si la bala va a matar, la cámara la sigue en cámara lenta.
func _on_shot(idx: int, w: Firearm) -> void:
	if not (follow_bullet or Settings.kill_cam == 1) or Settings.bullet_time == 0 or phase != "" or idx < 0 or Ballistics.instance == null:
		return
	var b := Ballistics.instance
	var pred := b.predict(b.position_of(idx), b.velocity_of(idx), float(w.stats.drag), player.hitbox_rids(), 1.2)
	if pred.is_empty():
		return
	var col: Object = pred.collider
	if not (col is Area3D and (col as Area3D).has_meta("actor")):
		return
	var victim := (col as Area3D).get_meta("actor") as Actor
	if victim == null or victim == player or victim.is_dead():
		return
	var zone := str((col as Area3D).get_meta("zone", "torso"))
	var est := float(w.stats.damage) * float(Actor.ZONE_MULT.get(zone, 1.0)) * float(w.stats.pellets) * 0.5 + 12.0
	if Settings.bullet_time < 2 and not (est >= victim.health or zone == "head"):
		return
	if (pred.point as Vector3).distance_to(b.position_of(idx)) < 2.5:
		return
	phase = "bullet"
	_proj = idx
	_victim = victim
	b.tracked = idx
	# la bala visible sale de la boca del arma y entra al cuerpo a la profundidad del hueso que va a pegar
	var tz := (col as Area3D).global_position.z
	b.visual_z = [w.muzzle_world().x, w.muzzle_world().z, (pred.point as Vector3).x, tz]
	TimeFx.slowmo(0.03, 6.0, "bullet_time", 0.05)
	_until = _now() + 4.0
	if not _connected:
		b.projectile_hit.connect(_on_proj_hit)
		_connected = true
	get_tree().call_group("hud", "set_cinematic", true)
	Sfx.play_ui("bullet_whoosh", -4.0)

func _on_proj_hit(idx: int, _info: Dictionary) -> void:
	if phase == "bullet" and idx == _proj:
		_until = _now() + 0.12        # el daño se aplica justo después: se decide en el próximo cuadro

func _on_damage(a: Actor, info: Dictionary) -> void:
	var lines: Array = info.get("injuries", [])
	if not lines.is_empty():
		injury_report.emit(a, lines)
	var involved: bool = a == player or info.get("shooter") == player
	if not involved:
		return
	var t := str(info.get("type", ""))
	if bool(info.get("lethal", false)):
		if Settings.bullet_time > 0 and phase != "bullet":
			_killcam(a, info)
		return
	var nodes: Array = info.get("anatomy_nodes", [])
	if nodes.is_empty() or t == "punch":
		return
	if Settings.bullet_time >= 2 and phase == "":
		_killcam(a, info)             # modo práctica: toma de cerca de cada herida
		return
	# en la partida los rayos X son SÓLO para la muerte: las heridas que no matan no muestran nada (quedan en las
	# estadísticas). flash_wounds = true vuelve a mostrar el destello rápido (no se usa hoy).
	if flash_wounds or Settings.xray_hits == 1:
		AnatomyBody.for_actor(a).show_flash(nodes, 0.9)

func _killcam(a: Actor, info: Dictionary) -> void:
	if phase == "kill":
		return
	phase = "kill"
	closeup_active = true
	_set_vignette(true)
	_victim = a
	if Ballistics.instance:
		Ballistics.instance.tracked = -1
		Ballistics.instance.bullet_model.visible = false
	var t := str(info.get("type", ""))
	_focus = info.get("point", a.global_position + Vector3.UP * 1.2)
	var anat := AnatomyBody.for_actor(a)
	var main := str(info.get("anatomy_main", ""))
	_main = ""
	if main != "" and anat.groups.has(main):
		_main = main
		_main_pos = anat.wounds[main][-1].pos if anat.wounds.has(main) else anat.groups[main].center
		_focus = anat.bind_to_world(main, _main_pos)
	if focus_label != "":
		# modo práctica: la cámara enfoca la zona elegida (si esa estructura quedó herida) y no «la que más daño hizo»
		var best := ""
		var bd := INF
		for n in anat.wounds:
			if str(anat.groups[n].label).begins_with(focus_label):
				var d := anat.bind_to_world(n, anat.wounds[n][-1].pos).distance_to(a.global_position + Vector3.UP * 1.3)
				if best == "" or d < bd:
					best = n
					bd = d
		if best != "":
			main = best
			_main = best
			_main_pos = anat.wounds[best][-1].pos
			_focus = anat.bind_to_world(best, _main_pos)
	_kind = t
	if t == "fall":
		_focus = a.global_position + Vector3.UP * 0.4
	elif t in ["blast", "impact"]:
		_focus = a.global_position + Vector3.UP * 1.1
	var d: Vector3 = info.get("dir", Vector3.RIGHT)
	_side = -signf(d.x) if absf(d.x) > 0.1 else 1.0
	# estructuras chicas y delicadas: ventana más chica y cámara más cerca, de costado hacia el frente, para verlas en detalle
	_dist0 = 4.2
	_dist1 = 2.8
	_ang1 = 0.3
	var radius := 0.3                # ventana de rayos X grande: se lee a la distancia moderada
	if _main != "":
		var lab := str(anat.groups[_main].label)
		for k in CLOSEUPS:
			if lab.begins_with(k):
				var c: Array = CLOSEUPS[k]
				radius = c[0]
				_dist1 = c[1]
				_dist0 = c[1] + 0.8
				_ang1 = c[2]
	if (bullet_replay or Settings.kill_cam == 1) and t == "bullet" and (info.get("bullet_path", []) as Array).size() >= 2:
		anat.set_reveal(int(info.get("seq0", 1)) - 1)
	anat.show_killcam(main, radius)
	if Blood.instance:
		Blood.instance.set_closeup(true)
	# repetición del proyectil por dentro (sólo balas): primero se ve la bala entrar, romper y desviarse
	_replay = (info.get("bullet_path", []) as Array).duplicate()
	var rp := 0.0
	if (bullet_replay or Settings.kill_cam == 1) and t == "bullet" and _replay.size() >= 2:
		rp = REPLAY_SECONDS
		_rp_anat = anat
		_rp_seen = -1
		_rp_spin = 0.0
		_rp_tumble = false
		_rp_flat = false
		anat.set_reveal(int(info.get("seq0", 1)) - 1)
	else:
		_replay = []
	# cámara lenta SUAVE (35 %) y corta; la repetición cinematográfica sólo existe como herramienta de desarrollo
	TimeFx.slowmo(0.35 if rp == 0.0 else 0.06, KILL_SECONDS + rp + 0.2, "kill", 0.05)
	_rp_t0 = _now()
	_t0 = _now() + rp
	_until = _t0 + KILL_SECONDS
	get_tree().call_group("hud", "set_cinematic", true)
	Sfx.play_ui("heartbeat", -2.0)

func _process(_d: float) -> void:
	if phase == "":
		return
	if phase == "bullet":
		var b := Ballistics.instance
		if b and b.is_alive(_proj):
			var p := b.position_of(_proj)
			if b.visual_z.size() == 4:
				p.z = lerpf(float(b.visual_z[1]), float(b.visual_z[3]), clampf(inverse_lerp(float(b.visual_z[0]), float(b.visual_z[2]), p.x), 0.0, 1.0))
			var v := b.velocity_of(_proj).normalized()
			camera.override_target(p - v * 1.1 + Vector3(0, 0.25, 0.9), p + v * 2.0, 34.0)
		if _now() > _until:
			var v2 := _victim
			_end()
			if is_instance_valid(v2) and (v2.is_dead() or (Settings.bullet_time >= 2 and not (v2.last_hit_info.get("anatomy_nodes", []) as Array).is_empty())):
				_killcam(v2, v2.last_hit_info)
		return
	_drip(_d)
	if not _replay.is_empty():
		if _replay_step():
			return
	# toma de muerte: la cámara se acerca a la herida y gira un poco
	if is_instance_valid(_victim):
		var anat := AnatomyBody.for_actor(_victim)
		if _main != "":
			_focus = anat.bind_to_world(_main, _main_pos)
		elif _kind == "fall":
			_focus = _victim.global_position + Vector3.UP * 0.4
		else:
			_focus = _victim.global_position + Vector3.UP * 1.1
	var k := clampf((_now() - _t0) / KILL_SECONDS, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	var dist := lerpf(_dist0, _dist1, e)
	var ang := lerpf(-0.45, _ang1, e) * _side
	var off := Vector3(sin(ang) * _side, 0.12, cos(ang)).normalized() * dist
	camera.override_target(_focus + off, _focus, lerpf(40.0, 36.0, e))
	if _now() > _until:
		_end()

## La sangre chorrea del orificio de entrada hacia el piso (gotas finas que caen y hacen charco).
func _drip(_delta: float) -> void:
	if _drip_node == "" or Blood.instance == null or not is_instance_valid(_victim):
		return
	if _now() < _drip_t:
		return
	_drip_t = _now() + 0.12
	var anat := AnatomyBody.for_actor(_victim)
	if not anat.groups.has(_drip_node):
		return
	var p := anat.bind_to_world(_drip_node, _drip_p)
	Blood.instance.drops(p, Vector3(randf_range(-0.2, 0.2), -1.0, randf_range(-0.1, 0.1)), 0.18, 0.6, 12.0)

func skip() -> void:
	if phase != "":
		_end()

func _end() -> void:
	closeup_active = false
	_drip_node = ""
	_replay = []
	if _rp_bullet:
		_rp_bullet.visible = false
	if _rp_anat and is_instance_valid(_rp_anat):
		_rp_anat.set_reveal(1 << 30)
	_set_vignette(false)
	if Blood.instance:
		Blood.instance.set_closeup(false)
	if is_instance_valid(_victim):
		AnatomyBody.for_actor(_victim).hide_all()
	phase = ""
	_proj = -1
	if Ballistics.instance:
		Ballistics.instance.tracked = -1
		Ballistics.instance.bullet_model.visible = false
	TimeFx.end_slowmo()
	if Ballistics.instance:
		Ballistics.instance.visual_z = []
	if camera:
		camera.release_override()
	get_tree().call_group("hud", "set_cinematic", false)

## Efecto foco: los bordes de la pantalla se oscurecen y la mirada va al centro (la herida).
var _vig: CanvasLayer
func _set_vignette(on: bool) -> void:
	if _vig == null:
		_vig = CanvasLayer.new()
		_vig.layer = 4
		var r := ColorRect.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment() { vec2 d = UV - vec2(0.5); float v = smoothstep(0.28, 0.78, length(d * vec2(1.25, 1.0))); COLOR = vec4(0.0, 0.0, 0.0, v * 0.85); }"
		var m := ShaderMaterial.new()
		m.shader = sh
		r.material = m
		_vig.add_child(r)
		add_child(_vig)
	_vig.visible = on

## Un paso de la repetición: la bala recorre su camino real por dentro del cuerpo (en el espacio de cada estructura, así
## sigue al cuerpo que cae). Cada estructura que alcanza aparece dañada en ese momento (el hueso se abre, salen las
## esquirlas y gotas finas); en hueso duro se aplasta y si se desvía empieza a dar vueltas. Devuelve false al terminar.
func _replay_step() -> bool:
	var anat := _rp_anat
	if anat == null or not is_instance_valid(anat):
		_replay = []
		return false
	var u := clampf((_now() - _rp_t0) / REPLAY_SECONDS, 0.0, 1.0) if debug_u < 0.0 else debug_u
	if u >= 1.0:
		anat.set_reveal(1 << 30)
		if _now() < _rp_t0 + REPLAY_SECONDS + HOLD_SECONDS and debug_u < 0.0:
			return true                  # se queda quieta en el último cuadro de la toma (rayos X)
		_replay = []
		if _rp_bullet:
			_rp_bullet.visible = false
		_end()
		return true
	var pts := PackedVector3Array()
	for e in _replay:
		pts.append(anat.bind_to_world(str(e.node), e.p))
	var lens := [0.0]
	for i in range(1, pts.size()):
		lens.append(float(lens[-1]) + pts[i - 1].distance_to(pts[i]))
	var total := maxf(float(lens[-1]), 0.001)
	# más lenta adentro del cuerpo: la primera y la última parte (afuera) pasan rápido
	var target := total * (u * u * (3.0 - 2.0 * u) * 0.35 + u * 0.65)
	var i := 1
	while i < pts.size() - 1 and float(lens[i]) < target:
		i += 1
	var a := pts[i - 1]
	var b := pts[i]
	var seg := maxf(float(lens[i]) - float(lens[i - 1]), 0.0001)
	var pos := a.lerp(b, clampf((target - float(lens[i - 1])) / seg, 0.0, 1.0))
	var fwd := (b - a).normalized() if a.distance_to(b) > 0.0001 else Vector3.RIGHT
	# estructuras ya alcanzadas: se revelan sus heridas, sangre fina en vasos y órganos, aplastamiento y vuelco
	for k in i:
		if k <= _rp_seen:
			continue
		_rp_seen = k
		var e: Dictionary = _replay[k]
		if Blood.instance:
			if k == 1:
				Blood.instance.spray(pts[k], fwd, false, true)        # orificio de entrada: salpica hacia atrás
				_drip_node = str(e.node)
				_drip_p = e.p
			if e.get("exit", false):
				Blood.instance.spray(pts[k - 1], fwd, true, true)      # orificio de salida: chorro hacia adelante
		if int(e.get("seq", -1)) >= 0:
			anat.set_reveal(maxi(anat.reveal_seq, int(e.seq)))
			if Blood.instance and str(e.get("sys", "")) in ["vaso", "organo"]:
				Blood.instance.drops(pts[k], fwd, 0.6, 1.2, 55.0)
			if str(e.get("sys", "")) == "hueso":
				_rp_flat = true
		if e.get("deflect", false):
			_rp_tumble = true
	if _rp_bullet == null:
		_rp_bullet = MeshInstance3D.new()
		_rp_bullet.top_level = true
		_rp_bullet.set_meta("no_tech", true)
		_rp_bullet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_rp_bullet)
	var want := bullet_mesh(_rp_flat)
	if _rp_bullet.mesh != want:
		_rp_bullet.mesh = want
		# la bala se ve SIEMPRE, también dentro del hueso: materiales del modelo (cobre y plomo) dibujados encima de todo
		for k in want.get_surface_count():
			var src := want.surface_get_material(k)
			var bm: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
			bm.no_depth_test = true
			bm.render_priority = 10
			bm.emission_enabled = true
			bm.emission = bm.albedo_color * 0.45
			bm.metallic = 0.6
			bm.roughness = 0.3
			_rp_bullet.set_surface_override_material(k, bm)
	_rp_bullet.visible = true
	var basis := Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT)
	_rp_spin += 0.35
	basis = basis * Basis(Vector3.BACK, _rp_spin)                       # gira sobre su eje (estrías del cañón)
	if _rp_tumble:
		basis = basis * Basis(Vector3.RIGHT, _rp_spin * 0.55)           # se desvió: da vueltas
	# bala de Blender (tools/ammo/make_bullets.py), a 1,5× su tamaño real para que se lea en pantalla; en hueso duro se
	# cambia por la versión aplastada en hongo
	var sc := Vector3.ONE * 3.0
	var mc := _rp_bullet.mesh.get_aabb().get_center() if _rp_bullet.mesh else Vector3.ZERO
	_rp_bullet.global_transform = Transform3D(basis.scaled(sc), pos) * Transform3D(Basis.IDENTITY, -mc)
	# cámara pegada a la bala, del lado de la cámara del juego, un poco por delante
	var side := Vector3(0, 0, 1)
	# cámara de costado, a distancia (sin zoom): mira el cuerpo y sigue a la bala de forma suave
	var center := _focus if _focus != Vector3.ZERO else pos
	var look := center.lerp(pos, 0.5)
	var cam_p := look + side * 1.7 + Vector3.UP * 0.15 - fwd * 0.25
	camera.override_target(cam_p, look, 38.0)
	return true

static var _bullet_meshes := {}
## Malla de la bala (entera o en hongo) sacada del GLB de Blender.
static func bullet_mesh(flat: bool) -> Mesh:
	var key := "res://assets/ammo/bullet_mushroom.glb" if flat else "res://assets/ammo/bullet_fmj.glb"
	if not _bullet_meshes.has(key):
		var m: Mesh = null
		if ResourceLoader.exists(key):
			var inst: Node = (load(key) as PackedScene).instantiate()
			for c in inst.find_children("*", "MeshInstance3D", true, false):
				m = (c as MeshInstance3D).mesh
				break
			inst.free()
		if m == null and Gibs.instance:
			m = Gibs.instance.bullet_mesh
		_bullet_meshes[key] = m
	return _bullet_meshes[key]
