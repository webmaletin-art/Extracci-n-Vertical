extends Node
## Efectos visuales (autoload «Fx»): chispas, polvo, astillas, vidrio, sangre, humo, fuego, fogonazos, marcas de impacto y
## fragmentos físicos. Todo sale de grupos fijos de nodos reutilizables (nada se crea ni se destruye durante el combate) y
## la cantidad se escala con la configuración (Settings.particles / smoke / explosions).
##
## Renderer GL Compatibility: CPUParticles3D (lo más barato y compatible en teléfonos de gama baja), materiales sin luz.

const POOL := {"spark": 10, "dust": 10, "splinter": 8, "glass": 4, "blood": 10, "smoke": 6, "fire": 4, "fireball": 3,
	"muzzle": 6, "shard_bone": 4}
const MAX_DEBRIS := 40
const MAX_MARKS := 48

var _pools := {}           ## tipo → Array[CPUParticles3D]
var _idx := {}
var _debris: Array[RigidBody3D] = []
var _debris_i := 0
var _debris_t: Array[float] = []
var _marks: Array[MeshInstance3D] = []
var _marks_i := 0
var _lights: Array[OmniLight3D] = []
var _lights_t: Array[float] = []
var _root: Node3D
var _mats := {}
var stats := {"emitted": 0, "debris": 0}

var _flash_g := {"p": Vector3(0, -1000, 0), "range": 4.0, "c": Color.BLACK, "e": 0.0, "decay": 30.0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# el escenario es «unshaded» con la luz pintada (fast_surface.gdshader): los fogonazos y explosiones lo iluminan por
	# estas dos variables globales (una sola luz de destello a la vez, la más fuerte)
	var names := RenderingServer.global_shader_parameter_get_list()
	for n in ["flash_p", "flash_c"]:
		if not StringName(n) in names:
			RenderingServer.global_shader_parameter_add(n, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(0, -1000, 0, 1) if n == "flash_p" else Vector4(0, 0, 0, 0))

## Se llama al cargar un mapa: los nodos viven dentro del mundo (para que se vean con su cámara y su física).
func attach(world_root: Node3D) -> void:
	_root = Node3D.new()
	_root.name = "FxPool"
	world_root.add_child(_root)
	_pools.clear()
	_idx.clear()
	for kind in POOL:
		var arr: Array[CPUParticles3D] = []
		for i in POOL[kind]:
			var p := _make(kind)
			_root.add_child(p)
			arr.append(p)
		_pools[kind] = arr
		_idx[kind] = 0
	_debris.clear()
	_debris_t.clear()
	for i in MAX_DEBRIS:
		var rb := RigidBody3D.new()
		rb.collision_layer = 1 << 6
		rb.collision_mask = 1
		rb.mass = 0.4
		rb.freeze = true
		rb.visible = false
		rb.continuous_cd = false
		rb.can_sleep = true
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.12, 0.05, 0.12)
		cs.shape = bs
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = bs.size
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		_root.add_child(rb)
		_debris.append(rb)
		_debris_t.append(0.0)
	_marks.clear()
	for i in MAX_MARKS:
		var m := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.09, 0.09)
		m.mesh = q
		m.material_override = _mark_material()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		_root.add_child(m)
		_marks.append(m)
	var blood := Blood.new()
	blood.name = "Sangre"
	_root.add_child(blood)
	var gibs := Gibs.new()
	gibs.name = "Trozos"
	_root.add_child(gibs)
	_lights.clear()
	_lights_t.clear()
	for i in 3:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		l.omni_range = 6.0
		_root.add_child(l)
		_lights.append(l)
		_lights_t.append(0.0)

func _process(delta: float) -> void:
	if _flash_g.e > 0.0:
		_flash_g.e = maxf(_flash_g.e - delta * _flash_g.decay, 0.0)
		var c: Color = _flash_g.c
		RenderingServer.global_shader_parameter_set("flash_p", Vector4(_flash_g.p.x, _flash_g.p.y, _flash_g.p.z, _flash_g.range))
		RenderingServer.global_shader_parameter_set("flash_c", Vector4(c.r * _flash_g.e * 0.5, c.g * _flash_g.e * 0.5, c.b * _flash_g.e * 0.5, 1.0))
	if _root == null or not is_instance_valid(_root):
		return
	for i in _lights.size():
		if _lights_t[i] > 0.0:
			_lights_t[i] -= delta
			var l := _lights[i]
			l.light_energy = maxf(l.light_energy - delta * l.get_meta("decay", 30.0), 0.0)
			if _lights_t[i] <= 0.0:
				l.visible = false
	for i in _debris.size():
		if _debris_t[i] > 0.0:
			_debris_t[i] -= delta
			if _debris_t[i] <= 0.0:
				_debris[i].freeze = true
				_debris[i].visible = false

# ---------------------------------------------------------------- plantillas

func _quad_mat(color: Color, additive: bool, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color if not additive else Color(color.r * 1.2, color.g * 1.2, color.b * 1.2, color.a)
	m.albedo_texture = tex if tex else _soft_tex()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

var _soft: Texture2D
func _soft_tex() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft = t
	return _soft

func _mark_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 1), Color(0.05, 0.04, 0.03, 0.95), Color(0.12, 0.1, 0.08, 0.5), Color(0, 0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	m.albedo_texture = t
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.render_priority = 1
	return m

func _make(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	var q := QuadMesh.new()
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"spark":
			q.size = Vector2(0.03, 0.03)
			q.material = _quad_mat(Color(1.0, 0.75, 0.3), true)
			p.amount = 18; p.lifetime = 0.35
			p.direction = Vector3(0, 0, 1); p.spread = 50.0
			p.initial_velocity_min = 3.0; p.initial_velocity_max = 8.0
			p.gravity = Vector3(0, -12, 0)
			p.scale_amount_min = 0.6; p.scale_amount_max = 1.4
		"dust":
			q.size = Vector2(0.25, 0.25)
			q.material = _quad_mat(Color(1, 1, 1, 1), false)
			p.amount = 10; p.lifetime = 0.9
			p.direction = Vector3(0, 0, 1); p.spread = 40.0
			p.initial_velocity_min = 0.6; p.initial_velocity_max = 2.2
			p.gravity = Vector3(0, -0.6, 0)
			p.damping_min = 2.0; p.damping_max = 3.0
			p.scale_amount_min = 0.6; p.scale_amount_max = 1.8
			p.color_ramp = _fade_ramp(Color(0.6, 0.57, 0.52, 0.6))
		"splinter":
			q.size = Vector2(0.06, 0.02)
			q.material = _quad_mat(Color(0.55, 0.38, 0.2), false)
			p.amount = 14; p.lifetime = 0.8
			p.direction = Vector3(0, 0, 1); p.spread = 60.0
			p.initial_velocity_min = 2.0; p.initial_velocity_max = 5.0
			p.gravity = Vector3(0, -9.8, 0)
			p.angular_velocity_min = -400; p.angular_velocity_max = 400
		"glass":
			q.size = Vector2(0.05, 0.05)
			q.material = _quad_mat(Color(0.7, 0.85, 0.95, 0.8), true)
			p.amount = 24; p.lifetime = 0.9
			p.direction = Vector3(0, 0, 1); p.spread = 70.0
			p.initial_velocity_min = 1.5; p.initial_velocity_max = 5.0
			p.gravity = Vector3(0, -9.8, 0)
		"blood":
			q.size = Vector2(0.07, 0.07)
			q.material = _quad_mat(Color(0.45, 0.0, 0.02, 0.95), false)
			p.amount = 16; p.lifetime = 0.7
			p.direction = Vector3(0, 0, 1); p.spread = 30.0
			p.initial_velocity_min = 1.5; p.initial_velocity_max = 4.5
			p.gravity = Vector3(0, -9.8, 0)
			p.scale_amount_min = 0.4; p.scale_amount_max = 1.6
		"shard_bone":
			q.size = Vector2(0.03, 0.03)
			q.material = _quad_mat(Color(0.95, 0.92, 0.82, 1.0), false)
			p.amount = 12; p.lifetime = 1.2
			p.direction = Vector3(0, 0, 1); p.spread = 55.0
			p.initial_velocity_min = 0.6; p.initial_velocity_max = 2.0
			p.gravity = Vector3(0, -3.0, 0)
		"smoke":
			q.size = Vector2(1.2, 1.2)
			q.material = _quad_mat(Color(1, 1, 1, 1), false)
			p.amount = 24; p.lifetime = 6.0; p.explosiveness = 0.3
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.8
			p.direction = Vector3(0, 1, 0); p.spread = 80.0
			p.initial_velocity_min = 0.3; p.initial_velocity_max = 1.2
			p.gravity = Vector3(0, 0.25, 0)
			p.damping_min = 0.5; p.damping_max = 1.0
			p.scale_amount_min = 1.0; p.scale_amount_max = 3.0
			p.color_ramp = _fade_ramp(Color(0.62, 0.62, 0.66, 0.5))
		"fire":
			q.size = Vector2(0.5, 0.5)
			q.material = _quad_mat(Color(1.0, 0.55, 0.15, 0.9), true)
			p.amount = 20; p.lifetime = 0.8; p.explosiveness = 0.0
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			p.emission_box_extents = Vector3(0.8, 0.05, 0.4)
			p.direction = Vector3(0, 1, 0); p.spread = 15.0
			p.initial_velocity_min = 0.8; p.initial_velocity_max = 2.0
			p.gravity = Vector3(0, 1.0, 0)
			p.color_ramp = _fade_ramp(Color(1.0, 0.7, 0.2, 1.0))
			p.one_shot = false
		"fireball":
			q.size = Vector2(1.0, 1.0)
			q.material = _quad_mat(Color(1.0, 0.6, 0.2, 1.0), true)
			p.amount = 16; p.lifetime = 0.55
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.4
			p.direction = Vector3(0, 1, 0); p.spread = 180.0
			p.initial_velocity_min = 2.0; p.initial_velocity_max = 6.0
			p.damping_min = 6.0; p.damping_max = 9.0
			p.scale_amount_min = 1.0; p.scale_amount_max = 2.6
			p.color_ramp = _fade_ramp(Color(1.0, 0.8, 0.35, 1.0))
		"muzzle":
			q.size = Vector2(0.22, 0.22)
			q.material = _quad_mat(Color(1.0, 0.8, 0.4, 1.0), true)
			p.amount = 5; p.lifetime = 0.06
			p.direction = Vector3(0, 0, 1); p.spread = 12.0
			p.initial_velocity_min = 1.0; p.initial_velocity_max = 3.0
			p.scale_amount_min = 0.6; p.scale_amount_max = 1.3
	return p

func _fade_ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	return g

func _amount(kind: String) -> float:
	match kind:
		"smoke":
			return Settings.level_mult(Settings.smoke)
		"fireball", "fire":
			return Settings.level_mult(Settings.explosions)
		_:
			return Settings.level_mult(Settings.particles)

# ---------------------------------------------------------------- API

## Emite un efecto del grupo en una posición, mirando hacia `dir` (normal de la superficie o dirección del chorro).
func emit(kind: String, pos: Vector3, dir := Vector3.UP, scale := 1.0) -> CPUParticles3D:
	if not _pools.has(kind):
		return null
	var k := _amount(kind)
	if k < 0.4 and kind in ["dust", "splinter"] and randf() > 0.5:
		return null
	var arr: Array = _pools[kind]
	var p: CPUParticles3D = arr[_idx[kind]] if is_instance_valid(arr[_idx[kind]]) else null
	_idx[kind] = (_idx[kind] + 1) % arr.size()
	if p == null:
		return null                      # el grupo quedó de un mapa anterior ya liberado
	p.global_position = pos
	if dir.length_squared() > 0.0001:
		var d := dir.normalized()
		var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
		p.global_basis = Basis.looking_at(-d, up)
	if not p.has_meta("base_amount"):
		p.set_meta("base_amount", p.amount)
	var want := maxi(2, int(int(p.get_meta("base_amount")) * k * scale))
	if p.amount != want:
		p.amount = want
	p.restart()
	p.emitting = true
	stats.emitted += 1
	return p

## Impacto de bala o golpe según el material de la superficie.
func impact(pos: Vector3, normal: Vector3, material: String) -> void:
	match material:
		"metal":
			emit("spark", pos, normal)
		"wood":
			emit("splinter", pos, normal)
			emit("dust", pos, normal, 0.5)
		"glass":
			emit("glass", pos, normal)
		"flesh":
			blood(pos, normal, 1.0)
			return
		_:
			emit("dust", pos, normal)
			emit("spark", pos, normal, 0.3)
	mark(pos, normal)

## Sangre líquida (gotas que caen y manchan). scale > 1 = herida grave.
func blood(pos: Vector3, dir: Vector3, scale := 1.0) -> void:
	if Blood.instance:
		Blood.instance.drops(pos, dir, clampf(0.3 * scale, 0.1, 1.0), 3.0 + scale, 30.0)
	else:
		emit("blood", pos, dir, scale)

func mark(pos: Vector3, normal: Vector3) -> void:
	if _marks.is_empty():
		return
	var m := _marks[_marks_i]
	_marks_i = (_marks_i + 1) % _marks.size()
	m.visible = true
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	m.global_transform = Transform3D(Basis.looking_at(-n, up), pos + n * 0.012)
	m.scale = Vector3.ONE * randf_range(0.7, 1.3)

func muzzle(pos: Vector3, dir: Vector3) -> void:
	emit("muzzle", pos, dir)
	flash(pos + dir * 0.1, 1.6, 4.0, 0.05, Color(1.0, 0.75, 0.4))

## Luz breve (fogonazo, explosión). Sólo hay 3 a la vez; con luces en BAJA se omiten las chicas.
func flash(pos: Vector3, energy: float, range_m: float, seconds: float, color := Color(1, 0.7, 0.35)) -> void:
	# luz del escenario (casi gratis): el destello más fuerte manda
	if energy >= _flash_g.e:
		_flash_g.p = pos
		_flash_g.range = range_m
		_flash_g.c = color
		_flash_g.e = energy
		_flash_g.decay = energy / maxf(seconds, 0.01)
	# luz real sobre personajes y objetos: sólo las grandes (explosiones) y no en el preset sin luces
	if _lights.is_empty() or Settings.lights == 0 or energy < 4.0:
		return
	var best := 0
	for i in _lights.size():
		if _lights_t[i] <= 0.0:
			best = i
			break
		if _lights_t[i] < _lights_t[best]:
			best = i
	var l := _lights[best]
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.set_meta("decay", energy / maxf(seconds, 0.01))
	l.visible = true
	_lights_t[best] = seconds

func smoke(pos: Vector3, scale := 1.0) -> void:
	if Settings.smoke == 0 and scale < 1.5:
		return
	emit("smoke", pos, Vector3.UP, scale)

## Fragmentos físicos (astillas grandes de cajas, chapas, vidrio). Se reciclan; cada uno vive unos segundos.
func debris(pos: Vector3, color: Color, count: int, impulse: float, size := Vector3(0.12, 0.05, 0.12)) -> void:
	if _debris.is_empty():
		return
	count = maxi(1, int(count * Settings.level_mult(Settings.explosions)))
	for n in count:
		var rb := _debris[_debris_i]
		var slot := _debris_i
		_debris_i = (_debris_i + 1) % _debris.size()
		var mi := rb.get_child(1) as MeshInstance3D
		(mi.mesh as BoxMesh).size = size * randf_range(0.6, 1.4)
		((rb.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = (mi.mesh as BoxMesh).size
		var mat: StandardMaterial3D = _mats.get(color)
		if mat == null:
			mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mat.roughness = 0.9
			_mats[color] = mat
		mi.material_override = mat
		rb.global_position = pos + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.3), randf_range(-0.1, 0.1))
		rb.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		rb.visible = true
		rb.freeze = false
		rb.sleeping = false
		rb.linear_velocity = Vector3(randf_range(-1, 1), randf_range(0.4, 1.4), randf_range(-0.3, 0.3)).normalized() * impulse * randf_range(0.5, 1.2)
		rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		_debris_t[slot] = randf_range(3.0, 5.0)
		stats.debris += 1
