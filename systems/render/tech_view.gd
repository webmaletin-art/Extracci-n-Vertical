extends Node
## VISUALIZACIÓN TÉCNICA 3D (experimento, autoload «TechView»). Prueba el estilo de ilustración técnica sobre el juego
## real (mapa, personajes, armas, efectos) sin tocar los recursos originales y de forma reversible:
##   0 DESACTIVADA        → el juego como siempre.
##   1 A · FILTRO         → una pasada de pantalla: papel blanco en 4 tonos de gris + líneas por profundidad; el rojo
##                          (sangre, láser) se conserva. No cambia ningún material.
##   2 B · MATERIALES     → cambia TEMPORALMENTE los materiales por un sombreado técnico de 4 tonos (sin luces) y agrega
##                          contorno de silueta (casco invertido). Guarda los originales y los devuelve al desactivar.
##   3 C · HÍBRIDO        → B + líneas interiores de pantalla (pliegues, uniones, escalones) sin filtro de color.
## Rayos X: 0 realista · 1 técnico gris · 2 técnico con colores (la anatomía dibujada con líneas pero con sus colores).
## Nada se guarda en disco: es para probar en la sesión (Modo práctica › VISUALIZACIÓN TÉCNICA 3D).

signal changed

const MODES := ["Desactivada", "A · Filtro sobre el juego", "B · Materiales técnicos", "C · Híbrido (B + líneas)"]
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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in [["tech_line_w", line_w], ["tech_line_k", line_k], ["tech_shade", shade], ["tech_detail", detail],
			["tech_contrast", contrast], ["tech_red", red], ["tech_xray", 0.0], ["tech_on", 0.0]]:
		RenderingServer.global_shader_parameter_add(str(p[0]), RenderingServer.GLOBAL_VAR_TYPE_FLOAT, float(p[1]))

## Cambia el modo (y aplica en el acto sobre lo que está en pantalla).
func set_mode(m: int) -> void:
	if m == mode:
		return
	_restore_all()
	mode = m
	RenderingServer.global_shader_parameter_set("tech_on", 1.0 if mode >= 2 else 0.0)
	if mode >= 2:
		_convert_tree(get_tree().root)
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

func _process(delta: float) -> void:
	if mode == 0:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.5
		_update_post()
		if mode >= 2:
			_convert_tree(get_tree().root)        # lo que apareció después (cajas rotas, armas recogidas…)

# ------------------------------------------------------------------------------------------------ materiales (B, C)

## Lo que NO se convierte: efectos (sangre, chispas, humo), balas y trazadoras, láseres, anatomía (tiene su propio
## estilo de rayos X), el menú y la interfaz.
func _skip(n: Node) -> bool:
	var p := n
	while p:
		if p.has_meta("no_tech") or p is Blood or p is Gibs or p is Ballistics or p is MenuTower or p is AnatomyBody:
			return true
		if p.name == "FxPool":
			return true
		p = p.get_parent()
	return false

func _convert_tree(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or _orig.has(mi.get_instance_id()) or mi.has_meta("tech_skip_checked"):
			continue
		if _skip(mi):
			mi.set_meta("tech_skip_checked", true)
			continue
		_convert(mi)

func _convert(mi: MeshInstance3D) -> void:
	var surf := []
	for s in mi.mesh.get_surface_count():
		surf.append(mi.get_surface_override_material(s))
	_orig[mi.get_instance_id()] = [mi, mi.material_override, surf]
	# contorno de silueta: personajes, armas, cajas y objetos (en el híbrido la arquitectura usa las líneas de pantalla)
	var small := mi.get_aabb().size.length() < 6.0
	var outline := mode == 2 or small
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

func _restore_all() -> void:
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
