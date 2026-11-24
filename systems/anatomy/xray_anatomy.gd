class_name XRayAnatomy
extends Node3D
## Anatomía interna de un personaje para la cámara de rayos X (estilo «kill cam»): huesos, órganos, cerebro y vasos de
## BodyParts3D (assets/anatomy, reducidos por tools/anatomy/build_anatomy.py) pegados a los huesos del esqueleto
## Mixamo con BoneAttachment3D, así se mueven con la animación.
##
## Ajuste al cuerpo: el torso, la cabeza y las piernas se escalan y trasladan con dos referencias (caderas y hombros);
## los brazos (en BodyParts3D cuelgan al costado, en Mixamo están en T) se alinean segmento por segmento: hombro→codo,
## codo→muñeca, muñeca→dedos.
##
## Lesiones: injuries_at(info) busca los grupos anatómicos más cercanos al punto del impacto (en el espacio del hueso
## golpeado) y devuelve qué se rompió («Fractura de fémur izq.», «Hígado perforado»). Funciona aunque los rayos X estén
## apagados (no necesita las mallas), porque las lesiones también tienen efecto en el juego (pierna rota = renguea).
## Más adelante, con Blender, se reemplazan los grupos por mallas con daño real (ver docs/ANATOMIA.md).

const GLB := "res://assets/anatomy/anatomy.glb"
const JSON_PATH := "res://assets/anatomy/anatomy.json"
const P := "mixamorig_"

static var _meta := {}
static var _scene: PackedScene
static var _mats := {}
static var _xray_body_mat: ShaderMaterial

var actor: Actor
var skel: Skeleton3D
var groups := {}              ## node → {label, bone, system, local: Transform3D (espacio del hueso), center_bone: Vector3}
var meshes := {}              ## node → MeshInstance3D (sólo si se armaron las mallas)
var built_meshes := false
var _attach := {}             ## hueso → BoneAttachment3D
var _saved_overrides := {}
var showing := false

static func meta() -> Dictionary:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	return _meta

## Se crea una por personaje (sin mallas: sólo transformaciones); las mallas se cargan la primera vez que se muestran.
static func for_actor(a: Actor) -> XRayAnatomy:
	var x := a.get_node_or_null("XRay") as XRayAnatomy
	if x:
		return x
	x = XRayAnatomy.new()
	x.name = "XRay"
	x.actor = a
	x.skel = a.skel
	a.add_child(x)
	x._compute()
	return x

# ---------------------------------------------------------------- ajuste al esqueleto

func _rest(bone: String) -> Transform3D:
	var i := skel.find_bone(P + bone)
	return skel.get_bone_global_rest(i) if i >= 0 else Transform3D.IDENTITY

