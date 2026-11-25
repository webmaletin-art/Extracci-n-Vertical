extends Node
## Desmembramiento: mata al maniquí, le arranca miembros y guarda capturas (normales y con rayos X) en la carpeta indicada.
func _ready() -> void:
	var out := "/tmp/limb"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	var pg := PracticeGame.new()
	add_child(pg)
	for i in 40:
		await get_tree().process_frame
	pg.controller.set_physics_process(false)
	var d := pg.dummy
	d.max_health = 100.0
	d.health = 1.0
	var c := d.global_position + Vector3(0, 1.2, 0)
	d.take_damage({"damage": 60.0, "type": "bullet", "zone": "torso", "bone": "mixamorig_Spine1", "point": c, "dir": Vector3(-1, 0, 0), "shooter": pg.player})
	for i in 90:
		await get_tree().physics_frame
	for j in ["mixamorig_LeftForeArm", "mixamorig_RightLeg", "mixamorig_Neck", "mixamorig_LeftUpLeg"]:
		for k in 3:
			d.take_damage({"damage": 95.0, "type": "bullet", "zone": "arm", "bone": j, "point": c, "dir": Vector3(-1, 0, 0), "shooter": pg.player})
	print("CORTADOS ", d.severed.keys())
	for n in 3:
		for i in 14:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "/limb_%d.png" % n)
	get_tree().quit()
