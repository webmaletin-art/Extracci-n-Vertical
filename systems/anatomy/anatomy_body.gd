class_name AnatomyBody
extends Node
## Anatomía interna de UN personaje: la de Z-Anatomy ajustada a su cuerpo por tools/anatomy/fit_anatomy.gd
## (assets/anatomy/fit/<id>.scn). Son mallas con piel que usan el MISMO esqueleto y los MISMOS pesos que el personaje,
## así que van siempre dentro del cuerpo y se mueven con cualquier animación.
##
##  * trace(): recorre la trayectoria de un proyectil o de una esquirla por adentro del cuerpo y devuelve, en orden, cada
##    estructura que atraviesa (hueso, músculo, órgano, vaso, nervio) con su punto de entrada y salida. Se calcula en el
##    espacio de enlace (el de la malla sin deformar) con el hueso dominante de cada grupo, contra los triángulos reales.
##  * Las heridas se guardan en ese espacio de enlace: quedan pegadas al órgano aunque el cuerpo se mueva.
##  * Sólo se dibujan las partes DAÑADAS: destello rápido en el juego (show_flash) o la toma lenta de la muerte
##    (show_killcam). Shader de heridas: fractura dentada con astillas, túnel de bala (entrada y salida), esquirla alojada,
##    estallido por onda expansiva. Usa la posición de enlace guardada en CUSTOM0 (no la deformada).

const FIT_DIR := "res://assets/anatomy/fit/"
const MAX_WOUNDS := 6

static var _scenes := {}         ## id → PackedScene
static var _cpu := {}            ## id → {node: {v, i, aabb, label, system, bone, center}}
static var _wound_shader: Shader
static var _flash_shader: Shader
static var _skin_shader: Shader

var actor: Actor
var skel: Skeleton3D
var skin: Skin
var mesh_xf := Transform3D.IDENTITY
var groups := {}                 ## node → datos de CPU (compartidos)
var meshes := {}                 ## node → MeshInstance3D (se crean recién cuando hacen falta)
var wounds := {}                 ## node → Array de heridas {pos, dir, r, type, depth}
var _bind_of := {}               ## hueso → índice de enlace
var _flash_t := 0.0
var _killcam := false
var _skin_saved := {}
var available := false

static func for_actor(a: Actor) -> AnatomyBody:
	var x := a.get_node_or_null("Anatomia") as AnatomyBody
	if x:
		return x
	x = AnatomyBody.new()
	x.name = "Anatomia"
	x.actor = a
	a.add_child(x)
	x._setup()
	return x

func _setup() -> void:
	skel = actor.skel
	for c in skel.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).skin:
			skin = (c as MeshInstance3D).skin
			mesh_xf = (c as MeshInstance3D).transform
	if skin == null:
		return
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = skel.find_bone(str(skin.get_bind_name(i)).replace(":", "_"))
		_bind_of[b] = i
	var id := actor.character_id
	var path := FIT_DIR + id + ".scn"
	if not ResourceLoader.exists(path):
		push_warning("Sin anatomía ajustada para " + id + " (correr tools/anatomy/fit_anatomy.gd)")
		return
	if not _scenes.has(id):
		_scenes[id] = load(path)
	if not _cpu.has(id):
		var inst: Node = (_scenes[id] as PackedScene).instantiate()
		var data := {}
		for mi in inst.get_children():
			var m := mi as MeshInstance3D
			var arr := m.mesh.surface_get_arrays(0)
			data[str(m.name)] = {"v": arr[Mesh.ARRAY_VERTEX], "i": arr[Mesh.ARRAY_INDEX], "aabb": m.mesh.get_aabb(),
				"label": str(m.get_meta("label")), "system": str(m.get_meta("system")), "bone": str(m.get_meta("bone")),
				"center": m.get_meta("center_bind"), "mesh": m.mesh}
		inst.free()
		_cpu[id] = data
	groups = _cpu[id]
	available = true

# ---------------------------------------------------------------- espacios

## Matriz de piel (enlace → esqueleto) del hueso en la pose actual.
func _skin_mat(bone_name: String) -> Transform3D:
	var b := skel.find_bone(bone_name)
	if b < 0 or not _bind_of.has(b):
		return Transform3D.IDENTITY
	return skel.get_bone_global_pose(b) * skin.get_bind_pose(_bind_of[b])

