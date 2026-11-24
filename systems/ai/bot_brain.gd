class_name BotBrain
extends Node
## IA de un enemigo (PvE). Llena el ActorInput de su Actor igual que lo haría un jugador (mismas reglas, mismo código).
## Estados: PATRULLA → ALERTA (oyó algo: va a mirar) → COMBATE (ve al jugador: apunta con tiempo de reacción y error que
## se achica, dispara ráfagas, mantiene distancia, golpea si está pegado) → BÚSQUEDA (lo perdió: va al último lugar
## conocido) → vuelve a patrullar.
## Sentidos: vista con rayo contra el mundo (las paredes y el humo tapan), alcance menor si el jugador está agachado y
## quieto; oído por NoiseBus (los pasos al correr, disparos, cajas forzadas, ascensores y explosiones lo alertan).

enum S { PATROL, ALERT, COMBAT, SEARCH }

var actor: Actor
var home_x := 0.0
var floor_y := 0.0
var state := S.PATROL
var target: Actor
var last_seen := Vector3.ZERO
var alert_pos := Vector3.ZERO
var _t := 0.0
var _patrol_dir := 1.0
var _pause := 0.0
var _seen_t := 0.0
var _lost_t := 0.0
var _burst := 0
var _burst_cool := 0.0
var _aim := Vector2(-1, 0)
var _think := 0.0
var _sees := false
var reaction := 0.45            ## segundos desde que lo ve hasta que empieza a disparar
const SIGHT := 17.0
const SIGHT_CROUCH := 8.0

func _ready() -> void:
	process_physics_priority = -10
	NoiseBus.register(self)
	_patrol_dir = -1.0 if randf() < 0.5 else 1.0
	_aim = actor.aim_dir

func _exit_tree() -> void:
	NoiseBus.unregister(self)

## NoiseBus necesita una posición para medir la distancia.
var global_position: Vector3:
	get:
		return actor.global_position if is_instance_valid(actor) else Vector3.ZERO

func get_world_3d() -> World3D:
	return actor.get_world_3d()

func on_noise(pos: Vector3, k: float, source: Node) -> void:
	if actor.is_dead() or state == S.COMBAT:
		return
	if source is Actor and (source as Actor).team == actor.team:
		return
	if k > 0.05:
		state = S.ALERT
		alert_pos = pos
		_t = 0.0

func _physics_process(delta: float) -> void:
	if actor == null or actor.is_dead():
		return
	var inp := actor.inp
	inp.fire = false
	inp.move = Vector2.ZERO
	inp.melee = false
	_t += delta
	_think -= delta
	_burst_cool -= delta
	if actor.stunned > 0.0:
		return
	if _think <= 0.0:
		_think = 0.15
		_sense()
	match state:
		S.PATROL:
			_patrol(delta)
		S.ALERT:
			_go_to(alert_pos.x, 0.45)
			_look_at(alert_pos + Vector3.UP * 1.2, delta, 2.0)
			if absf(actor.global_position.x - alert_pos.x) < 0.8 or _t > 7.0:
				state = S.SEARCH
				_t = 0.0
		S.COMBAT:
			_combat(delta)
		S.SEARCH:
			_go_to(last_seen.x if last_seen != Vector3.ZERO else home_x, 0.4)
			if _t > 6.0:
				state = S.PATROL
	inp.aim = _aim

func _sense() -> void:
	var p := get_tree().get_first_node_in_group("player") as Actor
	_sees = false
	if p == null or p.is_dead():
		if state == S.COMBAT:
			state = S.PATROL
		return
	var eye := actor.global_position + Vector3.UP * 1.55
	var chest := p.global_position + Vector3.UP * (0.9 if p.crouching else 1.3)
	var d := eye.distance_to(chest)
	var rng := SIGHT_CROUCH if p.crouching and absf(p.velocity.x) < 0.5 else SIGHT
	if state == S.COMBAT:
		rng *= 1.4
	if d > rng:
		return
	# hacia dónde mira: adelante (o cualquier lado si ya está en combate / alerta)
	var dx := chest.x - eye.x
	if state == S.PATROL and signf(dx) != actor.facing and absf(dx) > 1.5:
		return
	var q := PhysicsRayQueryParameters3D.create(eye, chest, 1 | 8)
	q.exclude = actor.hitbox_rids()
	if not actor.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return
	for s in get_tree().get_nodes_in_group("smoke"):
		if s.has_method("blocks") and s.blocks(eye, chest):
			return
	_sees = true
	target = p
	last_seen = p.global_position
	if state != S.COMBAT:
		state = S.COMBAT
		_seen_t = 0.0
		Sfx.play("breath_fast", actor.global_position + Vector3.UP * 1.5, -14.0)

