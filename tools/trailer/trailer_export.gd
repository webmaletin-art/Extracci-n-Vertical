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
var _blood: Array = []            ## [{t, p, dir, n, life}] chorros de sangre (se arman al exportar)
var _anat_mats := {}
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
	RenderingServer.frame_pre_draw.connect(func(): if is_instance_valid(game): capture(game.vt))
	g.ballistics.projectile_hit.connect(func(_i, info: Dictionary):
		var sh = info.get("shooter")
		hits.append({"t": _t, "x": (info.point as Vector3).x, "y": (info.point as Vector3).y, "z": (info.point as Vector3).z,
			"nx": (info.normal as Vector3).x, "ny": (info.normal as Vector3).y, "nz": (info.normal as Vector3).z,
			"zona": str(info.get("zone", "")), "daño": snappedf(float(info.get("damage", 0.0)), 0.1),
			"quien": str(sh.name) if sh is Node else "", "tipo": str(info.get("type", "mundo"))})
		if str(info.get("zone", "")) != "":
			var dmg := float(info.get("damage", 20.0))
			_blood.append({"t": _t, "p": info.point, "dir": info.dir, "n": int(clampf(10.0 + dmg * 0.5, 12.0, 40.0)), "life": 1.1, "pw": clampf(dmg / 30.0, 0.6, 2.5)}))

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
	for node in game.map_root.find_children("*", "MeshInstance3D", true, false):
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
		d["sc_t"] = _appear(w.name, t_spawn)
		_add_anatomy(d, a, sk)
	a.dismembered.connect(func(_j, info: Dictionary):
		var c: Vector3 = (info.point as Vector3) if info.has("point") else a.global_position + Vector3(0, 1.2, 0)
		for k in 4:
			_blood.append({"t": _t + 0.28 * k, "p": c, "dir": info.get("dir", Vector3.RIGHT), "n": 46 - k * 8, "life": 1.4, "pw": 2.4 - k * 0.4}))

## Anatomía del personaje (huesos, órganos y vasos) en un segundo esqueleto con los mismos movimientos. Aparece (y el traje
## desaparece) mientras el juego muestra los rayos X de ese cuerpo.
func _add_anatomy(d: Dictionary, a: Actor, sk_dup: Skeleton3D) -> void:
	var anat := AnatomyBody.for_actor(a)
	if not anat.available or anat.skin == null:
		return
	var aw := Node3D.new()
	aw.name = "Anatomia"
	(d.wrapper as Node3D).add_child(aw)
	var sk2 := Skeleton3D.new()
	sk2.name = "Skeleton3D"
	aw.add_child(sk2)
	for b in sk_dup.get_bone_count():
		sk2.add_bone(sk_dup.get_bone_name(b))
	for b in sk_dup.get_bone_count():
		sk2.set_bone_parent(b, sk_dup.get_bone_parent(b))
		sk2.set_bone_rest(b, sk_dup.get_bone_rest(b))
	sk2.reset_bone_poses()
	var n := 0
	for g in anat.groups.values():
		var sysn := str(g.system)
		var mi := MeshInstance3D.new()
		mi.name = "%s_%s" % [sysn, str(g.label).replace(" ", "_")]       # en Blender se agrupan / ocultan por sistema (hueso_, musculo_, organo_, vaso_, nervio_)
		mi.mesh = g.mesh
		mi.skin = anat.skin
		mi.transform = anat.mesh_xf
		mi.set_surface_override_material(0, _anat_mat(sysn, str(g.label)))
		sk2.add_child(mi)
		mi.skeleton = NodePath("..")
		n += 1
	var base2 := "%s/Anatomia/Skeleton3D" % (d.wrapper as Node3D).name
	d["rot2"] = []
	for b in sk2.get_bone_count():
		d.rot2.append(_rot_track("%s:%s" % [base2, sk2.get_bone_name(b)]))
	d["hips2"] = _pos_track("%s:%s" % [base2, "mixamorig_Hips"])
	d["an_scale"] = _scale_track("%s/Anatomia" % (d.wrapper as Node3D).name)
	d["suit_scale"] = _scale_track("%s/Modelo" % (d.wrapper as Node3D).name)
	d["xon"] = false
	anim.scale_track_insert_key(d.an_scale, 0.0, Vector3.ONE * 0.0001)
	anim.scale_track_insert_key(d.suit_scale, 0.0, Vector3.ONE)
	d["anat"] = anat
	print("EXPORT anatomía: ", n, " estructuras para ", a.name)

