extends Node
## Varios disparos seguidos a un maniquí inmortal y captura de la toma final de rayos X (con o sin músculos).
##   godot ... tests/practice_seq.tscn -- <carpeta> <con|sin> zona zona zona
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	AnatomyBody.hide_muscles = a[1] == "sin"
	if OS.get_environment("SOLO") != "":
		AnatomyBody.only_system = OS.get_environment("SOLO")
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	await _w(40)
	pg.immortal = true
	pg._spawn_dummy()
	pg.panel.visible = false
	await _w(40)
	var bt := pg.bullet_time
	for z in a.slice(2):
		pg.shoot_zone(z)
		var t := 0
		while bt.phase != "kill" and t < 900:
			await _w(1)
			t += 1
		bt.skip()
		await _w(30)
	# última toma: se repite el primer impacto no, se muestra la toma con todas las heridas acumuladas
	pg.shoot_zone(a[a.size() - 1])
	var t2 := 0
	while bt.phase != "kill" and t2 < 900:
		await _w(1)
		t2 += 1
	for pr in [0.5, 0.98]:
		bt._t0 = TimeFx.now() - BulletTime.KILL_SECONDS * pr
		bt._until = TimeFx.now() + 120.0
		await _w(8)
		await _snap(out, "%s_%s_%d" % [a[1], OS.get_environment("SOLO"), int(pr * 100)])
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _snap(out: String, n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