func world_to_bind(node: String, p: Vector3) -> Vector3:
	var m := _skin_mat(groups[node].bone) * mesh_xf
	return m.affine_inverse() * (skel.global_transform.affine_inverse() * p)

func bind_to_world(node: String, p: Vector3) -> Vector3:
	return skel.global_transform * (_skin_mat(groups[node].bone) * mesh_xf) * p

func dir_to_bind(node: String, d: Vector3) -> Vector3:
	var m := (_skin_mat(groups[node].bone) * mesh_xf).basis
	return (m.inverse() * (skel.global_transform.basis.inverse() * d)).normalized()

func find_group(label_prefix: String, near_world := Vector3.INF) -> String:
	var best := ""
	var bd := INF
	for n in groups:
		if not str(groups[n].label).begins_with(label_prefix):
			continue
		var d := 0.0
		if near_world != Vector3.INF:
			d = bind_to_world(n, groups[n].center).distance_to(near_world)
		if d < bd:
			bd = d
			best = n
	return best

# ---------------------------------------------------------------- trayectorias

## Estructuras que atraviesa un segmento (mundo): [{node, label, system, t_in, t_out, p_in, p_out (enlace), dir (enlace)}]
## ordenadas por distancia de entrada. max_depth: cuánto entra (esquirla / cuchillo); INF = lo atraviesa.
func trace(origin: Vector3, dir: Vector3, length: float, max_depth := INF) -> Array:
	var out := []
	if not available:
		return out
	dir = dir.normalized()
	var first_t := INF
	for n in groups:
		var g: Dictionary = groups[n]
		var a := world_to_bind(n, origin)
		var b := world_to_bind(n, origin + dir * length)
		var aabb: AABB = (g.aabb as AABB).grow(0.01)
		if not aabb.intersects_segment(a, b) and not aabb.has_point(a):
			continue
		var v: PackedVector3Array = g.v
		var idx: PackedInt32Array = g.i
		var tmin := INF
		var tmax := -INF
		var seg := b - a
		var sl := seg.length()
		var tri_count := idx.size() / 3
		var step := 1 if tri_count < 9000 else 2
		for k in range(0, idx.size(), 3 * step):
			var hit = Geometry3D.segment_intersects_triangle(a, b, v[idx[k]], v[idx[k + 1]], v[idx[k + 2]])
			if hit != null:
				var t := a.distance_to(hit) / maxf(sl, 1e-6) * length
				tmin = minf(tmin, t)
				tmax = maxf(tmax, t)
		if tmin == INF:
			continue
		if tmax - tmin < 0.004:
			tmax = tmin + 0.004
		out.append({"node": n, "label": g.label, "system": g.system, "t_in": tmin, "t_out": tmax,
			"p_in": a + seg / sl * (tmin / length * sl), "p_out": a + seg / sl * (tmax / length * sl), "dir": seg / sl})
		first_t = minf(first_t, tmin)
	out.sort_custom(func(x, y): return x.t_in < y.t_in)
	if max_depth < INF and first_t < INF:
		out = out.filter(func(x): return x.t_in <= first_t + max_depth)
		for x in out:
			if x.t_out > first_t + max_depth:
				x.t_out = first_t + max_depth
				x["lodged"] = true
	return out

## Grupos cuyo centro está a menos de radius (mundo).
func near(point: Vector3, radius: float, system := "") -> Array:
	var out := []
	for n in groups:
		if system != "" and groups[n].system != system:
			continue
		var c := bind_to_world(n, groups[n].center)
		var d := c.distance_to(point)
		if d < radius:
			out.append([d, n])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out.map(func(x): return x[1])

# ---------------------------------------------------------------- heridas

## type: 0 fractura · 1 túnel (bala/cuchillo) · 2 estallido (onda expansiva) · 3 esquirla alojada · 4 contusión
func add_wound(node: String, pos_bind: Vector3, dir_bind: Vector3, r: float, type: int, depth := 1.0) -> void:
	var arr: Array = wounds.get(node, [])
	if arr.size() >= MAX_WOUNDS:
		arr.pop_front()
	arr.append({"pos": pos_bind, "dir": dir_bind.normalized(), "r": r, "type": type, "depth": depth})
	wounds[node] = arr
	if meshes.has(node):
		_update_material(node)