func _anat_mat(sysn: String, label: String) -> StandardMaterial3D:
	var key := sysn + ("" if sysn != "organo" else label.get_slice(" ", 0))
	if not _anat_mats.has(key):
		var m := StandardMaterial3D.new()
		var c: Color = AnatomyBody.SYS_COLOR.get(sysn, Color(0.9, 0.85, 0.7))
		if sysn == "musculo":
			c = Color(0.62, 0.1, 0.08, 0.5)                   # la carne es translúcida: dejan verse los huesos y los órganos
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if sysn == "organo":
			for k in AnatomyBody.ORGAN_COLOR:
				if label.begins_with(k):
					c = AnatomyBody.ORGAN_COLOR[k]
		m.albedo_color = c
		m.roughness = 0.55
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_anat_mats[key] = m
	return _anat_mats[key]

## El nodo está escondido (escala casi cero) hasta el momento en que aparece en la escena.
func _appear(node_name: String, t: float) -> int:
	var st := _scale_track(node_name)
	anim.scale_track_insert_key(st, 0.0, Vector3.ONE * 0.0001)
	anim.scale_track_insert_key(st, maxf(t - 1.0 / FPS, 0.0), Vector3.ONE * 0.0001)
	anim.scale_track_insert_key(st, t, Vector3.ONE)
	return st

## El personaje sale de la escena (fin de la ronda): se esconde y deja de grabarse.
func remove_actor(a: Actor, t: float) -> void:
	for d in _actors:
		if d.actor == a and d.has("sc_t") and not d.get("gone", false):
			d["gone"] = true
			anim.scale_track_insert_key(d.sc_t, t, Vector3.ONE)
			anim.scale_track_insert_key(d.sc_t, t + 1.0 / FPS, Vector3.ONE * 0.0001)

