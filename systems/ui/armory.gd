class_name Armory
extends Control
## ARMERÍA: catálogo de armas con el operador sosteniéndolas (cámara libre: girar, acercar, alejar), cartel con los datos del arma
## y, abajo, la munición que usa parada en 3D (estándar, trazante, punta hueca, perforante, incendiaria y punta de flor) con su precio
## y el botón de comprar. La munición sólo se puede comprar si ya se tiene el arma. Todo en blanco con líneas, como el juego.

signal closed

const CLASSES := [["pistol", "PISTOLAS"], ["smg", "SUBFUSILES"], ["rifle", "FUSILES"], ["shotgun", "ESCOPETAS"], ["dmr", "TIRADORES"], ["sniper", "FRANCOTIRADORES"]]
const INK := Color(0.07, 0.07, 0.09)
const PAPER := Color(0.97, 0.97, 0.96)
const MUTED := Color(0.42, 0.42, 0.45)

var cls := "pistol"
var sel := ""
var _list: VBoxContainer
var _tabs := {}
var _card: VBoxContainer
var _title: Label
var _sub: Label
var _credits: Label
var _bars: VBoxContainer
var _btn_buy: Button
var _btn_equip: Button
var _ammo_cols := {}
var _ammo_note: Label
# escenario 3D del operador
var _stage: SubViewport
var _cam: Camera3D
var _op: Actor
var _yaw := 35.0
var _pitch := 6.0
var _dist := 3.3
var _target := Vector3(0, 1.2, 0)
var _drag := false
var _touches := {}
var _pinch0 := 0.0
# vitrina de munición
var _avp: SubViewport
var _acam: Camera3D
var _aroot: Node3D
var _ammo_view: SubViewportContainer

func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	var first := _weapons_of(cls)
	_select(first[0] if first.size() > 0 else "m1911")
	Profile.changed.connect(_refresh)

# ------------------------------------------------------------------------------------------------ datos

func _weapons_of(c: String) -> Array:
	var out := []
	for k in Firearm.all_stats():
		if str(Firearm.all_stats()[k].get("class", "")) == c:
			out.append(k)
	out.sort_custom(func(a, b): return int(Firearm.all_stats()[a].price) < int(Firearm.all_stats()[b].price))
	return out

static func _maxes() -> Dictionary:
	var m := {"dmg": 1.0, "rpm": 1.0, "dps": 1.0, "range": 1.0, "mag": 1.0, "reload": 1.0, "recoil": 1.0, "spread": 1.0}
	for k in Firearm.all_stats():
		var s: Dictionary = Firearm.all_stats()[k]
		m.dmg = maxf(m.dmg, float(s.damage) * (float(s.pellets) if int(s.pellets) > 1 else 1.0))
		m.rpm = maxf(m.rpm, float(s.rpm))
		m.dps = maxf(m.dps, float(s.damage) * float(s.pellets) * float(s.rpm) / 60.0)
		m.range = maxf(m.range, float(s.range))
		m.mag = maxf(m.mag, float(s.mag))
		m.reload = maxf(m.reload, float(s.reload))
		m.recoil = maxf(m.recoil, float(s.recoil))
		m.spread = maxf(m.spread, float(s.spread))
	return m

