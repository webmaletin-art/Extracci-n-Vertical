class_name MenuScene
extends Node3D
## Escena de la portada (toma en cámara lenta, todo en línea): un tirador apunta, el letrero «EXTRACCIÓN EXTREME VERTICAL»
## detrás, y las municiones viajando: una entera que se acerca, una perforante, una deformada en «hongo» que ya atravesó el
## cuerpo con sus esquirlas, y un casquillo girando. Modelado en Blender (tools/menu_scene/make_scene.py) y horneado en línea.
## Se puede girar y acercar (ver MenuTower). Los movimientos son lentísimos y en bucle: «foto» pausada.

const SHOOTER_X := -3.4
const TARGET_X := 1.6
const AIM_Y := 1.32

var _ammo: Node3D
var _letrero: Node3D
var _moving: Array = []           ## [{node, from, to, spin, t, dur}]
var _t := 0.0
var _trail_nodes: Array = []          ## [bala, estela, posición inicial]: la estela acompaña a su bala

func _ready() -> void:
	_letrero = _load("menu_letrero")
	if _letrero:
		_letrero.position = Vector3(-0.2, 0.75, -3.0)
		_letrero.scale = Vector3.ONE * 0.62
		add_child(_letrero)
	_ammo = _load("menu_municion")
	_actors()
	_bullets()
	_floor()

func _load(id: String) -> Node3D:
	var p := LinedBake.lined_path("props", id)
	if p == "":
		return null
	return (load(p) as PackedScene).instantiate() as Node3D

func _actors() -> void:
	var sh := _actor("alfa", Vector3(SHOOTER_X, 0.0, 0.0), 1.0, true)
	sh.give_weapon("primary", "m4a1")
	sh.equip("primary")
	sh.aim_dir = Vector2(1, 0.0)
	sh.inp.aim_snap = true
	sh.inp.aim = Vector2(1, 0.0)
	var en := _actor("vigia", Vector3(TARGET_X, 0.0, 0.0), -1.0, false)
	en.menu_pose = true
	en.give_weapon("primary", "ak47")
	en.equip("primary")

func _actor(cid: String, pos: Vector3, facing_: float, shooter: bool) -> Actor:
	var a := Actor.new()
	a.character_id = cid
	a.team = 0 if shooter else 1
	a.laser_enabled = false
	add_child(a)
	a.position = pos
	a.facing = facing_
	a.aim_dir = Vector2(facing_, 0.0)
	return a

## Una pieza de la escena de municiones (copia suelta) puesta en un lugar, con su estela y anillos de velocidad.
func _piece(node_name: String, pos: Vector3, trail := true, scale_k := 1.0, rot := Vector3.ZERO) -> Node3D:
	if _ammo == null:
		return null
	var src := _ammo.get_node_or_null(node_name) as Node3D
	if src == null:
		return null
	var n := src.duplicate() as Node3D
	n.position = pos
	n.scale = Vector3.ONE * scale_k
	n.rotation_degrees = rot
	add_child(n)
	if trail:
		for extra in ["Estela", "AnillosVelocidad"]:
			var e := _ammo.get_node_or_null(extra) as Node3D
			if e:
				var d := e.duplicate() as Node3D
				d.position = pos
				d.rotation_degrees = rot
				d.scale = Vector3(scale_k, scale_k * (0.32 if extra == "Estela" else 1.0), scale_k)
				add_child(d)
				_trail_nodes.append([n, d, pos])
	return n

func _bullets() -> void:
	var fwd := Vector3(0, 0, -90)             # las piezas se modelan con la punta hacia arriba: se giran para apuntar a +X
	var k := 1.5                              # municiones sobredimensionadas para que se lean (como en un afiche)
	# 1) bala entera que se acerca al pecho (con estela y anillos de velocidad)
	var a := _piece("Bala", Vector3(-0.9, AIM_Y + 0.1, 0.9), true, k, fwd)
	# 2) perforante, más atrás y más alta
	var b := _piece("BalaPerforante", Vector3(-2.3, AIM_Y + 0.7, 0.2), true, k, fwd)
	# 3) bala deformada en «hongo» que ya salió por la espalda, con esquirlas y el anillo de la salida
	var c := _piece("BalaHongo", Vector3(TARGET_X + 1.5, AIM_Y - 0.05, 0.7), false, k, fwd)
	var fr := _piece("Fragmentos", Vector3(TARGET_X + 0.8, AIM_Y + 0.25, 0.5), false, 2.2)
	var rin := _piece("AnilloImpacto", Vector3(TARGET_X + 0.5, AIM_Y, 0.0), false, 1.5, Vector3(0, 90, 0))
	var rin2 := _piece("AnilloImpacto", Vector3(TARGET_X - 0.45, AIM_Y, 0.0), false, 1.1, Vector3(0, 90, 0))
	# 4) fogonazo en la boca del arma y casquillo que sale girando
	var fl := _piece("Fogonazo", Vector3(SHOOTER_X + 1.0, AIM_Y + 0.02, 0.0), false, 1.1)
	var cs := _piece("Casquillo", Vector3(SHOOTER_X + 0.35, AIM_Y + 0.6, 0.4), false, 1.6, Vector3(0, 0, 60))
	# movimiento en cámara lenta (bucle): las balas avanzan un poco y vuelven
	for it in [[a, 0.5], [b, 0.45], [c, 0.35], [fr, 0.3], [rin, 0.08], [rin2, 0.05], [fl, 0.04]]:
		if it[0]:
			_moving.append({"node": it[0], "from": (it[0] as Node3D).position, "to": (it[0] as Node3D).position + Vector3(float(it[1]), 0, 0), "spin": 0.0, "t": 0.0, "dur": 8.0})
	if cs:
		_moving.append({"node": cs, "from": cs.position, "to": cs.position + Vector3(-0.3, 0.3, 0.4), "spin": 16.0, "t": 0.0, "dur": 8.0})

func _floor() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30.0, 0.4, 9.0)
	cs.shape = bs
	body.position = Vector3(-1.0, -0.2, -0.8)
	body.add_child(cs)
	add_child(body)
	var f := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(24.0, 0.2, 7.0)
	f.mesh = bm
	f.position = Vector3(-1.0, -0.1, -0.8)
	add_child(f)
	LinedBake.style_tree(f)

func _process(delta: float) -> void:
	_t += delta
	for m in _moving:
		var n := m.node as Node3D
		if n == null or not is_instance_valid(n):
			continue
		m.t += delta
		var k := 0.5 - 0.5 * cos(TAU * float(m.t) / float(m.dur))           # ida y vuelta suave
		n.position = (m.from as Vector3).lerp(m.to, k)
		if float(m.spin) != 0.0:
			n.rotate_z(delta * deg_to_rad(float(m.spin)))
	for tr in _trail_nodes:
		if is_instance_valid(tr[0]) and is_instance_valid(tr[1]):
			(tr[1] as Node3D).position = (tr[0] as Node3D).position - Vector3(0.45, 0, 0) * (1.0 if (tr[1] as Node3D).name.begins_with("Estela") else 0.0)
