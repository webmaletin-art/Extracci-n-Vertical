class_name MenuTower
extends Node3D
## Portada: la Torre Alfa REAL (la del juego) dibujada en línea sobre blanco, y delante, de espaldas, el operador con su arma
## mirando el edificio, como si fuera a entrar. Hace movimientos tranquilos: mira el arma, la controla, recarga, la cuelga.

var _cam: Camera3D
var _tower: TowerBuilder
var _op: Actor
var _t := 0.0
var _next := 3.0
var _step := 0
var _scene: MenuScene
var _orbit := false                   ## el jugador tomó la cámara (girar / acercar la escena)
var _yaw := 0.0
var _pitch := 0.12
var _dist := 11.0
var _touches := {}
var _pinch0 := 0.0
const SCENE_POS := Vector3(22.6, 0.0, 4.2)
const PIVOT := Vector3(22.6, 1.7, 4.2)

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.97, 0.97, 0.96)
	env.environment = e
	add_child(env)
	_tower = TowerBuilder.new()
	add_child(_tower)
	_tower.build(TorreAlfa.data())
	for en in _tower.enemies:
		en.queue_free()
	_tower.enemies.clear()
	for g in get_tree().get_nodes_in_group("enemies"):
		if is_ancestor_of(g):
			g.queue_free()
	for c in _tower.covers.values():
		(c as Node3D).visible = false           # velos de sectores sin descubrir
	# suelo de la plaza delante del edificio
	var plaza := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80, 0.4, 30)
	cs.shape = bx
	plaza.add_child(cs)
	plaza.position = Vector3(20, -0.2, 8)
	add_child(plaza)
	# operador: su "adelante" (+X del juego) apunta a -Z (hacia el edificio); la cámara lo ve de espaldas
	var pivot := Node3D.new()
	pivot.rotation_degrees.y = 90.0
	pivot.position = Vector3(14.9, 0.0, 6.4)
	add_child(pivot)
	_op = Actor.new()
	_op.name = "OperadorMenu"
	_op.character_id = Settings.character_id
	_op.team = 0
	_op.laser_enabled = false
	_op.menu_pose = true
	pivot.add_child(_op)
	_op.position = Vector3.ZERO
	_op.give_weapon("primary", Profile.equipped.get("primary", "m4a1"))
	_op.give_weapon("secondary", Profile.equipped.get("secondary", "m1911"))
	_op.equip("primary")
	_op.facing = 1.0
	_op.inp.aim_snap = true
	_op.inp.aim = Vector2(1, 0.25)
	_scene = MenuScene.new()
	_scene.position = SCENE_POS
	add_child(_scene)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.far = 300.0
	add_child(_cam)
	_cam.make_current()

func _process(delta: float) -> void:
	_t += delta
	if _cam == null:
		return
	_cam.fov = 58.0
	if _orbit:
		var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
		_cam.position = PIVOT + off
		_cam.look_at(PIVOT, Vector3.UP)
	else:
		_cam.position = Vector3(17.2 + sin(_t * 0.2) * 0.3, 1.7, 12.6)
		_cam.look_at(Vector3(20.3 + sin(_t * 0.2) * 0.3, 2.5, 3.0), Vector3.UP)
	if _op == null or not is_instance_valid(_op):
		return
	# guion tranquilo de movimientos (sin disparar): controla el arma, la cambia por la pistola, recarga, la vuelve a sacar
	if _t > _next:
		_step = (_step + 1) % 6
		match _step:
			0: _op.equip("primary")
			1:
				if _op.weapon() and not _op.weapon().reloading:
					_op.weapon().start_reload()
			2: _op.equip("secondary")
			3: _op.equip("primary")
			4:
				if _op.weapon() and not _op.weapon().reloading:
					_op.weapon().start_reload()
			5: _op.equip("secondary")
		_next = _t + 3.4

## Girar (arrastrar) y acercar (rueda / pellizco) la escena de la portada.
func _unhandled_input(ev: InputEvent) -> void:
	var moved := false
	if ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
		_take_camera()
		_yaw -= (ev as InputEventMouseMotion).relative.x * 0.006
		_pitch = clampf(_pitch + (ev as InputEventMouseMotion).relative.y * 0.004, -0.2, 0.9)
		moved = true
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_take_camera()
			_dist = clampf(_dist - 0.8, 3.5, 24.0)
			moved = true
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_take_camera()
			_dist = clampf(_dist + 0.8, 3.5, 24.0)
			moved = true
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch0 = 0.0
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		_touches[sd.index] = sd.position
		_take_camera()
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1])
			if _pinch0 > 0.0:
				_dist = clampf(_dist + (_pinch0 - d) * 0.02, 3.5, 24.0)
			_pinch0 = d
		else:
			_yaw -= sd.relative.x * 0.006
			_pitch = clampf(_pitch + sd.relative.y * 0.004, -0.2, 0.9)
		moved = true
	if moved:
		get_viewport().set_input_as_handled()

func _take_camera() -> void:
	if not _orbit:
		_orbit = true
		var d := _cam.position - PIVOT
		_dist = clampf(d.length(), 3.5, 24.0)
		_yaw = atan2(d.x, d.z)
		_pitch = clampf(asin(d.y / maxf(d.length(), 0.01)), -0.2, 0.9)