## Fin de una ronda: la sangre del piso y los miembros se limpian a partir de este momento.
var _clear_times: Array = []
func clear_round(t: float) -> void:
	_clear_times.append(t)
	for id in _limbs:
		var ld: Dictionary = _limbs[id]
		if not ld.get("gone", false):
			ld["gone"] = true
			anim.scale_track_insert_key(ld.st, t, Vector3.ONE)
			anim.scale_track_insert_key(ld.st, t + 1.0 / FPS, Vector3.ONE * 0.0001)

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
		if not is_instance_valid(a) or d.get("gone", false):
			continue
		var m: Transform3D = a.model.global_transform
		anim.position_track_insert_key(d.pos_t, t, m.origin)
		anim.rotation_track_insert_key(d.rot_t, t, m.basis.orthonormalized().get_rotation_quaternion())
		var sk: Skeleton3D = d.sk_src
		# se toma la pose FINAL (global, con la IK de los brazos y el arma ya aplicadas) y se la pasa a local de cada hueso
		var globs: Array = []
		globs.resize(d.n)
		for b in d.n:
			globs[b] = sk.get_bone_global_pose(b)
		# lo que realmente se dibuja (con la IK de los brazos y el arma): las matrices de piel que recibe el renderizador
		if not d.has("skin_mi"):
			d["skin_mi"] = null
			for c in sk.get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).skin != null and c.has_meta("actor_mesh"):
					d["skin_mi"] = c
					break
		var smi = d.skin_mi
		if smi != null and is_instance_valid(smi):
			var sref: SkinReference = (smi as MeshInstance3D).get_skin_reference()
			if sref != null:
				var skn: Skin = (smi as MeshInstance3D).skin
				for i in skn.get_bind_count():
					var bb := skn.get_bind_bone(i)
					if bb < 0:
						bb = sk.find_bone(str(skn.get_bind_name(i)).replace(":", "_"))
					if bb >= 0 and bb < d.n:
						var sm: Transform3D = RenderingServer.skeleton_bone_get_transform(sref.get_skeleton(), i)
						globs[bb] = sm * skn.get_bind_pose(i).affine_inverse()
		var locs: Array = []
		locs.resize(d.n)
		for b in d.n:
			var pb := sk.get_bone_parent(b)
			locs[b] = ((globs[pb] as Transform3D).affine_inverse() * (globs[b] as Transform3D)) if pb >= 0 else globs[b]
		d["locs"] = locs
		for b in d.n:
			var lt: Transform3D = locs[b]
			anim.rotation_track_insert_key(d.rot[b], t, lt.basis.orthonormalized().get_rotation_quaternion())
			var sc: Vector3 = lt.basis.get_scale()
			if not (d.scale as Dictionary).has(b):
				if sc.x < 0.5:
					var tr := _scale_track("%s:%s" % [d.base, sk.get_bone_name(b)])
					d.scale[b] = tr
					anim.scale_track_insert_key(tr, 0.0, Vector3.ONE)
					anim.scale_track_insert_key(tr, t, sc)
			else:
				anim.scale_track_insert_key(d.scale[b], t, sc)
		anim.position_track_insert_key(d.hips_t, t, (locs[sk.find_bone("mixamorig_Hips")] as Transform3D).origin)
		if not d.has("pos_tr"):
			d["pos_tr"] = {}
		for b in d.n:
			var po: Vector3 = (locs[b] as Transform3D).origin
			var pr: Vector3 = sk.get_bone_rest(b).origin
			if (d.pos_tr as Dictionary).has(b):
				anim.position_track_insert_key(d.pos_tr[b], t, po)
			elif po.distance_to(pr) > 0.002 and sk.get_bone_name(b) != "mixamorig_Hips":
				var ptr := _pos_track("%s:%s" % [d.base, sk.get_bone_name(b)])
				d.pos_tr[b] = ptr
				anim.position_track_insert_key(ptr, 0.0, pr)
				anim.position_track_insert_key(ptr, t, po)
		if d.has("rot2"):
			for b in d.n:
				anim.rotation_track_insert_key(d.rot2[b], t, (d.locs[b] as Transform3D).basis.orthonormalized().get_rotation_quaternion())
			anim.position_track_insert_key(d.hips2, t, (d.locs[sk.find_bone("mixamorig_Hips")] as Transform3D).origin)
			var on: bool = is_instance_valid(d.anat) and d.anat._showing
			if on != d.xon:
				print("RAYOSX ", d.wrapper.name, " t=", snappedf(t, 0.01), " visible=", on)
				d.xon = on
				var t0 := maxf(t - 1.0 / FPS, 0.0)
				anim.scale_track_insert_key(d.an_scale, t0, Vector3.ONE * (0.0001 if on else 1.0))
				anim.scale_track_insert_key(d.an_scale, t, Vector3.ONE * (1.0 if on else 0.0001))
				anim.scale_track_insert_key(d.suit_scale, t0, Vector3.ONE * (1.0 if on else 0.0001))
				anim.scale_track_insert_key(d.suit_scale, t, Vector3.ONE * (0.0001 if on else 1.0))
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
		if not is_instance_valid(a.actor):
			continue
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
				cm.name = "Traje"
				lw.add_child(cm)
				var ld := {"n": n, "pt": _pos_track(lw.name), "rt": _rot_track(lw.name), "st": _scale_track(lw.name), "owner": a, "lx": false}
				for dd in _actors:
					if dd.get("anat") != null and dd.get("anat") == (n as Limb).anat:
						ld["owner"] = dd
				if (n as Limb).xray != null:
					var xm := MeshInstance3D.new()
					xm.name = "Anatomia"
					xm.mesh = (n as Limb).xray.mesh
					lw.add_child(xm)
					ld["xt"] = _scale_track("%s/Anatomia" % lw.name)
					ld["tt"] = _scale_track("%s/Traje" % lw.name)
					anim.scale_track_insert_key(ld.xt, 0.0, Vector3.ONE * 0.0001)
					anim.scale_track_insert_key(ld.tt, 0.0, Vector3.ONE)
				anim.scale_track_insert_key(ld.st, 0.0, Vector3.ONE * 0.0001)
				anim.scale_track_insert_key(ld.st, maxf(t - 1.0 / FPS, 0.0), Vector3.ONE * 0.0001)
				anim.scale_track_insert_key(ld.st, t, Vector3.ONE)
				_limbs[n.get_instance_id()] = ld
	for id in _limbs:
		var ld: Dictionary = _limbs[id]
		if is_instance_valid(ld.n) and not ld.get("gone", false):
			var ln := ld.n as Limb
			if ld.has("xt"):
				var xo: bool = ld.owner.get("xon", false)
				if xo != ld.lx:
					ld.lx = xo
					var tp := maxf(t - 1.0 / FPS, 0.0)
					anim.scale_track_insert_key(ld.xt, tp, Vector3.ONE * (0.0001 if xo else 1.0))
					anim.scale_track_insert_key(ld.xt, t, Vector3.ONE * (1.0 if xo else 0.0001))
					anim.scale_track_insert_key(ld.tt, tp, Vector3.ONE * (1.0 if xo else 0.0001))
					anim.scale_track_insert_key(ld.tt, t, Vector3.ONE * (0.0001 if xo else 1.0))
			anim.position_track_insert_key(ld.pt, t, ln.global_position)
			anim.rotation_track_insert_key(ld.rt, t, ln.global_basis.orthonormalized().get_rotation_quaternion())