# ------------------------------------------------------------------------------------------------ interfaz

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# escenario del operador (centro)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.anchor_left = 0.0
	svc.offset_left = 330
	svc.offset_right = -370
	svc.offset_top = 58
	svc.offset_bottom = -262
	svc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(svc)
	_stage = SubViewport.new()
	_stage.own_world_3d = true
	_stage.transparent_bg = true
	_stage.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_stage)
	_build_stage()
	var cam_hint := Label.new()
	cam_hint.text = "Arrastrá para girar · rueda o pellizco para acercar"
	cam_hint.add_theme_font_size_override("font_size", 14)
	cam_hint.add_theme_color_override("font_color", MUTED)
	cam_hint.position = Vector2(344, 64)
	add_child(cam_hint)
	var cam_btns := HBoxContainer.new()
	cam_btns.position = Vector2(344, 600 - 232 + 50)
	cam_btns.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cam_btns.anchor_top = 1.0
	cam_btns.anchor_bottom = 1.0
	cam_btns.offset_left = 384
	cam_btns.offset_top = -304
	cam_btns.offset_bottom = -266
	cam_btns.add_theme_constant_override("separation", 8)
	add_child(cam_btns)
	for d in [["−", func(): _zoom(0.25)], ["+", func(): _zoom(-0.25)], ["VER EL ARMA", _focus_weapon], ["VER AL OPERADOR", _focus_body]]:
		var b := _small_btn(d[0], d[1])
		cam_btns.add_child(b)
	# columna izquierda: título, créditos, clases y lista
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 14
	left.offset_right = 320
	left.offset_top = 14
	left.offset_bottom = -14
	left.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.95), 14, INK, 2))
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	var t := Label.new()
	t.text = "ARMERÍA"
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", INK)
	lv.add_child(t)
	_credits = Label.new()
	_credits.add_theme_font_size_override("font_size", 20)
	_credits.add_theme_color_override("font_color", MUTED)
	lv.add_child(_credits)
	var tabs := GridContainer.new()
	tabs.columns = 2
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	lv.add_child(tabs)
	for c in CLASSES:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(140, 40)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func(): _set_class(str(c[0])))
		tabs.add_child(b)
		_tabs[c[0]] = b
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	var back := Button.new()
	back.text = "VOLVER"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(func(): closed.emit())
	lv.add_child(back)
	# columna derecha: cartel con los datos
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -356
	right.offset_right = -14
	right.offset_top = 14
	right.offset_bottom = -262
	right.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.95), 14, INK, 2))
	add_child(right)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 6)
	right.add_child(_card)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(_title)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", MUTED)
	_card.add_child(_sub)
	_bars = VBoxContainer.new()
	_bars.add_theme_constant_override("separation", 3)
	_card.add_child(_bars)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.add_child(sp)
	_btn_buy = Button.new()
	_btn_buy.custom_minimum_size = Vector2(0, 42)
	_btn_buy.pressed.connect(func():
		if Profile.buy_weapon(sel):
			Sfx.play_ui("ui_confirm", -6.0))
	_card.add_child(_btn_buy)
	_btn_equip = Button.new()
	_btn_equip.custom_minimum_size = Vector2(0, 40)
	_btn_equip.pressed.connect(func(): Profile.equip(sel))
	_card.add_child(_btn_equip)
	# fondo: munición
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 334
	bottom.offset_right = -14
	bottom.offset_top = -254
	bottom.offset_bottom = -14
	bottom.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.95), 14, INK, 2))
	add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	bottom.add_child(bv)
	_ammo_note = Label.new()
	_ammo_note.add_theme_font_size_override("font_size", 15)
	_ammo_note.add_theme_color_override("font_color", MUTED)
	bv.add_child(_ammo_note)
	_ammo_view = SubViewportContainer.new()
	_ammo_view.stretch = true
	_ammo_view.custom_minimum_size = Vector2(0, 104)
	bv.add_child(_ammo_view)
	_avp = SubViewport.new()
	_avp.own_world_3d = true
	_avp.transparent_bg = true
	_avp.msaa_3d = Viewport.MSAA_2X
	_ammo_view.add_child(_avp)
	_aroot = Node3D.new()
	_avp.add_child(_aroot)
	_acam = Camera3D.new()
	_acam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_acam.size = 1.5
	_avp.add_child(_acam)
	_acam.global_position = Vector3(0, 0.5, 3)
	var env := WorldEnvironment.new()
	env.set_meta("no_tech", true)
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	env.environment = e
	_avp.add_child(env)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	bv.add_child(cols)
	for ty in Ammo.TYPE_ORDER:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		cols.add_child(col)
		var nm := Label.new()
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 15)
		nm.add_theme_color_override("font_color", INK)
		col.add_child(nm)
		var info := Label.new()
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", MUTED)
		col.add_child(info)
		var use := Button.new()
		use.toggle_mode = false
		use.custom_minimum_size = Vector2(0, 34)
		use.add_theme_font_size_override("font_size", 12)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		col.add_child(row)
		row.add_child(use)
		use.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(0, 34)
		buy.add_theme_font_size_override("font_size", 12)
		buy.clip_text = true
		use.clip_text = true
		buy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(buy)
		_tight(use)
		_tight(buy)
		_ammo_cols[ty] = {"name": nm, "info": info, "use": use, "buy": buy}
		use.pressed.connect(func():
			Profile.select_ammo(sel, str(ty)))
		buy.pressed.connect(func():
			if Profile.buy_ammo(sel, str(ty)):
				Sfx.play_ui("ui_confirm", -8.0))
	_ammo_view.resized.connect(_layout_ammo)

