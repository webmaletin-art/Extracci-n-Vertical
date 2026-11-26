class_name MenuTower
extends SubViewportContainer
## Portada (como la imagen de referencia): la Torre Alfa de noche bajo la lluvia, en corte, con sus 5 pisos (B0-B4)
## iluminados (tubos blancos, rojos y naranjas), escaleras amarillas, cajas, estanterías y barriles; portón con franjas
## de peligro en B0; azotea con baranda, reflectores y antena con baliza roja. Alrededor: piso mojado que refleja la
## torre, charcos, valla con alambre de púas, cartel «TORRE ALFA A», farol naranja, luna entre nubes, silueta industrial
## al fondo con luces rojas y lluvia. Todo con materiales sin sombreado (la luz está «pintada»): liviano en teléfonos.

var _vp: SubViewport
var _root: Node3D
var _cam: Camera3D
var _t := 0.0
var _beacons: Array[MeshInstance3D] = []
var _flicker: Array = []                 ## [material, color base]
var rng := RandomNumberGenerator.new()

const W := 13.0          ## ancho de la torre
const D := 5.0           ## profundidad
const FH := 2.7          ## alto de piso
const FLOORS := 5

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.seed = 7
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_2X if Settings.quality_preset >= 1 else Viewport.MSAA_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.97, 0.97, 0.96)
	env.environment = e
	_vp.add_child(env)
	_root = Node3D.new()
	_vp.add_child(_root)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.far = 400.0
	_vp.add_child(_cam)
	_sky()
	_background()
	_ground()
	var tower := Node3D.new()
	_root.add_child(tower)
	_tower(tower)
	# reflejo en el piso mojado: la torre espejada debajo del suelo semitransparente
	var refl := Node3D.new()
	_root.add_child(refl)
	_tower(refl, true)
	refl.scale = Vector3(1, -1, 1)
	_foreground()
	_rain()

# ------------------------------------------------------------------------------------------------ materiales

