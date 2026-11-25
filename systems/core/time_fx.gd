extends Node
## Tiempo del juego (autoload «TimeFx»): cámara lenta, micro-pausas al golpear y pedidos de vibración de cámara.
## Usa tiempo real para medir duraciones, así funciona aunque Engine.time_scale esté muy bajo.

signal shake_requested(amount: float)
signal slowmo_changed(active: bool)

var _slow_until := 0.0
var _slow_scale := 1.0
var _slow_in := 0.0
var _slow_start := 0.0
var _stop_until := 0.0
var active := false              ## hay cámara lenta en curso
var owner_tag := ""              ## quién la pidió («bullet_time», «explosion»…)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

var fixed_fps := 0.0             ## > 0: el reloj cuenta cuadros (grabación de escenas a 30 fps fijos) y no segundos reales

func now() -> float:
	if fixed_fps > 0.0:
		return float(Engine.get_frames_drawn()) / fixed_fps
	return Time.get_ticks_usec() / 1e6

## Cámara lenta durante `real_seconds` reales, entrando en `ease_in` s. Si ya hay una más lenta en curso, gana la más lenta.
func slowmo(scale: float, real_seconds: float, tag := "", ease_in := 0.08) -> void:
	var t := now()
	if active and scale > _slow_scale and t < _slow_until:
		return
	_slow_scale = clampf(scale, 0.02, 1.0)
	_slow_start = t
	_slow_in = ease_in
	_slow_until = t + real_seconds
	owner_tag = tag
	if not active:
		active = true
		slowmo_changed.emit(true)

func end_slowmo() -> void:
	_slow_until = 0.0

## Pausa cortísima al conectar un golpe fuerte (da peso al impacto). En tiempo real.
func hitstop(real_seconds := 0.05) -> void:
	_stop_until = maxf(_stop_until, now() + real_seconds)

func shake(amount: float) -> void:
	if Settings.camera_shake > 0.0:
		shake_requested.emit(amount * Settings.camera_shake)

func _process(_delta: float) -> void:
	var t := now()
	var target := 1.0
	if t < _slow_until:
		var k := clampf((t - _slow_start) / maxf(_slow_in, 0.001), 0.0, 1.0)
		target = lerpf(1.0, _slow_scale, k)
	elif active:
		active = false
		owner_tag = ""
		slowmo_changed.emit(false)
	if t < _stop_until:
		target = minf(target, 0.05)
	if active or t < _stop_until:
		Engine.time_scale = target
	else:
		# salida suave de la cámara lenta
		Engine.time_scale = move_toward(Engine.time_scale, 1.0, _delta_real() * 4.0)

var _last_real := 0.0
func _delta_real() -> float:
	var t := now()
	var d := clampf(t - _last_real, 0.0, 0.1) if _last_real > 0.0 else 0.016
	_last_real = t
	return d
