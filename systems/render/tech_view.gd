extends Node
## VISUALIZACIÓN TÉCNICA 3D (experimento, autoload «TechView»). Prueba el estilo de ilustración técnica sobre el juego
## real (mapa, personajes, armas, efectos) sin tocar los recursos originales y de forma reversible:
##   0 DESACTIVADA        → el juego como siempre.
##   1 A · FILTRO         → una pasada de pantalla: papel blanco en 4 tonos de gris + líneas por profundidad; el rojo
##                          (sangre, láser) se conserva. No cambia ningún material.
##   2 B · MATERIALES     → cambia TEMPORALMENTE los materiales por un sombreado técnico de 4 tonos (sin luces) y agrega
##                          contorno de silueta (casco invertido). Guarda los originales y los devuelve al desactivar.
##   3 C · HÍBRIDO        → B + líneas interiores de pantalla (pliegues, uniones, escalones) sin filtro de color.
##   4 D · PLANO DIBUJADO → sin texturas ni luces ni sombras: cada plano del mapa en un tono de papel y sus ARISTAS como
##                          geometría de líneas fija (se calcula una vez); personajes y armas con contorno. El más liviano
##                          por píxel. La colisión y la física son las mismas (sólo cambia el dibujo).
## Rayos X: 0 realista · 1 técnico gris · 2 técnico con colores (la anatomía dibujada con líneas pero con sus colores).
## Nada se guarda en disco: es para probar en la sesión (Modo práctica › VISUALIZACIÓN TÉCNICA 3D).

signal changed

const MODES := ["Desactivada", "A · Filtro sobre el juego", "B · Materiales técnicos", "C · Híbrido (B + líneas)", "D · Plano dibujado"]
const XRAY := ["Rayos X realista", "Rayos X técnico (gris)", "Rayos X técnico con colores"]

var mode := 0
var xray_style := 0
var line_w := 1.6           ## grosor de las líneas (px)
var line_k := 1.0           ## intensidad de las líneas
var shade := 1.0            ## intensidad del sombreado de 4 tonos
var detail := 0.25          ## cuánto del color original se conserva
var contrast := 1.0
var red := 1.0              ## intensidad del rojo (sangre, láser) en el filtro

var _orig := {}             ## instance_id → [MeshInstance3D, material_override, [overrides por superficie]]
var _mats := {}             ## clave (textura/color) → ShaderMaterial técnico
var _outline: ShaderMaterial
var _post: MeshInstance3D
var _post_mat: ShaderMaterial
var _scan_t := 0.0
var _flat: ShaderMaterial
var _lines_mat: ShaderMaterial
var _line_cache := {}       ## mesh → ArrayMesh de aristas
var _lines_nodes: Array = []
var _lights := {}           ## luz → visible original
var _env := {}              ## Environment → [modo de fondo, color]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in [["tech_line_w", line_w], ["tech_line_k", line_k], ["tech_shade", shade], ["tech_detail", detail],
			["tech_contrast", contrast], ["tech_red", red], ["tech_xray", 0.0], ["tech_on", 0.0]]:
		RenderingServer.global_shader_parameter_add(str(p[0]), RenderingServer.GLOBAL_VAR_TYPE_FLOAT, float(p[1]))
	get_tree().node_added.connect(func(n: Node):
		if mode < 2:
			return
		if n is MeshInstance3D:
			_dirty = true
			_pending.append(n)
			_queue_flush()
		elif n is Light3D or n is WorldEnvironment:
			_lights_dirty = true
			_queue_flush())
	if DisplayServer.get_name() != "headless":          # sin pantalla (pruebas) no hay datos de malla para las aristas
		set_mode.call_deferred(4)        # estilo por defecto: D · Plano dibujado (el modo práctica permite volver al original)

## Cambia el modo (y aplica en el acto sobre lo que está en pantalla).
func set_mode(m: int) -> void:
	if m == mode:
		return
	_restore_all()
	mode = m
	RenderingServer.global_shader_parameter_set("tech_on", 1.0 if mode >= 2 else 0.0)
	if mode >= 2:
		_convert_tree(get_tree().root)
	if mode == 4:
		_lights_off()
	_update_post()
	changed.emit()

func set_param(key: String, v: float) -> void:
	set(key, v)
	var g := {"line_w": "tech_line_w", "line_k": "tech_line_k", "shade": "tech_shade", "detail": "tech_detail",
		"contrast": "tech_contrast", "red": "tech_red"}
	if g.has(key):
		RenderingServer.global_shader_parameter_set(g[key], v)

func set_xray(s: int) -> void:
	xray_style = s
	RenderingServer.global_shader_parameter_set("tech_xray", float(s))

