extends Node
## Corre el test de rendimiento de estilos del modo práctica (versión corta) y guarda una captura de cada fase.
func _ready() -> void:
	var pg := PracticeGame.new()
	add_child(pg)
	for i in 40:
		await get_tree().process_frame
	var r: String = await pg.style_benchmark(3.0)
	print(r)
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	get_tree().quit()
