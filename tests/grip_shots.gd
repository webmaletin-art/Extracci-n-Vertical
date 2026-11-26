extends Node
## Capturas del agarre de armas en la Armería: tests/grip_shots.tscn -- <carpeta> id1 id2 ...
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	if OS.get_environment("CHAR") != "":
		Settings.character_id = OS.get_environment("CHAR")
	var ui := CanvasLayer.new()
	add_child(ui)
	var ar := Armory.new()
	ui.add_child(ar)
	await _w(30)
	if OS.get_environment("NATURAL") != "":
		TechView.set_mode(0)             # colores naturales: se ve la deformación real de la malla
		await _w(10)
	for id in a.slice(1):
		ar._select(id)
		await _w(30)
		for yaw in [0.0, 50.0, -50.0, 180.0]:
			ar._yaw = yaw
			ar._pitch = 4.0
			ar._focus_weapon()
			ar._yaw = yaw
			ar._dist = 1.9
			ar._update_cam()
			await _w(6)
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out.path_join("%s_%d.png" % [id, int(yaw)]))
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
