class_name CharacterModel
extends RefCounted
## Personajes intercambiables sobre el MISMO esqueleto Mixamo y las MISMAS animaciones (data/characters.json).
## Adaptado de Operación Nexus (player/character_model.gd): en lugar de cargar el FBX del operador (13 MB) usa
## assets/anims/ref_skeleton.json, la pose de reposo del esqueleto de referencia que guarda tools/anim_builder.
##
## instantiate(id) devuelve un Node3D raíz → "Skeleton3D" → mallas, mirando hacia +Z, en metros.
## anim_library(id) adapta las animaciones (pensadas para el esqueleto de referencia) a los ejes de cada esqueleto:
##   O(b) = Gref(b)⁻¹ · Rc · Gcand(b)          (G = rotación global de reposo; Rc = giro del nodo del esqueleto)
##   q_cand(b) = O(padre)⁻¹ · q_ref(b) · O(b)
## La posición de la cadera se gira con Rc⁻¹ y se escala por la altura. Se calcula una vez por personaje.

const DATA := "res://data/characters.json"
const ANIMS := "res://assets/anims/player_anims.res"
const REF := "res://assets/anims/ref_skeleton.json"

static var _defs: Array = []
static var _libs := {}
static var _ref_rest := {}
static var _ref_height := 0.0
static var _fix := {}

static func all() -> Array:
	if _defs.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if d is Dictionary:
			for c in d.characters:
				if ResourceLoader.exists(str(c.path)):
					_defs.append(c)
	return _defs

static func find(id: String) -> Dictionary:
	for c in all():
		if str(c.id) == id:
			return c
	return all()[0]

static func enemies() -> Array:
	return all().filter(func(c): return str(c.get("uso", "")) == "enemigo")

static func normalize_bone_names(sk: Skeleton3D) -> void:
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if ":" in n:
			sk.set_bone_name(i, n.replace(":", "_"))

static func find_skeleton(root: Node) -> Skeleton3D:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

static func instantiate(id: String) -> Node3D:
	var def := find(id)
	var src: Node = (load(str(def.path)) as PackedScene).instantiate()
	var sk := find_skeleton(src)
	if sk == null:
		return src as Node3D
	normalize_bone_names(sk)
	var fix := _fix_for(str(def.id), sk)
	var acc := Transform3D.IDENTITY
	var c: Node = sk.get_parent()
	while c != null and c != src:
		if c is Node3D:
			acc = (c as Node3D).transform * acc
		c = c.get_parent()
	var root := Node3D.new()
	root.name = str(def.id)
	var sk_xf: Transform3D = acc * sk.transform
	sk.get_parent().remove_child(sk)
	sk.owner = null
	sk.name = "Skeleton3D"
	root.add_child(sk)
	sk.transform = Transform3D(fix.rc, Vector3.ZERO) * sk_xf
	src.free()
	_apply_materials(root, def)
	return root

static func anim_library(id: String) -> AnimationLibrary:
	var def := find(id)
	var cid := str(def.id)
	if _libs.has(cid):
		return _libs[cid]
	var base: AnimationLibrary = load(ANIMS)
	if not _fix.has(cid):
		var tmp := instantiate(cid)
		tmp.free()
	var fix: Dictionary = _fix[cid]
	if fix.identity:
		_libs[cid] = base
		return base
	var lib := AnimationLibrary.new()
	for an in base.get_animation_list():
		lib.add_animation(an, _retarget(base.get_animation(an), fix))
	_libs[cid] = lib
	return lib