var _pending: Array = []          ## mallas recién agregadas: se convierten antes de dibujar el cuadro (nunca se ve el color original)
var _lights_dirty := false
var _flush_q := false
func _queue_flush() -> void:
	if not _flush_q:
		_flush_q = true
		_flush_pending.call_deferred()

func _flush_pending() -> void:
	_flush_q = false
	if mode < 2:
		_pending.clear()
		return
	_batch = {}
	for n in _pending:
		if is_instance_valid(n) and (n as Node).is_inside_tree():
			_try_convert(n as MeshInstance3D)
	_pending.clear()
	_batch_commit(get_tree().root)
	if mode == 4 and _lights_dirty:
		_lights_off()
	_lights_dirty = false

var _dirty := false         ## apareció una malla nueva: se convierte en seguida (sin cuadros con los colores originales)
func _process(delta: float) -> void:
	if mode == 0:
		return
	if _dirty:
		_dirty = false
		_scan_t = minf(_scan_t, 0.03)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.5
		_update_post()
		if mode >= 2:
			_convert_tree(get_tree().root)        # lo que apareció después (cajas rotas, armas recogidas…)
		if mode == 4:
			_lights_off()                         # luces de escenas nuevas (al entrar a la Torre)

# ------------------------------------------------------------------------------------------------ materiales (B, C)

## Lo que NO se convierte: efectos (sangre, chispas, humo), balas y trazadoras, láseres, anatomía (tiene su propio
## estilo de rayos X), el menú y la interfaz.
func _skip(n: Node) -> bool:
	var p := n
	while p:
		if p.has_meta("no_tech") or p is Blood or p is Gibs or p is Ballistics or p is AnatomyBody:
			return true
		if p.name == "FxPool":
			return true
		p = p.get_parent()
	return false

