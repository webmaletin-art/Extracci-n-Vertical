class_name SettingsMenu
extends PanelContainer
## CONFIGURACIÓN: calidad gráfica (presets BAJA / MEDIA / ALTA para teléfonos de gama baja), calidad de render,
## partículas, humo, explosiones, sombras, luces, decorado, fondo, FPS, rayos X y cámara lenta, audio y controles.
## Pestaña RENDIMIENTO: botón del captador (PerfProbe) que hace desaparecer objetos del mapa uno por uno para encontrar
## lo que pone lento el juego, y muestra el informe.

signal closed
signal probe_requested

var _rows := {}
var _report: TextEdit
var _preset_lbl: Label
var _probe_status: Label
var probe_available := true

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.07, 0.96)
	add_theme_stylebox_override("panel", sb)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := Label.new()
	title.text = "CONFIGURACIÓN"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := _btn("✕ Cerrar", func(): closed.emit())
	top.add_child(close)
	# presets
	var pr := HBoxContainer.new()
	root.add_child(pr)
	var pl := Label.new()
	pl.text = "Calidad gráfica:"
	pl.add_theme_font_size_override("font_size", 22)
	pr.add_child(pl)
	for i in 3:
		var lv := i
		pr.add_child(_btn(Settings.LEVELS[i].to_upper(), func():
			Settings.preset(lv)
			_refresh()))
	_preset_lbl = Label.new()
	_preset_lbl.add_theme_font_size_override("font_size", 20)
	pr.add_child(_preset_lbl)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 22)
	root.add_child(tabs)
	var g := _tab(tabs, "Gráficos")
	_slider(g, "render_scale", "Calidad de render (escala 3D)", 0.5, 1.0, 0.05, true)
	_option(g, "shadows", "Sombras", ["Sin sombras", "Sólo luna", "Luna y lámparas cercanas"])
	_option(g, "lights", "Luces dinámicas", ["Baja (sólo emisivas)", "Media (piso actual ±1)", "Alta (todas)"])
	_option(g, "msaa", "Antialiasing MSAA", ["No", "2x", "4x"])
	_check(g, "fxaa", "Antialiasing FXAA (barato)")
	_option(g, "decor", "Detalle del decorado", Settings.LEVELS)
	_option(g, "background", "Fondo lejano", ["Plano", "Fachadas", "Fachadas + niebla"])
	_option(g, "view_floors", "Pisos vecinos visibles", ["Sólo el actual", "±1 piso", "±2 pisos"])
	_option(g, "fps_target", "FPS objetivo", ["30", "60"], [30, 60])
	var e := _tab(tabs, "Efectos")
	_option(e, "particles", "Partículas (chispas, polvo, sangre)", Settings.LEVELS)
	_option(e, "smoke", "Humo", Settings.LEVELS)
	_option(e, "explosions", "Explosiones (fuego, onda, escombros)", Settings.LEVELS)
	_option(e, "xray", "Rayos X en cámara lenta", ["Apagado", "Sólo huesos", "Huesos, órganos y vasos"])
	_option(e, "bullet_time", "Cámara lenta (bullet time)", ["Nunca", "Tiros decisivos", "Siempre que hiere"])
	_slider(e, "camera_shake", "Vibración de cámara", 0.0, 1.0, 0.1, true)
	_check(e, "laser", "Láser del arma (jugador)")
	_check(e, "laser_enemies", "Láser de los enemigos")
	var a := _tab(tabs, "Audio")
	_slider(a, "vol_master", "Volumen general", 0.0, 1.0, 0.05, true)
	_slider(a, "vol_sfx", "Efectos", 0.0, 1.0, 0.05, true)
	_slider(a, "vol_ambient", "Ambiente", 0.0, 1.0, 0.05, true)
	var c := _tab(tabs, "Controles")
	_slider(c, "joystick_size", "Tamaño de los joysticks", 0.7, 1.4, 0.05, false)
	_slider(c, "aim_sensitivity", "Sensibilidad del apuntado", 0.5, 1.5, 0.05, false)
	_check(c, "auto_fire_stick", "Disparar al llevar el joystick derecho al borde")
	_check(c, "show_fps", "Mostrar FPS y llamadas de dibujo")
	var r := _tab(tabs, "Rendimiento")
	var info := Label.new()
	info.text = "El captador recorre la torre y hace DESAPARECER una cosa por vez (luces, sombras, decorado, fondo, cajas,\npersonajes, partículas…) y después los objetos más pesados, midiendo cuánto se gana con cada uno.\nAl final muestra qué pesa más, lo guarda en informe_rendimiento.txt y lo copia al portapapeles."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_child(info)
	var rb := HBoxContainer.new()
	r.add_child(rb)
	rb.add_child(_btn("▶ ANALIZAR RENDIMIENTO", func(): probe_requested.emit()))
	rb.add_child(_btn("Copiar informe", func():
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			DisplayServer.clipboard_set(_report.text)))
	_probe_status = Label.new()
	r.add_child(_probe_status)
	_report = TextEdit.new()
	_report.editable = false
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.custom_minimum_size = Vector2(0, 260)
	_report.add_theme_font_size_override("font_size", 15)
	r.add_child(_report)
	if FileAccess.file_exists("user://informe_rendimiento.txt"):
		_report.text = FileAccess.get_file_as_string("user://informe_rendimiento.txt")
	_refresh()

