class_name Dismember
extends RefCounted
## DESMEMBRAMIENTO. Sólo un cuerpo que ya murió, o al que el disparo mata (si no va a morir, sigue moviéndose y no tiene
## sentido). El daño se acumula por miembro: pistola ≈ 3 tiros, fusil ≈ 2, calibre grueso 1; la escopeta de cerca suma
## todos los perdigones y arranca varios miembros. El cuello (cabeza) sólo cede con armas potentes.
##
## Cómo se corta: (1) el hueso de la articulación y todo lo que cuelga de él se achica a casi cero (LimbCutter) →
## el miembro desaparece del cuerpo con su traje, huesos y vasos; (2) con la piel por CPU y la pose del momento se arma
## el miembro suelto (Limb: cuerpo rígido, traje + versión de rayos X) que sale despedido y cae al suelo; (3) en el muñón
## queda un corte de carne con hueso y un chorro arterial a latidos; el miembro suelto también sangra.

## Hueso golpeado → articulaciones donde puede cortarse [hueso, probabilidad, lo que cuesta (daño acumulado)].
const CUTS := {
	"LeftArm": [["LeftArm", 0.3, 75.0], ["LeftForeArm", 0.7, 50.0]],
	"RightArm": [["RightArm", 0.3, 75.0], ["RightForeArm", 0.7, 50.0]],
	"LeftForeArm": [["LeftForeArm", 0.6, 50.0], ["LeftHand", 0.4, 40.0]],
	"RightForeArm": [["RightForeArm", 0.6, 50.0], ["RightHand", 0.4, 40.0]],
	"LeftHand": [["LeftHand", 1.0, 35.0]],
	"RightHand": [["RightHand", 1.0, 35.0]],
	"LeftUpLeg": [["LeftUpLeg", 0.3, 85.0], ["LeftLeg", 0.7, 60.0]],
	"RightUpLeg": [["RightUpLeg", 0.3, 85.0], ["RightLeg", 0.7, 60.0]],
	"LeftLeg": [["LeftLeg", 0.6, 60.0], ["LeftFoot", 0.4, 45.0]],
	"RightLeg": [["RightLeg", 0.6, 60.0], ["RightFoot", 0.4, 45.0]],
	"LeftFoot": [["LeftFoot", 1.0, 40.0]],
	"RightFoot": [["RightFoot", 1.0, 40.0]],
	"Neck": [["Head", 1.0, 80.0]],
}
## Radio aproximado del corte (m) por articulación.
const RADIUS := {"LeftArm": 0.055, "RightArm": 0.055, "LeftForeArm": 0.045, "RightForeArm": 0.045, "LeftHand": 0.035, "RightHand": 0.035,
	"LeftUpLeg": 0.085, "RightUpLeg": 0.085, "LeftLeg": 0.06, "RightLeg": 0.06, "LeftFoot": 0.045, "RightFoot": 0.045, "Head": 0.06}
const P := "mixamorig_"

## Llamar con cada impacto de bala / esquirla sobre un cuerpo que murió o que muere con este disparo.
static func apply_hit(a: Actor, info: Dictionary, lethal: bool) -> void:
	if a == null or a.skel == null or not (str(info.get("type", "")) in ["bullet", "fragment"]):
		return
	var bone := str(info.get("bone", "")).trim_prefix(P)
	if not CUTS.has(bone):
		return
	var sk := a.skel
	var hit_idx := sk.find_bone(P + bone)
	if hit_idx < 0 or _is_cut(a, hit_idx):
		return
	var dmg := float(info.get("damage", 20.0))
	var pellets := int(info.get("pellets", 1))
	if pellets > 1:
		dmg *= clampf(2.4 - float(info.get("distance", 6.0)) * 0.2, 0.6, 2.4)       # la escopeta de cerca arranca todo
	if lethal:
		dmg *= 1.5
	var acc: float = float(a.limb_damage.get(bone, 0.0)) + dmg
	a.limb_damage[bone] = acc
	var opts: Array = CUTS[bone]
	var pick: Array = opts[0]
	var roll := randf()
	var sum := 0.0
	for o in opts:
		sum += float(o[1])
		if roll <= sum:
			pick = o
			break
	# el cuello necesita un arma potente: un tiro fuerte o varios
	var need := float(pick[2])
	if bone == "Neck" and dmg < 38.0 and acc < need * 1.4:
		return
	if acc < need:
		return
	a.limb_damage[bone] = 0.0
	sever(a, P + str(pick[0]), info)

static func _is_cut(a: Actor, bone_idx: int) -> bool:
	var sk := a.skel
	var b := bone_idx
	while b >= 0:
		if a.severed.has(sk.get_bone_name(b)):
			return true
		b = sk.get_bone_parent(b)
	return false

