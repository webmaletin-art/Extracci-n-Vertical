extends SceneTree
## Construye assets/anims/player_anims.res a partir de los FBX de Mixamo (mixamo-respaldo).
## Adaptado de Operación Nexus (tools/anim_builder). Lo ejecuta build.sh; no se usa en tiempo de juego.
## Además guarda assets/anims/ref_skeleton.json: la pose de reposo del esqueleto de referencia (operador), que usa
## CharacterModel para adaptar las animaciones a cada personaje sin cargar el FBX de 13 MB en el juego.

const HIPS := "mixamorig_Hips"

func _init() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://anims.json"))
	var out_dir: String = OS.get_cmdline_user_args()[0]
	var ybot_hips := _hips_y("res://src/ybot.fbx")
	var oper_hips := _hips_y("res://src/operator.fbx")
	var ratio := oper_hips / ybot_hips
	var lib := AnimationLibrary.new()
	for id in cfg.player:
		var def: Dictionary = cfg.player[id]
		var scene: Node = load("res://src/player__%s.fbx" % id).instantiate()
		var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		var names := ap.get_animation_list()
		var raw: Animation = ap.get_animation("mixamo_com" if "mixamo_com" in names else names[0])
		var anim := _clean(raw, ratio, def.get("loop", false), def.get("inplace", true), def.get("inplace_y", false))
		lib.add_animation(id, anim)
		scene.free()
	var path := out_dir.path_join("player_anims.res")
	var err := ResourceSaver.save(lib, path, ResourceSaver.FLAG_COMPRESS)
	print("saved ", path, " anims=", lib.get_animation_list().size(), " err=", err)
	_save_ref(out_dir.path_join("ref_skeleton.json"))
	quit()

func _hips_y(path: String) -> float:
	var n: Node = load(path).instantiate()
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	var y := sk.get_bone_rest(sk.find_bone(HIPS)).origin.y
	n.free()
	return y

func _save_ref(path: String) -> void:
	var n: Node = load("res://src/operator.fbx").instantiate()
	var sk: Skeleton3D = n.find_child("Skeleton3D", true, false)
	var bones := {}
	for i in sk.get_bone_count():
		var q := sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
		bones[sk.get_bone_name(i).replace(":", "_")] = [q.x, q.y, q.z, q.w]
	var hi := sk.find_bone("mixamorig_Head")
	if hi < 0:
		hi = sk.find_bone("mixamorig:Head")
	var d := {"head_y": sk.get_bone_global_rest(hi).origin.y, "bones": bones}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	n.free()
	print("saved ", path)

func _clean(raw: Animation, ratio: float, loop: bool, inplace: bool, inplace_y := false) -> Animation:
	var a := Animation.new()
	a.length = raw.length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var drift_out := Vector3.ZERO
	for i in raw.get_track_count():
		var path := raw.track_get_path(i)
		var bone := str(path.get_subname(0))
		var type := raw.track_get_type(i)
		if type == Animation.TYPE_ROTATION_3D:
			var t := a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(t, path)
			for k in raw.track_get_key_count(i):
				a.rotation_track_insert_key(t, raw.track_get_key_time(i, k), raw.track_get_key_value(i, k))
		elif type == Animation.TYPE_POSITION_3D and bone == HIPS:
			var t := a.add_track(Animation.TYPE_POSITION_3D)
			a.track_set_path(t, path)
			var n := raw.track_get_key_count(i)
			var p0: Vector3 = raw.track_get_key_value(i, 0)
			var drift: Vector3 = raw.track_get_key_value(i, n - 1) - p0
			drift_out = drift * ratio
			for k in n:
				var time := raw.track_get_key_time(i, k)
				var p: Vector3 = raw.track_get_key_value(i, k)
				if inplace:
					# Saca el avance acumulado en XZ pero conserva el balanceo natural.
					var f: float = time / maxf(raw.length, 0.001)
					p.x -= p0.x + drift.x * f
					p.z -= p0.z + drift.z * f
					if inplace_y:
						p.y -= drift.y * f
				a.position_track_insert_key(t, time, p * ratio)
	# avance quitado (metros, espacio del personaje mirando a +Z): el código lo aplica a la cápsula
	a.set_meta("drift", drift_out)
	return a
