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
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.far = 300.0
	add_child(_cam)
	_cam.make_current()

func _process(delta: float) -> void:
	_t += delta
	if _cam == null:
		return
	_cam.fov = 60.0
	_cam.position = Vector3(13.6 + sin(_t * 0.2) * 0.3, 1.2, 10.4)
	_cam.look_at(Vector3(15.6 + sin(_t * 0.2) * 0.3, 4.2, 0.0), Vector3.UP)
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
