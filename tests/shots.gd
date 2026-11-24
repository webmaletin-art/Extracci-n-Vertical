extends Node
## Capturas por escenario para revisar la imagen (no es una prueba con aprobado/fallo). Uso:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 tests/shots.tscn -- <carpeta> [escenario]
## Escenarios: inicio, apunta_atras, escalera, colgado, rayos_x, explosion, patada, caja, ascensor, menu_config

var out := "user://shots"
var g: Game
var p: Actor

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var which := a[1] if a.size() > 1 else "all"
	g = Game.new()
	add_child(g)
	await _wait(30)
	p = g.player
	p.max_health = 100000.0
	p.health = 100000.0
	g.controller.set_physics_process(false)
	_freeze_bots(true)
	var list := ["inicio", "apunta_atras", "escalera", "colgado", "rayos_x", "explosion", "patada", "caja", "ascensor", "caida", "menu_config"]
	for s in list:
		if which == "all" or which == s:
			await call("_s_" + s)
			_clear_input()
	get_tree().quit()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _shot(name_: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name_ + ".png"))
	print("captura ", name_)

func _freeze_bots(on: bool) -> void:
	for e in g.tower.enemies:
		if is_instance_valid(e):
			for c in e.get_children():
				if c is BotBrain:
					c.set_physics_process(not on)
			e.inp = ActorInput.new()

func _clear_input() -> void:
	p.inp = ActorInput.new()

func _place(pos: Vector3, aim: Vector2) -> void:
	p.state = Actor.State.GROUND
	p._cap.disabled = false
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.aim_dir = aim.normalized()
	await _wait_phys(4)
	g.camera._pos = g.camera._desired()
	g.camera.global_position = g.camera._pos

func _s_inicio() -> void:
	await _place(Vector3(5, 0.05, 0), Vector2(1, 0.05))
	await _wait(40)
	await _shot("inicio")

func _s_apunta_atras() -> void:
	# camina a la derecha mientras apunta hacia atrás y arriba (el apuntado no lo pisa el movimiento)
	await _place(Vector3(14, 0.05, 0), Vector2(-1, 0.45))
	p.inp.move = Vector2(0.5, 0)
	await _wait_phys(50)
	await _shot("apunta_atras")
	p.inp.move = Vector2.ZERO
	print("  apuntado conservado: ", p.aim_dir, " frente: ", p.facing)

func _s_escalera() -> void:
	await _place(Vector3(8.0, 0.05, 0), Vector2(1, 0))
	p.inp.move = Vector2(0, 1)
	await _wait_phys(55)
	await _shot("escalera")
	print("  estado: ", Actor.State.keys()[p.state], " y=", p.global_position.y)
	await _wait_phys(200)
	print("  después: ", Actor.State.keys()[p.state], " y=", p.global_position.y)
	p.inp.move = Vector2.ZERO

func _s_colgado() -> void:
	# desde el pilar del cráter (6,8 m) hacia el borde del P2 (x = 38, y = 9)
	await _place(Vector3(40.0, 6.85, 0), Vector2(-1, 0))
	p.inp.move = Vector2(-0.8, 0)
	await _wait_phys(8)
	p.inp.jump = true
	await _wait_phys(30)
	p.inp.move = Vector2.ZERO
	await _wait_phys(20)
	await _shot("colgado")
	print("  estado: ", Actor.State.keys()[p.state], " pos=", p.global_position)
	p.inp.move = Vector2(0, 1)
	await _wait_phys(90)
	await _shot("trepando_listo")
	print("  después de trepar: ", Actor.State.keys()[p.state], " pos=", p.global_position)

