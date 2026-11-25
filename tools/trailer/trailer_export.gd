extends RefCounted
## Exporta lo que pasa en una escena del trailer como una ESCENA GLB con ANIMACIONES para Blender (no un video):
##   Mapa/        el escenario tal como estaba al empezar (mallas con materiales estándar, texturas incluidas)
##   Actor_N/     cada personaje (esqueleto + malla con la piel) con su posición y la pose de cada hueso en el tiempo
##   Arma_N/      las armas que llevan, con su posición y cuándo están a la vista
##   Miembro_N/   los miembros arrancados (aparecen cuando se desprenden y caen con su física)
##   Camara       la cámara del juego en el tiempo
## La animación se llama «escena»: 30 cuadros por segundo, comprimida (Animation.optimize). Los sonidos, los disparos y los
## impactos quedan aparte (sonidos.csv / disparos.csv) con el segundo exacto, para sumarlos en Blender.

const FPS := 30.0
var game                       ## TrailerGame (sin tipo: las dos clases se nombran entre sí)
var root: Node3D
var anim := Animation.new()
var _actors: Array = []          ## [{actor, wrapper, skel, bones: PackedInt32Array, tracks_rot, tracks_scale, ...}]
var _weapons: Array = []
var _limbs := {}                 ## instance_id → {node, wrapper, t_track...}
var _cam: Node3D
var _cam_tracks := [0, 0]
var hits: Array = []
var shots: Array = []
var _t := 0.0

func begin(g, actors: Array) -> void:
	game = g
	root = Node3D.new()
	root.name = "EscenaTrailer"
	g.add_child(root)
	anim.length = 0.0
	anim.loop_mode = Animation.LOOP_NONE
	if not game.no_map:
		_build_map()
	for a in actors:
		_add_actor(a)
	_cam = Node3D.new()
	_cam.name = "Camara"
	var cam := Camera3D.new()
	cam.name = "Camara3D"
	cam.fov = g.camera.base_fov
	cam.near = 0.1
	cam.far = 200.0
	_cam.add_child(cam)
	root.add_child(_cam)
	_cam_tracks = [_pos_track("Camara"), _rot_track("Camara")]
	g.ballistics.projectile_hit.connect(func(_i, info: Dictionary):
		var sh = info.get("shooter")
		hits.append({"t": _t, "x": (info.point as Vector3).x, "y": (info.point as Vector3).y, "z": (info.point as Vector3).z,
			"nx": (info.normal as Vector3).x, "ny": (info.normal as Vector3).y, "nz": (info.normal as Vector3).z,
			"zona": str(info.get("zone", "")), "daño": snappedf(float(info.get("damage", 0.0)), 0.1),
			"quien": str(sh.name) if sh is Node else "", "tipo": str(info.get("type", "mundo"))}))

# ------------------------------------------------------------------------------------------------ construcción

static var _whites := {}
## Estilo del juego: todo en blanco / gris claro, sin texturas ni colores (las líneas se agregan en Blender). tono = brillo.
static func _white(tone: float) -> StandardMaterial3D:
	var k := int(tone * 100.0)
	if not _whites.has(k):
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(tone, tone, tone * 0.985)
		sm.roughness = 1.0
		sm.metallic = 0.0
		sm.metallic_specular = 0.2
		_whites[k] = sm
	return _whites[k]

static func _std_mat(m: Material, tone := 0.92) -> Material:
	return _white(tone)

static func _std_mat_old(m: Material) -> Material:
	if m == null or m is BaseMaterial3D:
		return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.78, 0.78, 0.78)
	if m is ShaderMaterial:
		for u in (m as ShaderMaterial).shader.get_shader_uniform_list():
			var v = (m as ShaderMaterial).get_shader_parameter(u.name)
			if v is Texture2D and "albedo" in str(u.name) or (v is Texture2D and str(u.name) in ["tex", "texture"]):
				sm.albedo_texture = v
			elif v is Color and ("albedo" in str(u.name) or str(u.name) == "color"):
				sm.albedo_color = v
	return sm

static func _copy_mesh_instance(src: MeshInstance3D, tone := 0.92) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	for s in src.mesh.get_surface_count():
		var m: Material = src.get_surface_override_material(s)
		if m == null and src.material_override:
			m = src.material_override
		if m == null:
			m = src.mesh.surface_get_material(s)
		mi.set_surface_override_material(s, _std_mat(m, tone))
	return mi

