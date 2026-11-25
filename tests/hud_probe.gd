extends Node
## Disposición de los controles táctiles: captura de la partida con touch_mode activado.
func _ready() -> void:
	var out := "/tmp/hud"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	var g := Game.new()
	add_child(g)
	for i in 40:
		await get_tree().process_frame
	g.hud.touch_mode = true
	g.hud._layout()
	for i in 10:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	print("TAMAÑO ", img.get_size())
	img.save_png(out + "/hud.png")
	get_tree().quit()