func _mesh(node: String) -> MeshInstance3D:
	if meshes.has(node):
		return meshes[node]
	var mi := MeshInstance3D.new()
	mi.mesh = groups[node].mesh
	mi.skin = skin
	mi.transform = mesh_xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	skel.add_child(mi)
	mi.skeleton = mi.get_path_to(skel)
	meshes[node] = mi
	_update_material(node)
	return mi

const SYS_COLOR := {"hueso": Color(0.95, 0.92, 0.82), "musculo": Color(0.72, 0.17, 0.15), "organo": Color(0.78, 0.26, 0.28),
	"vaso": Color(0.75, 0.05, 0.08), "nervio": Color(0.95, 0.8, 0.45)}

func _update_material(node: String, overlay := false) -> void:
	var mi: MeshInstance3D = meshes[node]
	var m := ShaderMaterial.new()
	m.shader = _wshader(overlay)
	var g: Dictionary = groups[node]
	var aabb: AABB = g.aabb
	var axis := Vector3.UP
	if aabb.size.x >= aabb.size.y and aabb.size.x >= aabb.size.z:
		axis = Vector3.RIGHT
	elif aabb.size.z >= aabb.size.y:
		axis = Vector3.BACK
	m.set_shader_parameter("axis", axis)
	m.set_shader_parameter("base_color", SYS_COLOR.get(g.system, Color.WHITE))
	var ps := PackedVector4Array()
	var ds := PackedVector4Array()
	var arr: Array = wounds.get(node, [])
	for w in arr:
		ps.append(Vector4(w.pos.x, w.pos.y, w.pos.z, w.r))
		ds.append(Vector4(w.dir.x, w.dir.y, w.dir.z, float(w.type) + clampf(float(w.depth), 0.0, 0.99)))
	while ps.size() < MAX_WOUNDS:
		ps.append(Vector4(0, -100, 0, 0))
		ds.append(Vector4(0, 1, 0, 0))
	m.set_shader_parameter("w_pos", ps)
	m.set_shader_parameter("w_dir", ds)
	m.set_shader_parameter("w_count", arr.size())
	m.set_shader_parameter("flash", 0.0)
	mi.material_override = m

# ---------------------------------------------------------------- mostrar

## Destello en pleno juego: las partes recién dañadas se ven a través del cuerpo un instante (sin cámara lenta).
func show_flash(nodes: Array, seconds := 0.9) -> void:
	if Settings.xray == 0 or not available:
		return
	for n in nodes:
		var mi := _mesh(n)
		_update_material(n, true)
		mi.visible = Settings.xray >= 2 or groups[n].system == "hueso"
		(mi.material_override as ShaderMaterial).set_shader_parameter("flash", 1.0)
	_flash_t = seconds

## Toma de muerte: todas las heridas acumuladas, el cuerpo transparente alrededor.
func show_killcam() -> void:
	if not available:
		return
	_killcam = true
	for n in wounds:
		var mi := _mesh(n)
		_update_material(n, false)
		mi.visible = true
	for mi in actor.model.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).has_meta("actor_mesh"):
			_skin_saved[mi] = (mi as MeshInstance3D).material_override
			(mi as MeshInstance3D).material_override = _skin_mat_xray()

func hide_all() -> void:
	_killcam = false
	_flash_t = 0.0
	for n in meshes:
		(meshes[n] as MeshInstance3D).visible = false
	for mi in _skin_saved:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = _skin_saved[mi]
	_skin_saved.clear()

func _process(delta: float) -> void:
	if _flash_t > 0.0 and not _killcam:
		_flash_t -= delta / maxf(Engine.time_scale, 0.05)
		var k := clampf(_flash_t / 0.4, 0.0, 1.0)
		for n in meshes:
			var mi: MeshInstance3D = meshes[n]
			if mi.visible:
				(mi.material_override as ShaderMaterial).set_shader_parameter("flash", k)
		if _flash_t <= 0.0:
			for n in meshes:
				(meshes[n] as MeshInstance3D).visible = false

# ---------------------------------------------------------------- shaders

