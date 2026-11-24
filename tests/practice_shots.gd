extends Node
## Capturas del modo práctica: godot --path . tests/practice_shots.tscn -- <carpeta> [zona ...]
var out := "user://shots_practica"
var pg: PracticeGame

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var zones: Array = a.slice(1) if a.size() > 1 else ["ojo", "estómago", "testículos"]
	pg = PracticeGame.new()
	add_child(pg)
	await _wait(40)
	pg.immortal = true
	pg.panel.visible = false
	pg._spawn_dummy()
	await _wait(40)
	await _snap("inicio")
	for z in zones:
		pg.shoot_zone(z)
		var bt := pg.bullet_time
		var t := 0
		while bt.phase != "kill" and t < 900:
			await _wait(1)
			t += 1
			if bt.phase == "bullet" and t == 5:
				await _snap("%s_bala" % z)
		# con renderizado por software van pocos cuadros por segundo: se congela la toma al final del acercamiento
		for pr in [0.55, 0.98]:
			bt._t0 = TimeFx.now() - BulletTime.KILL_SECONDS * pr
			bt._until = TimeFx.now() + 120.0
			await _wait(8)
			await _snap("%s_herida_%d" % [z, int(pr * 100)])
		bt.skip()
		await _wait(60)
		pg._spawn_dummy()
		await _wait(40)
	get_tree().quit()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _snap(n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
	print("captura ", n)