func _small_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(44 if text.length() < 3 else 150, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	return b

# ------------------------------------------------------------------------------------------------ escenario 3D

func _build_stage() -> void:
	var env := WorldEnvironment.new()
	env.set_meta("no_tech", true)
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	env.environment = e
	_stage.add_child(env)
	var floor_ := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(8, 0.4, 8)
	cs.shape = bx
	cs.position.y = -0.2
	floor_.add_child(cs)
	_stage.add_child(floor_)
	# plataforma blanca con su sombra (en el menú se permiten sombras: una mancha suave bajo el operador)
	var pod := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.05
	cm.bottom_radius = 1.1
	cm.height = 0.12
	cm.radial_segments = 40
	pod.mesh = cm
	pod.position.y = -0.06
	_stage.add_child(pod)
	var shadow := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.9, 1.9)
	shadow.mesh = qm
	shadow.rotation_degrees.x = -90
	shadow.position.y = 0.01
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.colors = PackedColorArray([Color(0, 0, 0, 0.32), Color(0, 0, 0, 0.0)])
	gt.gradient = gr
	sm.albedo_texture = gt
	shadow.material_override = sm
	shadow.set_meta("no_tech", true)
	_stage.add_child(shadow)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.05
	_stage.add_child(_cam)
	_op = Actor.new()
	_op.name = "Operador"
	_op.character_id = Settings.character_id
	_op.team = 0
	_op.laser_enabled = false
	_stage.add_child(_op)
	_op.global_position = Vector3(0, 0.05, 0)
	_op.facing = 1.0
	_op.aim_dir = Vector2(1, 0)
	_update_cam()

func _update_cam() -> void:
	if _cam == null:
		return
	var y := deg_to_rad(_yaw)
	var p := deg_to_rad(_pitch)
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _dist
	_cam.global_position = _target + off
	_cam.look_at(_target, Vector3.UP)

func _zoom(d: float) -> void:
	_dist = clampf(_dist + d, 0.7, 6.0)
	_update_cam()

func _focus_weapon() -> void:
	var w := _op.weapon() if _op else null
	_target = w.global_position if w else Vector3(0.4, 1.3, 0)
	_dist = 1.3
	_update_cam()

func _focus_body() -> void:
	_target = Vector3(0, 1.2, 0)
	_dist = 3.3
	_yaw = 35.0
	_pitch = 6.0
	_update_cam()

func _gui_input(ev: InputEvent) -> void:
	var local := get_local_mouse_position()
	var in_stage := Rect2(Vector2(330, 58), size - Vector2(700, 320)).has_point(local)
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed and in_stage
		elif in_stage and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-0.2)
		elif in_stage and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.2)
	elif ev is InputEventMouseMotion and _drag:
		var mm := ev as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.4
		_pitch = clampf(_pitch + mm.relative.y * 0.25, -20.0, 60.0)
		_update_cam()
	elif ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_pinch0 = 0.0
	elif ev is InputEventScreenDrag:
		var sd := ev as InputEventScreenDrag
		if not in_stage:
			return
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			var pts: Array = _touches.values()
			var d: float = (pts[0] as Vector2).distance_to(pts[1])
			if _pinch0 > 0.0:
				_zoom((_pinch0 - d) * 0.01)
			_pinch0 = d
		else:
			_yaw -= sd.relative.x * 0.4
			_pitch = clampf(_pitch + sd.relative.y * 0.25, -20.0, 60.0)
			_update_cam()

# ------------------------------------------------------------------------------------------------ selección

