class_name Limb
extends RigidBody3D
## Miembro desprendido (brazo, antebrazo, mano, muslo, pantorrilla, pie o cabeza): cuerpo rígido en el plano del juego
## (z bloqueado), con la forma EXACTA que tenía en el cuerpo al cortarse. Tiene dos mallas: el traje y la versión de rayos X
## (huesos y vasos). Se ve la de rayos X mientras la toma de muerte de ese cuerpo muestra su anatomía; después, la normal.
## Chorrea sangre a latidos por el corte mientras gira y cae.

static var _active: Array = []
const MAX_LIMBS := 10

var suit: MeshInstance3D
var xray: MeshInstance3D
var anat: AnatomyBody
var cut_local := Vector3.ZERO        ## centro del corte (local del cuerpo)
var axis_local := Vector3.DOWN       ## hacia dónde mira el corte (local, hacia el muñón)
var bleed := 7.0                     ## segundos que sigue sangrando
var _beat := 0.0
var _age := 0.0

func setup(mesh_suit: Mesh, mesh_xray: Mesh, center: Vector3, shape_len: float, shape_r: float, shape_off: Vector3, axis: Vector3, cut_pt: Vector3, anat_body: AnatomyBody) -> void:
	collision_layer = 0
	collision_mask = 1 | 8
	axis_lock_linear_z = true
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	continuous_cd = true
	mass = 4.0
	linear_damp = 0.15
	angular_damp = 0.6
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.18
	pm.friction = 0.9
	physics_material_override = pm
	anat = anat_body
	axis_local = axis
	cut_local = cut_pt - center
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = shape_r
	cap.height = maxf(shape_len, shape_r * 2.0 + 0.02)
	cs.shape = cap
	var up := Vector3.UP
	var q := Quaternion(up, axis.normalized()) if absf(up.dot(axis.normalized())) < 0.999 else Quaternion.IDENTITY
	if up.dot(axis.normalized()) < -0.999:
		q = Quaternion(Vector3.BACK, PI)
	cs.transform = Transform3D(Basis(q), shape_off)
	add_child(cs)
	suit = MeshInstance3D.new()
	suit.mesh = mesh_suit
	suit.set_meta("no_tech", true)
	suit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(suit)
	if mesh_xray:
		xray = MeshInstance3D.new()
		xray.mesh = mesh_xray
		xray.set_meta("no_tech", true)
		xray.visible = false
		xray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(xray)
	global_position = center
	_active.append(self)
	while _active.size() > MAX_LIMBS:
		var old = _active.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()

func _exit_tree() -> void:
	_active.erase(self)

func _process(delta: float) -> void:
	_age += delta
	if _age > 60.0:
		queue_free()
		return
	var show_x := anat != null and is_instance_valid(anat) and anat._showing and _age < 12.0
	if xray:
		xray.visible = show_x
		suit.visible = not show_x
	if bleed > 0.0 and Blood.instance:
		bleed -= delta
		_beat -= delta
		if _beat <= 0.0:
			_beat = 0.3
			var k := clampf(bleed / 7.0, 0.15, 1.0)
			var p := global_transform * cut_local
			var d := (global_basis * axis_local).normalized()
			Blood.instance.drops(p, (d + Vector3.UP * 0.2).normalized(), 0.6 * k, 3.0 + 3.5 * k, 22.0)
