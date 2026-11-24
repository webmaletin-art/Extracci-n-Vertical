class_name ControlsEditor
extends Control
## Editor de la disposición táctil: se arrastra cada botón o joystick adonde se quiera, se elige su tamaño y la
## transparencia general. Lo guardado vive en Settings (ctl_pos / ctl_scale / ctl_opacity / ctl_mirror).
## Funciona con dedo y con mouse.

signal closed

const NAMES := {"stick_l": "Joystick de movimiento", "stick_r": "Joystick de apuntar", "fire": "Disparar", "jump": "Saltar / trepar",
	"melee": "Golpe / cuchillo", "grenade": "Granada", "crouch": "Agacharse", "use": "Usar", "reload": "Recargar", "swap": "Cambiar arma",
	"pause": "Pausa", "inventory": "Inventario", "heal": "Curar"}
const LABELS := {"fire": "◎", "jump": "⤒", "melee": "✊", "grenade": "●", "use": "USAR", "reload": "R", "swap": "⇄", "crouch": "▼",
	"pause": "II", "heal": "✚", "inventory": "▤", "stick_l": "MOVER", "stick_r": "APUNTAR"}
const RADIUS := {"fire": 64.0, "jump": 46.0, "melee": 42.0, "grenade": 34.0, "use": 44.0, "reload": 28.0, "swap": 30.0, "crouch": 30.0,
	"pause": 26.0, "heal": 32.0, "inventory": 26.0, "stick_l": 90.0, "stick_r": 90.0}
const TINT := {"stick_l": Color(0.45, 0.8, 1.0), "stick_r": Color(1.0, 0.75, 0.3), "fire": Color(1.0, 0.35, 0.25), "jump": Color(0.5, 0.85, 1.0),
	"grenade": Color(0.7, 0.9, 0.4), "use": Color(1.0, 0.85, 0.3), "heal": Color(0.4, 1.0, 0.5)}

var _sel := "fire"
var _drag := false
var _size_slider: HSlider
var _name_lbl: Label

func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.position = Vector2(0, 8)
	add_child(bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bar.add_child(v)
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 22)
	_name_lbl.add_theme_color_override("font_color", UiTheme.ACCENT)
	v.add_child(_name_lbl)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var l := Label.new()
	l.text = "Tamaño"
	h.add_child(l)
	_size_slider = HSlider.new()
	_size_slider.min_value = 0.5
	_size_slider.max_value = 2.0
	_size_slider.step = 0.05
	_size_slider.custom_minimum_size = Vector2(260, 40)
	_size_slider.value_changed.connect(func(x: float):
		Settings.ctl_scale[_sel] = x
		queue_redraw())
	h.add_child(_size_slider)
	var l2 := Label.new()
	l2.text = "Transparencia"
	h.add_child(l2)
	var op := HSlider.new()
	op.min_value = 0.2
	op.max_value = 1.0
	op.step = 0.05
	op.value = Settings.ctl_opacity
	op.custom_minimum_size = Vector2(180, 40)
	op.value_changed.connect(func(x: float):
		Settings.ctl_opacity = x
		queue_redraw())
	h.add_child(op)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	v.add_child(h2)
	var mir := CheckBox.new()
	mir.text = "Modo zurdo (espejar)"
	mir.button_pressed = Settings.ctl_mirror
	mir.toggled.connect(func(on: bool):
		Settings.ctl_mirror = on
		queue_redraw())
	h2.add_child(mir)
	var reset := Button.new()
	reset.text = "Restablecer"
	reset.pressed.connect(func():
		Settings.ctl_pos = {}
		Settings.ctl_scale = {}
		Settings.ctl_opacity = 0.9
		Settings.ctl_mirror = false
		mir.set_pressed_no_signal(false)
		op.value = 0.9
		_select(_sel)
		queue_redraw())
	h2.add_child(reset)
	var done := Button.new()
	done.text = "✔ Listo"
	done.pressed.connect(func():
		Settings.save_settings()
		Settings.changed.emit()
		closed.emit())
	h2.add_child(done)
	_select("fire")
	bar.set_anchors_and_offsets_preset.call_deferred(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)

func _select(n: String) -> void:
	_sel = n
	_name_lbl.text = "%s · arrastrá los controles para moverlos" % NAMES[n]
	_size_slider.set_value_no_signal(float(Settings.ctl_scale.get(n, 1.0)))
	queue_redraw()

func _frac(n: String) -> Vector2:
	var p: Vector2 = Settings.ctl_pos.get(n, Hud.DEFAULT_POS[n])
	return Vector2(1.0 - p.x, p.y) if Settings.ctl_mirror else p

func _radius(n: String) -> float:
	return float(RADIUS[n]) * Settings.joystick_size * float(Settings.ctl_scale.get(n, 1.0))

func _draw() -> void:
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.02, 0.03, 0.04, 0.97))
	# guías: mitades de pantalla
	draw_line(Vector2(s.x * 0.5, 0), Vector2(s.x * 0.5, s.y), Color(1, 1, 1, 0.06), 2.0)
	var f := get_theme_default_font()
	for n in NAMES:
		var c := _frac(n) * s
		var r := _radius(n)
		var col: Color = TINT.get(n, Color(0.9, 0.9, 0.9))
		var sel: bool = (n == _sel)
		draw_circle(c, r, Color(col.r, col.g, col.b, 0.28 if sel else 0.14))
		draw_arc(c, r, 0, TAU, 48, Color(col.r, col.g, col.b, 1.0 if sel else 0.65), 4.0 if sel else 2.0, true)
		var lab: String = LABELS[n]
		var fs := int(maxf(r * (0.5 if lab.length() <= 2 else 0.3), 14.0))
		var ts := f.get_string_size(lab, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, c - Vector2(ts.x * 0.5, -fs * 0.35), lab, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95))

func _pick(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for n in NAMES:
		var d := (_frac(n) * size).distance_to(p)
		if d <= _radius(n) * 1.15 and d < bd:
			best = n
			bd = d
	return best

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var n := _pick(e.position)
			if n != "":
				_select(n)
				_drag = true
		else:
			_drag = false
	elif e is InputEventMouseMotion and _drag:
		var f: Vector2 = (e.position as Vector2) / size
		f = Vector2(clampf(f.x, 0.03, 0.97), clampf(f.y, 0.06, 0.96))
		Settings.ctl_pos[_sel] = Vector2(1.0 - f.x, f.y) if Settings.ctl_mirror else f
		queue_redraw()
