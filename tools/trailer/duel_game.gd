extends PracticeGame
## DUELOS A MUERTE en el campo de prácticas (sólo para armar la animación GLB para Blender; no es parte del juego).
## Dos personajes con IA, el mismo arma cada uno, se disparan hasta que uno mata al otro (cada ronda). Cada arma tiene dos
## rondas: pistola → escopeta → subfusil → fusil → rifle de precisión .50. Las muertes usan la cámara de muerte del juego
## (rayos X, huesos rotos, miembros arrancados) y TrailerExport lo guarda todo como un GLB con animación.
## Uso: tools/trailer/export_scenes.sh duelo   (ver docs/TRAILER.md)

const Exporter := preload("res://tools/trailer/trailer_export.gd")
const FPS := 30.0
## [id del arma, nombre, distancia inicial entre los dos (m)]
const DUELS := [["m1911", "Pistola M1911", 14.0], ["mp5_1", "Subfusil MP5 A", 12.0], ["m16_1", "Fusil M16 B", 14.0],
	["m4a1", "Fusil M4A1", 16.0], ["m4dmr", "Tirador M4 DMR", 22.0]]

var vt := 0.0
var rec
var export_glb := ""
var no_map := false
var map_root: Node
var fa: Actor
var fb: Actor
var rondas := 2
var armas := 5
var solo := -1                      ## >= 0: sólo el arma con ese índice (para exportar un GLB por arma)
var _fin := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="):
			export_glb = a.substr(6)
		if a == "--nomap":
			no_map = true
		if a.begins_with("--rondas="):
			rondas = int(a.substr(9))
		if a.begins_with("--solo="):
			solo = int(a.substr(7))
		if a.begins_with("--armas="):
			armas = int(a.substr(8))
	super._ready()
	Settings.bullet_time = 1                   # cámara de muerte en los tiros decisivos, como en la partida
	Settings.particles = 2
	Settings.xray = 2
	ui.visible = false
	controller.set_process(false)
	controller.set_physics_process(false)
	controller.set_process_input(false)
	controller.set_process_unhandled_input(false)
	auto_respawn = false
	if dummy and is_instance_valid(dummy):
		dummy.queue_free()
	player.process_mode = Node.PROCESS_MODE_DISABLED     # el jugador de la práctica no participa: los dos combatientes son bots
	player.global_position = Vector3(-60, -60, 0)
	player.visible = false
	map_root = self
	AnatomyBody.warm("vigia")
	AnatomyBody.warm("zapador")
	TimeFx.fixed_fps = FPS                         # la cámara de muerte y la cámara lenta duran lo mismo que en el juego real
	Sfx.log_on = true
	Sfx.event_log.clear()
	Sfx.log_t0 = Engine.get_frames_drawn()
	_run.call_deferred()

func _process(_delta: float) -> void:
	vt += 1.0 / FPS
	if bullet_time.phase == "" and is_instance_valid(fa) and is_instance_valid(fb):
		var dx := fb.global_position.x - fa.global_position.x
		camera.look_offset_x = clampf(dx * 0.5, -12.0, 12.0)
		Settings.camera_distance = clampf(absf(dx) * 0.9 + 4.0, 8.0, 20.0)

func _fighter(id: String, team: int, x: float, facing: float, weapon_id: String) -> Actor:
	var a := Actor.new()
	a.name = "Duelista_%s" % id
	a.character_id = id
	a.team = team
	a.max_health = 170.0                          # duelos más largos: se ven los intercambios, los fallos y la persecución
	add_child(a)
	a.global_position = Vector3(x, 0.05, 0.0)
	a.facing = facing
	a.aim_dir = Vector2(facing, 0.0)
	var slot := "secondary" if str(Firearm.all_stats()[weapon_id].hold) == "pistol" else "primary"
	a.give_weapon(slot, weapon_id)
	a.equip(slot)
	bullet_time.watch(a)
	return a

func _run() -> void:
	TechView.set_mode(0)                          # materiales originales (los shaders del estilo plano no caben en un GLB)
	for i in 12:
		await get_tree().process_frame
	rec = Exporter.new()
	rec.begin(self, [])
	if no_map:
		pass
	await _wait(0.5)
	for wi in (range(DUELS.size()) if solo < 0 else [solo]):
		if solo < 0 and wi >= armas:
			break
		for r in rondas:
			await _round(DUELS[wi], r)
	await _wait(0.5)
	_finish()

func _wait(sec: float) -> void:
	for i in int(sec * FPS):
		await get_tree().process_frame

