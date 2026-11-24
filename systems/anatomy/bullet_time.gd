class_name BulletTime
extends Node
## Director de la cámara lenta con rayos X («bullet time»):
##  * DISPARO: cuando el jugador dispara, se predice la trayectoria (Ballistics.predict). Si la bala va a dar en un
##    enemigo y el tiro es decisivo (o la opción dice «siempre»), el tiempo baja a 3 %, la cámara sigue a la bala 3D
##    (munición de Nexus) y en el impacto pasa a primer plano del blanco con rayos X: huesos, órganos y vasos, y lo dañado
##    en rojo (fracturas con polvo de hueso). Al final el tiempo vuelve a 1×.
##  * GOLPES Y CAÍDAS: patadas, puñetazos y cuchilladas fuertes y las caídas con daño muestran un instante de rayos X
##    sobre la zona golpeada (sin seguir proyectil).
## Las lesiones se calculan siempre (XRayAnatomy.injuries_at) y quedan en el HUD; los rayos X se pueden apagar.
## Tocar la pantalla salta la toma (skip()).

signal injury_report(victim: Actor, lines: Array)

var camera: SideCamera
var player: Actor
var phase := ""              ## "" | "bullet" | "impact" | "moment"
var _proj := -1
var _victim: Actor
var _xray: XRayAnatomy
var _until := 0.0
var _cool_until := 0.0
var _connected := false

func setup(cam: SideCamera, p: Actor) -> void:
	camera = cam
	player = p
	player.shot_fired.connect(_on_shot)
	player.damaged.connect(func(info): _on_any_damage(player, info))
	for a in get_tree().get_nodes_in_group("enemies"):
		(a as Actor).damaged.connect(func(info): _on_any_damage(a, info))

func _now() -> float:
	return TimeFx.now()

func _on_shot(idx: int, w: Firearm) -> void:
	if Settings.bullet_time == 0 or phase != "" or idx < 0 or Ballistics.instance == null:
		return
	if _now() < _cool_until:
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
	var dmg := float(w.stats.damage) * float(Actor.ZONE_MULT.get(zone, 1.0)) * float(w.stats.pellets)
	var decisive := dmg >= victim.health or zone == "head"
	if Settings.bullet_time == 1 and not decisive:
		return
	# la toma sólo vale la pena si la bala viaja un poco (no a quemarropa)
	if (pred.point as Vector3).distance_to(b.position_of(idx)) < 2.5:
		return
	_start_bullet(idx, victim)

func _start_bullet(idx: int, victim: Actor) -> void:
	phase = "bullet"
	_proj = idx
	_victim = victim
	Ballistics.instance.tracked = idx
	TimeFx.slowmo(0.03, 6.0, "bullet_time", 0.05)
	_until = _now() + 4.0
	if not _connected:
		Ballistics.instance.projectile_hit.connect(_on_proj_hit)
		_connected = true
	get_tree().call_group("hud", "set_cinematic", true)
	Sfx.play_ui("bullet_whoosh", -4.0)

func _on_proj_hit(idx: int, info: Dictionary) -> void:
	if phase != "bullet" or idx != _proj:
		return
	var v: Actor = null
	if info.has("zone") and is_instance_valid(_victim):
		v = _victim
	if v == null:
		_end()
		return
	_impact(v, info, 1.8)

func _on_any_damage(a: Actor, info: Dictionary) -> void:
	var t := str(info.get("type", ""))
	# reporte de lesiones siempre (HUD); los rayos X de la bala los maneja _on_proj_hit
	var inj: Array = info.get("injuries", [])
	if not inj.is_empty():
		injury_report.emit(a, inj.map(func(i): return i.text))
	if phase != "" or Settings.bullet_time == 0:
		return
	if _now() < _cool_until:
		return
	var strong := false
	match t:
		"kick", "punch":
			strong = float(info.get("final_damage", 0.0)) >= 18.0 or bool(info.get("lethal", false))
		"knife":
			strong = bool(info.get("lethal", false)) or randf() < 0.35
		"fall":
			strong = float(info.get("final_damage", 0.0)) >= 20.0
		"bullet":
			strong = false
	if strong and (a == player or info.get("shooter") == player):
		_moment(a, info, inj)

func _moment(a: Actor, info: Dictionary, inj: Array) -> void:
	phase = "moment"
	_victim = a
	TimeFx.slowmo(0.12, 1.3, "xray", 0.03)
	_until = _now() + 1.1
	_show(a, info, inj)
	var p: Vector3 = info.get("point", a.global_position + Vector3.UP)
	camera.override_target(p + Vector3(0, 0.25, 2.6), p, 32.0)
	get_tree().call_group("hud", "set_cinematic", true)

func _impact(v: Actor, info: Dictionary, seconds: float) -> void:
	phase = "impact"
	TimeFx.slowmo(0.06, seconds + 0.3, "bullet_time", 0.0)
	_until = _now() + seconds
	var inj: Array = info.get("injuries", [])
	if inj.is_empty():
		inj = XRayAnatomy.for_actor(v).injuries_at(info)
	_show(v, info, inj)
	var p: Vector3 = info.get("point", v.global_position + Vector3.UP)
	var side := -signf((info.get("dir", Vector3.RIGHT) as Vector3).x)
	camera.override_target(p + Vector3(side * 0.9, 0.3, 2.2), p, 30.0)
	Sfx.play_ui("heartbeat", -2.0)

func _show(a: Actor, _info: Dictionary, inj: Array) -> void:
	_xray = XRayAnatomy.for_actor(a)
	_xray.show_xray(inj, _info)

func _process(_d: float) -> void:
	if phase == "":
		return
	if phase == "bullet":
		var b := Ballistics.instance
		if b == null or not b.is_alive(_proj):
			# la bala ya pegó (o se perdió) sin aviso: terminar
			if _now() > _until - 3.6:
				_end()
			return
		var p := b.position_of(_proj)
		var v := b.velocity_of(_proj).normalized()
		camera.override_target(p - v * 1.1 + Vector3(0, 0.25, 0.9), p + v * 2.0, 34.0)
	if _now() > _until:
		_end()

func skip() -> void:
	if phase != "":
		_end()

func _end() -> void:
	if _xray:
		_xray.hide_xray()
		_xray = null
	phase = ""
	_proj = -1
	if Ballistics.instance:
		Ballistics.instance.tracked = -1
		Ballistics.instance.bullet_model.visible = false
	TimeFx.end_slowmo()
	camera.release_override()
	_cool_until = _now() + (8.0 if Settings.bullet_time == 1 else 2.5)
	get_tree().call_group("hud", "set_cinematic", false)
