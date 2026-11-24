class_name Ladder
extends Area3D
## Escalera de mano (vertical) contra la pared del fondo. El Actor la toma con el joystick hacia arriba / abajo dentro
## del área, sube al ritmo de la animación Climbing_Ladder de Mixamo (un ciclo = dos peldaños) y arriba sale con
## Climbing_To_Top hacia exit_dir. La escalera pasa por una trampilla del piso de arriba (el mapa deja el hueco).

@export var bottom_y := 0.0
@export var top_y := 4.0
@export var exit_dir := 1.0         ## hacia dónde se sale arriba (+1 derecha, -1 izquierda)
const RUNG := 0.3                   ## separación de peldaños (calza con el paso de la animación)

func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("ladders")

func setup(x: float, z: float, y0: float, y1: float, dir: float) -> void:
	global_position = Vector3(x, y0, z)
	bottom_y = y0
	top_y = y1
	exit_dir = dir
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(0.7, y1 - y0 + 1.0, 2.6)
	cs.shape = b
	cs.position = Vector3(0, (y1 - y0) * 0.5 + 0.3, -z)
	add_child(cs)
	_build_mesh(y1 - y0)

func can_enter(actor: Node3D, dir: float) -> bool:
	var y := actor.global_position.y
	if dir > 0.0:
		return y < top_y - 1.5
	return y > bottom_y + 0.3

func _build_mesh(h: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.62, 0.08)
	mat.metallic = 0.6
	mat.roughness = 0.45
	var total := h + 1.1
	for side in [-0.22, 0.22]:
		var rail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, total, 0.05)
		rail.mesh = bm
		rail.material_override = mat
		rail.position = Vector3(side, total * 0.5, 0)
		add_child(rail)
	var rung_mesh := CylinderMesh.new()
	rung_mesh.top_radius = 0.015
	rung_mesh.bottom_radius = 0.015
	rung_mesh.height = 0.44
	rung_mesh.radial_segments = 6
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rung_mesh
	var n := int(total / RUNG)
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.25 + i * RUNG, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
