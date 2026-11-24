class_name SideCamera
extends Camera3D
## Cámara lateral: sigue al jugador en X e Y con suavizado, se adelanta un poco hacia donde apunta, respeta los límites
## del edificio y vibra con las explosiones (TimeFx.shake). Encuadre cerrado: muestra el piso actual y un poco de los
## vecinos, nunca toda la torre. La cámara de bala (BulletTime) la toma prestada con override_target().

@export var distance := 9.0
@export var height := 2.0
var target: Actor
var bounds := Rect2(0, -1, 60, 26)
var _pos := Vector3.ZERO
var _shake := 0.0
var _shake_t := 0.0
var _look := Vector3.ZERO
## cámara de bala / primer plano
var override_active := false
var override_pos := Vector3.ZERO
var override_look := Vector3.ZERO
var override_fov := 30.0
var base_fov := 40.0

func _ready() -> void:
	fov = base_fov
	near = 0.1
	far = 140.0
	TimeFx.shake_requested.connect(func(a: float): _shake = minf(_shake + a, 1.2))
	if target:
		_pos = _desired()
		global_position = _pos

func _desired() -> Vector3:
	var p := target.global_position
	var aim := Vector3(target.aim_dir.x, target.aim_dir.y, 0) * 1.6
	var vel_look := Vector3(clampf(target.velocity.x * 0.25, -1.2, 1.2), 0, 0)
	var x := clampf(p.x + aim.x + vel_look.x, bounds.position.x + 6.0, bounds.end.x - 6.0)
	var y := clampf(p.y + height + aim.y * 0.6, bounds.position.y + 2.0, bounds.end.y)
	return Vector3(x, y, distance)

func _process(delta: float) -> void:
	# usa tiempo real: en cámara lenta la cámara sigue fluida
	var rd := delta / maxf(Engine.time_scale, 0.05)
	rd = minf(rd, 0.05)
	if override_active:
		global_position = global_position.lerp(override_pos, clampf(rd * 4.0, 0.0, 1.0))
		_look = _look.lerp(override_look, clampf(rd * 6.0, 0.0, 1.0))
		fov = lerpf(fov, override_fov, clampf(rd * 3.0, 0.0, 1.0))
		look_at(_look, Vector3.UP)
		return
	if target == null or not is_instance_valid(target):
		return
	var want := _desired()
	var k := clampf(rd * 5.0, 0.0, 1.0)
	_pos.x = lerpf(_pos.x, want.x, k)
	_pos.y = lerpf(_pos.y, want.y, clampf(rd * 3.5, 0.0, 1.0))
	_pos.z = distance
	fov = lerpf(fov, base_fov, clampf(rd * 3.0, 0.0, 1.0))
	var off := Vector3.ZERO
	if _shake > 0.001:
		_shake_t += rd * 40.0
		off = Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.7 + 1.0), 0) * _shake * 0.18
		_shake = move_toward(_shake, 0.0, rd * 1.6)
	global_position = _pos + off
	_look = Vector3(_pos.x, _pos.y - 0.35, 0) + off * 0.5
	look_at(_look, Vector3.UP)

func override_target(pos: Vector3, look: Vector3, fov_deg := 30.0) -> void:
	override_active = true
	override_pos = pos
	override_look = look
	override_fov = fov_deg

func release_override() -> void:
	override_active = false
	if target:
		_pos = global_position