func _build_map() -> void:
	var map := Node3D.new()
	map.name = "Mapa"
	root.add_child(map)
	var n := 0
	for node in game.tower.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or mi.get_parent() is Skeleton3D or mi.has_meta("no_export") or (mi.has_meta("no_tech") and bool(mi.get_meta("no_tech"))):
			continue
		var p: Node = mi
		var skip := false
		while p:
			if p is Actor or p is Blood or p is Limb or p is Ballistics:
				skip = true
				break
			p = p.get_parent()
		if skip:
			continue
		var c := _copy_mesh_instance(mi)
		c.name = "malla_%d" % n
		n += 1
		map.add_child(c)
		c.global_transform = mi.global_transform
	print("EXPORT mapa: ", n, " mallas")

func _pos_track(path: String) -> int:
	var t := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(t, NodePath(path))
	return t

func _rot_track(path: String) -> int:
	var t := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(t, NodePath(path))
	return t

func _scale_track(path: String) -> int:
	var t := anim.add_track(Animation.TYPE_SCALE_3D)
	anim.track_set_path(t, NodePath(path))
	return t

func add_actor(a: Actor, t_spawn := 0.0) -> void:
	_add_actor(a, t_spawn)

func _add_actor(a: Actor, t_spawn := 0.0) -> void:
	var w := Node3D.new()
	w.name = "Actor_%d_%s" % [_actors.size(), str(a.character_id)]
	root.add_child(w)
	var model := a.model.duplicate(0) as Node3D
	model.name = "Modelo"
	model.transform = Transform3D.IDENTITY
	w.add_child(model)
	for c in model.find_children("*", "", true, false):
		if c is AnimationPlayer or c is AnimationTree or c is BoneAttachment3D or c is SkeletonModifier3D or c is Area3D or c is CollisionShape3D \
				or c is Light3D or c is Label3D or c is GPUParticles3D or c is CPUParticles3D:
			c.get_parent().remove_child(c)
			c.queue_free()
	var sk := model.get_node("Skeleton3D") as Skeleton3D
	for mi in sk.get_children():
		if mi is MeshInstance3D:
			for s in (mi as MeshInstance3D).mesh.get_surface_count():
				var m := (mi as MeshInstance3D).get_active_material(s)
				(mi as MeshInstance3D).set_surface_override_material(s, _std_mat(m))
	var base := "%s/Modelo/Skeleton3D" % w.name
	var d := {"actor": a, "wrapper": w, "sk_src": a.skel, "n": sk.get_bone_count(), "rot": [], "scale": {}, "base": base,
		"pos_t": _pos_track(w.name), "rot_t": _rot_track(w.name), "hips_t": -1}
	for b in sk.get_bone_count():
		d.rot.append(_rot_track("%s:%s" % [base, sk.get_bone_name(b)]))
	d.hips_t = _pos_track("%s:%s" % [base, "mixamorig_Hips"])
	_actors.append(d)
	if t_spawn > 0.0:
		_appear(w.name, t_spawn)

## El nodo está escondido (escala casi cero) hasta el momento en que aparece en la escena.
func _appear(node_name: String, t: float) -> void:
	var st := _scale_track(node_name)
	anim.scale_track_insert_key(st, 0.0, Vector3.ONE * 0.0001)
	anim.scale_track_insert_key(st, maxf(t - 1.0 / FPS, 0.0), Vector3.ONE * 0.0001)
	anim.scale_track_insert_key(st, t, Vector3.ONE)

func _track_weapons(a: Actor, t: float) -> void:
	for slot in a.weapons:
		var f = a.weapons[slot]
		if not is_instance_valid(f) or f.model == null or _weapon_ids.has(f.get_instance_id()):
			continue
		_weapon_ids[f.get_instance_id()] = true
		var ww := Node3D.new()
		ww.name = "Arma_%d_%s" % [_weapons.size(), f.id]
		root.add_child(ww)
		for mi in f.model.find_children("*", "MeshInstance3D", true, false):
			var c := _copy_mesh_instance(mi as MeshInstance3D, 0.16)
			ww.add_child(c)
			c.global_transform = f.model.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		var wd := {"f": f, "w": ww, "pt": _pos_track(ww.name), "rt": _rot_track(ww.name), "st": _scale_track(ww.name), "gone": false}
		anim.scale_track_insert_key(wd.st, 0.0, Vector3.ONE * 0.0001)
		_weapons.append(wd)

var _weapon_ids := {}

# ------------------------------------------------------------------------------------------------ captura (cada cuadro)

