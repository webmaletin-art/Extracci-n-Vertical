class_name Mine
extends Node3D
## Mina de proximidad: se planta en el piso con el botón «MINA»; se arma en 1,5 s y explota cuando un enemigo pasa cerca.
## El que la plantó (y su equipo) no la dispara.

var owner_actor: Actor
var team := 0
var _armed_t := 1.5
var _led: MeshInstance3D
var _t := 0.0
var _done := false

static func plant(a: Actor) -> Mine:
	var m := Mine.new()
	a.get_parent().add_child(m)
	m.global_position = Vector3(a.global_position.x + a.facing * 0.35, a.global_position.y + 0.03, 0.0)
	m.owner_actor = a
	m.team = a.team
	return m

func _ready() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.16
	cm.bottom_radius = 0.18
	cm.height = 0.05
	disc.mesh = cm
	disc.position.y = 0.025
	add_child(disc)
	_led = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	_led.mesh = sm
	_led.position.y = 0.07
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1, 0.1, 0.1)
	_led.material_override = lm
	_led.set_meta("no_tech", true)
	add_child(_led)
	LinedBake.style_tree(self)
	Sfx.play("pickup", global_position, -6.0, 1.6, 4.0)
	add_to_group("mines")

func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_led.visible = _armed_t > 0.0 or fmod(_t, 1.0) < 0.15
	if _armed_t > 0.0:
		_armed_t -= delta
		return
	for n in get_tree().get_nodes_in_group("actors"):
		var a := n as Actor
		if a == null or a.is_dead() or a.team == team:
			continue
		if absf(a.global_position.x - global_position.x) < 0.9 and absf(a.global_position.y - global_position.y) < 1.4:
			_done = true
			Explosion.spawn(get_parent(), "frag", global_position + Vector3.UP * 0.15, owner_actor)
			queue_free()
			return
