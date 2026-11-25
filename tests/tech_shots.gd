extends Node
## Capturas de la VISUALIZACIÓN TÉCNICA 3D: el mapa real (Torre Alfa) en los 4 modos, y una muerte con rayos X en los 3
## estilos, con la cámara normal del juego. También mide cuadros y llamadas de dibujo por modo (render por software:
## los ms NO representan un teléfono; las llamadas de dibujo sí).
var out := ""
func _ready() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var g := Game.new()
	add_child(g)
	await _w(40)
	var p := g.player
	p.max_health = 100000.0
	p.health = 100000.0
	g.controller.set_physics_process(false)
	for e in g.tower.enemies:
		for c in e.get_children():
			if c is BotBrain:
				c.set_physics_process(false)
		e.inp = ActorInput.new()
	# en el piso 0, frente a un enemigo
	p.global_position = Vector3(50.0, 0.05, 0)
	p.aim_dir = Vector2(1, 0.05).normalized()
	var e: Actor = g.tower.enemies[0]
	e.global_position = Vector3(56.0, 0.05, 0)
	e.facing = -1
	await _w(30)
	g.camera._pos = g.camera._desired()
	var report := []
	for m in 4:
		TechView.set_mode(m)
		await _w(20)
		var t0 := Time.get_ticks_usec()
		for i in 20:
			await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - t0) / 20000.0
		var dc := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var prim := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		report.append("%s: %.1f ms/cuadro (software) · %d llamadas de dibujo · %d primitivas" % [TechView.MODES[m], ms, dc, prim])
		await _snap("mapa_%d" % m)
	# muerte con rayos X (toma breve del juego) en cada estilo, sobre el modo C
	for xs in 3:
		TechView.set_mode(3)
		TechView.set_xray(xs)
		var en: Actor = g.tower.enemies[1 + xs]
		en.global_position = Vector3(55.0, 0.05, 0)
		en.velocity = Vector3.ZERO
		en.facing = -1
		await _w(20)
		var sb := en.skel.find_bone("mixamorig_Spine2")
		var target := en.skel.global_transform * en.skel.get_bone_global_pose(sb).origin
		var w := p.weapon()
		for i in 15:
			var mz := w.muzzle_world()
			p.aim_dir = Vector2(target.x - mz.x, target.y - mz.y).normalized()
			await get_tree().physics_frame
		en.health = 5.0
		p.inp.fire = true
		await get_tree().physics_frame
		p.inp.fire = false
		var t := 0
		while g.bullet_time.phase != "kill" and t < 300:
			await _w(1)
			t += 1
		var bt := g.bullet_time
		TimeFx.slowmo(0.0005, 9999.0, "kill", 0.0)
		bt._t0 = TimeFx.now() - BulletTime.KILL_SECONDS * 0.85
		bt._until = TimeFx.now() + 100.0
		await _w(24)
		await _snap("muerte_rayos_%d" % xs)
		bt.skip()
		TimeFx.end_slowmo()
		await _w(10)
	var f := FileAccess.open(out.path_join("medicion.txt"), FileAccess.WRITE)
	f.store_string("\n".join(report))
	f.close()
	print("\n".join(report))
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _snap(n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