func _set_class(c: String) -> void:
	cls = c
	var ws := _weapons_of(c)
	if ws.size() > 0:
		_select(ws[0])

func _select(id: String) -> void:
	sel = id
	cls = str(Firearm.all_stats()[id].get("class", cls))
	# el operador sostiene el arma elegida
	if _op:
		for k in _op.weapons.keys():
			(_op.weapons[k] as Node).queue_free()
		_op.weapons.clear()
		var slot := Profile.slot_for(id)
		_op.give_weapon(slot, id)
		_op.equip(slot)
		_op.inp.aim_snap = true
		_op.inp.aim = Vector2(1, 0.0)
	_refresh()

func _refresh() -> void:
	if _list == null:
		return
	_credits.text = "Créditos: %s CR" % _fmt(Profile.credits)
	for c in _tabs:
		(_tabs[c] as Button).button_pressed = c == cls
	for ch in _list.get_children():
		ch.queue_free()
	for id in _weapons_of(cls):
		var s: Dictionary = Firearm.all_stats()[id]
		var b := Button.new()
		var tag := "EQUIPADA" if Profile.equipped.get(Profile.slot_for(id)) == id else ("TUYA" if Profile.has_weapon(id) else "%s CR" % _fmt(int(s.price)))
		b.text = "%s\n%s · %s" % [str(s.name), str(s.get("caliber", "")), tag]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 58)
		b.add_theme_font_size_override("font_size", 15)
		if id == sel:
			b.add_theme_stylebox_override("normal", UiTheme.box(INK, 10, INK, 2))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(func(): _select(id))
		_list.add_child(b)
	var s2: Dictionary = Firearm.all_stats()[sel]
	_title.text = str(s2.name)
	_sub.text = "%s · %s · nivel %d" % [str(s2.get("caliber", "")), _cls_name(str(s2.get("class", ""))), int(s2.tier)]
	for ch in _bars.get_children():
		ch.queue_free()
	var m := _maxes()
	var pel := int(s2.pellets)
	var dmg := float(s2.damage) * (float(pel) if pel > 1 else 1.0)
	var dps := float(s2.damage) * float(pel) * float(s2.rpm) / 60.0
	var rows := [
		["Daño", ("%d×%d" % [int(s2.damage), pel]) if pel > 1 else str(int(s2.damage)), dmg / float(m.dmg)],
		["Cadencia", "%d %s" % [int(s2.rpm), "auto" if bool(s2.auto) else "semi"], float(s2.rpm) / float(m.rpm)],
		["Poder (DPS)", str(int(dps)), dps / float(m.dps)],
		["Alcance", "%d m" % int(s2.range), float(s2.range) / float(m.range)],
		["Cargador", str(int(s2.mag)), float(s2.mag) / float(m.mag)],
		["Recarga", "%.1f s" % float(s2.reload), 1.0 - float(s2.reload) / float(m.reload) * 0.8],
		["Control", "%.1f°" % float(s2.recoil), 1.0 - float(s2.recoil) / float(m.recoil) * 0.9],
		["Precisión", "%.1f°" % float(s2.spread), 1.0 - float(s2.spread) / float(m.spread) * 0.9],
	]
	for r in rows:
		_bars.add_child(_bar_row(str(r[0]), str(r[1]), clampf(float(r[2]), 0.02, 1.0)))
	var owned := Profile.has_weapon(sel)
	_btn_buy.visible = not owned
	_btn_buy.text = "COMPRAR ARMA · %s CR" % _fmt(int(s2.price))
	_btn_buy.disabled = not Profile.can_buy_weapon(sel)
	_btn_equip.visible = owned
	var eq: bool = Profile.equipped.get(Profile.slot_for(sel)) == sel
	_btn_equip.text = ("EQUIPADA (%s)" % ("secundaria" if Profile.slot_for(sel) == "secondary" else "principal")) if eq else ("EQUIPAR COMO %s" % ("SECUNDARIA" if Profile.slot_for(sel) == "secondary" else "PRINCIPAL"))
	_btn_equip.disabled = eq
	_refresh_ammo()