func _convert_tree(root: Node) -> void:
	_batch = {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		_try_convert(n as MeshInstance3D)
	_batch_commit(root)

func _try_convert(mi: MeshInstance3D) -> void:
	if mi.mesh == null or _orig.has(mi.get_instance_id()) or mi.has_meta("tech_skip_checked"):
		return
	if mi.has_meta("actor_mesh") and mi.material_override is ShaderMaterial:
		return                            # ventana de rayos X encendida: se convierte cuando termine (no pisar su material)
	if _skip(mi):
		mi.set_meta("tech_skip_checked", true)
		return
	_convert(mi)

func _convert(mi: MeshInstance3D) -> void:
	var surf := []
	for s in mi.mesh.get_surface_count():
		surf.append(mi.get_surface_override_material(s))
	_orig[mi.get_instance_id()] = [mi, mi.material_override, surf]
	var moving := mi.skin != null or _under_actor(mi)
	if mode == 4 and not moving:
		# mapa y objetos quietos: tono plano por plano + aristas dibujadas (geometría fija, se calcula una vez)
		mi.material_override = _flat_mat()
		var ln := _lines_for(mi.mesh)
		if ln:
			if _is_static(mi):
				_batch_add(ln, mi.global_transform)        # mapa fijo: a un bloque por sector (pocas llamadas de dibujo)
			else:
				var lm := MeshInstance3D.new()
				lm.name = "TechLines"
				lm.mesh = ln
				lm.material_override = _lines_mat_get()
				lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				lm.set_meta("no_tech", true)
				lm.extra_cull_margin = 0.5
				mi.add_child(lm)
				_lines_nodes.append(lm)
		return
	# contorno de silueta: personajes, armas, cajas y objetos (en el híbrido la arquitectura usa las líneas de pantalla)
	var small := mi.get_aabb().size.length() < 6.0
	var outline := mode == 2 or mode == 4 or small
	mi.material_override = null
	for s in mi.mesh.get_surface_count():
		var src: Material = surf[s] if surf[s] else mi.mesh.surface_get_material(s)
		mi.set_surface_override_material(s, _tech_for(src, outline))

func _tech_for(src: Material, outline: bool) -> ShaderMaterial:
	var tex: Texture2D = null
	var col := Color(0.8, 0.8, 0.8)
	if src is StandardMaterial3D:
		tex = (src as StandardMaterial3D).albedo_texture
		col = (src as StandardMaterial3D).albedo_color
	var key := "%s|%s|%s" % [str(tex.get_instance_id()) if tex else "-", col.to_html(), outline]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://systems/render/tech_surface.gdshader")
	m.set_shader_parameter("has_tex", tex != null)
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("albedo", col)
	if outline:
		if _outline == null:
			_outline = ShaderMaterial.new()
			_outline.shader = load("res://systems/render/tech_outline.gdshader")
		m.next_pass = _outline
	_mats[key] = m
	return m

## ¿Es parte fija del mapa? (no se mueve ni se rompe: ni cuerpos físicos, ni puertas, ni cajas destructibles)
func _is_static(mi: Node3D) -> bool:
	var p := mi.get_parent()
	while p:
		if p is RigidBody3D or p is AnimatableBody3D or p is CharacterBody3D or p is Destructible or p is Interactable:
			return false
		p = p.get_parent()
	return true

var _batch := {}            ## sector (15 m) → [vértices, custom, índices]
const BATCH := 15.0
func _batch_add(ln: ArrayMesh, xf: Transform3D) -> void:
	var arr := ln.surface_get_arrays(0)
	if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null or arr[Mesh.ARRAY_CUSTOM0] == null:
		return                          # sin renderizador (pruebas sin pantalla): no hay datos de malla
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cc: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var key := int(floor(xf.origin.x / BATCH)) if vv.is_empty() else int(floor((xf * vv[0]).x / BATCH))
	if not _batch.has(key):
		_batch[key] = [PackedVector3Array(), PackedFloat32Array(), PackedInt32Array()]
	var b: Array = _batch[key]
	# (los arreglos compactos se COPIAN al leerlos de una lista: se trabaja sobre variables y se vuelven a guardar)
	var bv: PackedVector3Array = b[0]
	var bc: PackedFloat32Array = b[1]
	var bi: PackedInt32Array = b[2]
	var base := bv.size()
	for k in vv.size():
		bv.append(xf * vv[k])
		var o := xf * Vector3(cc[k * 4], cc[k * 4 + 1], cc[k * 4 + 2])
		bc.append_array([o.x, o.y, o.z, cc[k * 4 + 3]])
	for k in ii:
		bi.append(base + k)
	_batch[key] = [bv, bc, bi]

## Borra las líneas agrupadas de lo que ya no existe (al salir de una escena); lo nuevo se vuelve a convertir.
func purge_lines() -> void:
	for ln in _lines_nodes:
		if is_instance_valid(ln):
			(ln as Node).queue_free()
	_lines_nodes.clear()
	for k in _orig.keys():
		var e: Array = _orig[k]
		if not is_instance_valid(e[0]):
			_orig.erase(k)

func _batch_commit(root: Node) -> void:
	for key in _batch:
		var b: Array = _batch[key]
		if (b[0] as PackedVector3Array).is_empty():
			continue
		var la := []
		la.resize(Mesh.ARRAY_MAX)
		la[Mesh.ARRAY_VERTEX] = b[0]
		la[Mesh.ARRAY_CUSTOM0] = b[1]
		la[Mesh.ARRAY_INDEX] = b[2]
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, la, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var lm := MeshInstance3D.new()
		lm.name = "TechLinesSector%d" % key
		lm.mesh = am
		lm.material_override = _lines_mat_get()
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lm.set_meta("no_tech", true)
		lm.extra_cull_margin = 0.5
		var host: Node = get_tree().current_scene if get_tree().current_scene else root
		host.add_child(lm)
		_lines_nodes.append(lm)
	_batch = {}

func _under_actor(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is Actor:
			return true
		p = p.get_parent()
	return false

func _flat_mat() -> ShaderMaterial:
	if _flat == null:
		_flat = ShaderMaterial.new()
		_flat.shader = load("res://systems/render/tech_flat.gdshader")
	return _flat

func _lines_mat_get() -> ShaderMaterial:
	if _lines_mat == null:
		_lines_mat = ShaderMaterial.new()
		_lines_mat.shader = load("res://systems/render/tech_lines.gdshader")
	return _lines_mat

## Aristas «de dibujo» de una malla: bordes abiertos y pliegues (caras vecinas a más de ~25°). Cada arista → cinta de
## 4 vértices que el shader engorda en pantalla. Se calcula una vez por malla (cache).
func _lines_for(mesh: Mesh) -> ArrayMesh:
	if _line_cache.has(mesh):
		return _line_cache[mesh]
	var am := LinedBake.lines_for(mesh)
	_line_cache[mesh] = am
	return am

## Modo D: sin luces reales ni sombras, fondo de papel. Se guarda todo para devolverlo al salir.
func _lights_off() -> void:
	_veils_light()
	for l in get_tree().root.find_children("*", "Light3D", true, false):
		if not _lights.has(l):
			_lights[l] = (l as Light3D).visible
		(l as Light3D).visible = false
	for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var e: Environment = (we as WorldEnvironment).environment
		if e and not _env.has(e) and not _skip(we):
			_env[e] = [e.background_mode, e.background_color]
			e.background_mode = Environment.BG_COLOR
			e.background_color = Color(0.84, 0.84, 0.83)

## Velos de sectores sin explorar: en el plano dibujado van en gris claro (no en gris oscuro).
var _veils := {}
func _veils_light() -> void:
	for v in get_tree().get_nodes_in_group("perf_cubiertas"):
		var mm := (v as MeshInstance3D).material_override as StandardMaterial3D
		if mm and not _veils.has(mm):
			_veils[mm] = mm.albedo_color
			mm.albedo_color = Color(0.78, 0.78, 0.77, mm.albedo_color.a)

func _veils_restore() -> void:
	for mm in _veils:
		if mm:
			var c: Color = _veils[mm]
			(mm as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, (mm as StandardMaterial3D).albedo_color.a)
	_veils.clear()

func _lights_restore() -> void:
	_veils_restore()
	for l in _lights:
		if is_instance_valid(l):
			(l as Light3D).visible = _lights[l]
	_lights.clear()
	for e in _env:
		if e:
			(e as Environment).background_mode = _env[e][0]
			(e as Environment).background_color = _env[e][1]
	_env.clear()

## Color del láser según el estilo: en tinta (casi negro) sobre papel, rojo en el juego normal.
func laser_color(player: bool) -> Color:
	if mode >= 1:
		return Color(0.08, 0.08, 0.09, 0.95) if player else Color(0.35, 0.3, 0.25, 0.75)
	return Color(1.0, 0.05, 0.03, 0.75) if player else Color(1.0, 0.55, 0.05, 0.45)

## Explosión en el estilo técnico: una onda expansiva de LÍNEAS (anillos que crecen y rayas radiales), no fuego.
func shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.6, radius * 2.6)
	mi.mesh = qm
	mi.set_meta("no_tech", true)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float t = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ink = 0.0;
	for (int i = 0; i < 3; i++) {
		float rr = t * (1.0 - float(i) * 0.18);
		float w = 0.012 + 0.01 * float(i);
		ink = max(ink, (1.0 - smoothstep(w * 0.5, w, abs(r - rr))) * (1.0 - float(i) * 0.3));
	}
	float rays = step(0.82, fract(a * 4.77)) * smoothstep(t * 0.35, t * 0.6, r) * (1.0 - smoothstep(t * 0.75, t * 0.95, r));
	ink = max(ink, rays * 0.8);
	float fade = 1.0 - smoothstep(0.65, 1.0, t);
	ALBEDO = vec3(0.1, 0.1, 0.11);
	ALPHA = ink * fade;
}"""
	m.shader = sh
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.6, 0.4)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("t", v), 0.0, 1.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(mi.queue_free)

func _restore_all() -> void:
	for ln in _lines_nodes:
		if is_instance_valid(ln):
			(ln as Node).queue_free()
	_lines_nodes.clear()
	_lights_restore()
	for id in _orig:
		var e: Array = _orig[id]
		var mi = e[0]
		if not is_instance_valid(mi):
			continue
		(mi as MeshInstance3D).material_override = e[1]
		var surf: Array = e[2]
		for s in surf.size():
			if s < (mi as MeshInstance3D).mesh.get_surface_count():
				(mi as MeshInstance3D).set_surface_override_material(s, surf[s])
	_orig.clear()
	for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta("tech_skip_checked"):
			n.remove_meta("tech_skip_checked")

# ------------------------------------------------------------------------------------------------ pasada de pantalla (A, C)

func _update_post() -> void:
	var want := mode == 1 or mode == 3
	var cam := get_viewport().get_camera_3d()
	if not want or cam == null:
		if _post and is_instance_valid(_post):
			_post.queue_free()
		_post = null
		return
	if _post == null or not is_instance_valid(_post) or _post.get_parent() != cam:
		if _post and is_instance_valid(_post):
			_post.queue_free()
		_post = MeshInstance3D.new()
		_post.name = "TechPost"
		_post.set_meta("no_tech", true)
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		_post.mesh = q
		_post.extra_cull_margin = 16384.0
		_post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _post_mat == null:
			_post_mat = ShaderMaterial.new()
			_post_mat.shader = load("res://systems/render/tech_post.gdshader")
			# primero entre lo transparente: la anatomía (rayos X), la sangre y los efectos se dibujan ENCIMA, no tapados
			_post_mat.render_priority = -128
		_post.material_override = _post_mat
		cam.add_child(_post)
	_post_mat.set_shader_parameter("filter_k", 1.0 if mode == 1 else 0.0)