static func _subtree(sk: Skeleton3D, root: int) -> Dictionary:
	var bones := {root: true}
	var todo := [root]
	while not todo.is_empty():
		var b: int = todo.pop_back()
		for c in sk.get_bone_children(b):
			bones[c] = true
			todo.append(c)
	return bones

## Corta el miembro desde la articulación `joint` (nombre completo del hueso).
static func sever(a: Actor, joint: String, info: Dictionary) -> void:
	var sk := a.skel
	var bi := sk.find_bone(joint)
	if bi < 0 or a.severed.has(joint) or _is_cut(a, bi):
		return
	var bones := _subtree(sk, bi)
	var dir: Vector3 = info.get("dir", Vector3(-a.facing, 0, 0))
	dir.z = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	var dmg := float(info.get("damage", 30.0))
	var xf_sk := sk.global_transform
	var joint_w: Vector3 = xf_sk * sk.get_bone_global_pose(bi).origin
	var kids := sk.get_bone_children(bi)
	var tip_w := joint_w + Vector3.DOWN * 0.3
	if not kids.is_empty():
		tip_w = xf_sk * sk.get_bone_global_pose(kids[0]).origin
	var axis_w := (tip_w - joint_w).normalized()           # del corte hacia la punta del miembro
	var jname := joint.trim_prefix(P)
	var radius: float = float(RADIUS.get(jname, 0.05))
	# --- el miembro suelto (con la pose del momento, ANTES de achicar los huesos)
	var anat := AnatomyBody.for_actor(a)
	var built := _build_meshes(a, anat, bones, joint_w, axis_w, radius)
	# --- el muñón: los huesos se achican a casi cero
	a.severed[joint] = true
	var cutter: LimbCutter = a.get_meta("limb_cutter") if a.has_meta("limb_cutter") else null
	if cutter == null:
		cutter = LimbCutter.new()
		sk.add_child(cutter)
		a.set_meta("limb_cutter", cutter)
	var list := cutter.cut
	list.append(bi)
	cutter.cut = list
	for h in a.hitboxes:
		var hb := str(h.get_meta("bone", ""))
		if sk.find_bone(hb) >= 0 and bones.has(sk.find_bone(hb)):
			h.collision_layer = 0
	if built.has("suit"):
		var limb := Limb.new()
		a.get_parent().add_child(limb)
		limb.setup(built.suit, built.get("xray"), built.center, built.length, radius, built.offset, -axis_w, joint_w, anat if a.is_dead() else null)
		var v := dir * (2.5 + dmg * 0.045) + Vector3.UP * randf_range(2.0, 4.0) + (limb.global_position - joint_w) * 2.0
		v.z = 0.0
		limb.linear_velocity = v
		limb.angular_velocity = Vector3(0, 0, randf_range(-14.0, 14.0))
	_stump(a, bi, joint_w, axis_w, radius, dir)
	# --- espectáculo
	if Blood.instance:
		Blood.instance.spray(joint_w, dir, true, true, 3.0)
		Blood.instance.drops(joint_w, Vector3.UP + dir * 0.5, 1.0, 7.0, 35.0)
		Blood.instance.drops(joint_w, -dir + Vector3.UP * 0.3, 0.8, 5.0, 40.0)
		Blood.instance.pool(a.global_position)
	Fx.impact(joint_w, -dir, "flesh")
	Sfx.play("body_fall", joint_w, 2.0, randf_range(0.8, 0.95), 14.0, a)
	Sfx.play("impact_flesh", joint_w, 4.0, 0.7, 12.0, a)
	TimeFx.shake(0.5)
	a.dismembered.emit(jname, info)

## Corte de carne con hueso y chorro arterial en el muñón (sigue al hueso padre).
static func _stump(a: Actor, bi: int, joint_w: Vector3, axis_w: Vector3, radius: float, dir: Vector3) -> void:
	var sk := a.skel
	var parent := sk.get_bone_parent(bi)
	if parent < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = sk.get_bone_name(parent)
	att.set_meta("no_tech", true)
	sk.add_child(att)
	var cap := MeshInstance3D.new()
	cap.set_meta("no_tech", true)
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius * 1.05
	cm.height = 0.012
	cm.radial_segments = 12
	cm.rings = 1
	cap.mesh = cm
	cap.material_override = _flesh_mat()
	att.add_child(cap)
	var bone_end := MeshInstance3D.new()
	bone_end.set_meta("no_tech", true)
	var bm := CylinderMesh.new()
	bm.top_radius = radius * 0.42
	bm.bottom_radius = radius * 0.42
	bm.height = 0.016
	bm.radial_segments = 10
	bone_end.mesh = bm
	bone_end.material_override = _bone_mat()
	att.add_child(bone_end)
	cap.global_transform = Transform3D(_basis_y(axis_w), joint_w)
	bone_end.global_transform = Transform3D(_basis_y(axis_w), joint_w)
	var s := Stump.new()
	s.name = "ChorroMunon"
	att.add_child(s)
	s.marker_world = joint_w
	s.out = -axis_w
	s.actor = a