func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _compute() -> void:
	var m := meta()
	var marks: Dictionary = m.marks
	# referencias en espacio del esqueleto
	var hipL := _rest("LeftUpLeg").origin
	var hipR := _rest("RightUpLeg").origin
	var shL := _rest("LeftArm").origin
	var shR := _rest("RightArm").origin
	var a_hip := (_v(marks.Left.hip) + _v(marks.Right.hip)) * 0.5
	var a_sh := (_v(marks.Left.shoulder) + _v(marks.Right.shoulder)) * 0.5
	var k_hip := (hipL + hipR) * 0.5
	var k_sh := (shL + shR) * 0.5
	var s := (k_sh.y - k_hip.y) / maxf(a_sh.y - a_hip.y, 0.01)
	# el esqueleto puede venir girado dentro del modelo: «adelante» del esqueleto (de la cadera a la punta del pie)
	var fwd := _rest("LeftToeBase").origin - _rest("LeftFoot").origin
	fwd.y = 0.0
	var rot := Basis.IDENTITY
	if fwd.length() > 0.01:
		rot = Basis(Quaternion(Vector3(0, 0, 1), fwd.normalized()))
	var left := (hipL - hipR)
	# si izquierda/derecha quedaron invertidas respecto de BodyParts3D (+X = izquierda), se corrige
	if (rot * Vector3.RIGHT).dot(left) < 0.0:
		rot = rot * Basis(Vector3.UP, PI)
	var body_fit := Transform3D(rot.scaled(Vector3.ONE * s), Vector3.ZERO)
	body_fit.origin = k_hip - body_fit.basis * a_hip
	for g in m.groups:
		var bone := str(g.bone)
		var bi := skel.find_bone(bone)
		if bi < 0:
			continue
		var fit := body_fit
		var seg := str(g.seg)
		if seg != "":
			var side := "Left" if bone.contains("Left") else "Right"
			var mk: Dictionary = marks[side]
			var a0: Vector3
			var a1: Vector3
			var k0: Vector3
			var k1: Vector3
			match seg:
				"upper":
					a0 = _v(mk.shoulder); a1 = _v(mk.elbow); k0 = _rest(side + "Arm").origin; k1 = _rest(side + "ForeArm").origin
				"fore":
					a0 = _v(mk.elbow); a1 = _v(mk.wrist); k0 = _rest(side + "ForeArm").origin; k1 = _rest(side + "Hand").origin
				_:
					a0 = _v(mk.wrist); a1 = _v(mk.tip); k0 = _rest(side + "Hand").origin
					k1 = _rest(side + "HandMiddle3").origin if skel.find_bone(P + side + "HandMiddle3") >= 0 else k0 + (k0 - _rest(side + "ForeArm").origin).normalized() * 0.15
			var da := (rot * (a1 - a0)).normalized()
			var dk := (k1 - k0).normalized()
			var sb := Basis(Quaternion(da, dk)) * rot
			var ls := k0.distance_to(k1) / maxf(a0.distance_to(a1), 0.01)
			fit = Transform3D(sb.scaled(Vector3.ONE * ls), Vector3.ZERO)
			fit.origin = k0 - fit.basis * a0
		var bone_rest := skel.get_bone_global_rest(bi)
		var local := bone_rest.affine_inverse() * fit
		groups[str(g.node)] = {"label": str(g.label), "bone": bone, "system": str(g.system), "local": local,
			"center_bone": local * _v(g.center), "radius": float(g.radius) * s, "tris": int(g.tris)}

# ---------------------------------------------------------------- mallas (sólo para mostrar)

static func _system_mat(system: String) -> StandardMaterial3D:
	if _mats.has(system):
		return _mats[system]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = false
	m.roughness = 0.6
	match system:
		"hueso":
			m.albedo_color = Color(0.95, 0.92, 0.82)
			m.emission_enabled = true
			m.emission = Color(0.35, 0.33, 0.28)
		"organo":
			m.albedo_color = Color(0.72, 0.16, 0.18)
			m.emission_enabled = true
			m.emission = Color(0.25, 0.03, 0.04)
		"nervio":
			m.albedo_color = Color(0.9, 0.6, 0.65)
			m.emission_enabled = true
			m.emission = Color(0.3, 0.15, 0.18)
		_:
			m.albedo_color = Color(0.7, 0.05, 0.08)
			m.emission_enabled = true
			m.emission = Color(0.3, 0.0, 0.02)
	_mats[system] = m
	return m

static func damaged_mat() -> StandardMaterial3D:
	if _mats.has("_dmg"):
		return _mats["_dmg"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.1, 0.05)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.12, 0.02)
	m.emission_energy_multiplier = 2.5
	_mats["_dmg"] = m
	return m

## Piel de rayos X: transparente con borde azulado (fresnel). Funciona en GL Compatibility.
static func xray_body_mat() -> ShaderMaterial:
	if _xray_body_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 rim_color : source_color = vec4(0.35, 0.75, 1.0, 1.0);
