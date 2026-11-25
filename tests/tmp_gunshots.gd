extends Node
## Vista lateral de cada arma (misma escala) para comparar modelos.
func _ready() -> void:
	var items := [["Shotgun_1", "/tmp/qglb/Shotgun_1.glb", false], ["Shotgun_2", "/tmp/qglb/Shotgun_2.glb", false], ["Shotgun_3", "/tmp/qglb/Shotgun_3.glb", false],
		["Shotgun_4", "/tmp/qglb/Shotgun_4.glb", false], ["Shotgun_ShortStock", "/tmp/qglb/Shotgun_ShortStock.glb", false], ["Shotgun_SawedOff", "/tmp/qglb/Shotgun_SawedOff.glb", false],
		["SniperRifle_1", "/tmp/qglb/SniperRifle_1.glb", false], ["SniperRifle_2", "/tmp/qglb/SniperRifle_2.glb", false], ["SniperRifle_3", "/tmp/qglb/SniperRifle_3.glb", false],
		["SniperRifle_4", "/tmp/qglb/SniperRifle_4.glb", false], ["SniperRifle_5", "/tmp/qglb/SniperRifle_5.glb", false], ["SniperRifle_6", "/tmp/qglb/SniperRifle_6.glb", false],
		["REF_m4dmr", "res://assets/weapons/m4dmr.glb", true], ["REF_scarh", "res://assets/weapons/scarh.glb", true], ["REF_m16", "res://assets/weapons/m16.glb", true], ["REF_g36c", "res://assets/weapons/g36c.glb", true]]
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.93, 0.92)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.85)
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-35, -30, 0)
	add_child(l)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.62
	cam.global_position = Vector3(0, 0, 3)
	add_child(cam)
	cam.make_current()
	for it in items:
		var node: Node3D
		if it[2]:
			node = (load(it[1]) as PackedScene).instantiate()
			node.rotation_degrees = Vector3(0, 90, 0)        # el arma del juego apunta a -Z: se gira para verla de costado
		else:
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			doc.append_from_file(it[1], st)
			node = doc.generate_scene(st)
		add_child(node)
		# centrar
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var bb := (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			mn = mn.min(bb.position)
			mx = mx.max(bb.end)
		node.global_position -= (mn + mx) * 0.5
		for i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("/tmp/qprev/%s.png" % it[0])
		node.queue_free()
	get_tree().quit()
