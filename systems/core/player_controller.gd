class_name PlayerController
extends Node
## Convierte los controles del jugador en ActorInput:
##  * Táctil: joystick izquierdo → move (la inclinación da la velocidad), joystick derecho → aim (persistente),
##    botones del HUD.
##  * Teclado y mouse (PC / pruebas): A/D mueven (caminar; Shift = correr al máximo; Ctrl = sigilo), W/S escaleras y
##    agacharse, el mouse apunta (la dirección queda fija si el mouse no se mueve), clic izquierdo dispara, G granada
##    (mantener = arco), F golpe / cuchillo, E usar, R recargar, Q cambiar arma, 1-4 armas, C agacharse, Esc pausa.
## Corre antes que el Actor en cada cuadro de física (prioridad -10).

var actor: Actor
var hud: Hud
var camera: Camera3D
var _mouse_moved := false
var _crouch_kb := false

static func setup_input_map() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT], "move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE], "interact": [KEY_E], "reload": [KEY_R], "melee": [KEY_F], "grenade": [KEY_G], "swap": [KEY_Q],
		"crouch": [KEY_C], "pause": [KEY_ESCAPE], "sprint": [KEY_SHIFT], "sneak": [KEY_CTRL], "slot_1": [KEY_1], "slot_2": [KEY_2],
		"slot_3": [KEY_3], "slot_4": [KEY_4], "perf_overlay": [KEY_F3], "heal": [KEY_H], "inventory": [KEY_TAB, KEY_I],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", mb)

func _ready() -> void:
	process_physics_priority = -10

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not hud.touch_mode:
		_mouse_moved = true

func _physics_process(_delta: float) -> void:
	if actor == null or actor.is_dead():
		return
	var inp := actor.inp
	var mv := Vector2.ZERO
	var aim := Vector2.ZERO
	# --- táctil
	if hud.touch_mode:
		mv = Vector2(hud.left_stick.value.x, -hud.left_stick.value.y)
		# vector crudo del joystick: la zona muerta, la curva y la sensibilidad las aplica el Actor (Settings)
		# sólo mientras el dedo está apoyado: al soltar, el joystick conserva su dibujo pero la mira NO se mueve más
		if hud.right_stick.active:
			aim = Vector2(hud.right_stick.value.x, -hud.right_stick.value.y)
	# --- teclado
	var kx := Input.get_axis("move_left", "move_right")
	if absf(kx) > 0.01:
		var tilt := 0.6
		if Input.is_action_pressed("sprint"):
			tilt = 1.0
		elif Input.is_action_pressed("sneak"):
			tilt = 0.25
		mv.x = kx * tilt
	var ky := Input.get_axis("move_down", "move_up")
	if absf(ky) > 0.01:
		mv.y = ky
	# --- mouse: dirección desde el pecho del personaje hasta el cursor (en pantalla → mundo)
	if not hud.touch_mode and _mouse_moved and camera:
		var chest := actor.global_position + Vector3(0, 1.4, 0)
		var sp := camera.unproject_position(chest)
		var d := get_viewport().get_mouse_position() - sp
		if d.length() > 12.0:
			aim = Vector2(d.x, -d.y).normalized()
		_mouse_moved = false
	inp.move = mv
	inp.aim_snap = not hud.touch_mode
	if aim != Vector2.ZERO:
		inp.aim = aim
	else:
		inp.aim = Vector2.ZERO
	inp.fire = hud.hold.fire or Input.is_action_pressed("fire") or (Settings.auto_fire_stick and hud.right_stick.active and hud.right_stick.value.length() > 0.95)
	inp.jump = inp.jump or hud.take_edge("jump") or Input.is_action_just_pressed("jump")
	inp.jump_held = hud.hold.jump or Input.is_action_pressed("jump")
	inp.melee = inp.melee or hud.take_edge("melee") or Input.is_action_just_pressed("melee")
	inp.interact = inp.interact or hud.take_edge("use") or Input.is_action_just_pressed("interact")
	inp.reload = inp.reload or hud.take_edge("reload") or Input.is_action_just_pressed("reload")
	inp.grenade = hud.hold.grenade or Input.is_action_pressed("grenade")
	if Input.is_action_just_pressed("crouch"):
		_crouch_kb = not _crouch_kb
	inp.crouch = hud.crouch_toggle or _crouch_kb
	if hud.take_edge("heal") or Input.is_action_just_pressed("heal"):
		actor.use_medical()
	if hud.take_edge("swap") or Input.is_action_just_pressed("swap"):
		inp.switch_to = "next"
	for i in 4:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			inp.switch_to = ["primary", "secondary", "knife", "fists"][i]
