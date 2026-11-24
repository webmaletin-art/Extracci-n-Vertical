extends Node
## Prueba rápida sin imagen: dispara a cada zona del maniquí y lista las estructuras dañadas.
##   godot --headless --path . tests/zone_probe.tscn -- [zona ...]
func _ready() -> void:
	var pg := PracticeGame.new()
	add_child(pg)
	for i in 30:
		await get_tree().process_frame
	pg.immortal = true
	var zones: Array = OS.get_cmdline_user_args() if OS.get_cmdline_user_args().size() > 0 else PracticeGame.ZONES.keys().filter(func(k): return k != "libre")
	for z in zones:
		pg._spawn_dummy()
		for i in 40:
			await get_tree().process_frame
		var t := pg._zone_point(z)
		pg.shoot_zone(z)
		for i in 120:
			await get_tree().physics_frame
		var info: Dictionary = pg.dummy.last_hit_info
		print("%-11s objetivo y=%.2f -> zona %s | %s" % [z, t.y, info.get("zone", "—"), "; ".join(PackedStringArray(info.get("injuries", ["sin impacto"])))])
	get_tree().quit()
