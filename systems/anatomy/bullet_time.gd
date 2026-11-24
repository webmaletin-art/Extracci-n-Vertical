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

const KILL_SECONDS := 2.6
## Tomas de cerca: comienzo del nombre del grupo → [radio de la ventana de rayos X (m), distancia final de la cámara (m), ángulo final (rad, 0 = de costado)]
const CLOSEUPS := {"mandíbula": [0.16, 0.5, 1.2], "vértebras": [0.14, 0.55, 0.9], "costillas": [0.17, 0.7, 0.8], "cráneo": [0.17, 0.55, 1.3], "cerebro": [0.17, 0.55, 1.3], "ojo": [0.075, 0.38, 0.95], "testículos": [0.11, 0.62, 0.55], "estómago": [0.15, 0.8, 0.45], "oreja": [0.08, 0.4, 0.8],
	"corazón": [0.16, 0.8, 0.4], "hígado": [0.15, 0.8, 0.45]}

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
var focus_label := ""
var debug_u := -1.0               ## (capturas) fija el avance de la repetición 0..1
const REPLAY_SECONDS := 2.6       ## (tiempo real) la bala atravesando el cuerpo
var _replay: Array = []
var _rp_t0 := 0.0
var _rp_anat: AnatomyBody
var _rp_bullet: MeshInstance3D
var _rp_seen := -1
var _rp_spin := 0.0
var _rp_tumble := false
var _rp_flat := false            ## (práctica) comienzo del nombre del grupo que la cámara debe enfocar
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
	if Settings.bullet_time == 0 or phase != "" or idx < 0 or Ballistics.instance == null:
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
	_dist0 = 2.0
	_dist1 = 0.8
	_ang1 = 0.25
	var radius := 0.0
	if _main != "":
		var lab := str(anat.groups[_main].label)
		for k in CLOSEUPS:
			if lab.begins_with(k):
				var c: Array = CLOSEUPS[k]
				radius = c[0]
				_dist1 = c[1]
				_dist0 = c[1] * 2.6
				_ang1 = c[2]
	anat.show_killcam(main, radius)
	if Blood.instance:
		Blood.instance.set_closeup(true)
	# repetición del proyectil por dentro (sólo balas): primero se ve la bala entrar, romper y desviarse
	_replay = (info.get("bullet_path", []) as Array).duplicate()
	var rp := 0.0
	if t == "bullet" and _replay.size() >= 2:
		rp = REPLAY_SECONDS
		_rp_anat = anat
		_rp_seen = -1
		_rp_spin = 0.0
		_rp_tumble = false
		_rp_flat = false
		anat.set_reveal(int(info.get("seq0", 1)) - 1)
	else:
		_replay = []
	TimeFx.slowmo(0.06, KILL_SECONDS + rp + 0.4, "kill", 0.02)
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
			var v := b.velocity_of(_proj).normalized()
			camera.override_target(p - v * 1.1 + Vector3(0, 0.25, 0.9), p + v * 2.0, 34.0)
		if _now() > _until:
			var v2 := _victim
			_end()
			if is_instance_valid(v2) and (v2.is_dead() or (Settings.bullet_time >= 2 and not (v2.last_hit_info.get("anatomy_nodes", []) as Array).is_empty())):
				_killcam(v2, v2.last_hit_info)
		return
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
	camera.override_target(_focus + off, _focus, lerpf(36.0, 30.0, e))
	if _now() > _until:
		_end()

func skip() -> void:
	if phase != "":
		_end()

func _end() -> void:
	closeup_active = false
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
		_replay = []
		if _rp_bullet:
			_rp_bullet.visible = false
		anat.set_reveal(1 << 30)
		return false
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
		if ResourceLoader.exists("res://assets/ammo/projectile.mesh"):
			_rp_bullet.mesh = load("res://assets/ammo/projectile.mesh")
		elif Gibs.instance:
			_rp_bullet.mesh = Gibs.instance.bullet_mesh
		_rp_bullet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# la bala se ve SIEMPRE, también dentro del hueso (como en los rayos X de Sniper Elite): cobre brillante encima de todo
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.85, 0.55, 0.3)
		bm.metallic = 0.9
		bm.roughness = 0.25
		bm.emission_enabled = true
		bm.emission = Color(0.55, 0.32, 0.15)
		bm.no_depth_test = true
		bm.render_priority = 10
		_rp_bullet.material_override = bm
		add_child(_rp_bullet)
	_rp_bullet.visible = true
	var basis := Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.95 else Vector3.RIGHT)
	_rp_spin += 0.35
	basis = basis * Basis(Vector3.BACK, _rp_spin)                       # gira sobre su eje (estrías del cañón)
	if _rp_tumble:
		basis = basis * Basis(Vector3.RIGHT, _rp_spin * 0.55)           # se desvió: da vueltas
	# tamaño real (~4 cm) y centrada: el modelo de la bala trae el origen corrido
	var sc := Vector3.ONE * 0.2
	if _rp_flat:
		sc = Vector3(1.7, 1.7, 0.6) * 0.2                                 # se aplastó contra el hueso duro
	var mc := _rp_bullet.mesh.get_aabb().get_center() if _rp_bullet.mesh else Vector3.ZERO
	_rp_bullet.global_transform = Transform3D(basis.scaled(sc), pos) * Transform3D(Basis.IDENTITY, -mc)
	# cámara pegada a la bala, del lado de la cámara del juego, un poco por delante
	var side := Vector3(0, 0, 1)
	var cam_p := pos + side * 0.34 + Vector3.UP * 0.06 - fwd * 0.10
	camera.override_target(cam_p, pos + fwd * 0.04, 34.0)
	camera.global_position = cam_p                                       # sin retraso: la bala va rápido
	camera._look = pos + fwd * 0.04
	camera.fov = 34.0
	camera.look_at(camera._look, Vector3.UP)
	return true
