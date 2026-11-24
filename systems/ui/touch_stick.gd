class_name TouchStick
extends Control
## Joystick táctil analógico. Aparece donde se apoya el dedo dentro de su zona (mitad izquierda / derecha de la pantalla)
## y devuelve un vector -1..1 proporcional a cuánto se estira: el movimiento usa la inclinación para la velocidad
## (sin botón de correr) y el apuntado usa la dirección. persist = true: al soltar, value queda en la última dirección
## (el apuntado no vuelve al centro).

signal released

@export var persist := false
@export var base_radius := 90.0
@export var tint := Color(0.4, 0.75, 1.0)
var value := Vector2.ZERO          ## -1..1 (y hacia abajo en pantalla)
var active := false
var _touch := -1
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
var _rest := Vector2.ZERO
var key := ""                          ## nombre en la disposición personalizada (stick_l / stick_r)
var rest_frac := Vector2(0.5, 0.62)    ## posición de reposo del dibujo dentro de la zona (fracción)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rest = size * rest_frac

func set_rest_frac(f: Vector2) -> void:
	rest_frac = f
	_rest = size * f
	queue_redraw()

func radius() -> float:
	return base_radius * Settings.joystick_size * float(Settings.ctl_scale.get(key, 1.0))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rest = size * rest_frac

## Lo llama el HUD con los eventos táctiles (posición en coordenadas del HUD). Devuelve true si lo tomó.
func touch_event(index: int, pos: Vector2, pressed: bool, is_drag: bool) -> bool:
	var local := pos - global_position
	if pressed and not is_drag and _touch < 0 and Rect2(Vector2.ZERO, size).has_point(local):
		_touch = index
		active = true
		_center = local
		_update(local)
		return true
	if index != _touch:
		return false
	if is_drag:
		_update(local)
	elif not pressed:
		_touch = -1
		active = false
		if not persist:
			value = Vector2.ZERO
		_knob = Vector2.ZERO
		released.emit()
		queue_redraw()
	return true

func _update(local: Vector2) -> void:
	var d := local - _center
	var r := radius()
	if d.length() > r:
		# el centro acompaña al dedo si se pasa del borde (no hay que volver para corregir)
		_center = local - d.normalized() * r
		d = local - _center
	_knob = d
	value = d / r
	queue_redraw()

func _draw() -> void:
	var r := radius()
	var c := _center if active else _rest
	draw_circle(c, r, Color(0.05, 0.08, 0.1, 0.35))
	draw_arc(c, r, 0, TAU, 48, Color(tint.r, tint.g, tint.b, 0.55), 2.0, true)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(tint.r, tint.g, tint.b, 0.18), 1.0, true)
	var k := c + (_knob if active else (value * r * 0.6 if persist else Vector2.ZERO))
	draw_circle(k, r * 0.36, Color(tint.r, tint.g, tint.b, 0.85 if active else 0.45))
	if persist and value.length() > 0.1:
		draw_line(c, c + value.normalized() * r * 1.15, Color(tint.r, tint.g, tint.b, 0.6), 3.0, true)
