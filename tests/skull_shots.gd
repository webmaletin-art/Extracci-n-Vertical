extends Node
## Cráneo intacto de cada personaje en rayos X (para revisar deformaciones del ajuste).
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	await _w(30)
	pg.panel.visible = false
	for c in CharacterModel.all():
		pg.dummy_char = str(c.id)
		pg._spawn_dummy()
		await _w(30)
		var an := AnatomyBody.for_actor(pg.dummy)
		var n := an.find_group("cráneo")
		var hc := an.bind_to_world(n, an.groups[n].center)
		an.show_xray([{"node": n, "pos": an.groups[n].center}], 99.0, true, 0.3)
		pg.camera.override_target(hc + Vector3(-0.35, 0.05, 0.55), hc, 34.0)
		await _w(25)
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join(str(c.id) + ".png"))
		an.hide_all()
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