func _m(c: Color, tex: Texture2D = null, uv := 1.0, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * uv
	if c.a < 1.0 or add:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if add:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _noise_tex(freq: float, c0: Color, c1: Color, size := 256, seed_ := 1) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = 4
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v := clampf(n.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, c0.lerp(c1, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Degradé radial (luces, halos, charcos de luz).
func _glow_tex() -> Texture2D:
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
	gr.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.gradient = gr
	return g

var _glow: Texture2D
func _glow_quad(parent: Node3D, pos: Vector3, size: Vector2, c: Color, billboard := false, rot := Vector3.ZERO) -> MeshInstance3D:
	if _glow == null:
		_glow = _glow_tex()
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := _m(c, null, 1.0, true)
	m.albedo_texture = _glow
	m.uv1_triplanar = false
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 14
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _label(parent: Node3D, text: String, pos: Vector3, size: int, c: Color, outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.modulate = c
	l.outline_size = outline
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.shaded = false
	l.double_sided = true
	l.position = pos
	parent.add_child(l)
	return l

# ------------------------------------------------------------------------------------------------ cielo y fondo

func _sky() -> void:
	# luna con halo
	var moon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.2
	sm.height = 6.4
	moon.mesh = sm
	moon.material_override = _m(Color(1, 1, 1), _noise_tex(0.03, Color(0.78, 0.8, 0.84), Color(1, 1, 1), 128, 3), 0.25)
	moon.position = Vector3(22, 58, -120)
	_root.add_child(moon)
	_glow_quad(_root, moon.position + Vector3(0, 0, 1), Vector2(40, 40), Color(0.55, 0.65, 0.85, 0.5), true)
	# nubes: capas oscuras con ruido, la de adelante tapa un poco la luna
	var ct := _noise_tex(0.012, Color(0.05, 0.06, 0.09, 0.0), Color(0.12, 0.14, 0.19, 0.85), 256, 11)
	for i in 4:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(220, 60)
		mi.mesh = q
		var m := _m(Color(1, 1, 1, 1), ct, 1.0)
		m.uv1_triplanar = false
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.uv1_offset = Vector3(i * 0.31, i * 0.17, 0)
		mi.material_override = m
		mi.position = Vector3(-10 + i * 12, 58 + i * 6, -110 + i * 4)
		_root.add_child(mi)

func _background() -> void:
	var sil := _m(Color(0.045, 0.055, 0.075))
	var sil2 := _m(Color(0.06, 0.07, 0.095))
	# naves industriales y chimeneas
	for i in 14:
		var x := -70.0 + i * 11.0 + rng.randf_range(-3, 3)
		var h := rng.randf_range(6, 22)
		var b := _box(_root, Vector3(x, h * 0.5, -55 - rng.randf_range(0, 25)), Vector3(rng.randf_range(7, 14), h, 8), sil if i % 2 else sil2)
		# ventanitas encendidas
		for k in rng.randi_range(0, 4):
			_box(_root, b.position + Vector3(rng.randf_range(-3, 3), rng.randf_range(-h * 0.3, h * 0.4), 4.05), Vector3(0.5, 0.35, 0.05),
				_m(Color(1.0, 0.72, 0.35) if rng.randf() < 0.7 else Color(0.6, 0.8, 1.0)))
	# torres de celosía con luces rojas (a la derecha, como en la imagen)
	for tx in [26.0, 48.0]:
		var tw := Node3D.new()
		tw.position = Vector3(tx, 0, -32 - tx * 0.3)
		_root.add_child(tw)
		var th := 26.0 if tx < 30 else 34.0
		for leg in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(-1.2, 1.2), Vector2(1.2, 1.2)]:
			_box(tw, Vector3(leg.x * 0.6, th * 0.5, leg.y * 0.6), Vector3(0.18, th, 0.18), sil2, Vector3(leg.y * 2.0, 0, -leg.x * 2.0))
		for k in int(th / 2.5):
			_box(tw, Vector3(0, k * 2.5 + 1.0, 0.75), Vector3(1.6, 0.08, 0.08), sil2, Vector3(0, 0, 35 if k % 2 else -35))
		for k in 3:
			var bl := _box(tw, Vector3(0, th * (0.45 + k * 0.27), 0.8), Vector3(0.4, 0.4, 0.4), _m(Color(1, 0.1, 0.05)))
			_beacons.append(bl)
			_glow_quad(tw, bl.position + Vector3(0, 0, 0.3), Vector2(3.5, 3.5), Color(1, 0.1, 0.05, 0.7), true)

func _ground() -> void:
	# piso mojado: casi negro y semitransparente sobre el reflejo de la torre; charcos más claros
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(240, 160)
	g.mesh = pm
	var gm := _m(Color(1, 1, 1, 0.82), _noise_tex(0.05, Color(0.02, 0.025, 0.035, 0.92), Color(0.05, 0.055, 0.07, 0.62), 256, 5), 0.08)
	gm.uv1_triplanar = true
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.material_override = gm
	g.position = Vector3(0, 0.01, -20)
	_root.add_child(g)
	# brillos de luz sobre el piso (el farol y la puerta de B0)
	_glow_quad(_root, Vector3(0.5, 0.03, D * 0.5 + 2.5), Vector2(10, 5), Color(1.0, 0.75, 0.35, 0.35), false, Vector3(-90, 0, 0))
	_glow_quad(_root, Vector3(9.9, 0.03, 9.5), Vector2(9, 7), Color(1.0, 0.55, 0.2, 0.4), false, Vector3(-90, 0, 0))

# ------------------------------------------------------------------------------------------------ torre

func _tower(parent: Node3D, mirrored := false) -> void:
	var rust := _noise_tex(0.06, Color(0.12, 0.11, 0.11), Color(0.32, 0.30, 0.29), 256, 21)
	var steel := _m(Color(1, 1, 1), rust, 0.9)
	var dark := _m(Color(0.07, 0.075, 0.09))
	var wallt := _noise_tex(0.02, Color(0.16, 0.17, 0.19), Color(0.28, 0.29, 0.31), 256, 9)
	var yellow := _m(Color(0.95, 0.72, 0.12))
	var wood := _m(Color(1, 1, 1), _noise_tex(0.08, Color(0.36, 0.25, 0.15), Color(0.55, 0.4, 0.25), 128, 4), 1.5)
	var crate_g := _m(Color(1, 1, 1), _noise_tex(0.08, Color(0.25, 0.27, 0.24), Color(0.38, 0.4, 0.36), 128, 6), 1.5)
	var tints := [Color(1.0, 0.96, 0.9), Color(1.0, 0.25, 0.15), Color(1.0, 0.62, 0.25), Color(1.0, 0.96, 0.9), Color(0.95, 0.85, 0.6)]
	for f in FLOORS:
		var y := f * FH
		# losa con canto
		_box(parent, Vector3(0, y, 0), Vector3(W, 0.28, D), steel)
		_box(parent, Vector3(0, y + 0.16, D * 0.5 - 0.04), Vector3(W, 0.06, 0.08), _m(Color(0.55, 0.45, 0.2)))
		# pared del fondo corrugada (franjas verticales)
		var back := _box(parent, Vector3(0, y + FH * 0.5, -D * 0.5), Vector3(W, FH, 0.1), _m(Color(1, 1, 1), wallt, 0.6))
		for k in int(W / 0.5):
			_box(parent, Vector3(-W * 0.5 + 0.25 + k * 0.5, y + FH * 0.5, -D * 0.5 + 0.06), Vector3(0.05, FH - 0.3, 0.02), dark)
		# habitaciones: 3 por piso, cada una con su luz
		var xs := [-W * 0.5, -W * 0.5 + W * 0.36, -W * 0.5 + W * 0.66, W * 0.5]
		for r in 3:
			var x0: float = xs[r]
			var x1: float = xs[r + 1]
			var cx := (x0 + x1) * 0.5
			var w := x1 - x0
			var tc: Color = tints[(f * 3 + r) % tints.size()] if rng.randf() < 0.8 else Color(1.0, 0.96, 0.9)
			# tubo del techo y su luz pintada sobre la pared y el piso
			var tube := _box(parent, Vector3(cx, y + FH - 0.22, -D * 0.15), Vector3(w * 0.38, 0.07, 0.12), _m(tc))
			if rng.randf() < 0.35:
				_flicker.append([tube.material_override, tc])
			_glow_quad(parent, Vector3(cx, y + FH * 0.55, -D * 0.5 + 0.12), Vector2(w * 1.2, FH * 1.4), Color(tc.r, tc.g, tc.b, 0.5))
			_glow_quad(parent, Vector3(cx, y + 0.2, 0.2), Vector2(w * 1.0, D * 0.9), Color(tc.r, tc.g, tc.b, 0.3), false, Vector3(-90, 0, 0))
			# contenido: cajas, estanterías, barriles, escritorios
			for k in rng.randi_range(2, 4):
				var bs := Vector3(rng.randf_range(0.5, 1.1), rng.randf_range(0.4, 0.9), rng.randf_range(0.5, 1.0))
				var px := rng.randf_range(x0 + 0.5, x1 - 0.5)
				_box(parent, Vector3(px, y + 0.14 + bs.y * 0.5, rng.randf_range(-1.6, 0.6)), bs, wood if rng.randf() < 0.6 else crate_g)
				if rng.randf() < 0.4:
					_box(parent, Vector3(px, y + 0.14 + bs.y + 0.25, rng.randf_range(-1.6, 0.0)), bs * 0.7, wood)
			if rng.randf() < 0.6:
				var sx := rng.randf_range(x0 + 0.6, x1 - 0.6)
				for k in 4:
					_box(parent, Vector3(sx, y + 0.3 + k * 0.5, -D * 0.5 + 0.45), Vector3(1.3, 0.05, 0.6), steel)
				_box(parent, Vector3(sx - 0.63, y + 1.1, -D * 0.5 + 0.45), Vector3(0.05, 1.9, 0.6), steel)
				_box(parent, Vector3(sx + 0.63, y + 1.1, -D * 0.5 + 0.45), Vector3(0.05, 1.9, 0.6), steel)
			if f == 0 and rng.randf() < 0.7:
				for k in 3:
					_cyl(parent, Vector3(rng.randf_range(x0 + 0.5, x1 - 0.5), y + 0.6, rng.randf_range(-1.0, 1.0)), 0.3, 0.9,
						_m(Color(0.55, 0.08, 0.06) if k % 2 else Color(0.18, 0.25, 0.2)))
			# pantalla azul o mapa en la pared (algunas habitaciones)
			if rng.randf() < 0.35:
				_box(parent, Vector3(cx + rng.randf_range(-0.6, 0.6), y + 1.4, -D * 0.5 + 0.12), Vector3(0.55, 0.38, 0.04), _m(Color(0.2, 0.6, 1.0)))
		# tabiques y columnas
		for x in xs:
			_box(parent, Vector3(x, y + FH * 0.5, 0), Vector3(0.22, FH, D), steel)
			_box(parent, Vector3(x, y + FH * 0.5, D * 0.5 - 0.12), Vector3(0.32, FH, 0.32), steel)
		# escaleras amarillas (una o dos por piso)
		for lx in ([-W * 0.12] if f % 2 else [-W * 0.12, W * 0.28]):
			var ly := y + FH * 0.5 + 0.1
			_box(parent, Vector3(lx - 0.25, ly, -D * 0.5 + 0.3), Vector3(0.06, FH + 0.2, 0.06), yellow)
			_box(parent, Vector3(lx + 0.25, ly, -D * 0.5 + 0.3), Vector3(0.06, FH + 0.2, 0.06), yellow)
			for k in 8:
				_box(parent, Vector3(lx, y + 0.3 + k * 0.32, -D * 0.5 + 0.3), Vector3(0.5, 0.04, 0.04), yellow)
		# número de piso pintado a la derecha
		if not mirrored:
			_label(parent, "B%d" % f, Vector3(W * 0.5 - 0.9, y + FH * 0.55, D * 0.5 - 0.05), 160, Color(0.88, 0.9, 0.95), 8)
	# portón de B0 con franjas de peligro
	_box(parent, Vector3(0.3, 1.15, D * 0.5 - 0.3), Vector3(2.4, 2.1, 0.08), _m(Color(1, 1, 1), _noise_tex(0.05, Color(0.45, 0.4, 0.3), Color(0.62, 0.58, 0.45), 128, 13), 1.0))
	for k in 6:
		_box(parent, Vector3(-0.8 + k * 0.45, 0.18, D * 0.5 - 0.24), Vector3(0.22, 0.2, 0.02), yellow, Vector3(0, 0, 35))
	# laterales: pared izquierda con ventanas iluminadas, la torre «cerrada» de ese lado
	_box(parent, Vector3(-W * 0.5 - 0.6, FLOORS * FH * 0.5, -0.3), Vector3(1.2, FLOORS * FH, D + 0.6), steel)
	for f in FLOORS:
		if rng.randf() < 0.6:
			_box(parent, Vector3(-W * 0.5 - 1.22, f * FH + 1.4, rng.randf_range(-1.5, 1.5)), Vector3(0.05, 0.7, 0.5), _m(Color(1.0, 0.7, 0.35)))
	# azotea: baranda, reflectores, antena de celosía con baliza
	var top := FLOORS * FH
	_box(parent, Vector3(0, top, 0), Vector3(W, 0.3, D), steel)
	for x in range(-6, 7):
		_box(parent, Vector3(x, top + 0.55, D * 0.5 - 0.1), Vector3(0.05, 1.0, 0.05), steel)
	_box(parent, Vector3(0, top + 1.05, D * 0.5 - 0.1), Vector3(W, 0.06, 0.06), steel)
	for fx in [-4.0, 3.5]:
		_box(parent, Vector3(fx, top + 0.5, D * 0.5 - 0.4), Vector3(0.9, 0.35, 0.3), dark)
		_box(parent, Vector3(fx, top + 0.5, D * 0.5 - 0.24), Vector3(0.8, 0.25, 0.02), _m(Color(0.95, 0.97, 1.0)))
		if not mirrored:
			_glow_quad(parent, Vector3(fx, top + 0.6, D * 0.5 + 0.2), Vector2(4, 2.5), Color(0.9, 0.95, 1.0, 0.45), true)
	var ant := Node3D.new()
	ant.position = Vector3(W * 0.12, top, -0.8)
	parent.add_child(ant)
	for leg in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_box(ant, Vector3(leg.x * 0.35, 2.4, leg.y * 0.35), Vector3(0.07, 4.8, 0.07), steel, Vector3(leg.y * 4.0, 0, -leg.x * 4.0))
	for k in 6:
		_box(ant, Vector3(0, 0.5 + k * 0.75, 0.33), Vector3(0.7, 0.04, 0.04), steel, Vector3(0, 0, 40 if k % 2 else -40))
	_box(ant, Vector3(0, 5.6, 0), Vector3(0.05, 1.8, 0.05), steel)
	var bc := _box(ant, Vector3(0, 6.55, 0), Vector3(0.28, 0.28, 0.28), _m(Color(1, 0.08, 0.04)))
	if not mirrored:
		_beacons.append(bc)
		_glow_quad(ant, Vector3(0, 6.55, 0.2), Vector2(3, 3), Color(1, 0.1, 0.05, 0.8), true)

# ------------------------------------------------------------------------------------------------ primer plano

func _foreground() -> void:
	var dark := _m(Color(0.06, 0.065, 0.08))
	var metal := _m(Color(0.22, 0.23, 0.26))
	# valla de alambre con alambre de púas (a la derecha y adelante)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 64:
		for k in [-1, 0, 1]:
			var a := clampi(i + k, 0, 63)
			img.set_pixel(i, a, Color(0.55, 0.58, 0.62, 0.9))
			img.set_pixel(i, 63 - a, Color(0.55, 0.58, 0.62, 0.9))
	var mesh_tex := ImageTexture.create_from_image(img)
	var fence := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(16, 3.2)
	fence.mesh = q
	var fm := _m(Color(1, 1, 1, 1), mesh_tex, 1.0)
	fm.uv1_triplanar = false
	fm.uv1_scale = Vector3(32, 6.4, 1)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fence.material_override = fm
	fence.position = Vector3(12.0, 1.6, 7.0)
	fence.rotation_degrees = Vector3(0, -62, 0)
	_root.add_child(fence)
	for k in 5:
		var p := fence.position + Vector3(-cos(deg_to_rad(62)) * (-8 + k * 4), 0, sin(deg_to_rad(62)) * (-8 + k * 4))
		_cyl(_root, p, 0.06, 3.6, metal)
	for k in 26:
		var u := -8.0 + k * 0.62
		var p := fence.position + Vector3(-cos(deg_to_rad(62)) * u, 1.85, sin(deg_to_rad(62)) * u)
		var tor := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.2
		tm.outer_radius = 0.24
		tor.mesh = tm
		tor.material_override = metal
		tor.position = p
		tor.rotation_degrees = Vector3(90, -62, 0)
		_root.add_child(tor)
	# cartel TORRE ALFA
	var sign := Node3D.new()
	sign.position = Vector3(7.6, 0, 11.0)
	sign.rotation_degrees = Vector3(0, -40, 0)
	_root.add_child(sign)
	_box(sign, Vector3(0, 1.9, 0), Vector3(2.2, 2.8, 0.08), _m(Color(0.07, 0.075, 0.08)))
	_box(sign, Vector3(0, 1.9, -0.06), Vector3(2.3, 2.9, 0.04), _m(Color(0.6, 0.6, 0.62)))
	_cyl(sign, Vector3(-0.9, 0.9, -0.1), 0.05, 1.8, metal)
	_cyl(sign, Vector3(0.9, 0.9, -0.1), 0.05, 1.8, metal)
	_label(sign, "TORRE\nALFA", Vector3(0, 2.75, 0.06), 70, Color(0.92, 0.93, 0.95))
	_label(sign, "A", Vector3(0, 1.75, 0.06), 190, Color(1.0, 0.72, 0.1))
	for k in 6:
		_box(sign, Vector3(-0.9 + k * 0.36, 0.72, 0.05), Vector3(0.16, 0.3, 0.02), _m(Color(1.0, 0.72, 0.1)), Vector3(0, 0, 35))
	# farol con luz naranja y su cono
	var lamp := Node3D.new()
	lamp.position = Vector3(10.8, 0, 9.0)
	_root.add_child(lamp)
	_cyl(lamp, Vector3(0, 3.0, 0), 0.08, 6.0, dark)
	_box(lamp, Vector3(-0.45, 5.9, 0), Vector3(1.0, 0.1, 0.1), dark)
	_box(lamp, Vector3(-0.9, 5.75, 0), Vector3(0.55, 0.3, 0.4), dark)
	_box(lamp, Vector3(-0.9, 5.58, 0), Vector3(0.45, 0.04, 0.3), _m(Color(1.0, 0.75, 0.35)))
	_glow_quad(lamp, Vector3(-0.9, 5.5, 0.3), Vector2(2.6, 2.6), Color(1.0, 0.6, 0.2, 0.9), true)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 2.4
	cm.height = 5.4
	cone.mesh = cm
	cone.material_override = _m(Color(1.0, 0.55, 0.18, 0.07), null, 1.0, true)
	cone.position = Vector3(-0.9, 2.8, 0)
	lamp.add_child(cone)
	# cajas tapadas con lona y barriles en primer plano
	_box(_root, Vector3(-9.5, 0.55, 8.5), Vector3(2.2, 1.1, 1.4), _m(Color(1, 1, 1), _noise_tex(0.06, Color(0.15, 0.16, 0.17), Color(0.25, 0.26, 0.27), 128, 17), 1.0), Vector3(0, 18, 0))
	_box(_root, Vector3(-10.5, 0.45, 10.5), Vector3(1.8, 0.9, 1.0), _m(Color(0.2, 0.15, 0.1)), Vector3(0, -10, 0))
	for k in 3:
		_cyl(_root, Vector3(4.6 + k * 0.65, 0.45, 11.6 - k * 0.3), 0.3, 0.9, _m(Color(0.5, 0.07, 0.05)))

func _rain() -> void:
	var rain := CPUParticles3D.new()
	rain.amount = 900 if Settings.particles >= 1 else 300
	rain.lifetime = 0.9
	rain.preprocess = 1.0
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(26, 0.1, 16)
	rain.position = Vector3(2, 24, 0)
	rain.direction = Vector3(-0.12, -1, 0)
	rain.spread = 2.0
	rain.initial_velocity_min = 24.0
	rain.initial_velocity_max = 28.0
	rain.gravity = Vector3.ZERO
	var rm := QuadMesh.new()
	rm.size = Vector2(0.018, 0.6)
	rain.mesh = rm
	var m := _m(Color(0.65, 0.75, 0.95, 0.35))
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rain.material_override = m
	_root.add_child(rain)

# ------------------------------------------------------------------------------------------------ animación

func _process(delta: float) -> void:
	_t += delta
	if _cam == null:
		return
	# cámara casi fija (como la foto), con un vaivén muy lento que deja ver la profundidad de la torre
	var sway := sin(_t * 0.12) * 0.12
	var target := Vector3(-5.0, FLOORS * FH * 0.5, 0)
	var dist := 30.0
	_cam.position = target + Vector3(sin(sway + 0.08) * dist, -3.5 + sin(_t * 0.09) * 0.6, cos(sway + 0.08) * dist)
	_cam.look_at(target, Vector3.UP)
	for i in _beacons.size():
		var b := _beacons[i]
		var k := 0.25 + 0.75 * maxf(sin(_t * 2.6 + i * 1.7), 0.0)
		var bm := b.material_override as StandardMaterial3D
		if bm:
			bm.albedo_color = Color(1.0, 0.08, 0.04) * k
	for f in _flicker:
		var on := fmod(_t * 0.7 + float(_flicker.find(f)), 7.0) > 0.25 or sin(_t * 40.0) > 0.0
		var fm := f[0] as StandardMaterial3D
		if fm:
			fm.albedo_color = (f[1] as Color) * (1.0 if on else 0.25)
