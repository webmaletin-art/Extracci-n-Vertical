extends Node
## El jugador sostiene cada arma (de cerca): revisa tamaño, orientación y manos (Grip / Support) de las armas nuevas.
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out := a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	await _w(40)
	pg.panel.visible = false
	pg.controller.set_physics_process(false)
	for id in a.slice(1):
		pg.weapon_id = id
		pg._equip()
		pg.player.aim_dir = Vector2(1, 0.15).normalized()
		await _w(30)
		var c := pg.player.global_position + Vector3(0, 1.3, 0)
		pg.camera.override_target(c + Vector3(0.2, 0.1, 2.0), c, 40.0)
		await _w(20)
		get_viewport().get_texture().get_image().save_png(out.path_join(id + ".png"))
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