func _s_rayos_x() -> void:
	Settings.bullet_time = 2
	Settings.xray = 2
	var e: Actor = g.tower.enemies[0]
	await _place(Vector3(50.0, 0.05, 0), Vector2(1, 0.0))
	e.global_position = Vector3(57.5, 0.05, 0)
	e.velocity = Vector3.ZERO
	e.facing = -1
	e.aim_dir = Vector2(-1, 0)
	await _wait_phys(10)
	var target := e.global_position + Vector3(0, 1.35, 0)
	var chest := p.global_position + Vector3(0, 1.4, 0)
	p.aim_dir = Vector2(target.x - chest.x, target.y - chest.y).normalized()
	await _wait_phys(20)
	p.inp.fire = true
	await _wait_phys(2)
	p.inp.fire = false
	var t := 0
	while g.bullet_time.phase == "" and t < 30:
		await get_tree().process_frame
		t += 1
	await _shot("bala_seguida")
	t = 0
	while g.bullet_time.phase != "impact" and t < 300:
		await get_tree().process_frame
		t += 1
	await _wait(2)
	await _shot("rayos_x")
	print("  fase: ", g.bullet_time.phase, " vida enemigo: ", e.health)
	g.bullet_time.skip()
	await _wait(20)

func _s_explosion() -> void:
	await _place(Vector3(37.5, 0.05, 0), Vector2(1, 0))
	Explosion.spawn(g, "frag", Vector3(41.5, 0.1, 0), p)
	await _wait(4)
	await _shot("explosion")
	await _wait(40)
	await _shot("explosion_humo")

func _s_patada() -> void:
	Settings.bullet_time = 2
	var e: Actor = g.tower.enemies[1]
	await _place(Vector3(52.0, 0.05, 0), Vector2(1, 0))
	e.global_position = Vector3(53.0, 0.05, 0)
	e.facing = -1
	p.equip("fists")
	for i in 3:
		p.inp.melee = true
		await _wait_phys(int(0.5 * 60))
		await _wait_phys(4)
	await _shot("patada")
	await _wait(30)
	g.bullet_time.skip()
	p.equip("primary")

func _s_caja() -> void:
	await _place(Vector3(5.5, 0.05, 0), Vector2(1, 0))
	await _wait_phys(4)
	p.inp.interact = true
	await _wait_phys(70)
	await _shot("caja_abriendo")
	await _wait_phys(120)
	await _shot("caja_abierta")
	print("  inventario: ", p.inventory.items, " granadas: ", p.grenades)

func _s_ascensor() -> void:
	await _place(Vector3(29.2, 0.1, 0), Vector2(1, 0.2))
	await _wait_phys(10)
	g.tower.elevator.go_to(2)
	await _wait_phys(150)
	await _shot("ascensor")
	await _wait_phys(250)
	print("  ascensor en parada ", g.tower.elevator.current, " jugador y=", p.global_position.y)

func _s_menu_config() -> void:
	g.open_settings()
	await _wait(10)
	await _shot("menu_config")
	g.settings_menu.queue_free()
	g.settings_menu = null

func _s_caida() -> void:
	# cae desde el borde del P3 al fondo del cráter (P1): 9 m → fractura de pierna, renguea hasta vendarse
	Settings.bullet_time = 1
	await _place(Vector3(39.6, 13.55, 0), Vector2(1, 0))
	p.inp.move = Vector2(0.5, 0)
	await _wait_phys(25)
	p.inp.move = Vector2.ZERO
	var t := 0
	while p.state != Actor.State.GROUND and t < 300:
		await get_tree().physics_frame
		t += 1
	await _wait(3)
	await _shot("caida_rayos_x")
	print("  lesiones: ", p.injuries.summary(), " vida ", p.health)
	await _wait(60)
	g.bullet_time.skip()
	p.inp.move = Vector2(-1.0, 0)
	await _wait_phys(40)
	await _shot("renguea")
	print("  velocidad con pierna rota: ", p.velocity.x)
	p.inp.move = Vector2.ZERO
	p.inventory.add("bandage", 1)
	p.use_medical("bandage")
	await _wait_phys(200)
	print("  tras la venda: ", p.injuries.summary(), " vida ", p.health)
