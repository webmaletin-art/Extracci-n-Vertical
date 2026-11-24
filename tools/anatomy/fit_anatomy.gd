extends SceneTree
## Ajusta la anatomía (tools/anatomy/anatomy_src.glb, de Z-Anatomy) DENTRO de cada personaje y la convierte en mallas con
## piel que usan el MISMO esqueleto y los MISMOS pesos que el personaje: así se deforman juntos en cualquier animación.
##
## Uso:  godot --headless --path . -s tools/anatomy/fit_anatomy.gd -- [id ...]      (sin ids: todos los de data/characters.json)
## Salida: assets/anatomy/fit/<id>.scn (+ informe en la consola: cuánto quedaba afuera y cuánto queda después).
##
## Pasos por personaje (todo en el espacio del esqueleto):
##  1. Pose anatómica: se bajan los brazos (y se acomodan las piernas) del personaje hasta las direcciones de la anatomía.
##  2. Mapeo anatomía → personaje: torso y cabeza con escala + traslación (caderas y hombros); brazos y piernas por
##     segmento articulación → articulación (hombro-codo, codo-muñeca, muñeca-dedos, cadera-rodilla, rodilla-tobillo).
##  3. Adentro de la piel: para cada vértice se lanza un rayo desde el eje del hueso hacia el vértice; si el vértice queda
##     más allá de la piel menos MARGIN, se lo trae hacia adentro.
##  4. Pesos de piel: los del vértice del personaje más cercano de la MISMA región (torso / brazo / pierna), así una
##     costilla no queda atada al brazo.
##  5. Piel inversa: posición de enlace = (Σ peso · pose · enlace)⁻¹ · posición en la pose anatómica.
##  6. Verificación en la pose de enlace (T) y en poses de animación reales (apuntar, correr, agachado, escalera, colgado):
##     lo que asome se vuelve a meter, y se informa el resultado.

const SRC := "res://tools/anatomy/anatomy_src.glb"
const GROUPS := "res://tools/anatomy/anatomy_groups.json"
const FRAG := "res://tools/anatomy/anatomy_frag.glb"           ## huesos rotos en Blender (fracture_bones.py)
const FRAGS := "res://tools/anatomy/anatomy_frags.json"
const OUT_DIR := "res://assets/anatomy/fit/"
const MARGIN := 0.008
const P := "mixamorig_"
const CHECK_ANIMS := [["idle_aim", 0.0], ["run_f", 0.2], ["crouch_aim", 0.0], ["ladder_climb", 0.3], ["hang_idle", 0.5], ["death_fall_back", 1.5], ["kick_front", 0.45]]

