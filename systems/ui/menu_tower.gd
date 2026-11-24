class_name MenuTower
extends SubViewportContainer
## Portada: la Torre Alfa en corte (5 pisos + azotea con helipuerto) girando despacio, con ventanas encendidas, ascensor,
## baliza roja, lluvia y reflectores. Todo con materiales sin sombreado: casi no cuesta nada y se ve bien en teléfonos flojos.

var _vp: SubViewport
var _root: Node3D
var _cam: Camera3D
var _t := 0.0
var _beacon: MeshInstance3D
var _lamps: Array[MeshInstance3D] = []

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X if Settings.quality_preset >= 1 else Viewport.MSAA_DISABLED
	add_child(_vp)
	_root = Node3D.new()
	_vp.add_child(_root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS
	env.environment = e
	_vp.add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_vp.add_child(_cam)
	_build()

func _unlit(c: Color, emit := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c.r * emit, c.g * emit, c.b * emit, c.a)
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _box(pos: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else _root).add_child(mi)
	return mi

func _build() -> void:
	var W := 12.0
	var D := 5.0
	var FH := 2.6
	var slab := _unlit(Color(0.30, 0.33, 0.38))
	var slab_edge := _unlit(Color(1.0, 0.55, 0.15))
	var wall := _unlit(Color(0.13, 0.15, 0.19))
	var back := _unlit(Color(0.07, 0.085, 0.11))
	var floors := 5
	# fondo de cada piso (pared trasera) con habitaciones que brillan distinto
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var tints := [Color(1.0, 0.62, 0.25), Color(0.4, 0.75, 1.0), Color(0.95, 0.9, 0.7), Color(1.0, 0.3, 0.25), Color(0.5, 1.0, 0.7)]
	for f in floors:
		var y := f * FH
		_box(Vector3(0, y, 0), Vector3(W, 0.18, D), slab)
		_box(Vector3(0, y + 0.1, D * 0.5), Vector3(W, 0.05, 0.05), slab_edge)             # canto naranja al frente
		_box(Vector3(0, y + FH * 0.5, -D * 0.5), Vector3(W, FH, 0.12), back)
		# habitaciones: paredes divisorias y luz de cada una
		var x := -W * 0.5
		while x < W * 0.5 - 1.5:
			var w := rng.randf_range(2.0, 3.6)
			w = minf(w, W * 0.5 - x)
			_box(Vector3(x, y + FH * 0.5, 0), Vector3(0.12, FH, D), wall)
			var tc: Color = tints[rng.randi() % tints.size()]
			var lamp := _box(Vector3(x + w * 0.5, y + FH - 0.35, -D * 0.5 + 0.1), Vector3(w * 0.6, 0.12, 0.08), _unlit(tc, 1.2))
			_lamps.append(lamp)
			_box(Vector3(x + w * 0.5, y + FH * 0.45, -D * 0.5 + 0.08), Vector3(w * 0.82, FH * 0.55, 0.04), _unlit(Color(tc.r, tc.g, tc.b, 0.22)))
			# muebles / cajas
			for k in rng.randi_range(1, 3):
				var bs := Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.3, 0.7), rng.randf_range(0.4, 0.9))
				_box(Vector3(x + rng.randf_range(0.3, w - 0.3), y + 0.09 + bs.y * 0.5, rng.randf_range(-1.2, 1.2)), bs, _unlit(Color(0.24, 0.2, 0.16)))
			x += w
		_box(Vector3(W * 0.5, y + FH * 0.5, 0), Vector3(0.12, FH, D), wall)
		# columnas al frente
		for cx in [-W * 0.5, -W * 0.17, W * 0.17, W * 0.5]:
			_box(Vector3(cx, y + FH * 0.5, D * 0.5 - 0.1), Vector3(0.16, FH, 0.16), slab)
	# techo / azotea con helipuerto
	var top := floors * FH
	_box(Vector3(0, top, 0), Vector3(W, 0.22, D), slab)
	_box(Vector3(0, top + 0.12, D * 0.5), Vector3(W, 0.05, 0.05), slab_edge)
	var pad := _box(Vector3(-W * 0.18, top + 0.14, 0), Vector3(3.2, 0.04, 3.2), _unlit(Color(0.18, 0.2, 0.24)))
	_box(Vector3(-W * 0.18, top + 0.17, 0), Vector3(2.2, 0.02, 0.28), _unlit(Color(1.0, 0.85, 0.2)))
	_box(Vector3(-W * 0.18 - 0.4, top + 0.17, 0), Vector3(0.28, 0.02, 1.7), _unlit(Color(1.0, 0.85, 0.2)))
	_box(Vector3(-W * 0.18 + 0.4, top + 0.17, 0), Vector3(0.28, 0.02, 1.7), _unlit(Color(1.0, 0.85, 0.2)))
	# antena + baliza roja
	_box(Vector3(W * 0.3, top + 2.2, -1.0), Vector3(0.1, 4.4, 0.1), slab)
	_box(Vector3(W * 0.3, top + 3.0, -1.0), Vector3(1.3, 0.06, 0.06), slab)
	_beacon = _box(Vector3(W * 0.3, top + 4.5, -1.0), Vector3(0.3, 0.3, 0.3), _unlit(Color(1.0, 0.1, 0.05), 1.0))
	# caja del ascensor (hueco central) con cabina
	var shaft := _box(Vector3(W * 0.05, top * 0.5, 0.2), Vector3(1.5, top, 1.5), _unlit(Color(0.3, 0.8, 1.0, 0.1)))
	_box(Vector3(W * 0.05, 2.0 * FH + 1.1, 0.2), Vector3(1.2, 1.9, 1.2), _unlit(Color(0.4, 0.85, 1.0, 0.55)))
	# subsuelo / cimientos
	_box(Vector3(0, -0.9, 0), Vector3(W + 1.2, 1.5, D + 1.2), _unlit(Color(0.1, 0.11, 0.14)))
	# luna y reflectores
	var spot := _box(Vector3(-W * 0.5 - 1.6, -0.1, D * 0.5 + 0.8), Vector3(0.4, 0.4, 0.4), _unlit(Color(1, 0.95, 0.8), 1.0))
	# lluvia
	var rain := CPUParticles3D.new()
	rain.amount = 400 if Settings.particles >= 1 else 120
	rain.lifetime = 1.0
	rain.preprocess = 1.0
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(11, 0.1, 6)
	rain.position = Vector3(0, 20, 0)
	rain.direction = Vector3(-0.15, -1, 0)
	rain.spread = 2.0
	rain.initial_velocity_min = 20.0
	rain.initial_velocity_max = 24.0
	rain.gravity = Vector3.ZERO
	var rm := QuadMesh.new()
	rm.size = Vector2(0.02, 0.5)
	rain.mesh = rm
	rain.material_override = _unlit(Color(0.7, 0.8, 1.0, 0.35))
	_root.add_child(rain)
	_root.position = Vector3(0, -FH * 2.4, 0)

func _process(delta: float) -> void:
	_t += delta
	if _cam == null:
		return
	# la cámara orbita despacio de un lado a otro mostrando la estructura
	var ang := sin(_t * 0.22) * 0.55 + 0.25
	var dist := 34.0
	_cam.position = Vector3(sin(ang) * dist, 5.0 + sin(_t * 0.17) * 2.0, cos(ang) * dist)
	_cam.look_at(Vector3(0, 1.0, 0))
	if _beacon:
		(_beacon.material_override as StandardMaterial3D).albedo_color = Color(1, 0.1, 0.05) * (0.25 + 0.75 * maxf(sin(_t * 3.0), 0.0))
