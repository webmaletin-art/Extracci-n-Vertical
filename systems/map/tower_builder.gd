class_name TowerBuilder
extends Node3D
## Arma la Torre Alfa a partir de TorreAlfa.data(): losas con huecos, pared del fondo, tabiques con puertas / conductos /
## puerta con llave, entrepisos y tarimas, escaleras de mano y escalera inclinada, ascensor, cráter de escombros,
## plataforma móvil, cajas rompibles y contenedores de botín, decorado (galería Sweet Home 3D de Nexus), lámparas, fondo
## lejano, zonas de extracción y enemigos.
##
## Rendimiento: la geometría fija de cada piso se junta en una malla por material (BoxBatcher); cada piso es un nodo
## propio (se ocultan los pisos lejanos a la cámara, ver Game._update_floor_visibility); el decorado va en grupos por
## nivel de detalle para que Settings.decor y el captador de rendimiento lo puedan apagar.
## Grupos que usa el captador de rendimiento: perf_fondo, perf_decorado, perf_luces, perf_tuberias, perf_cubiertas,
## perf_destructibles, perf_personajes, perf_cajas_botin, perf_escombros, perf_carteles.

signal extracted(actor: Actor, label: String)

const Z_BACK := -1.25            ## pared del fondo (el jugador camina en z = 0)
const Z_FRONT := 0.7             ## borde delantero de los pisos: sólo hace falta lugar para pisar
const DEPTH := Z_FRONT - Z_BACK

var data := {}
var graph: MapGraph
var floors_nodes: Array[Node3D] = []
var covers := {}               ## id de sector → MeshInstance3D (velo del sector sin descubrir)
var revealed := {}
var elevator: Elevator
var lamp_data: Array = []         ## [{pos, color, energy, floor, alarm}] focos PINTADOS en los materiales (no son luces reales)
var light_pool: Array[OmniLight3D] = []   ## 0–4 luces reales que siguen al jugador (sólo afectan personajes y objetos)
var _pool_t := 0.0
var cm := {}                     ## materiales del escenario del piso que se está armando (shader liviano, luz pintada)
var _floor_mats := {}
var enemies: Array[Actor] = []
var mats := {}
var stats := {"tris_static": 0, "props": 0, "lamps": 0}

func build(d: Dictionary) -> void:
	data = d
	graph = MapGraph.from_data(d)
	_make_materials()
	var fh := float(d.floor_h)
	var nf: int = d.floors.size()
	_collect_lamps(d)
	for f in d.floors:
		var node := Node3D.new()
		node.name = "Piso%d" % f.id
		node.add_to_group("floor_%d" % f.id)
		add_child(node)
		floors_nodes.append(node)
		_build_floor(node, f, fh)
	_build_roof(d, nf * fh)
	_build_ground(d)
	_build_ladders(d)
	_build_stairs(d)
	_build_crater(d)
	_build_elevator(d)
	_build_covers()
	_build_light_pool()
	_build_environment()

## Focos del escenario (de los datos del mapa): se pintan en los materiales y se dibuja un artefacto emisivo en cada uno.
func _collect_lamps(d: Dictionary) -> void:
	var fh := float(d.floor_h)
	var slab := float(TorreAlfa.SLAB)
	for f in d.floors:
		var y := float(f.id) * fh
		for lx in f.lamps:
			lamp_data.append({"pos": Vector3(float(lx), y + fh - slab - 0.55, 0.2), "color": Color(1.0, 0.8, 0.55), "energy": 1.5,
				"floor": int(f.id), "alarm": false})
		if int(f.id) % 2 == 1:
			lamp_data.append({"pos": Vector3(float(f.lamps[0]) + 1.5, y + 2.8, Z_BACK + 0.4), "color": Color(1.0, 0.12, 0.05), "energy": 1.1,
				"floor": int(f.id), "alarm": true})

# ---------------------------------------------------------------- materiales

