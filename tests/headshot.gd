extends Node
## Un tiro a la cabeza en el modo práctica, con capturas de la bala y de la toma de rayos X.
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	AnatomyBody.hide_muscles = true
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	await _w(40)
	pg.immortal = true
	pg._spawn_dummy()
	pg.panel.visible = false
	await _w(40)
	var bt := pg.bullet_time
	pg.shoot_zone("cabeza")
	var t := 0
	while bt.phase != "bullet" and bt.phase != "kill" and t < 400:
		await _w(1)
		t += 1
	await _snap(out, "1_bala")
	t = 0
	while bt.phase != "kill" and t < 900:
		await _w(1)
		t += 1
	for pr in [0.3, 0.6, 0.98]:
		bt._t0 = TimeFx.now() - BulletTime.KILL_SECONDS * pr
		bt._until = TimeFx.now() + 120.0
		await _w(8)
		await _snap(out, "2_herida_%d" % int(pr * 100))
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _snap(out: String, n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
