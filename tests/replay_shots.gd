extends Node
## Repetición de la bala por dentro del cuerpo en el modo práctica: por zona, 3 cuadros de la bala avanzando y la toma
## final.   godot ... tests/replay_shots.tscn -- <carpeta> zona zona ...
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	await _w(40)
	pg.panel.visible = false
	pg.auto_respawn = false
	var bt := pg.bullet_time
	for z in a.slice(1):
		pg.immortal = true
		pg._spawn_dummy()
		await _w(40)
		pg.shoot_zone(z)
		var t := 0
		while bt.phase != "kill" and t < 900:
			await _w(1)
			t += 1
		TimeFx.slowmo(0.0005, 9999.0, "kill", 0.0)        # tiempo casi detenido: el render por software es lento
		print(z, ": ", "; ".join(PackedStringArray(pg.dummy.last_hit_info.get("injuries", []))))
		if bt._replay.is_empty():
			print("  (sin repetición)")
		else:
			for u in [0.3, 0.55, 0.8]:
				bt.debug_u = u
				bt._t0 = TimeFx.now() + 100.0
				bt._until = TimeFx.now() + 200.0
				await _w(4)
				await _snap(out, "%s_bala_%d" % [z, int(u * 100)])
		bt.debug_u = 1.0
		await _w(2)
		bt.debug_u = -1.0
		bt._t0 = TimeFx.now() - BulletTime.KILL_SECONDS * 0.98
		bt._until = TimeFx.now() + 120.0
		await _w(28)
		await _snap(out, "%s_final" % z)
		bt.skip()
		await _w(20)
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _snap(out: String, n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
