class_name Grenade
extends RigidBody3D
## Granada lanzada: cuerpo rígido con trayectoria parabólica real (gravedad del motor), rebotes con sonido y espoleta.
## Se mueve sólo en el plano del juego (z bloqueado). Al terminar la espoleta llama a Explosion.spawn(tipo).

var kind := "frag"
var fuse := 2.5
var thrower: Node
var _t := 0.0
var _last_bounce := 0.0

const COLORS := {"frag": Color(0.25, 0.3, 0.18), "stun": Color(0.35, 0.35, 0.38), "smoke": Color(0.4, 0.45, 0.5),
	"incendiary": Color(0.55, 0.2, 0.1), "c4": Color(0.75, 0.72, 0.55)}

static func spawn(parent: Node, kind_: String, pos: Vector3, vel: Vector3, by: Node) -> Grenade:
	if parent == null:
		return null
	var g := Grenade.new()
	g.kind = kind_
	g.thrower = by
	var d: Dictionary = Explosion.defs().get(kind_, {})
	g.fuse = float(d.get("fuse", 2.5))
	parent.add_child(g)
	g.global_position = Vector3(pos.x, pos.y, 0.0)
	g.linear_velocity = Vector3(vel.x, vel.y, 0.0)
	g.angular_velocity = Vector3(0, 0, -signf(vel.x) * 12.0)
	return g

func _ready() -> void:
	mass = 0.4
	collision_layer = 64
	collision_mask = 1 | 8
	continuous_cd = true
	axis_lock_linear_z = true
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = float(Explosion.defs().get(kind, {}).get("bounce", 0.3))
	pm.friction = 0.8
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.05
	cs.shape = s
	add_child(cs)
	var mi := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.04
	body.height = 0.12 if kind != "c4" else 0.08
	mi.mesh = body
	var m := StandardMaterial3D.new()
	m.albedo_color = COLORS.get(kind, Color(0.3, 0.3, 0.3))
	m.roughness = 0.7
	mi.material_override = m
	add_child(mi)
	var spoon := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.08, 0.02)
	spoon.mesh = bm
	spoon.position = Vector3(0.04, 0.02, 0)
	spoon.material_override = m
	add_child(spoon)
	LinedBake.style_tree(self)
	body_entered.connect(_on_hit)

func _on_hit(_b: Node) -> void:
	if _t - _last_bounce > 0.12 and linear_velocity.length() > 1.0:
		_last_bounce = _t
		Sfx.play("grenade_bounce", global_position, -4.0, randf_range(0.9, 1.1), 6.0, thrower)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= fuse:
		set_physics_process(false)
		Explosion.spawn(get_parent(), kind, global_position, thrower)
		queue_free()

## Puntos del arco previsto (para el HUD mientras se mantiene el botón de granada).
static func arc_points(from: Vector3, vel: Vector3, steps := 24, dt := 0.06) -> PackedVector3Array:
	var out := PackedVector3Array()
	var p := from
	var v := vel
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	for i in steps:
		out.append(p)
		v.y -= g * dt
		p += v * dt
	return out