## Sangre: gotas con caída real (balística simple) que salen de cada impacto / miembro arrancado, y manchas donde caen.
func _build_blood() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var sm := SphereMesh.new()
	sm.radius = 0.013
	sm.height = 0.026
	sm.radial_segments = 6
	sm.rings = 3
	var dm := CylinderMesh.new()
	dm.top_radius = 0.06
	dm.bottom_radius = 0.06
	dm.height = 0.004
	dm.radial_segments = 10
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.55, 0.02, 0.03)
	red.roughness = 0.2
	sm.material = red
	dm.material = red
	var droplet := 0
	for ev in _blood:
		var p0: Vector3 = ev.p
		var dir: Vector3 = (ev.dir as Vector3).normalized()
		var floor_y: float = floor(p0.y / 4.5) * 4.5 + 0.03
		for k in int(ev.n):
			var v := dir * rng.randf_range(1.5, 5.5) * float(ev.pw) + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 3.5), rng.randf_range(-0.6, 0.6))
			if k % 3 == 0:
				v = -dir * rng.randf_range(0.8, 2.5) + Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 2.0), rng.randf_range(-0.4, 0.4))
			var n := MeshInstance3D.new()
			n.name = "Sangre_%d" % droplet
			droplet += 1
			n.mesh = sm
			root.add_child(n)
			var pt := _pos_track(n.name)
			var st := _scale_track(n.name)
			var t0: float = ev.t
			anim.scale_track_insert_key(st, 0.0, Vector3.ONE * 0.0001)
			anim.scale_track_insert_key(st, maxf(t0 - 1.0 / FPS, 0.0), Vector3.ONE * 0.0001)
			anim.scale_track_insert_key(st, t0, Vector3.ONE * rng.randf_range(0.6, 1.6))
			var land := -1.0
			var tau := 0.0
			while tau <= float(ev.life) + 0.001:
				var p := p0 + v * tau + Vector3(0, -4.9 * tau * tau, 0)
				if p.y <= floor_y:
					p.y = floor_y
					if land < 0.0:
						land = tau
				anim.position_track_insert_key(pt, t0 + tau, p)
				if land >= 0.0:
					break
				tau += 1.0 / 15.0
			if land >= 0.0:
				var lp := p0 + v * land + Vector3(0, -4.9 * land * land, 0)
				anim.scale_track_insert_key(st, t0 + land, Vector3.ONE * 0.0001)
				if k % 2 == 0:
					var sp := MeshInstance3D.new()
					sp.name = "Mancha_%d" % droplet
					sp.mesh = dm
					root.add_child(sp)
					sp.position = Vector3(lp.x, floor_y, lp.z)
					var ss := _scale_track(sp.name)
					var sz := rng.randf_range(0.5, 1.8)
					anim.scale_track_insert_key(ss, 0.0, Vector3.ONE * 0.0001)
					anim.scale_track_insert_key(ss, maxf(t0 + land - 1.0 / FPS, 0.0), Vector3.ONE * 0.0001)
					anim.scale_track_insert_key(ss, t0 + land, Vector3(sz, 1, sz))
					for ct in _clear_times:
						if ct > t0 + land:
							anim.scale_track_insert_key(ss, ct, Vector3(sz, 1, sz))
							anim.scale_track_insert_key(ss, ct + 1.0 / FPS, Vector3.ONE * 0.0001)
							break
					# (nodo estático con escala animada: su posición se guarda con una pista fija)
					var ps := _pos_track(sp.name)
					anim.position_track_insert_key(ps, 0.0, sp.position)
	print("EXPORT sangre: ", droplet, " gotas")

func export_to(path: String) -> bool:
	_build_blood()
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