func capture(t: float) -> void:
	_t = t
	anim.length = maxf(anim.length, t)
	for d in _actors:
		var a = d.actor
		if not is_instance_valid(a):
			continue
		var m: Transform3D = a.model.global_transform
		anim.position_track_insert_key(d.pos_t, t, m.origin)
		anim.rotation_track_insert_key(d.rot_t, t, m.basis.orthonormalized().get_rotation_quaternion())
		var sk: Skeleton3D = d.sk_src
		for b in d.n:
			anim.rotation_track_insert_key(d.rot[b], t, sk.get_bone_pose_rotation(b))
			var sc := sk.get_bone_pose_scale(b)
			if not (d.scale as Dictionary).has(b):
				if sc.x < 0.5:
					var tr := _scale_track("%s:%s" % [d.base, sk.get_bone_name(b)])
					d.scale[b] = tr
					anim.scale_track_insert_key(tr, 0.0, Vector3.ONE)
					anim.scale_track_insert_key(tr, t, sc)
			else:
				anim.scale_track_insert_key(d.scale[b], t, sc)
		anim.position_track_insert_key(d.hips_t, t, sk.get_bone_pose_position(sk.find_bone("mixamorig_Hips")))
	for d in _actors:
		if is_instance_valid(d.actor):
			_track_weapons(d.actor, t)
	for wd in _weapons:
		var f = wd.f
		if not is_instance_valid(f) or f.model == null:
			if not wd.gone:
				wd.gone = true
				anim.scale_track_insert_key(wd.st, t, Vector3.ONE * 0.0001)
			continue
		var gt: Transform3D = f.model.global_transform
		anim.position_track_insert_key(wd.pt, t, gt.origin)
		anim.rotation_track_insert_key(wd.rt, t, gt.basis.orthonormalized().get_rotation_quaternion())
		anim.scale_track_insert_key(wd.st, t, Vector3.ONE if f.is_visible_in_tree() else Vector3.ONE * 0.0001)
	var cam: Camera3D = game.get_viewport().get_camera_3d()
	if cam:
		anim.position_track_insert_key(_cam_tracks[0], t, cam.global_position)
		anim.rotation_track_insert_key(_cam_tracks[1], t, cam.global_basis.orthonormalized().get_rotation_quaternion())
	# miembros arrancados: aparecen cuando se desprenden
	for a in _actors:
		var par: Node = (a.actor as Actor).get_parent()
		if par == null:
			continue
		for n in par.get_children():
			if n is Limb and not _limbs.has(n.get_instance_id()):
				var lw := Node3D.new()
				lw.name = "Miembro_%d" % _limbs.size()
				root.add_child(lw)
				var cm := MeshInstance3D.new()
				cm.mesh = (n as Limb).suit.mesh
				for s in cm.mesh.get_surface_count():
					cm.set_surface_override_material(s, cm.mesh.surface_get_material(s) if s == cm.mesh.get_surface_count() - 1 else _white(0.92))
				lw.add_child(cm)
				var ld := {"n": n, "pt": _pos_track(lw.name), "rt": _rot_track(lw.name), "st": _scale_track(lw.name)}
				anim.scale_track_insert_key(ld.st, 0.0, Vector3.ONE * 0.0001)
				anim.scale_track_insert_key(ld.st, maxf(t - 1.0 / FPS, 0.0), Vector3.ONE * 0.0001)
				anim.scale_track_insert_key(ld.st, t, Vector3.ONE)
				_limbs[n.get_instance_id()] = ld
	for id in _limbs:
		var ld: Dictionary = _limbs[id]
		if is_instance_valid(ld.n):
			var ln := ld.n as Limb
			anim.position_track_insert_key(ld.pt, t, ln.global_position)
			anim.rotation_track_insert_key(ld.rt, t, ln.global_basis.orthonormalized().get_rotation_quaternion())

func export_to(path: String) -> bool:
	anim.optimize(0.01, 0.02, 3)
	var ap := AnimationPlayer.new()
	ap.name = "Animaciones"
	root.add_child(ap)
	ap.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	lib.add_animation("escena", anim)
	ap.add_animation_library("", lib)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	state.bake_fps = FPS
	var err := doc.append_from_scene(root, state, 0)
	if err != OK:
		push_error("GLB: append_from_scene falló (%d)" % err)
		return false
	err = doc.write_to_filesystem(state, path)
	print("EXPORT glb: ", path, " err=", err, " pistas=", anim.get_track_count(), " duración=", anim.length)
	return err == OK
