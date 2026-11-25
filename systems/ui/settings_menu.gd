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
	theme = UiTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = UiTheme.BG
	add_theme_stylebox_override("panel", bgs)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	# --- barra superior
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	outer.add_child(top)
	var bar := ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(6, 44)
	top.add_child(bar)
	var title := Label.new()
	title.text = "CONFIGURACIÓN"
	title.add_theme_font_size_override("font_size", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_preset_lbl = Label.new()
	_preset_lbl.add_theme_color_override("font_color", UiTheme.MUTED)
	top.add_child(_preset_lbl)
	top.add_child(_btn("✕  Cerrar", func(): closed.emit()))
	# --- cuerpo: navegación a la izquierda, contenido a la derecha
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	outer.add_child(body)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.custom_minimum_size = Vector2(230, 0)
	body.add_child(nav)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	var stack := Control.new()
	panel.add_child(stack)
	var pages := {}
	var nav_btns := {}
	var show_page := func(n: String):
		for k in pages:
			(pages[k] as Control).visible = k == n
			(nav_btns[k] as Button).button_pressed = k == n
	var add_page := func(icon_name: String) -> VBoxContainer:
		var sc := ScrollContainer.new()
		sc.set_anchors_preset(Control.PRESET_FULL_RECT)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		stack.add_child(sc)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 12)
		sc.add_child(v)
		pages[icon_name] = sc
		var nb := Button.new()
		nb.text = icon_name
		nb.toggle_mode = true
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.custom_minimum_size = Vector2(0, 62)
		nb.add_theme_font_size_override("font_size", 24)
		nb.pressed.connect(func(): show_page.call(icon_name))
		nav.add_child(nb)
		nav_btns[icon_name] = nb
		return v
	# ---- Gráficos
	var g: VBoxContainer = add_page.call("🖥  Gráficos")
	_head(g, "Calidad general")
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	g.add_child(pr)
	for i in 3:
		var lv := i
		pr.add_child(_btn(Settings.LEVELS[i].to_upper(), func():
			Settings.preset(lv)
			_refresh()))
	var note := Label.new()
	note.text = "La calidad sólo cambia la anatomía y el daño (rayos X, sangre y fragmentos). Resolución, sombras y luces son fijas: el estilo plano no las usa."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", UiTheme.MUTED)
	g.add_child(note)
	_head(g, "Imagen")
	_option(g, "fps_target", "FPS objetivo", ["30", "60"], [30, 60])
	_check(g, "fog_war", "Velos de sectores (niebla de exploración)")
	# ---- Efectos
	var e: VBoxContainer = add_page.call("💥  Efectos")
	_head(e, "Partículas")
	_option(e, "particles", "Chispas, polvo y sangre", Settings.LEVELS)
	_head(e, "Daño y cámara lenta")
	_option(e, "xray", "Rayos X en cámara lenta", ["Apagado", "Sólo huesos", "Huesos, órganos y vasos"])
	_option(e, "xray_hits", "Cuándo se ven los rayos X", ["Sólo al morir", "En cada impacto grave y al morir"])
	_option(e, "bullet_time", "Cámara lenta (bullet time)", ["Nunca", "Tiros decisivos", "Siempre que hiere"])
	_slider(e, "camera_shake", "Vibración de cámara", 0.0, 1.0, 0.1, true)
	_head(e, "Láser")
	_check(e, "laser", "Láser del arma (jugador)")
	_check(e, "laser_enemies", "Láser de los enemigos")
	# ---- Cámara y juego
	var j: VBoxContainer = add_page.call("🎥  Cámara")
	_head(j, "Encuadre")
	_slider(j, "camera_distance", "Distancia de la cámara (menos = más cerca)", 6.0, 14.0, 0.5, false)
	_slider(j, "cam_height", "Altura", 0.0, 4.0, 0.1, false)
	_slider(j, "cam_offset_x", "Desplazamiento horizontal", -3.0, 3.0, 0.1, false)
	_slider(j, "cam_offset_y", "Desplazamiento vertical", -2.0, 2.0, 0.1, false)
	_slider(j, "cam_follow", "Velocidad de seguimiento", 1.0, 12.0, 0.5, false)
	_slider(j, "cam_fov", "Zoom (campo visual, grados)", 25.0, 60.0, 1.0, false)
	_slider(j, "cam_aim_lead", "Adelanto hacia donde apuntás", 0.0, 4.0, 0.1, false)
	j.add_child(_btn("↺  Restablecer cámara y apuntado", func():
		Settings.reset_camera_aim()
		_refresh()))
	_check(j, "haptics", "Vibración del teléfono al recibir daño")
	_check(j, "show_fps", "Mostrar FPS y llamadas de dibujo")
	# ---- Audio
	var a: VBoxContainer = add_page.call("🔊  Audio")
	_head(a, "Volumen")
	_slider(a, "vol_master", "General", 0.0, 1.0, 0.05, true)
	_slider(a, "vol_sfx", "Efectos (disparos, golpes)", 0.0, 1.0, 0.05, true)
	_slider(a, "vol_ambient", "Ambiente (viento, lluvia, generador)", 0.0, 1.0, 0.05, true)
	# ---- Controles
	var c: VBoxContainer = add_page.call("🎮  Controles")
	_head(c, "Disposición táctil")
	var ed := _btn("✥  EDITAR DISPOSICIÓN: mover y agrandar botones", func(): _open_editor())
	ed.custom_minimum_size = Vector2(0, 64)
	ed.add_theme_color_override("font_color", UiTheme.ACCENT)
	c.add_child(ed)
	_check(c, "ctl_mirror", "Modo zurdo (espejar los controles)")
	_slider(c, "joystick_size", "Tamaño general de joysticks y botones", 0.7, 1.6, 0.05, false)
	_slider(c, "ctl_opacity", "Transparencia de los controles", 0.2, 1.0, 0.05, true)
	_head(c, "Apuntado")
	_slider(c, "aim_sens_h", "Sensibilidad horizontal", 0.2, 1.5, 0.05, false)
	_slider(c, "aim_sens_v", "Sensibilidad vertical", 0.2, 1.5, 0.05, false)
	_slider(c, "aim_deadzone", "Zona muerta del joystick", 0.05, 0.5, 0.01, false)
	_slider(c, "aim_curve", "Respuesta (más = más fino cerca del centro)", 1.0, 3.0, 0.1, false)
	_slider(c, "aim_max_speed", "Velocidad máxima de giro (°/s)", 60.0, 360.0, 10.0, false)
	_slider(c, "aim_smooth", "Suavizado del apuntado", 0.0, 0.8, 0.05, false)
	_check(c, "auto_fire_stick", "Disparar al llevar el joystick derecho al borde")
	_head(c, "Teclado y mouse")
	var kb := Label.new()
	kb.text = "A / D mover · Shift correr · Ctrl sigilo · W / S escaleras · Espacio saltar · Mouse apuntar · Clic disparar\nR recargar · G granada · F golpe · E usar · Q cambiar arma · 1-4 armas · C agacharse · H curar · Tab inventario · Esc pausa"
	kb.add_theme_color_override("font_color", UiTheme.MUTED)
	kb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(kb)
	# ---- Rendimiento
	var r: VBoxContainer = add_page.call("📈  Rendimiento")
	_head(r, "Captador de rendimiento")
	var info := Label.new()
	info.text = "El captador recorre la torre y hace DESAPARECER una cosa por vez (luces, sombras, decorado, fondo, cajas, personajes, partículas…) y después los objetos más pesados, midiendo cuánto se gana con cada uno. Al final muestra qué pesa más y lo guarda en informe_rendimiento.txt."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", UiTheme.MUTED)
	r.add_child(info)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 10)
	r.add_child(rb)
	rb.add_child(_btn("▶  ANALIZAR RENDIMIENTO", func(): probe_requested.emit()))
	rb.add_child(_btn("Copiar informe", func():
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			DisplayServer.clipboard_set(_report.text)))
	_probe_status = Label.new()
	r.add_child(_probe_status)
	_report = TextEdit.new()
	_report.editable = false
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.custom_minimum_size = Vector2(0, 300)
	_report.add_theme_font_size_override("font_size", 15)
	r.add_child(_report)
	if FileAccess.file_exists("user://informe_rendimiento.txt"):
		_report.text = FileAccess.get_file_as_string("user://informe_rendimiento.txt")
	show_page.call("🖥  Gráficos")
	_refresh()

func _head(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	parent.add_child(l)
	var sep := HSeparator.new()
	parent.add_child(sep)

func _open_editor() -> void:
	var ce := ControlsEditor.new()
	get_parent().add_child(ce)
	ce.closed.connect(func():
		ce.queue_free()
		_refresh())

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
	b.custom_minimum_size = Vector2(150, 54)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(func():
		Sfx.play_ui("ui_click", -6.0)
		cb.call())
	return b

func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.text = label
	l.custom_minimum_size = Vector2(380, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 20)
	h.add_child(l)
	parent.add_child(h)
	return h

func _option(parent: Control, key: String, label: String, items: Array, values := []) -> void:
	var h := _row(parent, label)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(300, 54)
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
	s.custom_minimum_size = Vector2(300, 48)
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
	_preset_lbl.text = "Calidad: " + Settings.PRESETS[Settings.quality_preset]