static func _basis_y(y: Vector3) -> Basis:
	y = y.normalized()
	var x := y.cross(Vector3.BACK).normalized() if absf(y.z) < 0.99 else Vector3.RIGHT
	return Basis(x, y, x.cross(y).normalized())

static var _fm: StandardMaterial3D
static func _flesh_mat() -> StandardMaterial3D:
	if _fm == null:
		_fm = StandardMaterial3D.new()
		_fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fm.albedo_color = Color(0.55, 0.03, 0.04)
		_fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _fm

static var _bm: StandardMaterial3D
static func _bone_mat() -> StandardMaterial3D:
	if _bm == null:
		_bm = StandardMaterial3D.new()
		_bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bm.albedo_color = Color(0.93, 0.89, 0.78)
	return _bm

## Malla del miembro: traje (de la malla del personaje) y rayos X (huesos y vasos de la anatomía), con la pose actual.
static func _build_meshes(a: Actor, anat: AnatomyBody, bones: Dictionary, joint_w: Vector3, axis_w: Vector3, radius: float) -> Dictionary:
	var sk := a.skel
	var out := {}
	var sk_xf := sk.global_transform
	# matriz de piel de cada hueso (pose actual), por índice de enlace
	var suit_tris := []          # [{pts: PackedVector3Array(3), uv: PackedVector2Array(3), surf: int, mat}]
	var all_pts := PackedVector3Array()
	var surfaces: Array = []
	for mi in sk.get_children():
		var m := mi as MeshInstance3D
		if m == null or m.skin == null or m.mesh == null or not m.has_meta("actor_mesh"):
			continue
		var skin := m.skin
		var bone_of := {}
		for i in skin.get_bind_count():
			var b := skin.get_bind_bone(i)
			if b < 0:
				b = sk.find_bone(str(skin.get_bind_name(i)).replace(":", "_"))
			bone_of[i] = b
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null or arr[Mesh.ARRAY_BONES] == null:
				continue
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bn: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var stride := bn.size() / maxi(v.size(), 1)
			var uv = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var ind: PackedInt32Array = idx if idx != null and (idx as PackedInt32Array).size() > 0 else PackedInt32Array(range(v.size()))
			var mats := {}
			var pts := PackedVector3Array()
			pts.resize(v.size())
			var inset := PackedByteArray()
			inset.resize(v.size())
			for i in v.size():
				var t := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
				var best_w := -1.0
				var best_b := -1
				for k in stride:
					var ww := w[i * stride + k]
					if ww <= 0.0:
						continue
					var bi: int = bone_of.get(bn[i * stride + k], 0)
					if not mats.has(bi):
						mats[bi] = sk_xf * sk.get_bone_global_pose(bi) * skin.get_bind_pose(bn[i * stride + k]) * m.transform
					var mm: Transform3D = mats[bi]
					t.basis.x += mm.basis.x * ww
					t.basis.y += mm.basis.y * ww
					t.basis.z += mm.basis.z * ww
					t.origin += mm.origin * ww
					if ww > best_w:
						best_w = ww
						best_b = bi
				pts[i] = t * v[i]
				inset[i] = 1 if bones.has(best_b) else 0
			var sel_idx := PackedInt32Array()
			for t in range(0, ind.size() - 2, 3):
				if int(inset[ind[t]]) + int(inset[ind[t + 1]]) + int(inset[ind[t + 2]]) >= 2:
					sel_idx.append_array([ind[t], ind[t + 1], ind[t + 2]])
			if sel_idx.is_empty():
				continue
			surfaces.append({"pts": pts, "uv": uv, "idx": sel_idx, "mat": m.get_active_material(s)})
			for k in sel_idx:
				all_pts.append(pts[k])
	if all_pts.is_empty():
		return out
	var center := Vector3.ZERO
	for p in all_pts:
		center += p
	center /= all_pts.size()
	# alcance del miembro a lo largo de su eje (para la cápsula de colisión)
	var lo := INF
	var hi := -INF
	for p in all_pts:
		var d := (p - center).dot(axis_w)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	out["center"] = center
	out["length"] = maxf(hi - lo, 0.1)
	out["offset"] = axis_w * (lo + hi) * 0.5
	var am := ArrayMesh.new()
	for sf in surfaces:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pts: PackedVector3Array = sf.pts
		var uvs = sf.uv
		for k in sf.idx:
			if uvs != null:
				st.set_uv((uvs as PackedVector2Array)[k])
			st.add_vertex(pts[k] - center)
		st.generate_normals()
		var sub := st.commit()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sub.surface_get_arrays(0))
		if sf.mat:
			am.surface_set_material(am.get_surface_count() - 1, sf.mat)
	# corte del miembro (carne roja con hueso) mirando hacia el muñón
	var cap_st := SurfaceTool.new()
	cap_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bx := _basis_y(axis_w)
	var c0 := joint_w - center
	for k in 12:
		var a0 := TAU * k / 12.0
		var a1 := TAU * (k + 1) / 12.0
		for p in [c0, c0 + bx * Vector3(cos(a0), 0, sin(a0)) * radius, c0 + bx * Vector3(cos(a1), 0, sin(a1)) * radius]:
			cap_st.add_vertex(p)
	cap_st.generate_normals()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cap_st.commit().surface_get_arrays(0))
	am.surface_set_material(am.get_surface_count() - 1, _flesh_mat())
	out["suit"] = am
	# versión de rayos X: huesos y vasos de la anatomía con la pose actual
	if anat != null and anat.available:
		var xv := PackedVector3Array()
		var xc := PackedColorArray()
		for n in anat.groups:
			var g: Dictionary = anat.groups[n]
			var sysn := str(g.system)
			if sysn != "hueso" and sysn != "vaso":
				continue
			var bidx := sk.find_bone(str(g.bone))
			if bidx < 0 or not bones.has(bidx):
				continue
			var farr := (g.mesh as Mesh).surface_get_arrays(0)
			var fv: PackedVector3Array = farr[Mesh.ARRAY_VERTEX]
			var fb: PackedInt32Array = farr[Mesh.ARRAY_BONES]
			var fw: PackedFloat32Array = farr[Mesh.ARRAY_WEIGHTS]
			var fi: PackedInt32Array = farr[Mesh.ARRAY_INDEX]
			var fstride := fb.size() / maxi(fv.size(), 1)
			var col: Color = AnatomyBody.SYS_COLOR.get(sysn, Color(0.9, 0.85, 0.7))
			var fm := {}
			var fpts := PackedVector3Array()
			fpts.resize(fv.size())
			for i in fv.size():
				var t := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
				for k in fstride:
					var ww := fw[i * fstride + k]
					if ww <= 0.0:
						continue
					var bind_i := fb[i * fstride + k]
					if not fm.has(bind_i):
						fm[bind_i] = sk_xf * sk.get_bone_global_pose(anat._bone_of_bind.get(bind_i, 0)) * anat.skin.get_bind_pose(bind_i) * anat.mesh_xf
					var mm: Transform3D = fm[bind_i]
					t.basis.x += mm.basis.x * ww
					t.basis.y += mm.basis.y * ww
					t.basis.z += mm.basis.z * ww
					t.origin += mm.origin * ww
				fpts[i] = t * fv[i]
			for k in fi:
				xv.append(fpts[k] - center)
				xc.append(col)
		if not xv.is_empty():
			var xst := SurfaceTool.new()
			xst.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in xv.size():
				xst.set_color(xc[i])
				xst.add_vertex(xv[i])
			xst.generate_normals()
			var xm := ArrayMesh.new()
			xm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, xst.commit().surface_get_arrays(0))
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.5
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.emission_enabled = true
			mat.emission = Color(0.18, 0.15, 0.12)
			xm.surface_set_material(0, mat)
			out["xray"] = xm
	return out

## Chorro arterial del muñón: latidos que bajan de intensidad durante ~9 s.
class Stump extends Node3D:
	var marker_world := Vector3.ZERO
	var out := Vector3.UP
	var actor: Actor
	var _local := Vector3.ZERO
	var _local_dir := Vector3.UP
	var _t := 0.0
	var _beat := 0.0
	func _ready() -> void:
		_local = get_parent().global_transform.affine_inverse() * marker_world
		_local_dir = get_parent().global_basis.inverse() * out
	func _process(delta: float) -> void:
		_t += delta
		if _t > 9.0:
			queue_free()
			return
		_beat -= delta
		if _beat <= 0.0 and Blood.instance:
			_beat = 0.26
			var k := clampf(1.0 - _t / 9.0, 0.15, 1.0)
			var p: Vector3 = get_parent().global_transform * _local
			var d: Vector3 = (get_parent().global_basis * _local_dir).normalized()
			Blood.instance.drops(p, (d + Vector3.UP * 0.35).normalized(), 0.7 * k, 3.5 + 4.0 * k, 16.0)
