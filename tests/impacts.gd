extends Node
## Varios impactos distintos con la anatomía a calidad máxima: una toma por zona (sin músculos).
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	AnatomyBody.hide_muscles = true
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
		bt._t0 = TimeFx.now() - BulletTime.KILL_SECONDS * 0.98
		bt._until = TimeFx.now() + 120.0
		await _w(28)
		await _snap(out, z)
		bt.skip()
		await _w(20)
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _snap(out: String, n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