## overlay = true: se dibuja por encima del cuerpo (destello en el juego); false: dentro (toma de muerte, piel de rayos X).
static func _wshader(overlay := false) -> Shader:
	if overlay:
		if _flash_shader == null:
			_flash_shader = Shader.new()
			_flash_shader.code = _wshader(false).code.replace("render_mode cull_disabled, depth_draw_opaque;", "render_mode cull_disabled, depth_test_disabled, unshaded;")
		return _flash_shader
	if _wound_shader == null:
		_wound_shader = Shader.new()
		_wound_shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform vec3 axis = vec3(0.0, 1.0, 0.0);
uniform vec4 base_color : source_color = vec4(0.9, 0.9, 0.8, 1.0);
uniform vec4 w_pos[6];      // xyz = punto (enlace), w = radio
uniform vec4 w_dir[6];      // xyz = dirección, w = tipo (0 fractura, 1 túnel, 2 estallido, 3 alojada, 4 contusión) + profundidad
uniform int w_count = 0;
uniform float flash = 0.0;  // destello en el juego (se ve a través del cuerpo)
varying vec3 lp;
varying float wound_k;

float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

void vertex() {
	lp = CUSTOM0.xyz;
	wound_k = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= w_count) break;
		vec3 c = w_pos[i].xyz;
		float r = w_pos[i].w;
		int t = int(floor(w_dir[i].w));
		if (t == 0) {
			// fractura: los extremos quebrados se astillan hacia afuera
			float d = abs(dot(lp - c, axis));
			float near_break = 1.0 - smoothstep(r * 0.3, r * 2.2, d) * step(length((lp - c) - axis * dot(lp - c, axis)), r * 6.0);
			VERTEX += NORMAL * near_break * (0.004 + hash(floor(lp * 400.0)) * 0.012);
			wound_k = max(wound_k, near_break);
		} else if (t == 2) {
			float d = length(lp - c);
			float k = 1.0 - smoothstep(r * 0.5, r * 1.6, d);
			VERTEX += NORMAL * k * hash(floor(lp * 300.0)) * 0.01;
			wound_k = max(wound_k, k);
		}
	}
}

void fragment() {
	float rim = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= w_count) break;
		vec3 c = w_pos[i].xyz;
		float r = w_pos[i].w;
		vec3 dir = w_dir[i].xyz;
		int t = int(floor(w_dir[i].w));
		float depth = fract(w_dir[i].w);
		if (t == 0) {
			float s = dot(lp - c, axis);
			float jag = (sin(lp.x * 830.0) * sin(lp.z * 610.0) + sin(lp.y * 520.0)) * r * 0.3;
			float radial = length((lp - c) - axis * s);
			if (abs(s + jag) < r * 0.35 && radial < r * 8.0) { discard; }
			rim = max(rim, 1.0 - smoothstep(r * 0.35, r * 2.0, abs(s + jag)));
			// el túnel de la bala también atraviesa el hueso
			float dl = length(cross(lp - c, dir));
			if (dl < r * 0.6) { discard; }
		} else if (t == 1 || t == 3) {
			float along = dot(lp - c, dir);
			float dl = length(cross(lp - c, dir));
			bool inside_len = (t == 1) || (along > -r && along < depth * 0.25);
			if (dl < r && inside_len) { discard; }
			if (inside_len) { rim = max(rim, 1.0 - smoothstep(r, r * 2.6, dl)); }
		} else if (t == 2) {
			float d = length(lp - c);
			float n = hash(floor(lp * 120.0));
			if (d < r && n > 0.45) { discard; }
			rim = max(rim, 1.0 - smoothstep(r * 0.6, r * 1.8, d));
		} else {
			rim = max(rim, (1.0 - smoothstep(0.0, r * 2.0, length(lp - c))) * 0.6);
		}
	}
	vec3 wound = vec3(0.5, 0.02, 0.02);
	ALBEDO = mix(base_color.rgb, wound, clamp(rim + wound_k * 0.5, 0.0, 1.0));
	ROUGHNESS = 0.55;
	EMISSION = base_color.rgb * (0.25 + flash * 0.9) + vec3(1.0, 0.1, 0.02) * rim * 1.8;

}
"""
	return _wound_shader

static var _xray_skin: ShaderMaterial
static func _skin_mat_xray() -> ShaderMaterial:
	if _xray_skin == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = vec3(0.35, 0.75, 1.0) * (0.06 + f * 0.8);
}
"""
		_xray_skin = ShaderMaterial.new()
		_xray_skin.shader = sh
	return _xray_skin
