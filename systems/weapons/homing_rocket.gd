class_name HomingRocket
extends Node3D
## Cohete de la especialidad «Cohete»: sale en la dirección de apuntado, busca al enemigo más cercano en su arco de visión
## y lo persigue (gira de a poco, no es instantáneo). Explota al tocar un actor, una pared o al agotarse el combustible.

var shooter: Actor
var vel := Vector3.ZERO
var speed := 15.0
var _life := 5.0
var _trail := 0.0

static func launch(a: Actor) -> void:
	var r := HomingRocket.new()
	r.shooter = a
	a.get_parent().add_child(r)
	var d := Vector3(a.aim_dir.x, a.aim_dir.y, 0).normalized()
	if d.length() < 0.1:
		d = Vector3(a.facing, 0.1, 0)
	r.global_position = a.global_position + Vector3(d.x * 0.6, 1.5, 0)
	r.vel = d * r.speed
	Sfx.play("grenade_pin", r.global_position, 2.0, 0.6, 20.0, a)

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.07
	cm.height = 0.5
	mi.mesh = cm
	mi.rotation.z = PI * 0.5
	add_child(mi)
	mi.name = "Cuerpo"

func _nearest() -> Actor:
	var best: Actor = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a.is_dead() or a.team == shooter.team:
			continue
		var to := a.global_position + Vector3.UP * 1.1 - global_position
		var dist := to.length()
		if dist < bd and dist < 40.0 and to.normalized().dot(vel.normalized()) > -0.2:
			bd = dist
			best = a
	return best

func _physics_process(delta: float) -> void:
	_life -= delta
	if shooter == null or not is_instance_valid(shooter):
		queue_free()
		return
	var tgt := _nearest()
	if tgt:
		var want := (tgt.global_position + Vector3.UP * 1.1 - global_position).normalized()
		var cur := vel.normalized()
		var ang := cur.angle_to(want)
		var step := minf(ang, delta * 2.6)
		if ang > 0.001:
			var axis := cur.cross(want)
			if axis.length() > 0.0001:
				cur = cur.rotated(axis.normalized(), step)
		vel = cur * speed
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	global_position = to
	rotation.z = atan2(vel.y, vel.x)
	_trail -= delta
	if _trail <= 0.0:
		_trail = 0.04
		Fx.smoke(global_position, 0.25)
	var boom := not hit.is_empty() or _life <= 0.0
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a and a != shooter and not a.is_dead() and a.team != shooter.team and (a.global_position + Vector3.UP * 1.0).distance_to(global_position) < 0.9:
			boom = true
	if boom:
		Explosion.spawn(get_parent(), "frag", global_position, shooter)
		queue_free()
