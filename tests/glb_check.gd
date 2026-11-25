extends Node
## Verifica un GLB exportado: lo abre con GLTFDocument, cuenta nodos y animaciones y guarda capturas en varios momentos.
func _ready() -> void:
	var path := "/tmp/glb/escena_pistolas.glb"
	var out := "/tmp/glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="):
			path = a.substr(6)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(path, st)
	print("GLB leer: ", err)
	var scene := doc.generate_scene(st)
	add_child(scene)
	var aps := scene.find_children("*", "AnimationPlayer", true, false)
	print("AnimationPlayers: ", aps.size(), " · esqueletos: ", scene.find_children("*", "Skeleton3D", true, false).size(), " · mallas: ", scene.find_children("*", "MeshInstance3D", true, false).size())
	var ap: AnimationPlayer = aps[0]
	for n in ap.get_animation_list():
		var an := ap.get_animation(n)
		print("anim ", n, " · duración ", an.length, " s · pistas ", an.get_track_count())
	var an0 := ap.get_animation(ap.get_animation_list()[0])
	var xt: Array = []
	for i in an0.get_track_count():
		var tp := str(an0.track_get_path(i))
		if an0.track_get_type(i) == Animation.TYPE_SCALE_3D and tp.ends_with("Anatomia"):
			for k in an0.track_get_key_count(i):
				var v: Vector3 = an0.track_get_key_value(i, k)
				if v.x > 0.5:
					xt.append(snappedf(an0.track_get_key_time(i, k), 0.1))
	print("ANATOMIA visible en t=", xt)
	for i in an0.get_track_count():
		var tq := str(an0.track_get_path(i))
		if "Anatomia" in tq and an0.track_get_type(i) == Animation.TYPE_SCALE_3D:
			print("  pista ", tq, " claves=", an0.track_get_key_count(i))
	var lt: Array = []
	for i in an0.get_track_count():
		var tp2 := str(an0.track_get_path(i))
		if an0.track_get_type(i) == Animation.TYPE_SCALE_3D and "Miembro_" in tp2:
			for k in an0.track_get_key_count(i):
				if (an0.track_get_key_value(i, k) as Vector3).x > 0.5:
					lt.append(snappedf(an0.track_get_key_time(i, k) + 0.5, 0.1))
					break
	print("MIEMBROS que aparecen en t=", lt)
	var cam := scene.find_child("Camara3D", true, false) as Camera3D
	if cam == null:
		cam = scene.find_children("*", "Camera3D", true, false)[0]
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	env.environment = e
	add_child(env)
	var l := DirectionalLight3D.new()
	l.rotation_degrees = Vector3(-50, 20, 0)
	add_child(l)
	var an_name: String = ap.get_animation_list()[0]
	ap.play(an_name)
	ap.pause()
	for t in ([3.0, 6.0] + xt.slice(0, 1) + lt.slice(0, 2)):
		ap.seek(t, true)
		var a0 := scene.find_child("Actor_0*", true, false) as Node3D
		print("t=", t, " camara=", cam.global_position, " actor0=", a0.global_position if a0 else "?")
		for i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "/chk_%d.png" % int(t * 10))
		var a0c := scene.find_child("Actor_0*", true, false) as Node3D
		if a0c:
			var sk0 := a0c.find_child("Skeleton3D", true, false) as Skeleton3D
			if sk0:
				sk0.force_update_all_bone_transforms()
				var rh := sk0.global_transform * sk0.get_bone_global_pose(sk0.find_bone("mixamorig_RightHand")).origin
				var lh := sk0.global_transform * sk0.get_bone_global_pose(sk0.find_bone("mixamorig_LeftHand")).origin
				for w in scene.find_children("Arma_*", "Node3D", true, false):
					print("t=", t, " mano_der=", rh, " mano_izq=", lh, " arma=", (w as Node3D).global_position, " dist_der=", snappedf(rh.distance_to((w as Node3D).global_position), 0.01))
			var cc := Camera3D.new()
			add_child(cc)
			cc.fov = 28.0
			cc.global_position = a0c.global_position + Vector3(0, 1.3, 3.2)
			cc.look_at(a0c.global_position + Vector3(0, 1.3, 0), Vector3.UP)
			cc.current = true
			for i in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(out + "/close_%d.png" % int(t * 10))
			cc.queue_free()
			cam.current = true
	get_tree().quit()