func _patrol(delta: float) -> void:
	if _pause > 0.0:
		_pause -= delta
		return
	var x := actor.global_position.x
	if absf(x - home_x) > 3.5 and signf(x - home_x) == _patrol_dir:
		_patrol_dir = -_patrol_dir
		_pause = randf_range(1.0, 3.0)
		return
	if not _floor_ahead(_patrol_dir) or _wall_ahead(_patrol_dir):
		_patrol_dir = -_patrol_dir
		_pause = 1.0
		return
	actor.inp.move.x = _patrol_dir * 0.3
	_aim = _aim.slerp(Vector2(_patrol_dir, -0.05).normalized(), clampf(delta * 3.0, 0.0, 1.0))

func _combat(delta: float) -> void:
	if not _sees:
		_lost_t += delta
		if _lost_t > 2.5:
			state = S.SEARCH
			_t = 0.0
			_lost_t = 0.0
		_go_to(last_seen.x, 0.5)
		return
	_lost_t = 0.0
	_seen_t += delta
	var tp := target.global_position
	var dx := tp.x - actor.global_position.x
	var dist := absf(dx)
	# error de puntería que se achica mientras lo sigue viendo
	var err := lerpf(0.35, 0.04, clampf(_seen_t / 3.0, 0.0, 1.0))
	var aim_pt := tp + Vector3.UP * (0.9 if target.crouching else 1.25) + Vector3(0, sin(_t * 3.1) * err * dist * 0.3, 0)
	_look_at(aim_pt, delta, 3.5)
	var w := actor.weapon()
	if dist < 1.3:
		actor.inp.melee = randf() < 0.08
		actor.inp.move.x = -signf(dx) * 0.2
		return
	# distancia preferida según el arma
	var want := 3.5 if w and str(w.stats["class"]) == "shotgun" else (8.0 if w and w.is_pistol else 10.0)
	if dist > want + 3.0:
		actor.inp.move.x = signf(dx) * 0.55
	elif dist < want - 3.0 and _floor_ahead(-signf(dx)):
		actor.inp.move.x = -signf(dx) * 0.45
	actor.inp.crouch = dist > 6.0 and fmod(_t, 7.0) < 3.0
	if not _floor_ahead(signf(actor.inp.move.x)):
		actor.inp.move.x = 0.0
	if w == null:
		return
	if w.mag == 0:
		actor.inp.reload = true
		return
	if _seen_t > reaction and _burst_cool <= 0.0:
		actor.inp.fire = true
		_burst += 1
		if _burst > (6 if bool(w.stats.auto) else 1):
			_burst = 0
			_burst_cool = randf_range(0.5, 1.2)

func _go_to(x: float, tilt: float) -> void:
	var dx := x - actor.global_position.x
	if absf(dx) < 0.4:
		return
	var dir := signf(dx)
	if not _floor_ahead(dir):
		return
	actor.inp.move.x = dir * tilt
	if _wall_ahead(dir) and actor.is_on_floor():
		actor.inp.jump = true

func _look_at(p: Vector3, delta: float, rate: float) -> void:
	var v := Vector2(p.x - actor.global_position.x, p.y - (actor.global_position.y + 1.4))
	if v.length() < 0.1:
		return
	_aim = _aim.slerp(v.normalized(), clampf(delta * rate, 0.0, 1.0)).normalized()

func _floor_ahead(dir: float) -> bool:
	var from := actor.global_position + Vector3(dir * 0.7, 0.4, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -1.6, 0), 1 | 8)
	return not actor.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _wall_ahead(dir: float) -> bool:
	var from := actor.global_position + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(dir * 0.7, 0, 0), 1 | 8)
	q.exclude = [actor.get_rid()]
	return not actor.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