func set_probe_status(t: String) -> void:
	_probe_status.text = t

func set_report(t: String) -> void:
	_report.text = t

func _tab(tabs: TabContainer, name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	sc.add_child(v)
	return v

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(130, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func():
		Sfx.play_ui("ui_click", -6.0)
		cb.call())
	return b

func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(420, 0)
	l.add_theme_font_size_override("font_size", 20)
	h.add_child(l)
	parent.add_child(h)
	return h

func _option(parent: Control, key: String, label: String, items: Array, values := []) -> void:
	var h := _row(parent, label)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(320, 46)
	ob.add_theme_font_size_override("font_size", 20)
	for it in items:
		ob.add_item(str(it))
	ob.item_selected.connect(func(i: int):
		Settings.set_value(key, values[i] if not values.is_empty() else i)
		_refresh())
	h.add_child(ob)
	_rows[key] = [ob, values]

func _slider(parent: Control, key: String, label: String, mn: float, mx: float, st: float, pct: bool) -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = st
	s.custom_minimum_size = Vector2(320, 40)
	var v := Label.new()
	v.custom_minimum_size = Vector2(80, 0)
	s.value_changed.connect(func(x: float):
		v.text = ("%d%%" % int(round(x * 100.0))) if pct else "%.2f" % x
		if not is_equal_approx(float(Settings.get(key)), x):
			Settings.set_value(key, x)
			_refresh_preset())
	h.add_child(s)
	h.add_child(v)
	_rows[key] = [s, []]

func _check(parent: Control, key: String, label: String) -> void:
	var h := _row(parent, label)
	var cb := CheckBox.new()
	cb.toggled.connect(func(on: bool):
		Settings.set_value(key, on)
		_refresh_preset())
	h.add_child(cb)
	_rows[key] = [cb, []]

func _refresh() -> void:
	for key in _rows:
		var ctl = _rows[key][0]
		var values: Array = _rows[key][1]
		var v = Settings.get(key)
		if ctl is OptionButton:
			var idx: int = values.find(v) if not values.is_empty() else int(v)
			(ctl as OptionButton).select(clampi(idx, 0, (ctl as OptionButton).item_count - 1))
		elif ctl is HSlider:
			(ctl as HSlider).set_value_no_signal(float(v))
			((ctl as HSlider).get_parent().get_child(2) as Label).text = "%d%%" % int(round(float(v) * 100.0)) if float((ctl as HSlider).max_value) <= 1.0 else "%.2f" % float(v)
		elif ctl is CheckBox:
			(ctl as CheckBox).set_pressed_no_signal(bool(v))
	_refresh_preset()

func _refresh_preset() -> void:
	_preset_lbl.text = "   Actual: " + Settings.PRESETS[Settings.quality_preset]