uniform float strength = 0.9;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = rim_color.rgb * (0.08 + f * strength);
}
"""
		_xray_body_mat = ShaderMaterial.new()
		_xray_body_mat.shader = sh
	return _xray_body_mat

func _build_meshes() -> void:
	if built_meshes:
		return
	built_meshes = true
	if _scene == null:
		_scene = load(GLB)
	var src := _scene.instantiate()
	for node_name in groups:
		var g: Dictionary = groups[node_name]
		var mi := src.find_child(node_name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var att: BoneAttachment3D = _attach.get(g.bone)
		if att == null:
			att = BoneAttachment3D.new()
			att.bone_name = g.bone
			skel.add_child(att)
			_attach[g.bone] = att
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.transform = g.local
		copy.material_override = _system_mat(g.system)
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.visible = false
		att.add_child(copy)
		meshes[node_name] = copy
	src.free()

# ---------------------------------------------------------------- lesiones

## Grupos anatómicos dañados por un impacto. Devuelve [{node, label, system, severity}] ordenado por cercanía.
func injuries_at(info: Dictionary) -> Array:
	var bone := str(info.get("bone", ""))
	var bi := skel.find_bone(bone)
	if bi < 0:
		return []
	var t := str(info.get("type", "bullet"))
	var point: Vector3 = info.get("point", actor.global_position + Vector3.UP)
	var pose := skel.global_transform * skel.get_bone_global_pose(bi)
	var lp := pose.affine_inverse() * point
	var cands := []
	var parent := skel.get_bone_parent(bi)
	var parent_name := skel.get_bone_name(parent) if parent >= 0 else ""
	for node_name in groups:
		var g: Dictionary = groups[node_name]
		if g.bone != bone and g.bone != parent_name:
			continue
		if t == "fall" and g.system != "hueso":
			continue
		if t in ["punch", "kick"] and g.system == "vaso":
			continue
		var c: Vector3 = g.center_bone if g.bone == bone else (pose.affine_inverse() * (skel.global_transform * skel.get_bone_global_pose(parent)) * g.center_bone)
		var d := lp.distance_to(c) - float(g.radius) * 0.5
		cands.append([d, node_name, g])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	var dmg := float(info.get("final_damage", info.get("damage", 10.0)))
	var n := 1 if t in ["punch", "kick", "fall"] else (3 if t == "blast" else 2)
	for i in mini(n, cands.size()):
		var g: Dictionary = cands[i][2]
		out.append({"node": cands[i][1], "label": g.label, "system": g.system, "severity": dmg, "text": _describe(g, t, dmg)})
	return out

static func _describe(g: Dictionary, t: String, dmg: float) -> String:
	var lab := str(g.label)
	match str(g.system):
		"hueso":
			if t in ["punch", "kick"] and dmg < 15.0:
				return "Contusión: %s" % lab
			return ("Fractura expuesta: %s" if dmg > 45.0 else "Fractura: %s") % lab
		"organo":
			return ("Órgano destrozado: %s" if dmg > 60.0 else "Perforación: %s") % lab
		"nervio":
			return "Daño cerebral (%s)" % lab
		_:
			return "Hemorragia: %s" % lab

# ---------------------------------------------------------------- mostrar / ocultar

## Muestra los rayos X: piel transparente, anatomía visible y lo dañado ROTO de verdad:
##  * hueso fracturado: corte dentado que lo atraviesa y las dos mitades se separan (shader), polvo de hueso;
##  * órgano / vaso perforado: túnel a lo largo de la trayectoria de la bala (o del cuchillo) con borde en carne viva;
##  * sangre siempre: chorro en el impacto y goteo desde lo perforado.
func show_xray(injuries: Array, info := {}) -> void:
	var point: Vector3 = info.get("point", actor.global_position + Vector3.UP * 1.2)
	var dir: Vector3 = info.get("dir", Vector3(-actor.facing, 0, 0))
	if dir.length() < 0.01:
		dir = Vector3.RIGHT
	dir = dir.normalized()
	Fx.blood(point, -dir, 1.5)
	Fx.blood(point + dir * 0.25, dir, 1.2)      # salida
	if Settings.xray == 0:
		return
	_build_meshes()
	showing = true
	for mi in actor.model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.has_meta("actor_mesh"):
			_saved_overrides[m] = m.material_override
			m.material_override = xray_body_mat()
	var damaged := {}
	for inj in injuries:
		damaged[inj.node] = inj
	for node_name in meshes:
		var mi: MeshInstance3D = meshes[node_name]
		var g: Dictionary = groups[node_name]
		mi.visible = Settings.xray >= 2 or g.system == "hueso"
		mi.material_override = _system_mat(g.system)
		if damaged.has(node_name):
			mi.visible = true
			var sev := float(damaged[node_name].severity)
			var t := str(info.get("type", "bullet"))
			mi.material_override = _wound_material(mi, g, point, dir, sev, t)
			if g.system == "hueso":
				Fx.emit("shard_bone", point, -dir, 1.0 + sev / 40.0)
			else:
				Fx.blood(mi.global_transform * mi.get_aabb().get_center(), Vector3.DOWN, 0.8)

## Material de la herida para una pieza anatómica (uniformes en el espacio local de la malla).
func _wound_material(mi: MeshInstance3D, g: Dictionary, point: Vector3, dir: Vector3, sev: float, t: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _wound_shader()
	var inv := mi.global_transform.affine_inverse()
	var aabb := mi.get_aabb()
	var lp := inv * point
	var ld := (inv.basis * dir).normalized()
	# punto donde la trayectoria pasa más cerca del centro de la pieza (la bala entra por la piel, no por el hueso)
	var c := aabb.get_center()
	var k := (c - lp).dot(ld)
	var through := lp + ld * k
	var ext := aabb.size
	var axis := Vector3.UP
	if ext.x >= ext.y and ext.x >= ext.z:
		axis = Vector3.RIGHT
	elif ext.z >= ext.y:
		axis = Vector3.BACK
	var minor := minf(minf(ext.x, ext.y), ext.z)
	var is_bone := str(g.system) == "hueso"
	m.set_shader_parameter("mode", 0 if is_bone else 1)
	m.set_shader_parameter("hit_pos", through)
	m.set_shader_parameter("hit_dir", ld)
	m.set_shader_parameter("axis", axis)
	var r := clampf(minor * (0.35 if is_bone else 0.25) * (1.0 + sev / 80.0), 0.004, 0.05)
	if t in ["punch", "kick", "fall"]:
		r *= 0.6
	m.set_shader_parameter("hole_r", r)
	m.set_shader_parameter("split", 0.0)
	m.set_shader_parameter("base_color", (_system_mat(g.system) as StandardMaterial3D).albedo_color)
	if is_bone and (sev > 12.0 or t == "fall"):
		# fractura: las dos mitades se separan
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): m.set_shader_parameter("split", v), 0.0, clampf(r * 0.9, 0.006, 0.03), 0.18)
	return m

static var _wshader: Shader
static func _wound_shader() -> Shader:
	if _wshader == null:
		_wshader = Shader.new()
		_wshader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform int mode = 0;               // 0 = fractura de hueso, 1 = perforación de órgano / vaso
uniform vec3 hit_pos;
uniform vec3 hit_dir = vec3(1.0, 0.0, 0.0);
uniform vec3 axis = vec3(0.0, 1.0, 0.0);
uniform float hole_r = 0.02;
uniform float split = 0.0;
uniform vec4 base_color : source_color = vec4(0.95, 0.92, 0.82, 1.0);
varying vec3 lp;
void vertex() {
	lp = VERTEX;
	if (mode == 0) {
		float side = sign(dot(VERTEX - hit_pos, axis));
		VERTEX += axis * side * split + hit_dir * split * 0.6 * step(0.0, side);
	}
}
void fragment() {
	float rim;
	if (mode == 0) {
		float t = dot(lp - hit_pos, axis);
		float jag = (sin(lp.x * 830.0) * sin(lp.z * 610.0) + sin(lp.y * 520.0)) * hole_r * 0.25;
		if (abs(t + jag) < hole_r * 0.3) { discard; }
		rim = 1.0 - smoothstep(hole_r * 0.3, hole_r * 1.8, abs(t + jag));
	} else {
		float d = length(cross(lp - hit_pos, hit_dir));
		if (d < hole_r) { discard; }
		rim = 1.0 - smoothstep(hole_r, hole_r * 2.5, d);
	}
	vec3 wound = mode == 0 ? vec3(0.55, 0.05, 0.03) : vec3(0.35, 0.0, 0.0);
	ALBEDO = mix(base_color.rgb, wound, rim);
	ROUGHNESS = 0.6;
	EMISSION = base_color.rgb * 0.3 + vec3(1.0, 0.08, 0.02) * rim * 2.2;
}
"""
	return _wshader

func hide_xray() -> void:
	if not showing:
		return
	showing = false
	for m in _saved_overrides:
		if is_instance_valid(m):
			(m as MeshInstance3D).material_override = _saved_overrides[m]
	_saved_overrides.clear()
	for node_name in meshes:
		var mi: MeshInstance3D = meshes[node_name]
		mi.visible = false
		mi.transform = groups[node_name].local
		mi.material_override = _system_mat(groups[node_name].system)
