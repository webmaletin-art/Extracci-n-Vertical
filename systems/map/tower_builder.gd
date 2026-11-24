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

const Z_BACK := -1.7
const Z_FRONT := 1.25
const DEPTH := Z_FRONT - Z_BACK

var data := {}
var graph: MapGraph
var floors_nodes: Array[Node3D] = []
var covers := {}               ## id de sector → MeshInstance3D (velo del sector sin descubrir)
var revealed := {}
var elevator: Elevator
var lamps: Array[OmniLight3D] = []
var enemies: Array[Actor] = []
var mats := {}
var stats := {"tris_static": 0, "props": 0, "lamps": 0}

func build(d: Dictionary) -> void:
	data = d
	graph = MapGraph.from_data(d)
	_make_materials()
	var fh := float(d.floor_h)
	var nf: int = d.floors.size()
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
	_build_background(d)
	_build_covers()
	_build_environment()

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
		bb.add_box("floor", mats.floor, c + Vector3(0, slab * 0.25, 0), Vector3(sz.x, slab * 0.5, sz.z))
		bb.add_box("concrete_dark", mats.concrete_dark, c - Vector3(0, slab * 0.25, 0), Vector3(sz.x, slab * 0.5, sz.z))
		_shape(body, c, sz)
	# bordes de los huecos: franjas de peligro y barandas bajas en el frente
	for h in f.holes:
		for edge in [float(h[0]), float(h[1])]:
			bb.add_box("hazard", mats.hazard, Vector3(edge, y + 0.01, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.18, 0.02, DEPTH))
	# pared del fondo
	var wall_mat: Material = mats.concrete if f.wall_tex == "concrete" else mats.metal_panel
	bb.add_box("wall_" + str(f.wall_tex), wall_mat, Vector3(w * 0.5, y + (fh - slab) * 0.5, Z_BACK - 0.1), Vector3(w, fh - slab, 0.2))
	_shape(body, Vector3(w * 0.5, y + (fh - slab) * 0.5, Z_BACK - 0.1), Vector3(w, fh - slab, 0.2))
	# paredes exteriores (con ventanas en el lado derecho)
	for ex in [-0.15, w + 0.15]:
		bb.add_box("concrete", mats.concrete, Vector3(ex, y + (fh - slab) * 0.5, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.3, fh - slab, DEPTH))
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
			var c := Vector3((x0 + x1) * 0.5, y + hgt * 0.5, -0.2)
			bb.add_box("metal_panel", mats.metal_panel, c, Vector3(x1 - x0, hgt, 2.2))
			bb.add_box("hazard", mats.hazard, Vector3(c.x, y + hgt + 0.005, 0.85), Vector3(x1 - x0, 0.01, 0.12))
			_shape(body, c, Vector3(x1 - x0, hgt, 2.2))
		else:
			var c := Vector3((x0 + x1) * 0.5, y + hgt - 0.1, -0.35)
			bb.add_box("floor", mats.floor, c, Vector3(x1 - x0, 0.2, 2.4))
			_shape(body, c, Vector3(x1 - x0, 0.2, 2.4))
			for px in [x0 + 0.15, x1 - 0.15]:
				bb.add_box("steel", mats.steel, Vector3(px, y + (hgt - 0.2) * 0.5, 0.6), Vector3(0.12, hgt - 0.2, 0.12))
				bb.add_box("steel", mats.steel, Vector3(px, y + (hgt - 0.2) * 0.5, -1.4), Vector3(0.12, hgt - 0.2, 0.12))
			# baranda del frente
			bb.add_box("yellow", mats.yellow, Vector3(c.x, y + hgt + 0.95, 0.75), Vector3(x1 - x0, 0.05, 0.05))
	# tuberías y cables del fondo (decorado barato, una malla)
	var pipes := BoxBatcher.new()
	pipes.add_box("pipe", mats.pipe, Vector3(w * 0.5, y + fh - slab - 0.45, Z_BACK + 0.15), Vector3(w, 0.16, 0.16))
	pipes.add_box("pipe_red", mats.pipe_red, Vector3(w * 0.5, y + fh - slab - 0.75, Z_BACK + 0.12), Vector3(w, 0.1, 0.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + int(f.id)
	for i in 7:
		var px := rng.randf_range(1.0, w - 1.0)
		pipes.add_box("pipe", mats.pipe, Vector3(px, y + (fh - slab) * 0.5, Z_BACK + 0.1), Vector3(0.1, fh - slab, 0.1))
	var pipe_node := Node3D.new()
	pipe_node.name = "Tuberias"
	pipe_node.add_to_group("perf_tuberias")
	pipe_node.add_to_group("decor_1")
	node.add_child(pipe_node)
	pipes.commit(pipe_node, false)
	var meshes := bb.commit(node)
	stats.tris_static += bb.tris + pipes.tris
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
		_prop(node, str(p[1]), Vector3(float(p[0]), y, -0.9 if str(p[3]) == "decor" else -0.3), float(p[2]), str(p[3]))
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
	if f.has("extraction"):
		_extraction(node, Vector3(float(f.extraction[0]), y, 0), str(f.extraction[1]))
	for e in f.enemies:
		_enemy(node, Vector3(float(e[0]), y + 0.05, 0), str(e[1]), str(e[2]), int(f.id))

func _build_wall(node: Node3D, bb: BoxBatcher, body: StaticBody3D, x: float, y: float, h: float, type: String) -> void:
	var t := 0.3
	match type:
		"door":
			var dh := 2.5
			bb.add_box("concrete", mats.concrete, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			_shape(body, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			# marco de la puerta
			bb.add_box("steel", mats.steel, Vector3(x, y + dh - 0.05, 0.9), Vector3(t + 0.08, 0.1, 0.1))
			bb.add_box("steel", mats.steel, Vector3(x, y + dh * 0.5, Z_BACK + 0.25), Vector3(t + 0.08, dh, 0.12))
		"duct":
			var dh := 1.3
			bb.add_box("metal_panel", mats.metal_panel, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			_shape(body, Vector3(x, y + dh + (h - dh) * 0.5, -0.2), Vector3(t, h - dh, DEPTH - 0.1))
			# boca del conducto: rejilla y franja
			bb.add_box("hazard", mats.hazard, Vector3(x, y + dh + 0.06, 0.9), Vector3(t + 0.1, 0.12, 0.1))
			var grate := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(1.6, 1.2)
			grate.mesh = qm
			grate.material_override = mats.grating
			grate.position = Vector3(x - 0.8, y + 0.6, Z_BACK + 0.3)
			grate.add_to_group("decor_1")
			node.add_child(grate)
		"locked":
			var door := WorldInteractables.LockedDoor.new()
			door.height = h
			node.add_child(door)
			door.global_position = Vector3(x, y, -0.2)
		"solid":
			bb.add_box("concrete", mats.concrete, Vector3(x, y + h * 0.5, -0.2), Vector3(t, h, DEPTH - 0.1))
			_shape(body, Vector3(x, y + h * 0.5, -0.2), Vector3(t, h, DEPTH - 0.1))

func _lamp(parent: Node3D, pos: Vector3, floor_i: int) -> void:
	var fix := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.08, 0.25)
	fix.mesh = bm
	fix.material_override = mats.lamp
	fix.position = pos
	fix.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fix)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.55)
	l.light_energy = 1.6
	l.omni_range = 7.5
	l.omni_attenuation = 1.2
	l.position = pos + Vector3(0, -0.3, 0.6)
	l.shadow_enabled = false
	l.set_meta("floor", floor_i)
	l.add_to_group("dyn_light")
	l.add_to_group("perf_luces")
	parent.add_child(l)
	lamps.append(l)
	stats.lamps += 1

func _red_light(parent: Node3D, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	mi.mesh = sm
	mi.material_override = mats.red_light
	mi.position = pos
	mi.add_to_group("decor_1")
	parent.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.12, 0.05)
	l.light_energy = 1.2
	l.omni_range = 4.0
	l.position = pos + Vector3(0, 0, 0.4)
	l.add_to_group("dyn_light")
	l.add_to_group("perf_luces")
	l.set_meta("alarm", true)
	parent.add_child(l)
	lamps.append(l)

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
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if role == "decor" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
		lc.table = "crate_wood" if table == "key" else table
		lc.floor_bonus = floor_i / 2
		lc.open_time = {"crate_wood": 2.4, "crate_metal": 3.2, "suitcase": 1.8, "lab_case": 3.6}.get(kind, 2.6)
		d.add_child(lc)
		lc.position = Vector3(0, size.y + 0.1, 0.15)
		lc.add_to_group("perf_cajas_botin")
		d.loot = lc
		if table == "key":
			lc.opened.connect(func(by: Actor):
				by.inventory.add("keycard_lab", 1)
				get_tree().call_group("hud", "toast", "Tarjeta del laboratorio (abre la puerta del P4)"))
			d.broken.connect(func(_by):
				var p := WorldInteractables.Pickup.new()
				p.item_id = "keycard_lab"
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
	_shape_static(body, Vector3(0, -0.1, -0.2), Vector3(w, 0.2, 2.2))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.2, 2.2)
	mi.mesh = bm
	mi.material_override = mats.hazard
	mi.position = Vector3(0, -0.1, -0.2)
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
	bb.add_box("hazard", mats.hazard, Vector3((n.x0 + n.x1) * 0.5, y + 0.01, 0), Vector3(n.x1 - n.x0, 0.02, 1.8))
	bb.commit(parent)

func _extraction(parent: Node3D, pos: Vector3, label: String) -> void:
	var z := WorldInteractables.ExtractionZone.new()
	z.label = label
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
	var bb := BoxBatcher.new()
	var w := float(d.width)
	bb.add_box("concrete_dark", mats.concrete_dark, Vector3(w * 0.5, -3.3, -10.0), Vector3(w + 200.0, 6.0, 40.0))
	bb.add_box("hazard", mats.hazard, Vector3(w * 0.5, -0.32, Z_FRONT + 0.2), Vector3(w, 0.06, 0.2))
	bb.commit(floors_nodes[0], false)

func _build_roof(d: Dictionary, y: float) -> void:
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
		bb.add_box("concrete", mats.concrete, c, Vector3(float(s[1]) - float(s[0]), slab, DEPTH))
		_shape(body, c, Vector3(float(s[1]) - float(s[0]), slab, DEPTH))
	# parapetos y antena
	for ex in [0.2, w - 0.2]:
		bb.add_box("concrete", mats.concrete, Vector3(ex, y + 0.5, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.4, 1.0, DEPTH))
		_shape(body, Vector3(ex, y + 0.5, (Z_BACK + Z_FRONT) * 0.5), Vector3(0.4, 1.0, DEPTH))
	bb.add_box("steel", mats.steel, Vector3(12.0, y + 4.0, Z_BACK), Vector3(0.2, 8.0, 0.2))
	bb.add_box("steel", mats.steel, Vector3(20.0, y + 1.2, Z_BACK + 0.3), Vector3(3.0, 2.4, 1.2))
	bb.commit(node)
	_red_light(node, Vector3(12.0, y + 8.1, Z_BACK + 0.2))
	if d.roof.has("extraction"):
		_extraction(node, Vector3(float(d.roof.extraction[0]), y, 0), str(d.roof.extraction[1]))
		_helicopter(node, Vector3(float(d.roof.extraction[0]), y + 4.5, -6.0))

func _helicopter(parent: Node3D, pos: Vector3) -> void:
	var h := Node3D.new()
	h.position = pos
	parent.add_child(h)
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
		var c := Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5 - 0.1, -0.6)
		var basis := Basis(Vector3.BACK, ang)
		_shape(body, c, Vector3(length, 0.2, 1.4), basis)
		var bb := BoxBatcher.new()
		var steps := int(dy / 0.22)
		for i in steps:
			var k := (i + 0.5) / steps
			bb.add_box("steel", mats.steel, Vector3(x0 + dx * k, y0 + dy * k - 0.08, -0.6), Vector3(dx / steps + 0.02, 0.06, 1.3))
		bb.add_box("yellow", mats.yellow, c + Vector3(0, 0.95, 0.7), Vector3(length, 0.05, 0.05), basis)
		bb.add_box("yellow", mats.yellow, c + Vector3(0, 0.0, -1.3 + 0.6), Vector3(length, 0.18, 0.06), basis)
		bb.commit(parent)

func _build_crater(d: Dictionary) -> void:
	if d.crater.is_empty():
		return
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
		bb.add_box("rubble", mats.rubble, c, Vector3(x1 - x0, top - y0, 2.0))
		_shape(body, c, Vector3(x1 - x0, top - y0, 2.0))
		# trozos sueltos (sólo imagen)
		for i in 3:
			var s := rng.randf_range(0.25, 0.6)
			bb.add_box("rubble", mats.rubble, Vector3(rng.randf_range(x0, x1), top + s * 0.3, rng.randf_range(-1.2, 0.4)),
				Vector3(s, s * 0.6, s), Basis.from_euler(Vector3(rng.randf() * 0.6, rng.randf() * 3.0, rng.randf() * 0.6)))
	# bordes rotos de las losas alrededor del cráter
	for i in 14:
		var x := rng.randf_range(37.5, 47.5)
		var yy: float = [float(d.floor_h) * 2.0, float(d.floor_h) * 3.0][i % 2]
		bb.add_box("rubble", mats.rubble, Vector3(x, yy - 0.35, rng.randf_range(-1.4, 0.9)), Vector3(rng.randf_range(0.3, 0.9), 0.25, 0.5),
			Basis.from_euler(Vector3(rng.randf() * 0.5, rng.randf() * 3.0, rng.randf() * 0.5)))
	var meshes := bb.commit(parent)
	for m in meshes:
		m.add_to_group("perf_escombros")

func _build_elevator(d: Dictionary) -> void:
	elevator = Elevator.new()
	var st: Array[float] = []
	var names: Array[String] = []
	for s in d.elevator.stops:
		st.append(float(s) * float(d.floor_h))
		names.append("P%d" % int(s))
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
		if int(r.floor) >= data.floors.size():
			mi.visible = false     # la azotea es exterior

## Revela el sector `id` (y deja a los ya vistos semi-oscuros: el jugador sólo ve bien donde está).
func update_covers(current_id: String, delta: float) -> void:
	revealed[current_id] = true
	for id in covers:
		var mi: MeshInstance3D = covers[id]
		var target := 0.0 if id == current_id else (0.35 if revealed.has(id) else 0.9)
		var mm := mi.material_override as StandardMaterial3D
		mm.albedo_color.a = move_toward(mm.albedo_color.a, target, delta * 2.5)
		mi.visible = mm.albedo_color.a > 0.01 and int(graph.room(id).get("floor", 0)) < data.floors.size()

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
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.45)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.09, 0.12)
	env.fog_density = 0.012
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

## Aplica la configuración gráfica que depende del mapa (luces, sombras, fondo, decorado, niebla, brillo).
func apply_settings(player_floor: int) -> void:
	moon.shadow_enabled = Settings.shadows >= 1
	var env := world_env.environment
	env.glow_enabled = Settings.quality_preset == 2
	env.fog_enabled = Settings.background >= 2
	for l in lamps:
		if not is_instance_valid(l):
			continue
		var lf := int(l.get_meta("floor", player_floor))
		var near := absi(lf - player_floor) <= 1
		l.visible = Settings.lights >= 2 or (Settings.lights == 1 and near) or bool(l.get_meta("alarm", false)) and Settings.lights >= 1
		l.shadow_enabled = Settings.shadows >= 2 and lf == player_floor
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
