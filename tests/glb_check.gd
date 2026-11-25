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
	for t in (xt.slice(0, 2) + lt.slice(0, 3) if not (xt.is_empty() and lt.is_empty()) else [8.0]):
		ap.seek(t, true)
		var a0 := scene.find_child("Actor_0*", true, false) as Node3D
		print("t=", t, " camara=", cam.global_position, " actor0=", a0.global_position if a0 else "?")
		for i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "/chk_%d.png" % int(t * 10))
	get_tree().quit()
