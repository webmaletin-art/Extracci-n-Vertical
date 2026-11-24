class_name Elevator
extends Node3D
## Ascensor industrial abierto (plataforma). Es parte del escenario: el hueco se cruza caminando de lado a lado cuando la
## plataforma está a la altura del piso, se puede caminar sobre ella y tiene colisión real (AnimatableBody3D: lleva a
## los personajes parados encima). No es una pared invisible: las barandas sólo se levantan mientras se mueve.
## Panel en la plataforma (USAR → elegir destino) y botón de llamada en cada parada.

signal arrived(stop: int)

@export var stops: Array[float] = [0.0, 4.0, 8.0]
@export var stop_names: Array[String] = ["P0", "P1", "P2"]
@export var width := 2.4
@export var speed := 1.7
var current := 0
var target := 0
var moving := false
var platform: AnimatableBody3D
var _gates: Array[Node3D] = []
var _gate_shapes: Array[CollisionShape3D] = []
var _hum_t := 0.0
var _y := 0.0

func _ready() -> void:
	add_to_group("elevators")
	_build()
	_y = stops[current]
	platform.position.y = _y
	for i in stops.size():
		var call := ElevatorCall.new()
		call.elevator = self
		call.stop = i
		call.position = Vector3(width * 0.5 + 0.55, stops[i] + 1.0, 0)
		add_child(call)

func _build() -> void:
	platform = AnimatableBody3D.new()
	platform.sync_to_physics = true
	platform.collision_layer = 1
	platform.set_meta("surface", "metal")
	add_child(platform)
	var deck := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(width, 0.16, 2.2)
	deck.shape = b
	deck.position.y = -0.08
	platform.add_child(deck)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/floor_plate.png")
	mat.uv1_scale = Vector3(2, 2, 1)
	mat.metallic = 0.5
	mat.roughness = 0.6
	var dm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = b.size
	dm.mesh = bm
	dm.material_override = mat
	dm.position.y = -0.08
	platform.add_child(dm)
	# marco amarillo + cables + panel
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.9, 0.66, 0.08)
	yellow.metallic = 0.5
	yellow.roughness = 0.5
	for sx in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.08, 2.4, 0.08)
		post.mesh = pm
		post.material_override = yellow
		post.position = Vector3(sx * (width * 0.5 - 0.04), 1.2, -1.0)
		platform.add_child(post)
		# baranda que se levanta al moverse
		var gate := Node3D.new()
		gate.position = Vector3(sx * (width * 0.5 - 0.03), 0.0, 0)
		var gm := MeshInstance3D.new()
		var gbm := BoxMesh.new()
		gbm.size = Vector3(0.05, 0.06, 2.0)
		gm.mesh = gbm
		gm.material_override = yellow
		gm.position.y = 1.0
		gate.add_child(gm)
		platform.add_child(gate)
		gate.scale.y = 0.05
		_gates.append(gate)
		var gs := CollisionShape3D.new()
		var gb := BoxShape3D.new()
		gb.size = Vector3(0.06, 1.1, 2.0)
		gs.shape = gb
		gs.position = Vector3(sx * (width * 0.5 - 0.03), 0.55, 0)
		gs.disabled = true
		platform.add_child(gs)
		_gate_shapes.append(gs)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(width, 0.08, 0.08)
	top.mesh = tm
	top.material_override = yellow
	top.position = Vector3(0, 2.4, -1.0)
	platform.add_child(top)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.7, 0.35)
	lamp.light_energy = 0.8
	lamp.omni_range = 4.0
	lamp.position = Vector3(0, 2.2, -0.5)
	lamp.add_to_group("dyn_light")
	platform.add_child(lamp)
	var panel := ElevatorPanel.new()
	panel.elevator = self
	panel.position = Vector3(width * 0.5 - 0.35, 1.1, -0.6)
	platform.add_child(panel)
	var pmesh := MeshInstance3D.new()
	var pbm := BoxMesh.new()
	pbm.size = Vector3(0.22, 0.34, 0.06)
	pmesh.mesh = pbm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.1, 0.1, 0.1)
	pmat.emission_enabled = true
	pmat.emission = Color(0.1, 0.9, 0.3)
	pmat.emission_energy_multiplier = 0.6
	pmesh.material_override = pmat
	pmesh.position = Vector3(width * 0.5 - 0.15, 1.2, -0.95)
	platform.add_child(pmesh)
	# guías del hueco (columnas fijas a todo lo alto)
	var h := stops[-1] - stops[0] + 4.0
	for sx in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.12, h, 0.12)
		rail.mesh = rm
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.25, 0.26, 0.28)
		steel.metallic = 0.7
		steel.roughness = 0.4
		rail.material_override = steel
		rail.position = Vector3(sx * (width * 0.5 + 0.1), stops[0] + h * 0.5, -1.15)
		add_child(rail)

func go_to(stop: int) -> void:
	stop = clampi(stop, 0, stops.size() - 1)
	if moving or stop == current:
		return
	target = stop
	moving = true
	Sfx.play("elevator_start", platform.global_position + Vector3.UP, 0.0, 1.0, 25.0, self)
	for g in _gates:
		create_tween().tween_property(g, "scale:y", 1.0, 0.4)
	for s in _gate_shapes:
		s.set_deferred("disabled", false)

func _physics_process(delta: float) -> void:
	if not moving:
		return
	var goal := stops[target]
	_y = move_toward(_y, goal, speed * delta)
	platform.position.y = _y
	_hum_t -= delta
	if _hum_t <= 0.0:
		_hum_t = 0.9
		Sfx.play("elevator_hum", platform.global_position + Vector3.UP, -6.0, 1.0, 18.0, self)
	if is_equal_approx(_y, goal):
		moving = false
		current = target
		Sfx.play("elevator_stop", platform.global_position + Vector3.UP, 0.0, 1.0, 20.0, self)
		for g in _gates:
			create_tween().tween_property(g, "scale:y", 0.05, 0.4)
		for s in _gate_shapes:
			s.set_deferred("disabled", true)
		arrived.emit(current)

func stop_index_near(y: float) -> int:
	var best := 0
	for i in stops.size():
		if absf(stops[i] - y) < absf(stops[best] - y):
			best = i
	return best


## Panel dentro de la plataforma: USAR abre el selector de destino en el HUD (o elige solo, para la IA).
class ElevatorPanel extends Interactable:
	var elevator: Elevator
	func _ready() -> void:
		radius = 1.1
		super._ready()
	func can_use(actor: Actor) -> bool:
		return not elevator.moving and absf(actor.global_position.y - elevator.platform.global_position.y) < 0.6
	func prompt_for(_actor: Actor) -> String:
		return "Ascensor: elegir piso"
	func use(actor: Actor) -> void:
		Sfx.play("button", global_position, -6.0)
		if actor.is_player:
			actor.get_tree().call_group("hud", "show_elevator_menu", elevator)
		else:
			elevator.go_to((elevator.current + 1) % elevator.stops.size())


## Botón de llamada en cada parada.
class ElevatorCall extends Interactable:
	var elevator: Elevator
	var stop := 0
	func can_use(actor: Actor) -> bool:
		return not elevator.moving and elevator.current != stop and absf(actor.global_position.y - elevator.stops[stop]) < 1.0
	func prompt_for(_actor: Actor) -> String:
		return "Llamar ascensor"
	func use(_actor: Actor) -> void:
		Sfx.play("button", global_position, -6.0)
		elevator.go_to(stop)