static func _retarget(a: Animation, fix: Dictionary) -> Animation:
	var o: Dictionary = fix.o
	var parent_o: Dictionary = fix.po
	var rc_inv: Basis = (fix.rc as Basis).inverse()
	var hs: float = fix.h
	var out := Animation.new()
	out.length = a.length
	out.loop_mode = a.loop_mode
	out.step = a.step
	if a.has_meta("drift"):
		out.set_meta("drift", (a.get_meta("drift") as Vector3) * hs)
	for ti in a.get_track_count():
		var path := a.track_get_path(ti)
		var bone := str(path.get_subname(0))
		var ty := a.track_get_type(ti)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
			continue
		if not o.has(bone):
			continue
		if ty == Animation.TYPE_POSITION_3D and not fix.roots.has(bone):
			continue
		var nt := out.add_track(ty)
		out.track_set_path(nt, path)
		out.track_set_interpolation_type(nt, a.track_get_interpolation_type(ti))
		out.track_set_interpolation_loop_wrap(nt, a.track_get_interpolation_loop_wrap(ti))
		var qo: Quaternion = o[bone]
		var qp_inv: Quaternion = (parent_o[bone] as Quaternion).inverse()
		for k in a.track_get_key_count(ti):
			var tm := a.track_get_key_time(ti, k)
			if ty == Animation.TYPE_ROTATION_3D:
				var q: Quaternion = a.track_get_key_value(ti, k)
				out.rotation_track_insert_key(nt, tm, (qp_inv * q * qo).normalized())
			else:
				var p: Vector3 = a.track_get_key_value(ti, k)
				out.position_track_insert_key(nt, tm, rc_inv * p * hs)
	return out

static func _fix_for(cid: String, sk: Skeleton3D) -> Dictionary:
	if _fix.has(cid):
		return _fix[cid]
	_load_ref()
	var def := find(cid)
	var rc := Basis.IDENTITY
	if def.has("yaw_deg"):
		rc = Basis(Vector3.UP, deg_to_rad(float(def.yaw_deg)))
	else:
		var la := sk.find_bone("mixamorig_LeftArm")
		var ra := sk.find_bone("mixamorig_RightArm")
		if la >= 0 and ra >= 0:
			var left := sk.get_bone_global_rest(la).origin - sk.get_bone_global_rest(ra).origin
			left.y = 0.0
			if left.length() > 0.001:
				var ang := snappedf(-atan2(-left.z, left.x), PI * 0.5)
				rc = Basis(Vector3.UP, ang)
	var o := {}
	var po := {}
	var roots := {}
	var identity := rc.is_equal_approx(Basis.IDENTITY)
	var rcq := rc.get_rotation_quaternion()
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if not _ref_rest.has(n):
			continue
		var gc := sk.get_bone_global_rest(i).basis.get_rotation_quaternion()
		var q: Quaternion = (_ref_rest[n] as Quaternion).inverse() * rcq * gc
		o[n] = q.normalized()
		if q.angle_to(Quaternion.IDENTITY) > deg_to_rad(0.5):
			identity = false
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if not o.has(n):
			continue
		var p := sk.get_bone_parent(i)
		if p < 0:
			po[n] = rcq
			roots[n] = true
		else:
			po[n] = o.get(sk.get_bone_name(p), rcq)
	var hi := sk.find_bone("mixamorig_Head")
	var h := 1.0
	if hi >= 0 and _ref_height > 0.0:
		var hc := sk.get_bone_global_rest(hi).origin.y
		h = hc / _ref_height if hc > 0.01 else 1.0
	if absf(h - 1.0) > 0.01:
		identity = false
	_fix[cid] = {"rc": rc, "o": o, "po": po, "roots": roots, "h": h, "identity": identity}
	return _fix[cid]

static func _load_ref() -> void:
	if not _ref_rest.is_empty():
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REF))
	for n in d.bones:
		var a: Array = d.bones[n]
		_ref_rest[n] = Quaternion(a[0], a[1], a[2], a[3])
	_ref_height = float(d.head_y)

static var _mat_done := {}
static func _apply_materials(root: Node, def: Dictionary) -> void:
	var m: Dictionary = def.get("material", {})
	if m.is_empty() or _mat_done.has(str(def.id)):
		return
	_mat_done[str(def.id)] = true
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(s) as StandardMaterial3D
				if sm:
					if m.has("roughness"):
						sm.roughness = float(m.roughness)
					if m.has("metallic"):
						sm.metallic = float(m.metallic)
		for c in n.get_children():
			stack.append(c)