var space: PhysicsDirectSpaceState3D
var body_rid: RID
var shape_rid: RID

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty():
		for c in CharacterModel.all():
			ids.append(str(c.id))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var src := _load_src()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GROUPS))
	# fragmentos de hueso: se ajustan igual que su hueso (mismo hueso Mixamo y región)
	if FileAccess.file_exists(FRAGS):
		var fsrc := _load_src(FRAG)
		var by_node := {}
		for g in meta.groups:
			by_node[str(g.node)] = g
		var fm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FRAGS))
		for f in fm.fragments:
			var par: Dictionary = by_node.get(str(f.parent), {})
			if par.is_empty() or not fsrc.has(str(f.node)):
				continue
			par["has_frags"] = true
			src[str(f.node)] = fsrc[str(f.node)]
			meta.groups.append({"node": f.node, "label": par.label, "system": "hueso", "bone": par.bone, "parent": f.parent})
	# cuerpo estático para los rayos contra la piel del personaje
	space = PhysicsServer3D.space_get_direct_state(root.get_world_3d().space)
	body_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body_rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body_rid, root.get_world_3d().space)
	shape_rid = PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.body_add_shape(body_rid, shape_rid)
	for id in ids:
		var t0 := Time.get_ticks_msec()
		await _fit(str(id), src, meta)
		print("  %s listo en %.1f s" % [id, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()

func _load_src(path := SRC) -> Dictionary:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path(path), st)
	var scene := doc.generate_scene(st)
	var out := {}
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var arr := m.mesh.surface_get_arrays(0)
		var xf := m.global_transform if m.is_inside_tree() else _acc(m)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var vv := PackedVector3Array()
		vv.resize(v.size())
		for i in v.size():
			vv[i] = xf * v[i]
		out[str(m.name)] = {"v": vv, "i": arr[Mesh.ARRAY_INDEX], "c": arr[Mesh.ARRAY_COLOR]}
	scene.free()
	return out

func _acc(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c := n
	while c:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

# ---------------------------------------------------------------- utilidades de piel

class SkinData:
	var verts: PackedVector3Array
	var bones: PackedInt32Array
	var weights: PackedFloat32Array
	var idx: PackedInt32Array
	var bind: Array[Transform3D] = []
	var bind_bone: PackedInt32Array = []

func _skin_data(mi: MeshInstance3D, sk: Skeleton3D) -> SkinData:
	var d := SkinData.new()
	var a := mi.mesh.surface_get_arrays(0)
	d.verts = a[Mesh.ARRAY_VERTEX]
	d.bones = a[Mesh.ARRAY_BONES]
	d.weights = a[Mesh.ARRAY_WEIGHTS]
	d.idx = a[Mesh.ARRAY_INDEX]
	for i in mi.skin.get_bind_count():
		d.bind.append(mi.skin.get_bind_pose(i))
		var b := mi.skin.get_bind_bone(i)
		if b < 0:
			b = sk.find_bone(str(mi.skin.get_bind_name(i)).replace(":", "_"))
		d.bind_bone.append(b)
	return d

func _mats(d: SkinData, pose: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in d.bind.size():
		out.append((pose[d.bind_bone[i]] as Transform3D) * d.bind[i])
	return out

static func _blend(mats: Array[Transform3D], b: PackedInt32Array, w: PackedFloat32Array, o: int) -> Transform3D:
	var t := Transform3D()
	t.basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	t.origin = Vector3.ZERO
	for k in 4:
		var ww := w[o + k]
		if ww <= 0.0:
			continue
		var m := mats[b[o + k]]
		t.basis.x += m.basis.x * ww
		t.basis.y += m.basis.y * ww
		t.basis.z += m.basis.z * ww
		t.origin += m.origin * ww
	return t

func _skin_all(d: SkinData, mats: Array[Transform3D]) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(d.verts.size())
	for i in d.verts.size():
		out[i] = _blend(mats, d.bones, d.weights, i * 4) * d.verts[i]
	return out

func _set_collision(posed: PackedVector3Array, idx: PackedInt32Array) -> void:
	var faces := PackedVector3Array()
	faces.resize(idx.size())
	for i in idx.size():
		faces[i] = posed[idx[i]]
	PhysicsServer3D.shape_set_data(shape_rid, {"faces": faces, "backface_collision": true})
	await physics_frame
	await physics_frame

## Distancia desde c en la dirección dir hasta la piel (o INF).
func _skin_dist(c: Vector3, dir: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(c, c + dir * 1.2)
	q.hit_back_faces = true
	q.hit_from_inside = false
	var h := space.intersect_ray(q)
	if h.is_empty():
		return INF
	return c.distance_to(h.position)

# ---------------------------------------------------------------- regiones y ejes

const REGION_BONES := {
	"armL": ["LeftArm", "LeftForeArm", "LeftHand"], "armR": ["RightArm", "RightForeArm", "RightHand"],
	"legL": ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"], "legR": ["RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"],
}

static func region_of_bone(n: String) -> String:
	n = n.replace(P, "")
	for r in REGION_BONES:
		for b in REGION_BONES[r]:
			if n.begins_with(b):
				return r
	return "torso"

## Eje (cadena de segmentos) de una región en una pose: lista de [a, b].
func _axis(sk: Skeleton3D, pose: Array, region: String) -> Array:
	var chain: Array
	match region:
		"armL": chain = ["LeftArm", "LeftForeArm", "LeftHand", "LeftHandMiddle3"]
		"armR": chain = ["RightArm", "RightForeArm", "RightHand", "RightHandMiddle3"]
		"legL": chain = ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "LeftToe_End"]
		"legR": chain = ["RightUpLeg", "RightLeg", "RightFoot", "RightToeBase", "RightToe_End"]
		_: chain = ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]
	var pts := []
	for b in chain:
		var i := sk.find_bone(P + b)
		if i >= 0:
			pts.append((pose[i] as Transform3D).origin)
	var segs := []
	for k in pts.size() - 1:
		segs.append([pts[k], pts[k + 1]])
	return segs

## Punto más cercano sobre el segmento del propio hueso (de su origen al de su primer hijo).
static func _closest_on_bone(sk: Skeleton3D, pose: Array, b: int, p: Vector3) -> Vector3:
	var kids := sk.get_bone_children(b)
	var a: Vector3 = (pose[b] as Transform3D).origin
	var e: Vector3
	if kids.is_empty():
		var par := sk.get_bone_parent(b)
		e = a
		a = (pose[par] as Transform3D).origin if par >= 0 else a
	else:
		# hijo principal: el de la cadena (Spine2 → Neck, no los hombros)
		var best: int = kids[0]
		for k in kids:
			var n := sk.get_bone_name(k)
			if n.ends_with("Neck") or n.ends_with("Spine") or n.ends_with("Spine1") or n.ends_with("Spine2") or n.ends_with("HandMiddle1"):
				best = k
		e = (pose[best] as Transform3D).origin
	var ab := e - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
	return a + ab * t

static func _closest_on_axis(segs: Array, p: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
		var c := a + ab * t
		var dd := c.distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = c
	return best

func _poses_global(sk: Skeleton3D) -> Array:
	var out := []
	for i in sk.get_bone_count():
		out.append(sk.get_bone_global_pose(i))
	return out

## Gira el hueso `bone` (en pose global) para que el segmento hacia `child` apunte a `dir`.
func _aim_bone(sk: Skeleton3D, bone: String, child: String, dir: Vector3) -> void:
	var b := sk.find_bone(P + bone)
	var c := sk.find_bone(P + child)
	if b < 0 or c < 0:
		return
	var gb := sk.get_bone_global_pose(b)
	var gc := sk.get_bone_global_pose(c)
	var d0 := (gc.origin - gb.origin).normalized()
	var q := Quaternion(d0, dir.normalized())
	var local_parent := Transform3D.IDENTITY
	var p := sk.get_bone_parent(b)
	if p >= 0:
		local_parent = sk.get_bone_global_pose(p)
	var new_global := Transform3D(Basis(q) * gb.basis, gb.origin)
	sk.set_bone_pose_rotation(b, (local_parent.basis.inverse() * new_global.basis).get_rotation_quaternion())
	sk.force_update_all_bone_transforms()

# ---------------------------------------------------------------- ajuste

func _fit(id: String, src: Dictionary, meta: Dictionary) -> void:
	var model := CharacterModel.instantiate(id)
	root.add_child(model)
	var sk: Skeleton3D = model.get_node("Skeleton3D")
	var cmi: MeshInstance3D = null
	for mi in sk.get_children():
		if mi is MeshInstance3D and (mi as MeshInstance3D).skin:
			cmi = mi
	var sd := _skin_data(cmi, sk)
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	var rest := _poses_global(sk)
	var marks: Dictionary = meta.marks
	var vm := func(a: Array) -> Vector3: return Vector3(a[0], a[1], a[2])
	# --- 1. ajuste del cuerpo (escala por caderas-hombros, frente según los pies)
	var kp := func(n: String) -> Vector3: return (rest[sk.find_bone(P + n)] as Transform3D).origin
	var a_hip: Vector3 = (vm.call(marks.Left.hip) + vm.call(marks.Right.hip)) * 0.5
	var a_sh: Vector3 = (vm.call(marks.Left.shoulder) + vm.call(marks.Right.shoulder)) * 0.5
	var k_hip: Vector3 = (kp.call("LeftUpLeg") + kp.call("RightUpLeg")) * 0.5
	var k_sh: Vector3 = (kp.call("LeftArm") + kp.call("RightArm")) * 0.5
	var fwd: Vector3 = kp.call("LeftToeBase") - kp.call("LeftFoot")
	fwd.y = 0.0
	var rot := Basis(Quaternion(Vector3(0, 0, 1), fwd.normalized()))
	if (rot * Vector3.RIGHT).dot(kp.call("LeftUpLeg") - kp.call("RightUpLeg")) < 0.0:
		rot = rot * Basis(Vector3.UP, PI)
	var up := (rot.inverse() * (k_sh - k_hip)).normalized()
	var s := (k_sh - k_hip).length() / maxf((a_sh - a_hip).length(), 0.01)
	var body := Transform3D(rot.scaled(Vector3.ONE * s), Vector3.ZERO)
	body.origin = k_hip - body.basis * a_hip
	# --- 2. pose anatómica del personaje: brazos y piernas en la dirección de la anatomía
	for side in ["Left", "Right"]:
		var mk: Dictionary = marks[side]
		_aim_bone(sk, side + "Arm", side + "ForeArm", body.basis * (vm.call(mk.elbow) - vm.call(mk.shoulder)))
		_aim_bone(sk, side + "ForeArm", side + "Hand", body.basis * (vm.call(mk.wrist) - vm.call(mk.elbow)))
		_aim_bone(sk, side + "Hand", side + "HandMiddle1", body.basis * (vm.call(mk.tip) - vm.call(mk.wrist)))
		_aim_bone(sk, side + "UpLeg", side + "Leg", body.basis * (vm.call(mk.knee) - vm.call(mk.hip)))
		_aim_bone(sk, side + "Leg", side + "Foot", body.basis * (vm.call(mk.ankle) - vm.call(mk.knee)))
	var apose := _poses_global(sk)
	var amats := _mats(sd, apose)
	var cposed := _skin_all(sd, amats)
	await _set_collision(cposed, sd.idx)
	# regiones de los vértices del personaje (por el hueso de más peso) y grilla para buscar el más cercano
	var grids := {}
	for i in sd.verts.size():
		var bmax := 0
		for k in 4:
			if sd.weights[i * 4 + k] > sd.weights[i * 4 + bmax]:
				bmax = k
		var bn := sk.get_bone_name(sd.bind_bone[sd.bones[i * 4 + bmax]])
		var r := region_of_bone(bn)
		var g: Dictionary = grids.get(r, {})
		var key := Vector3i((cposed[i] / 0.04).floor())
		if not g.has(key):
			g[key] = PackedInt32Array()
		var arr: PackedInt32Array = g[key]
		arr.append(i)
		g[key] = arr
		grids[r] = g
	var segs_a := {}
	for r in ["torso", "armL", "armR", "legL", "legR"]:
		segs_a[r] = _axis(sk, apose, r)
	# articulaciones del personaje en la pose anatómica (para el mapeo por segmento)
	var kj := func(n: String) -> Vector3: return (apose[sk.find_bone(P + n)] as Transform3D).origin
	var out_root := Node3D.new()
	out_root.name = "Anatomia_" + id
	var stats := {"verts": 0, "pulled": 0, "post_out": 0, "max_out": 0.0}
	var group_data := []
	for g in meta.groups:
		var node := str(g.node)
		if not src.has(node) or g.get("has_frags", false):
			continue                    # el hueso entero ES la unión de sus fragmentos (no se guarda dos veces)
		var v: PackedVector3Array = src[node].v
		var region := region_of_bone(str(g.bone))
		var side := "Left" if region.ends_with("L") else "Right"
		var mk: Dictionary = marks.get(side, {})
		var pv := PackedVector3Array()
		pv.resize(v.size())
		for i in v.size():
			pv[i] = _map_point(v[i], str(g.bone), region, body, mk, kj, vm, side)
		# --- 3. adentro de la piel (pose anatómica)
		for i in pv.size():
			var c := _closest_on_axis(segs_a[region], pv[i])
			var dv := pv[i] - c
			var dl := dv.length()
			if dl < 0.001:
				continue
			var dist := _skin_dist(c, dv / dl)
			if dist < INF and dl > dist - MARGIN:
				pv[i] = c + dv / dl * maxf(dist - MARGIN, 0.002)
				stats.pulled += 1
		# --- 4. pesos del vértice más cercano de la misma región
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(pv.size() * 4)
		weights.resize(pv.size() * 4)
		var grid: Dictionary = grids.get(region, grids.torso)
		for i in pv.size():
			var n := _nearest(grid, cposed, pv[i])
			for k in 4:
				bones[i * 4 + k] = sd.bones[n * 4 + k]
				weights[i * 4 + k] = sd.weights[n * 4 + k]
		# --- 5. piel inversa → posición de enlace
		var bindv := PackedVector3Array()
		bindv.resize(pv.size())
		for i in pv.size():
			bindv[i] = _blend(amats, bones, weights, i * 4).affine_inverse() * pv[i]
		var dom := PackedInt32Array()
		dom.resize(pv.size())
		for i in pv.size():
			var bk := 0
			for k in 4:
				if weights[i * 4 + k] > weights[i * 4 + bk]:
					bk = k
			dom[i] = sd.bind_bone[bones[i * 4 + bk]]
		group_data.append({"g": g, "region": region, "bind": bindv, "bones": bones, "weights": weights, "idx": src[node].i, "dom": dom})
		stats.verts += pv.size()
	# --- 6. verificación: pose de enlace (reposo) y poses de animación; lo que asome se mete hacia el eje en enlace
	var lib := CharacterModel.anim_library(id)
	var check_poses := [["reposo", -1.0]] + CHECK_ANIMS
	var per_pose := {}
	# Cada pasada: se mide en TODAS las poses cuánto tiene que acercarse cada vértice a su eje (factor ≤ 1) y se aplica
	# el menor de todos de una vez en la pose de reposo; la última pasada sólo verifica.
	const PASSES := 6
	var pose_cache := []
	for cp in check_poses:
		sk.reset_bone_poses()
		if cp[1] >= 0.0 and lib.has_animation(cp[0]):
			ArmIK.apply_animation_pose(sk, lib.get_animation(cp[0]), float(cp[1]))
		sk.force_update_all_bone_transforms()
		var pose := _poses_global(sk)
		var mats := _mats(sd, pose)
		var segs := {}
		for r in ["torso", "armL", "armR", "legL", "legR"]:
			segs[r] = _axis(sk, pose, r)
		pose_cache.append({"name": cp[0], "mats": mats, "skin": _skin_all(sd, mats), "segs": segs, "pose": pose})
	for pass_i in PASSES:
		var verify := pass_i == PASSES - 1
		var factors := []
		for gd in group_data:
			var f := PackedFloat32Array()
			f.resize((gd.bind as PackedVector3Array).size())
			f.fill(1.0)
			factors.append(f)
		for pc in pose_cache:
			await _set_collision(pc.skin, sd.idx)
			for gi in group_data.size():
				var gd: Dictionary = group_data[gi]
				var bindv: PackedVector3Array = gd.bind
				var f: PackedFloat32Array = factors[gi]
				for i in bindv.size():
					var p := _blend(pc.mats, gd.bones, gd.weights, i * 4) * bindv[i]
					var c := _closest_on_bone(sk, pc.pose, gd.dom[i], p)
					var dl := p.distance_to(c)
					if dl < 0.001:
						continue
					var dist := _skin_dist(c, (p - c) / dl)
					if dist == INF:
						continue
					if verify:
						if dl > dist:
							stats.post_out += 1
							stats.max_out = maxf(stats.max_out, dl - dist)
							per_pose[pc.name] = int(per_pose.get(pc.name, 0)) + 1
						continue
					var allowed := maxf(dist - MARGIN - 0.002 * pass_i, 0.002)
					if dl > allowed:
						f[i] = minf(f[i], allowed / dl)
				factors[gi] = f
		if verify:
			break
		# aplicar en reposo: cada vértice se acerca a su eje lo que pidió la peor pose
		var rest_pc: Dictionary = pose_cache[0]
		for gi in group_data.size():
			var gd: Dictionary = group_data[gi]
			var bindv: PackedVector3Array = gd.bind
			var f: PackedFloat32Array = factors[gi]
			for i in bindv.size():
				if f[i] >= 0.9999:
					continue
				var m := _blend(rest_pc.mats, gd.bones, gd.weights, i * 4)
				var p := m * bindv[i]
				var c := _closest_on_bone(sk, rest_pc.pose, gd.dom[i], p)
				bindv[i] = m.affine_inverse() * (c + (p - c) * f[i])
			gd.bind = bindv
	print("%s: %d vértices · metidos en la pose anatómica %d · fuera de la piel (verificación en %d poses): %d (máx %.1f mm)" % [id, stats.verts,
		stats.pulled, check_poses.size(), stats.post_out, stats.max_out * 1000.0], " por pose: ", per_pose)
	# --- 7. mallas con piel
	for gd in group_data:
		var g: Dictionary = gd.g
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
		var bindv: PackedVector3Array = gd.bind
		var idx: PackedInt32Array = gd.idx
		var cols = src[str(g.node)].get("c")
		var has_col: bool = cols is PackedColorArray and (cols as PackedColorArray).size() == bindv.size()
		for i in bindv.size():
			if has_col:
				st.set_color((cols as PackedColorArray)[i])
			var b := PackedInt32Array([gd.bones[i * 4], gd.bones[i * 4 + 1], gd.bones[i * 4 + 2], gd.bones[i * 4 + 3]])
			var w := PackedFloat32Array([gd.weights[i * 4], gd.weights[i * 4 + 1], gd.weights[i * 4 + 2], gd.weights[i * 4 + 3]])
			st.set_bones(b)
			st.set_weights(w)
			var p: Vector3 = bindv[i]
			st.set_custom(0, Color(p.x, p.y, p.z))
			st.add_vertex(p)
		for k in idx:
			st.add_index(k)
		st.generate_normals()
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = str(g.node)
		mi.mesh = mesh
		mi.transform = cmi.transform
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# hueso dominante y centro del grupo en el espacio de ese hueso (reposo) para las lesiones
		var count := {}
		var center := Vector3.ZERO
		for i in bindv.size():
			var bb: int = sd.bind_bone[gd.bones[i * 4]]
			count[bb] = int(count.get(bb, 0)) + 1
			center += bindv[i]
		center /= maxf(bindv.size(), 1)
		var dom: int = count.keys()[0]
		for k in count:
			if count[k] > count[dom]:
				dom = k
		var aabb := mesh.get_aabb()
		mi.set_meta("label", g.label)
		mi.set_meta("system", g.system)
		mi.set_meta("bone", sk.get_bone_name(dom))
		mi.set_meta("center_bind", center)
		mi.set_meta("radius", aabb.size.length() * 0.5)
		if g.has("parent"):
			mi.set_meta("parent", str(g.parent))
		out_root.add_child(mi)
		mi.owner = out_root
	# marcadores de los huesos que se guardan como fragmentos: nombre, sistema y hueso Mixamo del grupo
	for g in meta.groups:
		if g.get("has_frags", false):
			var mk := Node3D.new()
			mk.name = str(g.node)
			mk.set_meta("label", g.label)
			mk.set_meta("system", g.system)
			mk.set_meta("bone", g.bone)
			mk.set_meta("fragmented", true)
			out_root.add_child(mk)
			mk.owner = out_root
	var ps := PackedScene.new()
	ps.pack(out_root)
	var err := ResourceSaver.save(ps, OUT_DIR + id + ".scn", ResourceSaver.FLAG_COMPRESS)
	print("  guardado ", OUT_DIR + id + ".scn err=", err)
	out_root.free()
	model.queue_free()
	await process_frame

## Lleva un punto de la anatomía al espacio del esqueleto (pose anatómica): torso y cabeza con el ajuste del cuerpo;
## brazos y piernas por segmento entre articulaciones (así coincide el largo de cada hueso).
func _map_point(p: Vector3, bone: String, region: String, body: Transform3D, mk: Dictionary, kj: Callable, vm: Callable, side: String) -> Vector3:
	if region == "torso":
		return body * p
	var b := bone.replace(P, "")
	var a0: Vector3
	var a1: Vector3
	var k0: Vector3
	var k1: Vector3
	if b.ends_with("ForeArm"):
		a0 = vm.call(mk.elbow); a1 = vm.call(mk.wrist); k0 = kj.call(side + "ForeArm"); k1 = kj.call(side + "Hand")
	elif b.ends_with("Arm"):
		a0 = vm.call(mk.shoulder); a1 = vm.call(mk.elbow); k0 = kj.call(side + "Arm"); k1 = kj.call(side + "ForeArm")
	elif b.ends_with("Hand"):
		a0 = vm.call(mk.wrist); a1 = vm.call(mk.tip); k0 = kj.call(side + "Hand"); k1 = kj.call(side + "HandMiddle3")
	elif b.ends_with("UpLeg"):
		a0 = vm.call(mk.hip); a1 = vm.call(mk.knee); k0 = kj.call(side + "UpLeg"); k1 = kj.call(side + "Leg")
	elif b.ends_with("Leg"):
		a0 = vm.call(mk.knee); a1 = vm.call(mk.ankle); k0 = kj.call(side + "Leg"); k1 = kj.call(side + "Foot")
	else:
		# pie: traslación por el tobillo con la escala del cuerpo
		return body.basis * (p - vm.call(mk.ankle)) + kj.call(side + "Foot")
	var da := a1 - a0
	var la := maxf(da.length(), 0.001)
	var t := (p - a0).dot(da) / (la * la)
	var radial := (p - a0) - da * t
	var dk := k1 - k0
	var q := Quaternion((body.basis * da).normalized(), dk.normalized())
	var rs := body.basis.get_scale().x
	return k0 + dk * t + Basis(q) * (body.basis.orthonormalized() * radial) * rs

static func _nearest(grid: Dictionary, pts: PackedVector3Array, p: Vector3) -> int:
	var c := Vector3i((p / 0.04).floor())
	var best := -1
	var bd := INF
	for r in range(0, 6):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				for z in range(-r, r + 1):
					if maxi(maxi(absi(x), absi(y)), absi(z)) != r:
						continue
					var key := c + Vector3i(x, y, z)
					if not grid.has(key):
						continue
					for i in (grid[key] as PackedInt32Array):
						var d := pts[i].distance_squared_to(p)
						if d < bd:
							bd = d
							best = i
		if best >= 0 and r >= 1:
			break
	if best < 0:
		for key in grid:
			for i in (grid[key] as PackedInt32Array):
				var d := pts[i].distance_squared_to(p)
				if d < bd:
					bd = d
					best = i
	return best
