extends Node
func _ready() -> void:
	var pg := PracticeGame.new()
	add_child(pg)
	for i in 40:
		await get_tree().process_frame
	pg.immortal = true
	var t := pg._zone_point("ojo")
	print("objetivo ", t, " cabeza hueso ", pg.dummy.skel.global_transform * pg.dummy.skel.get_bone_global_pose(pg.dummy.skel.find_bone("mixamorig_Head")).origin)
	var hits := []
	Ballistics.instance.projectile_hit.connect(func(i, info): hits.append([info.get("zone", "?"), info.point]))
	pg.shoot_zone("ojo")
	for i in 120:
		await get_tree().physics_frame
	print("aim ", pg.player.aim_dir, " muzzle ", pg.player.weapon().muzzle_world(), " hits ", hits, " stats ", Ballistics.instance.stats)
	get_tree().quit()
