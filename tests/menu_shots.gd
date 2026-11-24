extends Node
## Capturas del menú principal, configuración, editor de controles y HUD táctil.
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	var m: Node = load("res://scenes/main.tscn").instantiate()
	add_child(m)
	await _w(60)
	await _snap(out, "menu")
	m._settings()
	await _w(20)
	await _snap(out, "config")
	var sm: SettingsMenu = m.ui.get_child(m.ui.get_child_count() - 1)
	sm._open_editor()
	await _w(20)
	await _snap(out, "editor")
	m.ui.get_child(m.ui.get_child_count() - 1).closed.emit()
	await _w(5)
	sm.closed.emit()
	if out.ends_with("nohud"):
		get_tree().quit()
		return
	m.start_game()
	await _w(60)
	m.game.hud.touch_mode = true
	m.game.hud._layout()
	await _w(10)
	await _snap(out, "hud_tactil")
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
func _snap(out: String, n: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(n + ".png"))
