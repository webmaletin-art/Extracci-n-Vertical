extends Node
## Capturas del mapa Abismo Vertical: tests/map_shots.tscn -- <carpeta> [piso:x ...]
func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var g := Game.new()
	g.map_id = "abismo"
	add_child(g)
	await _w(30)
	var spots: Array = a.slice(1) if a.size() > 1 else ["0:6", "0:40", "1:60", "2:30", "3:100", "4:95", "6:112", "7:60"]
	for sp in spots:
		var f := int(str(sp).get_slice(":", 0))
		var x := float(str(sp).get_slice(":", 1))
		g.player.global_position = Vector3(x, f * 4.5 + 0.1, 0)
		g.player.velocity = Vector3.ZERO
		await _w(50)
		get_viewport().get_texture().get_image().save_png(out.path_join("f%d_%d.png" % [f, int(x)]))
	print("MAPA OK enemigos=", g.tower.enemies.size(), " props=", g.tower.stats.props, " tris=", g.tower.stats.tris_static)
	get_tree().quit()
func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame
