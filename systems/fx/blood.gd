class_name Blood
extends Node3D
## Sangre LÍQUIDA (idea de BLACK VEIL, Operación Nexus, rehecha con grupos fijos para el teléfono):
##  * spray(): gotas que se estiran con la velocidad, caen con gravedad y manchan piso y paredes donde caen.
##  * Hemorragias que siguen al cuerpo (BleedSource, pegadas al hueso de la herida):
##      - ARTERIAL (arterias, aorta, corazón): CHORRO PULSÁTIL al ritmo del corazón; la presión baja con la vida.
##      - VENOSA / VÍSCERAS (hígado, intestinos, pulmón, músculos): sangre oscura que mana y gotea.
##    Se cortan al vendar / usar el botiquín (según lo que cure cada herida) o al morir (pasa a charco).
##  * pool(): charco que crece debajo del cuerpo.
## Límites: 14 emisores de gotas reutilizables, 90 manchas (las más viejas se reciclan).

const EMITTERS := 14
const MAX_STAINS := 90

static var instance: Blood

var _em: Array[CPUParticles3D] = []
var _em_i := 0
var _stains: Array[MeshInstance3D] = []
var _stain_i := 0
var _drop_mat: StandardMaterial3D
var _dark_mat: StandardMaterial3D
var _stain_mat: StandardMaterial3D
var _pool_mat: StandardMaterial3D

func _ready() -> void:
	instance = self
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_color = Color(0.6, 0.0, 0.03)
	_drop_mat.roughness = 0.12
	_drop_mat.metallic_specular = 0.9
	_drop_mat.emission_enabled = true
	_drop_mat.emission = Color(0.12, 0.0, 0.0)
	_dark_mat = _drop_mat.duplicate()
	_dark_mat.albedo_color = Color(0.3, 0.0, 0.02)
	_stain_mat = StandardMaterial3D.new()
	_stain_mat.albedo_texture = _stain_tex()
	_stain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stain_mat.roughness = 0.18
	_stain_mat.metallic_specular = 0.8
	_stain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stain_mat.render_priority = 3
	_pool_mat = _stain_mat.duplicate()
	_pool_mat.albedo_color = Color(0.75, 0.7, 0.7)
	for i in EMITTERS:
		var p := _make_emitter()
		add_child(p)
		_em.append(p)
	var qm := QuadMesh.new()
	qm.size = Vector2.ONE
	for i in MAX_STAINS:
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = _stain_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_stains.append(mi)

func _exit_tree() -> void:
	if instance == self:
		instance = null

func _make_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.011
	sm.height = 0.022
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = _drop_mat
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = 1.3
	p.local_coords = false
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	p.particle_flag_align_y = true            # la gota se estira en la dirección en que vuela: aspecto líquido
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.8, 0.85))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

static func _stain_tex() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1807
	var blobs: Array = [[0.5, 0.5, 0.24]]
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.12, 0.44)
		blobs.append([0.5 + cos(a) * r, 0.5 + sin(a) * r, rng.randf_range(0.02, 0.09)])
	for y in n:
		for x in n:
			var u := float(x) / n
			var v := float(y) / n
			var a := 0.0
			for b in blobs:
				a = maxf(a, clampf(1.0 - Vector2(u - float(b[0]), v - float(b[1])).length() / float(b[2]), 0.0, 1.0))
			var edge := clampf(1.0 - absf(a - 0.25) * 6.0, 0.0, 1.0)
			a = clampf(a * 3.0, 0.0, 1.0)
			var c := Color(0.48, 0.02, 0.02).lerp(Color(0.22, 0.0, 0.0), edge * 0.7)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * 0.92))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Gotas en una dirección. amount 0..1 (cantidad), speed m/s, dark = sangre venosa / de vísceras.
func drops(point: Vector3, dir: Vector3, amount: float, speed: float, spread := 22.0, dark := false) -> void:
	var p := _em[_em_i]
	_em_i = (_em_i + 1) % _em.size()
	var n := maxi(3, int(60.0 * amount * Settings.level_mult(maxi(Settings.particles, 1))))
	if p.amount != n:
		p.amount = n
	p.material_override = _dark_mat if dark else _drop_mat
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.DOWN
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.global_position = point
	p.restart()
	p.emitting = true
	# dónde caen: unas pocas trayectorias balísticas contra el mundo → manchas
	var space := get_world_3d().direct_space_state
	for i in (3 if amount > 0.4 else 1):
		var v := (dir.normalized() * randf_range(speed * 0.4, speed)).rotated(Vector3.BACK, deg_to_rad(randf_range(-spread, spread)))
		var pos := point
		for s in 14:
			var nxt := pos + v * 0.06
			v.y -= 9.8 * 0.06
			var q := PhysicsRayQueryParameters3D.create(pos, nxt, 1 | 8)
			var h := space.intersect_ray(q)
			if not h.is_empty():
				stain(h.position, h.normal, randf_range(0.12, 0.32) * (0.6 + amount), true)
				break
			pos = nxt

## Impacto: chorro de entrada (corto, hacia atrás) y de salida (más fuerte, hacia adelante si la bala atravesó).
func spray(point: Vector3, dir: Vector3, through: bool, heavy := false) -> void:
	drops(point, -dir, 0.35 if not heavy else 0.6, 2.5, 40.0)
	if through:
		drops(point + dir * 0.15, dir, 0.8 if not heavy else 1.0, 6.0, 26.0)

func stain(pos: Vector3, normal: Vector3, size: float, grow := false, mat: Material = null) -> MeshInstance3D:
	var mi := _stains[_stain_i]
	_stain_i = (_stain_i + 1) % _stains.size()
	mi.material_override = mat if mat else _stain_mat
	var up := normal.normalized()
	var fwd := up.cross(Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT).normalized()
	var b := Basis(fwd, fwd.cross(up), up).rotated(up, randf() * TAU)
	mi.global_transform = Transform3D(b.orthonormalized(), pos + up * (0.012 + randf() * 0.004))
	mi.visible = true
	var full := Vector3(size, size, 1.0)
	if grow:
		mi.scale = full * Vector3(0.1, 0.1, 1.0)
		var tw := mi.create_tween()
		tw.tween_interval(randf_range(0.15, 0.5))
		tw.tween_property(mi, "scale", full, 0.25)
	else:
		mi.scale = full
	return mi

## Charco que crece debajo de un cuerpo (≈ 8 s).
func pool(pos: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.6, pos + Vector3.DOWN * 3.0, 1)
	var h := get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty():
		return
	var mi := stain(h.position, h.normal, randf_range(1.4, 1.9), false, _pool_mat)
	var full := mi.scale
	mi.scale = full * Vector3(0.08, 0.08, 1.0)
	mi.create_tween().tween_property(mi, "scale", full, 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Hemorragia pegada a una herida (sigue al hueso). arterial = chorro pulsátil; si no, mana y gotea.
class BleedSource extends BoneAttachment3D:
	var actor: Actor
	var arterial := false
	var rate := 1.0              ## vida por segundo de esta herida (da la intensidad)
	var out_dir := Vector3.RIGHT ## hacia dónde sale (mundo, al crearse)
	var _local_dir := Vector3.RIGHT
	var _t := 0.0
	var _beat := 0.0
	var _drip := 0.0
	var marker: Node3D
	func setup(a: Actor, bone: String, world_point: Vector3, dir: Vector3) -> void:
		actor = a
		bone_name = bone
		a.skel.add_child(self)
		marker = Node3D.new()
		add_child(marker)
		marker.global_position = world_point
		_local_dir = global_basis.inverse() * dir.normalized()
	func _process(delta: float) -> void:
		if Blood.instance == null or not is_instance_valid(actor):
			return
		_t += delta
		var p := marker.global_position
		var d := (global_basis * _local_dir).normalized()
		var hp_k := clampf(actor.health / maxf(actor.max_health, 1.0), 0.05, 1.0)
		if arterial and not actor.is_dead():
			# corazón a ~75-140 latidos/min (más rápido cuanto más sangre perdió); el chorro sale en cada latido
			var bpm := lerpf(140.0, 75.0, hp_k)
			_beat -= delta
			if _beat <= 0.0:
				_beat = 60.0 / bpm
				var pressure := clampf(rate / 5.0, 0.4, 1.6) * lerpf(0.35, 1.0, hp_k)
				Blood.instance.drops(p, (d + Vector3.UP * 0.25).normalized(), 0.35 * pressure, 2.2 + 3.2 * pressure, 10.0)
		else:
			_drip -= delta
			if _drip <= 0.0:
				_drip = clampf(1.2 / maxf(rate, 0.2), 0.12, 1.5)
				Blood.instance.drops(p, Vector3.DOWN + d * 0.15, 0.08 + minf(rate, 3.0) * 0.04, 0.4, 25.0, not arterial)
