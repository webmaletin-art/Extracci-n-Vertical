extends Node
## Orificios: dispara al maniquí vivo (torso, brazo, pierna) y guarda una captura de cerca.
func _ready() -> void:
	var out := "/tmp/wound"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	for i in 40:
		await get_tree().process_frame
	pg.controller.set_physics_process(false)
	var d := pg.dummy
	d.max_health = 1000000.0
	d.health = 1000000.0
	for h in [Vector3(0, 1.25, 0), Vector3(0, 0.55, 0), Vector3(0, 1.6, 0)]:
		var tgt: Vector3 = d.global_position + h
		var from := Vector3(tgt.x - 8.0, tgt.y, 0.0)
		Ballistics.instance.fire(from, Vector3(1, 0, 0), 400.0, 30.0, pg.player, [], {"penetration": 1.0, "ricochet": 0.0, "kind": "bullet"})
		for i in 20:
			await get_tree().physics_frame
	print("DISPAROS OK")
	pg.camera.set_process(false)
	pg.camera.global_position = d.global_position + Vector3(0, 1.1, 2.0)
	pg.camera.look_at(d.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	pg.camera.fov = 30.0
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "/wound.png")
	get_tree().quit()