func _bar_row(label: String, value: String, k: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", MUTED)
	l.custom_minimum_size = Vector2(112, 0)
	l.clip_text = true
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = k
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(40, 7)
	bar.add_theme_stylebox_override("background", UiTheme.box(Color(0.9, 0.9, 0.89), 3))
	bar.add_theme_stylebox_override("fill", UiTheme.box(INK, 3))
	h.add_child(bar)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", INK)
	val.custom_minimum_size = Vector2(70, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	return h

func _tight(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := b.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		if sb:
			sb.content_margin_left = 3
			sb.content_margin_right = 3
			b.add_theme_stylebox_override(st, sb)

func _cls_name(c: String) -> String:
	for x in CLASSES:
		if x[0] == c:
			return str(x[1]).capitalize()
	return c

static func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		out += s[i]
		if (s.length() - i - 1) % 3 == 0 and i < s.length() - 1:
			out += "."
	return out

# ------------------------------------------------------------------------------------------------ munición

func _refresh_ammo() -> void:
	var owned := Profile.has_weapon(sel)
	var cal := Ammo.caliber_key(sel)
	_ammo_note.text = ("MUNICIÓN · %s" % str(Ammo.data().calibers[cal].name)) + ("" if owned else "   —   Comprá el arma para poder comprar su munición")
	for t in Ammo.TYPE_ORDER:
		var c: Dictionary = _ammo_cols[t]
		var it := Ammo.item(sel, t)
		var m := Ammo.mods(sel, t)
		(c.name as Label).text = str(m.name)
		(c.info as Label).text = "%s CR · caja de %d\ntenés %d" % [_fmt(int(it.price)), int(it.box), Profile.rounds(sel, t)]
		var buy := c.buy as Button
		buy.text = "COMPRAR"
		buy.disabled = not Profile.can_buy_ammo(sel, t)
		buy.tooltip_text = str(m.text)
		var use := c.use as Button
		var chosen: bool = Profile.ammo_type(sel) == t
		use.text = "EN USO" if chosen else "USAR"
		use.disabled = chosen or not owned
		(c.name as Label).tooltip_text = str(m.text)
	_load_cartridges(cal)

func _load_cartridges(cal: String) -> void:
	for ch in _aroot.get_children():
		_aroot.remove_child(ch)
		ch.queue_free()
	var c: Dictionary = Ammo.data().calibers[cal]
	var oal := float(c.oal) * 0.001
	var k := 1.0 / oal                          # todos los cartuchos se ven a la misma altura
	var i := 0
	for t in Ammo.TYPE_ORDER:
		var path := "res://assets/ammo/cartridges/%s_%s.glb" % [cal, t]
		if not ResourceLoader.exists(path):
			continue
		var n := (load(path) as PackedScene).instantiate() as Node3D
		n.scale = Vector3.ONE * k
		n.name = "c_" + str(t)
		_aroot.add_child(n)
		n.position = Vector3(float(i), 0.0, 0.0)
		if i % 2 == 1:                              # algunas munición tumbada (como sueltas sobre la mesa)
			n.rotation_degrees = Vector3(0, 0, 90 + (i % 3) * 6)
		i += 1
	_layout_ammo()

## Un cartucho por columna: se reparten a lo ancho para quedar justo sobre su cartel y su botón.
func _layout_ammo() -> void:
	if _acam == null or _ammo_view == null:
		return
	var n := Ammo.TYPE_ORDER.size()
	var sz := _ammo_view.size
	if sz.x < 10 or sz.y < 10:
		return
	_acam.size = 1.3
	var width := _acam.size * sz.x / sz.y
	var step := width / float(n)
	_acam.global_position = Vector3(float(n - 1) * 0.5 * 1.0, 0.5, 3.0)
	var i := 0
	for ch in _aroot.get_children():
		var idx := i
		ch.position.x = (float(idx) - float(n - 1) * 0.5) * step
		if idx % 2 == 1:
			ch.position.x += 0.5 * minf(step, 1.0) * 0.9      # el pie queda en el origen: se centra el cuerpo tumbado
			ch.position.y = 0.2
		else:
			ch.position.y = 0.0
		i += 1
	_acam.global_position = Vector3(0.0, 0.5, 3.0)