func _round(w: Array, r: int) -> void:
	var sep: float = float(w[2])
	var xa := 12.0
	var xb := xa + sep
	if r % 2 == 1:
		var tmp := xa
		xa = xb
		xb = tmp                                   # la segunda ronda cambia de lado
	fa = _fighter("vigia", 0, xa, signf(xb - xa), str(w[0]))
	fb = _fighter("zapador", 1, xb, signf(xa - xb), str(w[0]))
	rec.add_actor(fa, vt)
	rec.add_actor(fb, vt)
	bullet_time.player = fa
	camera.target = fa
	var ba := DuelBrain.new()
	ba.actor = fa
	ba.foe = fb
	ba.style = r % 2
	ba.reaction = randf_range(0.6, 1.0)
	fa.add_child(ba)
	var bb := DuelBrain.new()
	bb.actor = fb
	bb.foe = fa
	bb.style = (r + 1) % 2
	bb.reaction = randf_range(0.6, 1.0)
	fb.add_child(bb)
	var t0 := vt
	var dbg := 0
	while not (fa.is_dead() or fb.is_dead()) and vt - t0 < 20.0:
		await get_tree().process_frame
		dbg += 1
		if dbg % 15 == 0:
			print("DUELO t=%.1f vidaA=%.0f vidaB=%.0f dist=%.1f fase=%s" % [vt - t0, fa.health, fb.health, absf(fa.global_position.x - fb.global_position.x), bullet_time.phase])
	if not (fa.is_dead() or fb.is_dead()):
		# se pasó el tiempo: gana quien tiene más vida (un tiro de gracia decide)
		var loser := fa if fa.health < fb.health else fb
		var winner := fb if loser == fa else fa
		loser.take_damage({"damage": 90.0, "type": "bullet", "zone": "head", "bone": "mixamorig_Head",
			"point": loser.global_position + Vector3(0, 1.65, 0), "dir": Vector3(signf(loser.global_position.x - winner.global_position.x), 0, 0), "shooter": winner})
	print("DUELO fin ronda t=%.1f muertoA=%s muertoB=%s fase=%s" % [vt - t0, fa.is_dead(), fb.is_dead(), bullet_time.phase])
	await _wait(0.4)
	var n := 0
	while bullet_time.phase != "" and n < int(6.0 * FPS):          # la toma de muerte termina sola (es corta)
		await get_tree().process_frame
		n += 1
		if n % 10 == 0:
			var vic: Actor = fa if fa.is_dead() else fb
			print("KILLCAM n=%d fase=%s rayosX=%s" % [n, bullet_time.phase, AnatomyBody.for_actor(vic)._showing])
	await _wait(0.5)
	rec.remove_actor(fa, vt)
	rec.remove_actor(fb, vt)
	rec.clear_round(vt)
	fa.queue_free()
	fb.queue_free()
	if Blood.instance:
		Blood.instance.clear()
	await get_tree().process_frame

func _finish() -> void:
	if _fin:
		return
	_fin = true
	if rec != null and export_glb != "":
		rec.export_to(ProjectSettings.globalize_path(export_glb))
		var hf := FileAccess.open(export_glb.get_basename() + "_disparos.json", FileAccess.WRITE)
		hf.store_string(JSON.stringify(rec.hits, "\t"))
		hf.close()
		var f := FileAccess.open(export_glb.get_basename() + "_sonidos.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"fps": FPS, "seconds": vt, "events": Sfx.event_log}, "\t"))
		f.close()
	print("TRAILER_LISTO ", vt, " s · sonidos ", Sfx.event_log.size())
	get_tree().quit()


## IA del duelo: apunta con error que se achica, mantiene la distancia que le conviene al arma, dispara en ráfagas y recarga.
class DuelBrain extends Node:
	var actor: Actor
	var foe: Actor
	var style := 0              ## 0 mantiene la distancia · 1 avanza disparando
	var reaction := 0.4
	var _t := 0.0
	var _seen := -1.2
	var _burst := 0
	var _cool := 0.0

	func _ready() -> void:
		process_physics_priority = -10

	func _physics_process(delta: float) -> void:
		var inp := actor.inp
		inp.fire = false
		inp.move = Vector2.ZERO
		inp.crouch = false
		if actor.is_dead() or not is_instance_valid(foe) or foe.is_dead():
			return
		_t += delta
		_seen += delta
		_cool -= delta
		var w := actor.weapon()
		if w == null:
			return
		var dx := foe.global_position.x - actor.global_position.x
		var dist := absf(dx)
		var cls := str(w.stats["class"])
		var want: float = {"shotgun": 3.5, "smg": 7.0, "rifle": 10.0, "dmr": 13.0, "sniper": 16.0}.get(cls, 8.0)
		var err := lerpf(3.2, 0.15, clampf(_seen / 9.0, 0.0, 1.0))        # al principio falla mucho; mejora si lo sigue viendo
		var eye := actor.global_position + Vector3(0, 1.45, 0)
		var tgt := foe.global_position + Vector3(0, 1.25 + sin(_t * 3.1) * err * 0.5 + cos(_t * 1.7) * err * 0.25, 0)
		inp.aim_snap = false
		inp.aim = Vector2(tgt.x - eye.x, tgt.y - eye.y).normalized()
		if style == 1 and dist > want:
			inp.move.x = signf(dx) * 0.7
		elif dist > want + 3.0:
			inp.move.x = signf(dx) * 0.6
		elif dist < want - 3.0:
			inp.move.x = -signf(dx) * 0.45
		inp.crouch = style == 0 and dist > 6.0 and fmod(_t, 6.0) < 1.4
		if w.mag == 0:
			inp.reload = true
			return
		if _seen > reaction and _cool <= 0.0 and not w.reloading:
			inp.fire = true
			_burst += 1
			if _burst > (6 if bool(w.stats.auto) else 1):
				_burst = 0
				_cool = randf_range(0.5, 1.1) if cls != "sniper" else randf_range(1.0, 1.6)
