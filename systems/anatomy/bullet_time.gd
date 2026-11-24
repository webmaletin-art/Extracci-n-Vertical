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
const CLOSEUPS := {"cráneo": [0.17, 0.55, 1.3], "cerebro": [0.17, 0.55, 1.3], "ojo": [0.075, 0.38, 0.95], "testículos": [0.11, 0.62, 0.55], "estómago": [0.15, 0.8, 0.45], "oreja": [0.08, 0.4, 0.8],
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
var focus_label := ""            ## (práctica) comienzo del nombre del grupo que la cámara debe enfocar
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
	TimeFx.slowmo(0.06, KILL_SECONDS + 0.4, "kill", 0.02)
	_t0 = _now()
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