func _tex_mat(tex: String, uv := 1.0, metal := 0.0, rough := 0.85, tint := Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s.png" % tex)
	m.albedo_color = tint
	m.uv1_scale = Vector3(uv, uv, 1)
	m.metallic = metal
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _col_mat(c: Color, metal := 0.0, rough := 0.8, emission := Color.BLACK, e_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if e_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = e_energy
	return m

## Materiales livianos del escenario para un piso: shader sin luces reales con la luz de SUS lámparas pintada
## (fast_surface.gdshader). Se crean una vez por piso porque cada piso tiene sus propias lámparas.
func _fast(tex: String, tint: Color, uv: float, paint: int, lamps: Array, ambient := 0.30) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://systems/map/fast_surface.gdshader")
	if tex != "":
		m.set_shader_parameter("tex", load("res://assets/textures/%s.png" % tex))
	else:
		m.set_shader_parameter("tex", _white_tex())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("uv_scale", uv)
	m.set_shader_parameter("paint", paint)
	m.set_shader_parameter("ambient", ambient)
	m.set_shader_parameter("floor_h", float(data.get("floor_h", 4.5)))
	var ps := PackedVector4Array()
	var cs := PackedVector4Array()
	for l in lamps:
		ps.append(Vector4(l.pos.x, l.pos.y, l.pos.z, 64.0 if not l.alarm else 36.0))
		cs.append(Vector4(l.color.r * l.energy, l.color.g * l.energy, l.color.b * l.energy, 1.0))
	while ps.size() < 8:
		ps.append(Vector4(0, -1000, 0, 1))
		cs.append(Vector4(0, 0, 0, 0))
	m.set_shader_parameter("lamp_p", ps)
	m.set_shader_parameter("lamp_c", cs)
	return m

static var _wt: Texture2D
static func _white_tex() -> Texture2D:
	if _wt == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		_wt = ImageTexture.create_from_image(img)
	return _wt

func _use_floor(fi: int) -> void:
	if not _floor_mats.has(fi):
		var ls := lamp_data.filter(func(l): return int(l.floor) == fi)
		_floor_mats[fi] = {
			"concrete": _fast("concrete", Color.WHITE, 1.0, 1, ls),
			"concrete_dark": _fast("concrete", Color(0.55, 0.55, 0.58), 1.0, 2, ls, 0.26),
			"floor": _fast("floor_plate", Color.WHITE, 1.0, 2, ls),
			"metal_panel": _fast("metal_panel", Color.WHITE, 1.0, 1, ls),
			"hazard": _fast("hazard", Color.WHITE, 2.0, 0, ls),
			"rubble": _fast("concrete", Color(0.62, 0.58, 0.52), 2.0, 2, ls),
			"steel": _fast("", Color(0.22, 0.23, 0.26), 1.0, 0, ls),
			"yellow": _fast("", Color(0.9, 0.66, 0.08), 1.0, 0, ls, 0.5),
		}
	cm = _floor_mats[fi]

func _make_materials() -> void:
	mats.concrete = _tex_mat("concrete", 1.0, 0.0, 0.9)
	mats.concrete_dark = _tex_mat("concrete", 1.0, 0.0, 0.95, Color(0.55, 0.55, 0.58))
	mats.floor = _tex_mat("floor_plate", 1.0, 0.45, 0.6)
	mats.metal_panel = _tex_mat("metal_panel", 1.0, 0.5, 0.6)
	mats.hazard = _tex_mat("hazard", 2.0, 0.2, 0.7)
	mats.rubble = _tex_mat("concrete", 2.0, 0.0, 1.0, Color(0.62, 0.58, 0.52))
	mats.steel = _col_mat(Color(0.18, 0.19, 0.21), 0.75, 0.45)
	mats.pipe = _col_mat(Color(0.28, 0.3, 0.3), 0.6, 0.5)
	mats.pipe_red = _col_mat(Color(0.45, 0.08, 0.05), 0.4, 0.6)
	mats.yellow = _col_mat(Color(0.9, 0.66, 0.08), 0.5, 0.5)
	mats.lamp = _col_mat(Color(1, 0.9, 0.7), 0.0, 0.5, Color(1.0, 0.82, 0.55), 4.0)
	mats.red_light = _col_mat(Color(1, 0.1, 0.05), 0.0, 0.5, Color(1.0, 0.1, 0.05), 3.0)
	mats.grating = _tex_mat("grating", 1.0, 0.6, 0.5)
	(mats.grating as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	(mats.grating as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED

# ---------------------------------------------------------------- pisos

func _segments(x0: float, x1: float, holes: Array) -> Array:
	var segs := [[x0, x1]]
	for h in holes:
		var out := []
		for s in segs:
			var a := float(s[0])
			var b := float(s[1])
			var h0 := float(h[0])
			var h1 := float(h[1])
			if h1 <= a or h0 >= b:
				out.append(s)
				continue
			if h0 > a:
				out.append([a, h0])
			if h1 < b:
				out.append([h1, b])
		segs = out
	return segs

func _static_body(parent: Node3D, surface := "concrete") -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("surface", surface)
	parent.add_child(sb)
	return sb

func _shape(sb: StaticBody3D, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.transform = Transform3D(basis, center)
	sb.add_child(cs)

func _build_floor(node: Node3D, f: Dictionary, fh: float) -> void:
	_use_floor(int(f.id))
	var y := float(f.id) * fh
	var w := float(data.width)
	var bb := BoxBatcher.new()
	var body := _static_body(node, "metal" if f.wall_tex == "metal_panel" else "concrete")
	var slab := float(TorreAlfa.SLAB)
	# losa del piso (con huecos)
	for s in _segments(0.0, w, f.holes):
		var x0 := float(s[0])
		var x1 := float(s[1])
		var c := Vector3((x0 + x1) * 0.5, y - slab * 0.5, (Z_BACK + Z_FRONT) * 0.5)
		var sz := Vector3(x1 - x0, slab, DEPTH)
		bb.add_box("floor", cm.floor, c + Vector3(0, slab * 0.25, 0), Vector3(sz.x, slab * 0.5, sz.z))
		bb.add_box("concrete_dark", cm.concrete_dark, c - Vector3(0, slab * 0.25, 0), Vector3(sz.x, slab * 0.5, sz.z))
		_shape(body, c, sz)
	# bordes de los huecos: franjas de peligro y barandas bajas en el frente
	for h in f.holes:
		for edge in [float(h[0]), float(h[1])]:
			bb.add_box("hazard", cm.hazard, Vector3(edge, y + 0.01, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.18, 0.02, DEPTH))
	# pared del fondo
	var wall_mat: Material = cm.concrete if f.wall_tex == "concrete" else cm.metal_panel
	bb.add_box("wall_" + str(f.wall_tex), wall_mat, Vector3(w * 0.5, y + (fh - slab) * 0.5, Z_BACK - 0.1), Vector3(w, fh - slab, 0.2))
	_shape(body, Vector3(w * 0.5, y + (fh - slab) * 0.5, Z_BACK - 0.1), Vector3(w, fh - slab, 0.2))
	# paredes exteriores (con ventanas en el lado derecho)
	for ex in [-0.15, w + 0.15]:
		bb.add_box("concrete", cm.concrete, Vector3(ex, y + (fh - slab) * 0.5, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.3, fh - slab, DEPTH))
		_shape(body, Vector3(ex, y + (fh - slab) * 0.5, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.3, fh - slab, DEPTH))
	# tabiques
	for wl in f.walls:
		_build_wall(node, bb, body, float(wl[0]), y, fh - slab, str(wl[1]))
	# tarimas y entrepisos
	for p in f.platforms:
		var x0 := float(p[0])
		var x1 := float(p[1])
		var hgt := float(p[2])
		if hgt <= 1.35:
			var c := Vector3((x0 + x1) * 0.5, y + hgt * 0.5, -0.3)
			bb.add_box("metal_panel", cm.metal_panel, c, Vector3(x1 - x0, hgt, 1.9))
			bb.add_box("hazard", cm.hazard, Vector3(c.x, y + hgt + 0.005, 0.6), Vector3(x1 - x0, 0.01, 0.12))
			_shape(body, c, Vector3(x1 - x0, hgt, 1.9))
		else:
			var c := Vector3((x0 + x1) * 0.5, y + hgt - 0.1, -0.3)
			bb.add_box("floor", cm.floor, c, Vector3(x1 - x0, 0.2, 1.9))
			_shape(body, c, Vector3(x1 - x0, 0.2, 1.9))
			for px in [x0 + 0.15, x1 - 0.15]:
				bb.add_box("steel", cm.steel, Vector3(px, y + (hgt - 0.2) * 0.5, 0.45), Vector3(0.12, hgt - 0.2, 0.12))
				bb.add_box("steel", cm.steel, Vector3(px, y + (hgt - 0.2) * 0.5, -1.05), Vector3(0.12, hgt - 0.2, 0.12))
			# baranda del frente
			bb.add_box("yellow", cm.yellow, Vector3(c.x, y + hgt + 0.95, 0.6), Vector3(x1 - x0, 0.05, 0.05))
	# tuberías, cables y manchas: PINTADOS en el shader de la pared (sin geometría)
	var meshes := bb.commit(node, false)
	stats.tris_static += bb.tris
	for m in meshes:
		m.add_to_group("perf_estructura")
	# carteles (B0..B4) y número de piso
	for k in range(0, int(w), 15):
		var lab := Label3D.new()
		lab.text = str(f.tag)
		lab.font_size = 220
		lab.modulate = Color(0.75, 0.75, 0.78, 0.35)
		lab.outline_size = 0
		lab.position = Vector3(k + 6.5, y + 2.2, Z_BACK + 0.02)
		lab.shaded = false
		lab.add_to_group("perf_carteles")
		node.add_child(lab)
	# lámparas
	for lx in f.lamps:
		_lamp(node, Vector3(float(lx), y + fh - slab - 0.25, -0.4), f.id)
	if int(f.id) % 2 == 1:
		_red_light(node, Vector3(float(f.lamps[0]) + 1.5, y + 2.8, Z_BACK + 0.05))
	# decorado (galería) y coberturas
	for p in f.props:
		_prop(node, str(p[1]), Vector3(float(p[0]), y, -0.7 if str(p[3]) == "decor" else -0.3), float(p[2]), str(p[3]))
	# cajas y contenedores
	for c in f.crates:
		_crate(node, float(c[0]), y + float(c[3]), str(c[1]), str(c[2]), int(f.id))
	for pk in f.get("pickups", []):
		var p := WorldInteractables.Pickup.new()
		p.item_id = str(pk[1])
		node.add_child(p)
		p.global_position = Vector3(float(pk[0]), y + 0.02, 0)
	if f.has("moving_platform"):
		_moving_platform(node, f.moving_platform, y)
	if f.has("hazard"):
		_hazard(node, f.hazard, y)
	for lv in f.get("levers", []):       # [x, id de la persiana que abre]
		var l := WorldInteractables.Lever.new()
		l.lever_id = str(lv[1])
		node.add_child(l)
		l.global_position = Vector3(float(lv[0]), y, Z_BACK + 0.35)
	for gt in f.get("gas_traps", []):    # [x palanca, x0 nube, x1 nube]
		var g := WorldInteractables.GasTrap.new()
		g.x0 = float(gt[1])
		g.x1 = float(gt[2])
		node.add_child(g)
		g.global_position = Vector3(float(gt[0]), y, Z_BACK + 0.35)
	if f.has("extraction"):
		_extraction(node, Vector3(float(f.extraction[0]), y, 0), str(f.extraction[1]), float(f.extraction[2]) if f.extraction.size() > 2 else 0.0)
	for e in f.enemies:
		_enemy(node, Vector3(float(e[0]), y + 0.05, 0), str(e[1]), str(e[2]), int(f.id))

func _build_wall(node: Node3D, bb: BoxBatcher, body: StaticBody3D, x: float, y: float, h: float, type: String) -> void:
	var t := 0.3
	match type:
		"door":
			var dh := 2.5
			bb.add_box("concrete", cm.concrete, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			_shape(body, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			# marco de la puerta
			bb.add_box("steel", cm.steel, Vector3(x, y + dh - 0.05, 0.55), Vector3(t + 0.08, 0.1, 0.1))
			bb.add_box("steel", cm.steel, Vector3(x, y + dh * 0.5, Z_BACK + 0.25), Vector3(t + 0.08, dh, 0.12))
		"duct":
			var dh := 1.3
			bb.add_box("metal_panel", cm.metal_panel, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			_shape(body, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			# boca del conducto: rejilla y franja
			bb.add_box("hazard", cm.hazard, Vector3(x, y + dh + 0.06, 0.55), Vector3(t + 0.1, 0.12, 0.1))
			var grate := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(1.6, 1.2)
			grate.mesh = qm
			grate.material_override = mats.grating
			grate.position = Vector3(x - 0.8, y + 0.6, Z_BACK + 0.3)
			grate.add_to_group("decor_1")
			node.add_child(grate)
		"office", "glass", "thin":
			_closed_wall(node, bb, body, x, y, h, type)
		"locked":
			var door := WorldInteractables.LockedDoor.new()
			door.height = h
			node.add_child(door)
			door.global_position = Vector3(x, y, -0.2)
		_:
			if type.begins_with("locked:"):
				var d2 := WorldInteractables.LockedDoor.new()
				d2.height = h
				d2.key_item = type.get_slice(":", 1)
				node.add_child(d2)
				d2.global_position = Vector3(x, y, -0.2)
			elif type.begins_with("shutter:"):
				var sh := WorldInteractables.Shutter.new()
				sh.height = h
				sh.lever_id = type.get_slice(":", 1)
				node.add_child(sh)
				sh.global_position = Vector3(x, y, -0.2)
		"solid":
			bb.add_box("concrete", cm.concrete, Vector3(x, y + h * 0.5, -0.2), Vector3(t, h, DEPTH - 0.1))
			_shape(body, Vector3(x, y + h * 0.5, -0.2), Vector3(t, h, DEPTH - 0.1))

## Paredes que cierran el paso pero se pueden romper: puerta de oficina (se patea o se baleá), vidrio y tabique fino.
## Romperlas hace ruido (la IA y el indicador de ruido lo reciben).
func _closed_wall(node: Node3D, bb: BoxBatcher, body: StaticBody3D, x: float, y: float, h: float, type: String) -> void:
	var t := 0.3
	var dh := 2.5
	# dintel macizo sobre el vano (igual que una puerta abierta)
	bb.add_box("concrete", cm.concrete, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
	_shape(body, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
	var d := Destructible.new()
	var kind := "door" if type == "office" else ("glass" if type == "glass" else "drywall")
	d.kind = kind
	node.add_child(d)
	var thick := 0.12 if kind != "drywall" else 0.2
	d.setup(kind, Vector3(thick, dh, DEPTH - 0.15), "")
	d.global_position = Vector3(x, y, -0.2)
	d.add_to_group("perf_destructibles")
	if kind == "door":
		# manija y marco: se distingue a simple vista que es una puerta
		bb.add_box("steel", cm.steel, Vector3(x, y + dh - 0.05, 0.55), Vector3(t + 0.08, 0.1, 0.1))
		var k := DoorKick.new()
		k.door = d
		d.add_child(k)
		k.position = Vector3(0, 1.0, 0.45)

## Interactuable de una puerta cerrada: el operador la patea de frente.
class DoorKick extends Interactable:
	var door: Destructible
	func _ready() -> void:
		prompt = "Patear la puerta (hace ruido)"
		radius = 1.2
		super._ready()
		door.broken.connect(func(_by): queue_free())
	func can_use(_a: Actor) -> bool:
		return door != null and door.phase != Destructible.Phase.BROKEN
	func use(a: Actor) -> void:
		a.kick_at(door)

## Artefacto de la lámpara (emisivo). La luz está pintada en los materiales del piso; las luces reales las maneja el pool.
func _lamp(parent: Node3D, pos: Vector3, _floor_i: int) -> void:
	var fix := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.08, 0.25)
	fix.mesh = bm
	fix.material_override = mats.lamp
	fix.position = pos
	fix.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fix)
	stats.lamps += 1

func _red_light(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 8
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = mats.red_light
	mi.position = pos
	mi.add_to_group("decor_1")
	parent.add_child(mi)

## Luces reales: un grupo chico que se coloca en las lámparas más cercanas al jugador (Settings.lights: 0, 2 o 4).
func _build_light_pool() -> void:
	for i in 4:
		var l := OmniLight3D.new()
		l.light_energy = 0.0
		l.omni_range = 8.0
		l.omni_attenuation = 1.0
		l.light_specular = 0.2
		l.shadow_enabled = false
		l.visible = false
		l.add_to_group("perf_luces")
		l.set_meta("target", Vector3(0, -1000, 0))
		l.set_meta("energy", 0.0)
		add_child(l)
		light_pool.append(l)

func update_lights(player_pos: Vector3, delta: float) -> void:
	var n: int = [0, 2, 4][clampi(Settings.lights, 0, 2)]
	_pool_t -= delta
	if _pool_t <= 0.0:
		_pool_t = 0.25
		var order := lamp_data.duplicate()
		order.sort_custom(func(a, b): return (a.pos as Vector3).distance_squared_to(player_pos) < (b.pos as Vector3).distance_squared_to(player_pos))
		for i in light_pool.size():
			var l := light_pool[i]
			if i < n and i < order.size() and (order[i].pos as Vector3).distance_to(player_pos) < 14.0:
				var d: Dictionary = order[i]
				l.set_meta("target", (d.pos as Vector3) + Vector3(0, -0.2, 0.6))
				l.set_meta("energy", 1.6 if not d.alarm else 1.0)
				l.light_color = d.color
			else:
				l.set_meta("energy", 0.0)
	for l in light_pool:
		var e := float(l.get_meta("energy"))
		l.light_energy = move_toward(l.light_energy, e, delta * 4.0)
		l.visible = l.light_energy > 0.02
		var t: Vector3 = l.get_meta("target")
		l.position = t if l.position.distance_to(t) > 12.0 else l.position.lerp(t, clampf(delta * 6.0, 0.0, 1.0))

static var _prop_defs := {}
func _prop(parent: Node3D, id: String, pos: Vector3, scale: float, role: String) -> void:
	var path := "res://assets/props/%s.glb" % id
	if not ResourceLoader.exists(path):
		return
	var n := (load(path) as PackedScene).instantiate() as Node3D
	if scale > 0.0:
		n.scale = Vector3.ONE * scale
	# los modelos de la galería tienen el origen en la base; se giran de costado para verse bien de perfil
	n.rotation.y = PI * 0.5 if id in ["truck_fork_lift", "crate_shipping_container"] else 0.0
	n.position = pos
	parent.add_child(n)
	stats.props += 1
	if role == "cover":
		# cobertura: colisión de caja (detiene balas y personajes)
		var aabb := Destructible._aabb(n, Transform3D.IDENTITY)
		var sb := _static_body(parent, "metal")
		_shape(sb, pos + Vector3(0, aabb.size.y * 0.5 * n.scale.y, 0), Vector3(aabb.size.x * n.scale.x, aabb.size.y * n.scale.y, 1.0))
		n.add_to_group("perf_decorado")
	else:
		n.add_to_group("decor_%d" % (1 if id.begins_with("sf_") or id.begins_with("shelf") else 2))
		n.add_to_group("perf_decorado")
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

const CRATE_SIZE := {"crate_wood": Vector3(0.75, 0.62, 0.75), "crate_metal": Vector3(0.95, 0.7, 0.7), "barrel": Vector3(0.6, 0.9, 0.6),
	"suitcase": Vector3(0.6, 0.22, 0.42), "lab_case": Vector3(0.7, 0.32, 0.5), "glass": Vector3(0.08, 2.0, 1.6), "cardboard": Vector3(0.55, 0.45, 0.5)}
const CRATE_MODEL := {"crate_wood": "res://assets/props/crate_crate_2.glb", "barrel": "res://assets/props/crate_barrel.glb",
	"cardboard": "res://assets/props/sc_cardboard_box.glb", "crate_metal": "res://assets/props/crate_plastic_storage_box.glb"}

func _crate(parent: Node3D, x: float, y: float, kind: String, table: String, floor_i: int) -> void:
	var dk := kind
	if kind in ["suitcase", "lab_case"]:
		dk = "crate_metal"
	var d := Destructible.new()
	d.kind = dk
	parent.add_child(d)
	var size: Vector3 = CRATE_SIZE.get(kind, Vector3(0.7, 0.6, 0.7))
	d.setup(dk, size, "" if kind in ["suitcase", "lab_case", "crate_metal"] else str(CRATE_MODEL.get(kind, "")))
	d.global_position = Vector3(x, y, -0.15 if kind != "glass" else 0.0)
	d.add_to_group("perf_destructibles")
	if kind in ["suitcase", "lab_case"]:
		# maletines: oscuros con franja
		var m := (d.visual as MeshInstance3D).material_override as StandardMaterial3D
		m.albedo_texture = null
		m.albedo_color = Color(0.12, 0.13, 0.14) if kind == "suitcase" else Color(0.75, 0.78, 0.8)
		m.metallic = 0.6
		m.roughness = 0.35
	if table != "":
		var lc := LootContainer.new()
		var key_id := ""
		if table == "key":
			key_id = "keycard_lab"
		elif table.begins_with("key:"):
			key_id = table.get_slice(":", 1)
		lc.table = "crate_wood" if key_id != "" else table
		lc.floor_bonus = floor_i / 2
		lc.open_time = {"crate_wood": 2.4, "crate_metal": 3.2, "suitcase": 1.8, "lab_case": 3.6}.get(kind, 2.6)
		d.add_child(lc)
		lc.position = Vector3(0, size.y + 0.1, 0.15)
		lc.add_to_group("perf_cajas_botin")
		d.loot = lc
		if key_id != "":
			lc.opened.connect(func(by: Actor):
				by.inventory.add(key_id, 1)
				get_tree().call_group("hud", "toast", "%s (abre una puerta bloqueada)" % str(Inventory.def(key_id).get("name", key_id))))
			d.broken.connect(func(_by):
				var p := WorldInteractables.Pickup.new()
				p.item_id = key_id
				d.get_parent().add_child(p)
				p.global_position = d.global_position + Vector3(0.4, 0.05, 0.15))
		# tapa que se levanta al abrir (cajas y maletines)
		var lid := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x * 1.02, 0.05, size.z * 1.02)
		lid.mesh = bm
		lid.material_override = _col_mat(Color(0.3, 0.22, 0.12) if kind == "crate_wood" else Color(0.2, 0.22, 0.22), 0.3, 0.7)
		var pivot := Node3D.new()
		pivot.position = Vector3(0, size.y + 0.025, -size.z * 0.5)
		d.add_child(pivot)
		lid.position = Vector3(0, 0, size.z * 0.5)
		pivot.add_child(lid)
		lc.lid = pivot

func _moving_platform(parent: Node3D, mp: Array, y: float) -> void:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = 1
	body.set_meta("surface", "metal")
	parent.add_child(body)
	var w := 1.8
	_shape_static(body, Vector3(0, -0.1, -0.3), Vector3(w, 0.2, 1.8))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.2, 1.8)
	mi.mesh = bm
	mi.material_override = mats.hazard
	mi.position = Vector3(0, -0.1, -0.3)
	body.add_child(mi)
	var x0 := float(mp[0]) + w * 0.5
	var x1 := float(mp[1]) - w * 0.5
	body.position = Vector3(x0, y + float(mp[2]), 0)
	var tw := create_tween().set_loops()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(body, "position:x", x1, 3.5).set_trans(Tween.TRANS_SINE).set_delay(1.2)
	tw.tween_property(body, "position:x", x0, 3.5).set_trans(Tween.TRANS_SINE).set_delay(1.2)
	# riel en el fondo
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(float(mp[1]) - float(mp[0]), 0.08, 0.08)
	rail.mesh = rm
	rail.material_override = mats.steel
	rail.position = Vector3((float(mp[0]) + float(mp[1])) * 0.5, y + 0.3, Z_BACK + 0.15)
	parent.add_child(rail)

func _shape_static(body: CollisionObject3D, c: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = c
	body.add_child(cs)

## Zona peligrosa (P4): chorros de vapor que queman cada pocos segundos.
func _hazard(parent: Node3D, hz: Array, y: float) -> void:
	var n := SteamVent.new()
	n.x0 = float(hz[0])
	n.x1 = float(hz[1])
	parent.add_child(n)
	n.global_position = Vector3((n.x0 + n.x1) * 0.5, y, 0)
	var bb := BoxBatcher.new()
	bb.add_box("hazard", cm.hazard, Vector3((n.x0 + n.x1) * 0.5, y + 0.01, 0), Vector3(n.x1 - n.x0, 0.02, 1.4))
	bb.commit(parent, false)

func _extraction(parent: Node3D, pos: Vector3, label: String, opens_at := 0.0) -> void:
	var z := WorldInteractables.ExtractionZone.new()
	z.label = label
	z.opens_at = opens_at
	parent.add_child(z)
	z.global_position = pos
	z.extracted.connect(func(a: Actor): extracted.emit(a, label))
	var lab := Label3D.new()
	lab.text = "EXTRACCIÓN"
	lab.font_size = 64
	lab.modulate = Color(0.3, 1.0, 0.5)
	lab.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lab.position = pos + Vector3(0, 2.8, Z_BACK + 0.05)
	parent.add_child(lab)

func _enemy(parent: Node3D, pos: Vector3, char_id: String, weapon_id: String, floor_i: int) -> void:
	var a := Actor.new()
	a.character_id = char_id
	a.team = 1
	a.max_health = 90.0 if floor_i < 3 else 110.0
	a.name = "Enemigo_%s_%d" % [char_id, enemies.size()]
	parent.add_child(a)
	a.global_position = pos
	a.facing = -1.0
	a.aim_dir = Vector2(-1, 0)
	var slot_name := "secondary" if Firearm.all_stats()[weapon_id].hold == "pistol" else "primary"
	a.give_weapon(slot_name, weapon_id)
	a.equip(slot_name)
	a.add_to_group("perf_personajes")
	a.add_to_group("enemies")
	var bot := BotBrain.new()
	bot.actor = a
	bot.home_x = pos.x
	bot.floor_y = pos.y
	a.add_child(bot)
	a.died.connect(func(_i): _drop_enemy_loot(a, weapon_id))
	enemies.append(a)

func _drop_enemy_loot(a: Actor, weapon_id: String) -> void:
	var p := WorldInteractables.Pickup.new()
	p.item_id = "w_" + weapon_id
	a.get_parent().add_child(p)
	p.global_position = a.global_position + Vector3(0.6 * -a.facing, 0.05, 0.2)

# ---------------------------------------------------------------- conexiones verticales

## Cimientos y vereda bajo el P0 (si no, debajo del primer piso se ve el vacío).
func _build_ground(d: Dictionary) -> void:
	_use_floor(0)
	var bb := BoxBatcher.new()
	var w := float(d.width)
	bb.add_box("concrete_dark", cm.concrete_dark, Vector3(w * 0.5, -3.3, -10.0), Vector3(w + 200.0, 6.0, 40.0))
	bb.add_box("hazard", cm.hazard, Vector3(w * 0.5, -0.32, Z_FRONT + 0.2), Vector3(w, 0.06, 0.2))
	bb.commit(floors_nodes[0], false)

func _build_roof(d: Dictionary, y: float) -> void:
	_use_floor(d.floors.size())
	var node := Node3D.new()
	node.name = "Azotea"
	node.add_to_group("floor_%d" % d.floors.size())
	add_child(node)
	floors_nodes.append(node)
	var bb := BoxBatcher.new()
	var body := _static_body(node)
	var w := float(data.width)
	var slab := float(TorreAlfa.SLAB)
	for s in _segments(0.0, w, d.roof.get("holes", [])):
		var c := Vector3((float(s[0]) + float(s[1])) * 0.5, y - slab * 0.5, (Z_BACK + Z_FRONT) * 0.5)
		bb.add_box("concrete", cm.concrete, c, Vector3(float(s[1]) - float(s[0]), slab, DEPTH))
		_shape(body, c, Vector3(float(s[1]) - float(s[0]), slab, DEPTH))
	# parapetos y antena
	for ex in [0.2, w - 0.2]:
		bb.add_box("concrete", cm.concrete, Vector3(ex, y + 0.5, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.4, 1.0, DEPTH))
		_shape(body, Vector3(ex, y + 0.5, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.4, 1.0, DEPTH))
	bb.add_box("steel", cm.steel, Vector3(12.0, y + 4.0, Z_BACK), Vector3(0.2, 8.0, 0.2))
	bb.add_box("steel", cm.steel, Vector3(20.0, y + 1.2, Z_BACK + 0.3), Vector3(3.0, 2.4, 1.2))
	bb.commit(node, false)
	_red_light(node, Vector3(12.0, y + 8.1, Z_BACK + 0.2))
	if d.roof.has("extraction"):
		_extraction(node, Vector3(float(d.roof.extraction[0]), y, 0), str(d.roof.extraction[1]), float(d.roof.extraction[2]) if d.roof.extraction.size() > 2 else 0.0)
		_helicopter(node, Vector3(float(d.roof.extraction[0]), y + 4.5, -6.0))

const HELI_MODEL := "res://assets/props/military_helicopter.glb"

## Helicóptero de extracción de la azotea (modelo propio de assets/props; si falta, el de cajas de abajo). Es parte del mapa:
## los mapas con IA pueden reutilizarlo como punto de extracción.
func _helicopter(parent: Node3D, pos: Vector3) -> void:
	var h := Node3D.new()
	h.position = pos
	parent.add_child(h)
	if ResourceLoader.exists(HELI_MODEL):
		var ps := load(HELI_MODEL) as PackedScene
		if ps:
			var m := ps.instantiate() as Node3D
			m.scale = Vector3.ONE * 12.0               # el modelo mide 1 m de largo: ~12 m de helicóptero
			m.position = Vector3(0, -1.0, 0)
			h.add_child(m)
			for hm in m.find_children("*", "MeshInstance3D", true, false):
				(hm as MeshInstance3D).material_override = _col_mat(Color(0.82, 0.83, 0.85))      # liso: el estilo de línea lo dibuja de blanco
			# el modelo es una sola malla: las hélices se agregan aparte y giran (rotor principal)
			var ab := Destructible._aabb(m, Transform3D.IDENTITY)
			var hub := Node3D.new()
			hub.position = Vector3(ab.get_center().x * 12.0, m.position.y + ab.end.y * 12.0 + 0.1, ab.get_center().z * 12.0)
			h.add_child(hub)
			for k in 2:
				var bl := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(11.0, 0.05, 0.4)
				bl.mesh = bm
				bl.rotation.y = k * PI * 0.5
				bl.material_override = mats.steel
				hub.add_child(bl)
			var spin := create_tween().set_loops()
			spin.tween_property(hub, "rotation:y", TAU, 0.16).as_relative()
			var bob0 := create_tween().set_loops()
			bob0.tween_property(h, "position:y", pos.y + 0.25, 1.8).set_trans(Tween.TRANS_SINE)
			bob0.tween_property(h, "position:y", pos.y - 0.25, 1.8).set_trans(Tween.TRANS_SINE)
			return
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 1.0
	cm.height = 4.6
	body.mesh = cm
	body.rotation.z = PI * 0.5
	body.material_override = _col_mat(Color(0.12, 0.14, 0.12), 0.4, 0.5)
	h.add_child(body)
	var tail := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(4.0, 0.3, 0.3)
	tail.mesh = tm
	tail.position = Vector3(3.6, 0.3, 0)
	tail.material_override = body.material_override
	h.add_child(tail)
	var rotor := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(9.0, 0.05, 0.3)
	rotor.mesh = rm
	rotor.position = Vector3(0, 1.2, 0)
	rotor.material_override = mats.steel
	h.add_child(rotor)
	var tw := create_tween().set_loops()
	tw.tween_property(rotor, "rotation:y", TAU, 0.25).as_relative()
	var bob := create_tween().set_loops()
	bob.tween_property(h, "position:y", pos.y + 0.3, 1.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(h, "position:y", pos.y - 0.3, 1.6).set_trans(Tween.TRANS_SINE)

func _build_ladders(d: Dictionary) -> void:
	for l in d.ladders:
		var lad := Ladder.new()
		var floor_i := int(floor(float(l[1]) / float(d.floor_h) + 0.01))
		var parent: Node3D = floors_nodes[mini(floor_i, floors_nodes.size() - 1)]
		parent.add_child(lad)
		lad.setup(float(l[0]), Z_BACK + 0.12, float(l[1]), float(l[2]), float(l[3]))

func _build_stairs(d: Dictionary) -> void:
	for s in d.stairs:
		_use_floor(int(s[2]))
		var x0 := float(s[0])
		var x1 := float(s[1])
		var y0 := float(s[2]) * float(d.floor_h)
		var y1 := y0 + float(d.floor_h)
		var parent: Node3D = floors_nodes[int(s[2])]
		var body := _static_body(parent, "metal")
		var dx := x1 - x0
		var dy := y1 - y0
		var ang := atan2(dy, dx)
		var length := sqrt(dx * dx + dy * dy)
		var c := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5 - 0.1, -0.45)
		var basis := Basis(Vector3.BACK, ang)
		_shape(body, c, Vector3(length, 0.2, 1.3), basis)
		var bb := BoxBatcher.new()
		var steps := int(dy / 0.22)
		for i in steps:
			var k := (i + 0.5) / steps
			bb.add_box("steel", cm.steel, Vector3(x0 + dx * k, y0 + dy * k - 0.08, -0.45), Vector3(dx / steps + 0.02, 0.06, 1.2))
		bb.add_box("yellow", cm.yellow, c + Vector3(0, 0.95, 0.55), Vector3(length, 0.05, 0.05), basis)
		bb.add_box("yellow", cm.yellow, c + Vector3(0, 0.0, -0.65), Vector3(length, 0.18, 0.06), basis)
		bb.commit(parent, false)

func _build_crater(d: Dictionary) -> void:
	if d.crater.is_empty():
		return
	_use_floor(1)
	var parent: Node3D = floors_nodes[1]
	var y0 := float(d.floor_h)
	var bb := BoxBatcher.new()
	var body := _static_body(parent, "concrete")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for p in d.crater:
		var x0 := float(p[0])
		var x1 := float(p[1])
		var top := float(p[2])
		var c := Vector3((x0 + x1) * 0.5, (y0 + top) * 0.5, -0.3)
		bb.add_box("rubble", cm.rubble, c, Vector3(x1 - x0, top - y0, 1.7))
		_shape(body, c, Vector3(x1 - x0, top - y0, 1.7))
		# trozos sueltos (sólo imagen)
		for i in 3:
			var s := rng.randf_range(0.25, 0.6)
			bb.add_box("rubble", cm.rubble, Vector3(rng.randf_range(x0, x1), top + s * 0.3, rng.randf_range(-1.0, 0.4)),
				Vector3(s, s * 0.6, s), Basis.from_euler(Vector3(rng.randf() * 0.6, rng.randf() * 3.0, rng.randf() * 0.6)))
	# bordes rotos de las losas alrededor del cráter
	for i in 14:
		var x := rng.randf_range(37.5, 47.5)
		var yy: float = [float(d.floor_h) * 2.0, float(d.floor_h) * 3.0][i % 2]
		bb.add_box("rubble", cm.rubble, Vector3(x, yy - 0.35, rng.randf_range(-1.0, 0.5)), Vector3(rng.randf_range(0.3, 0.9), 0.25, 0.5),
			Basis.from_euler(Vector3(rng.randf() * 0.5, rng.randf() * 3.0, rng.randf() * 0.5)))
	var meshes := bb.commit(parent, false)
	for m in meshes:
		m.add_to_group("perf_escombros")

func _build_elevator(d: Dictionary) -> void:
	elevator = Elevator.new()
	var st: Array[float] = []
	var names: Array[String] = []
	for s in d.elevator.stops:
		st.append(float(s) * float(d.floor_h))
		names.append(str((d.floors[int(s)] as Dictionary).get("elev_name", "P%d" % int(s))))
	elevator.stops = st
	elevator.stop_names = names
	elevator.width = float(d.elevator.width)
	elevator.position = Vector3(float(d.elevator.x), 0, 0)
	add_child(elevator)

# ---------------------------------------------------------------- fondo, velos y ambiente

func _build_background(d: Dictionary) -> void:
	var bg := Node3D.new()
	bg.name = "Fondo"
	bg.add_to_group("perf_fondo")
	add_child(bg)
	var tex: Texture2D = load("res://assets/textures/far_facade.png")
	var h := float(d.floor_h) * 7.0
	for layer in [[-28.0, 0.6, 140.0], [-60.0, 0.35, 260.0]]:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(float(layer[2]), h * (1.0 if layer[0] > -40 else 1.6))
		mi.mesh = qm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.albedo_color = Color(float(layer[1]), float(layer[1]), float(layer[1]))
		m.uv1_scale = Vector3(float(layer[2]) / 40.0, 2.0, 1)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(float(d.width) * 0.5, h * 0.45, float(layer[0]))
		mi.add_to_group("bg_%d" % (1 if layer[0] > -40 else 2))
		bg.add_child(mi)

func _build_covers() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.02, 0.025, 0.03, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for r in graph.rooms:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var w := float(r.x1) - float(r.x0)
		qm.size = Vector2(w, float(data.floor_h) - 0.02)
		mi.mesh = qm
		var mm := m.duplicate() as StandardMaterial3D
		mi.material_override = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3((float(r.x0) + float(r.x1)) * 0.5, float(r.y) + float(data.floor_h) * 0.5 - 0.3, Z_FRONT + 0.05)
		mi.add_to_group("perf_cubiertas")
		add_child(mi)
		covers[r.id] = mi
		mi.set_meta("no_tech", true)          # velos de sectores: su material se anima (TechView no lo toca)
		if int(r.floor) >= data.floors.size():
			mi.visible = false     # la azotea es exterior

## Revela el sector `id` (y deja a los ya vistos semi-oscuros: el jugador sólo ve bien donde está).
var _cur_floor := 0
func update_covers(current_id: String, delta: float) -> void:
	revealed[current_id] = true
	_cur_floor = int(graph.room(current_id).get("floor", 0))
	for id in covers:
		var mi: MeshInstance3D = covers[id]
		var target := 0.0 if (id == current_id or not Settings.fog_war) else (0.18 if revealed.has(id) else 0.6)
		var mm := mi.material_override as StandardMaterial3D
		mm.albedo_color.a = move_toward(mm.albedo_color.a, target, delta * 2.5)
		var rf := int(graph.room(id).get("floor", 0))
		mi.visible = mm.albedo_color.a > 0.01 and rf < data.floors.size() and absi(rf - _cur_floor) <= 1

func room_id_at(pos: Vector3) -> String:
	var fi := clampi(int(floor((pos.y + 0.5) / float(data.floor_h))), 0, data.floors.size())
	return graph.room_at(fi, pos.x)

func floor_at(y: float) -> int:
	return clampi(int(floor((y + 0.5) / float(data.floor_h))), 0, data.floors.size())

var world_env: WorldEnvironment
var moon: DirectionalLight3D
func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.022, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.45)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = false           # sin niebla ni brillo: son pasadas de pantalla completa (17 % del cuadro en el Mali-G57)
	env.glow_enabled = false
	world_env.environment = env
	add_child(world_env)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.62, 0.8)
	moon.light_energy = 0.35
	moon.rotation_degrees = Vector3(-35, -25, 0)
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 30.0
	add_child(moon)

## Aplica la configuración gráfica que depende del mapa (luces reales, sombras, fondo, decorado).
func apply_settings(_player_floor: int) -> void:
	moon.shadow_enabled = Settings.shadows >= 2          # sólo en ALTA: sombras reales de la luna sobre personajes
	moon.light_energy = 0.35 if Settings.lights > 0 else 0.5
	world_env.environment.glow_enabled = false
	world_env.environment.fog_enabled = false
	for n in get_tree().get_nodes_in_group("bg_1"):
		(n as Node3D).visible = Settings.background >= 1
	for n in get_tree().get_nodes_in_group("bg_2"):
		(n as Node3D).visible = Settings.background >= 2
	for n in get_tree().get_nodes_in_group("decor_1"):
		(n as Node3D).visible = Settings.decor >= 1
	for n in get_tree().get_nodes_in_group("decor_2"):
		(n as Node3D).visible = Settings.decor >= 2


## Respiradero de vapor (zona peligrosa): cada ~4 s lanza un chorro que quema.
class SteamVent extends Node3D:
	var x0 := 0.0
	var x1 := 2.0
	var _t := 0.0
	var _on := false
	func _process(delta: float) -> void:
		_t += delta
		var phase := fmod(_t, 4.0)
		var on := phase > 2.8
		if on and not _on:
			Sfx.play("steam_burst", global_position + Vector3.UP, 0.0, 1.0, 14.0)
		if on:
			if randf() < 0.5:
				Fx.smoke(Vector3(randf_range(x0, x1), global_position.y + 0.3, 0), 0.6)
			for a in get_tree().get_nodes_in_group("actors"):
				var ac := a as Actor
				if not ac.is_dead() and ac.global_position.x > x0 and ac.global_position.x < x1 and absf(ac.global_position.y - global_position.y) < 1.0:
					ac.take_damage({"damage": 18.0 * delta, "type": "fire", "zone": "leg", "point": ac.global_position + Vector3.UP * 0.5, "dir": Vector3.UP})
		_on = on
