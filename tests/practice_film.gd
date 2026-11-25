extends Node
## Secuencia completa del modo práctica (bala en vuelo → bala por dentro → toma quieta): cuadros en orden.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	await _w(40)
	pg.panel.visible = false
	pg.auto_respawn = false
	pg.immortal = true
	pg._spawn_dummy()
	await _w(40)
	var bt := pg.bullet_time
	pg.shoot_zone(a[1] if a.size() > 1 else "cabeza")
	var t := 0
	while bt.phase != "bullet" and t < 400:
		await _w(1)
		t += 1
	TimeFx.slowmo(0.0005, 9999.0, "bullet_time", 0.0)
	# vuelo: se adelanta la bala a mano por su recorrido
	var b := Ballistics.instance
	var p0 := b.position_of(bt._proj)
	var v := b.velocity_of(bt._proj)
	var x1 := float(b.visual_z[2]) if b.visual_z.size() == 4 else p0.x + 8.0
	for k in 3:
		var u := [0.1, 0.5, 0.9][k]
		b._pos[bt._proj] = p0 + v.normalized() * (x1 - p0.x) * u / maxf(absf(v.normalized().x), 0.1)
		await _w(4)
		await _snap(out, "1_vuelo_%d" % k)
	TimeFx.end_slowmo()
	t = 0
	while bt.phase != "kill" and t < 900:
		await _w(1)
		t += 1
	TimeFx.slowmo(0.0005, 9999.0, "kill", 0.0)
	for k in 4:
		bt.debug_u = [0.15, 0.4, 0.65, 0.95][k]
		await _w(4)
		await _snap(out, "2_dentro_%d" % k)
	bt.debug_u = 1.0
	await _w(4)
	await _snap(out, "3_quieta")
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _snap(out: String, n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
