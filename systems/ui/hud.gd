class_name Hud
extends Control
## Interfaz de juego: joysticks (izquierdo = movimiento progresivo, derecho = apuntado persistente), botones contextuales
## (disparar, salto/parkour, golpe/cuchillo, granada con arco, USAR que aparece sólo cuando hay algo para usar,
## recargar, cambiar arma, agacharse, pausa, inventario), vida, munición, piso, objetivo, minimapa esquemático, ruido,
## avisos, lesiones (rayos X), barra de acción (forzar caja), selector de destino del ascensor y cuenta de extracción.
## Pocos botones a la vista: USAR sólo aparece cuando sirve, granada y recarga son chicos.

signal pause_pressed
signal inventory_pressed

var game: Node
var player: Actor
var tower: TowerBuilder
var camera: SideCamera
var touch_mode := false
var left_stick: TouchStick
var right_stick: TouchStick
var buttons := {}                  ## nombre → TouchButton
var _touch_owner := {}             ## índice de toque → control que lo tomó
var _lbl := {}
var _toasts: Array = []
var _injuries: Array = []
var _injury_t := 0.0
var _flash := 0.0
var _cinematic := 0.0
var _cinematic_on := false
var _elev_panel: PanelContainer
var _fps_t := 0.0
var font_big := 34
var hold := {"fire": false, "grenade": false, "jump": false, "use": false}
var edge := {"jump": false, "melee": false, "use": false, "reload": false, "swap": false, "crouch": false, "heal": false}
var crouch_toggle := false

func _ready() -> void:
	add_to_group("hud")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_mode = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or OS.has_feature("web_android")
	_build()

func _build() -> void:
	left_stick = TouchStick.new()
	left_stick.persist = false
	left_stick.tint = Color(0.45, 0.8, 1.0)
	add_child(left_stick)
	right_stick = TouchStick.new()
	right_stick.persist = true
	right_stick.tint = Color(1.0, 0.75, 0.3)
	add_child(right_stick)
	for d in [["fire", "◎", 64.0, Color(1.0, 0.35, 0.25)], ["jump", "⤒", 46.0, Color(0.5, 0.85, 1.0)],
			["melee", "✊", 42.0, Color(0.95, 0.95, 0.95)], ["grenade", "●", 34.0, Color(0.7, 0.9, 0.4)],
			["use", "USAR", 44.0, Color(1.0, 0.85, 0.3)], ["reload", "R", 28.0, Color(0.9, 0.9, 0.9)],
			["swap", "⇄", 30.0, Color(0.9, 0.9, 0.9)], ["crouch", "▼", 30.0, Color(0.8, 0.8, 0.8)],
			["pause", "II", 26.0, Color(0.9, 0.9, 0.9)], ["heal", "✚", 32.0, Color(0.4, 1.0, 0.5)], ["inventory", "▤", 26.0, Color(0.9, 0.9, 0.9)]]:
		var b := TouchButton.new()
		b.label = d[1]
		b.radius = d[2]
		b.tint = d[3]
		b.name = "Btn_" + str(d[0])
		add_child(b)
		buttons[d[0]] = b
	for k in ["health", "ammo", "floor", "objective", "prompt", "toast", "injury", "fps", "noise", "extract", "weapon", "loot", "status"]:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_lbl[k] = l
	_lbl.ammo.add_theme_font_size_override("font_size", 38)
	_lbl.floor.add_theme_font_size_override("font_size", 24)
	_lbl.prompt.add_theme_font_size_override("font_size", 22)
	_lbl.prompt.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	_lbl.injury.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	_lbl.extract.add_theme_font_size_override("font_size", 30)
	_lbl.extract.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	_lbl.objective.text = "◆ OBJETIVO: saqueá y extraé con vida (P0 o helicóptero en la azotea)"
	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var s := get_viewport_rect().size
	var k := Settings.joystick_size
	left_stick.position = Vector2(0, s.y * 0.35)
	left_stick.size = Vector2(s.x * 0.42, s.y * 0.65)
	right_stick.position = Vector2(s.x * 0.5, s.y * 0.35)
	right_stick.size = Vector2(s.x * 0.3, s.y * 0.65)
	var r := s.x - 80.0
	_place("fire", Vector2(r - 30, s.y - 230))
	_place("jump", Vector2(r - 10, s.y - 95))
	_place("melee", Vector2(r - 130, s.y - 120))
	_place("grenade", Vector2(r - 150, s.y - 240))
	_place("use", Vector2(r - 200, s.y * 0.42))
	_place("reload", Vector2(s.x - 262, 40))
	_place("swap", Vector2(s.x - 330, 40))
	_place("crouch", Vector2(r - 30, s.y - 360))
	_place("pause", Vector2(40, 40))
	_place("heal", Vector2(330, s.y - 60))
	_place("inventory", Vector2(110, 40))
	_lbl.health.position = Vector2(20, s.y - 52)
	_lbl.ammo.position = Vector2(s.x - 216, 8)
	_lbl.weapon.position = Vector2(s.x - 216, 58)
	_lbl.floor.position = Vector2(s.x - 216, 262)
	_lbl.weapon.position = Vector2(s.x - 216, 290)
	_lbl.objective.position = Vector2(160, 24)
	_lbl.objective.add_theme_font_size_override("font_size", 17)
	_lbl.prompt.position = Vector2(s.x * 0.5 - 150, s.y * 0.30)
	_lbl.toast.position = Vector2(s.x * 0.5 - 200, 70)
	_lbl.injury.position = Vector2(20, 90)
	_lbl.fps.position = Vector2(20, s.y - 90)
	_lbl.noise.position = Vector2(20, s.y - 120)
	_lbl.extract.position = Vector2(s.x * 0.5 - 180, s.y * 0.18)
	_lbl.loot.position = Vector2(170, s.y - 52)
	_lbl.status.position = Vector2(20, s.y - 150)
	_lbl.status.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	for b in buttons.values():
		(b as TouchButton).scale_k = k
	for n in ["fire", "jump", "melee", "grenade", "use", "reload", "swap", "crouch", "inventory", "heal"]:
		(buttons[n] as Control).visible = touch_mode
	left_stick.visible = touch_mode
	right_stick.visible = touch_mode

func _place(n: String, p: Vector2) -> void:
	var b: TouchButton = buttons[n]
	b.size = Vector2(b.radius * 2.2, b.radius * 2.2)
	b.position = p - b.size * 0.5

# ---------------------------------------------------------------- toques (multitáctil)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if _cinematic_on and e.pressed:
			get_tree().call_group("bullet_time", "skip")
		if _elev_panel and _elev_panel.visible:
			return
		if e.pressed:
			touch_mode = true
			if not left_stick.visible:
				_layout()
			for n in buttons:
				var b: TouchButton = buttons[n]
				if b.visible and b.hit(e.position):
					_touch_owner[e.index] = n
					_button(n, true)
					get_viewport().set_input_as_handled()
					return
			if left_stick.touch_event(e.index, e.position, true, false):
				_touch_owner[e.index] = left_stick
			elif right_stick.touch_event(e.index, e.position, true, false):
				_touch_owner[e.index] = right_stick
		else:
			var o = _touch_owner.get(e.index)
			if o is String:
				_button(o, false)
			elif o is TouchStick:
				(o as TouchStick).touch_event(e.index, e.position, false, false)
			_touch_owner.erase(e.index)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		var o = _touch_owner.get(e.index)
		if o is TouchStick:
			(o as TouchStick).touch_event(e.index, e.position, true, true)

func _button(n: String, down: bool) -> void:
	var b: TouchButton = buttons[n]
	b.pressed = down
	b.queue_redraw()
	if hold.has(n):
		hold[n] = down
	if down and edge.has(n):
		edge[n] = true
	if down and n == "pause":
		pause_pressed.emit()
	if down and n == "inventory":
		inventory_pressed.emit()
	if down and n == "crouch":
		crouch_toggle = not crouch_toggle

func take_edge(n: String) -> bool:
	var v: bool = edge.get(n, false)
	edge[n] = false
	return v

# ---------------------------------------------------------------- llamados desde el juego (grupo «hud»)

func toast(msg: String) -> void:
	_toasts.append([msg, 3.0])
	if _toasts.size() > 4:
		_toasts.pop_front()

func flashbang(k: float) -> void:
	_flash = maxf(_flash, clampf(k, 0.3, 1.0))

func set_cinematic(on: bool) -> void:
	_cinematic_on = on

func show_injuries(victim: Actor, lines: Array) -> void:
	var who := "VOS" if victim == player else "ENEMIGO"
	_injuries = ["RAYOS X · %s" % who] + lines
	_injury_t = 4.0

func show_elevator_menu(e: Elevator) -> void:
	if _elev_panel:
		_elev_panel.queue_free()
	_elev_panel = PanelContainer.new()
	var box := VBoxContainer.new()
	_elev_panel.add_child(box)
	var t := Label.new()
	t.text = "ASCENSOR · elegí el piso"
	box.add_child(t)
	for i in e.stops.size():
		var b := Button.new()
		b.text = "%s%s" % [e.stop_names[i], "  (acá)" if i == e.current else ""]
		b.disabled = i == e.current
		b.custom_minimum_size = Vector2(260, 54)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(func():
			e.go_to(i)
			_elev_panel.queue_free()
			_elev_panel = null)
		box.add_child(b)
	var c := Button.new()
	c.text = "Cancelar"
	c.custom_minimum_size = Vector2(260, 46)
	c.pressed.connect(func():
		_elev_panel.queue_free()
		_elev_panel = null)
	box.add_child(c)
	add_child(_elev_panel)
	_elev_panel.position = Vector2(get_viewport_rect().size.x * 0.5 - 140, 90)

# ---------------------------------------------------------------- dibujo

func _process(delta: float) -> void:
	var rd := delta / maxf(Engine.time_scale, 0.05)
	rd = minf(rd, 0.1)
	if player == null or not is_instance_valid(player):
		return
	_lbl.health.text = "♥ %d" % int(maxf(player.health, 0.0))
	_lbl.status.text = player.injuries.summary() + ("   [H] curar" if not touch_mode and player.injuries.any() else "")
	var can_heal := player.injuries.any() and (player.inventory.count("bandage") + player.inventory.count("medkit")) > 0
	(buttons.heal as Control).visible = touch_mode and can_heal
	var w := player.weapon()
	if w:
		_lbl.ammo.text = ("RECARGANDO" if w.reloading else "%d | %d" % [w.mag, w.reserve])
		_lbl.weapon.text = w.display_name()
	else:
		_lbl.ammo.text = "—"
		_lbl.weapon.text = "Cuchillo" if player.current == "knife" else "Puños"
	_lbl.weapon.text += "\n● %d × %s" % [int(player.grenades.get(player.grenade_kind, 0)), str(Explosion.defs().get(player.grenade_kind, {}).get("name", "")).replace("Granada de ", "").replace("Granada ", "")]
	_lbl.loot.text = "Botín: $%d" % player.inventory.total_value()
	if tower:
		var fi := tower.floor_at(player.global_position.y)
		_lbl.floor.text = "PISO %d" % fi if fi < tower.data.floors.size() else "AZOTEA"
	var it := player.interact_target
	_lbl.prompt.text = ("[E] " if not touch_mode else "") + (it as Interactable).prompt_for(player) if it else ""
	(buttons.use as Control).visible = touch_mode and it != null
	if player.action_progress >= 0.0:
		_lbl.prompt.text = "Forzando… %d%%" % int(player.action_progress * 100.0)
	var nl := int(clampf(player.noise_level / 2.5, 0.0, 6.0))
	_lbl.noise.text = ("Ruido " + "▮".repeat(nl)) if nl > 0 else ""
	# avisos
	var lines := []
	for tst in _toasts:
		tst[1] -= rd
		lines.append(tst[0])
	_toasts = _toasts.filter(func(x): return x[1] > 0.0)
	_lbl.toast.text = "\n".join(lines)
	_injury_t -= rd
	_lbl.injury.text = "\n".join(_injuries) if _injury_t > 0.0 else ""
	# extracción
	var ext := ""
	for z in get_tree().get_nodes_in_group("extraction"):
		if z.inside == player:
			ext = "EXTRAYENDO… %d%%" % int(z.progress() * 100.0)
	_lbl.extract.text = ext
	_fps_t -= rd
	if _fps_t <= 0.0:
		_fps_t = 0.5
		_lbl.fps.text = "%d FPS · %d dibujos" % [Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)] if Settings.show_fps else ""
	_flash = move_toward(_flash, 0.0, rd * 0.5)
	_cinematic = move_toward(_cinematic, 1.0 if _cinematic_on else 0.0, rd * 4.0)
	for n in ["fire", "jump", "melee", "grenade", "reload", "swap", "crouch"]:
		(buttons[n] as Control).modulate.a = 1.0 - _cinematic
	(buttons.melee as TouchButton).label = "🔪" if player.current == "knife" else "✊"
	for n in ["ammo", "weapon", "floor", "objective", "prompt", "loot"]:
		(_lbl[n] as Label).visible = not _cinematic_on
	(buttons.crouch as TouchButton).pressed = crouch_toggle
	queue_redraw()

func _draw() -> void:
	var s := get_viewport_rect().size
	if player == null:
		return
	# barra de vida
	draw_rect(Rect2(20, s.y - 22, 260, 10), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(20, s.y - 22, 260 * clampf(player.health / player.max_health, 0, 1), 10), Color(0.35, 0.9, 0.45))
	# barra de acción (forzar contenedor)
	if player.action_progress >= 0.0:
		draw_rect(Rect2(s.x * 0.5 - 150, s.y * 0.30 + 36, 300, 10), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(s.x * 0.5 - 150, s.y * 0.30 + 36, 300 * player.action_progress, 10), Color(1.0, 0.8, 0.3))
	# arco de la granada
	if hold.grenade or Input.is_action_pressed("grenade"):
		var pts := Grenade.arc_points(player.grenade_origin(), player.grenade_velocity())
		var prev := Vector2.INF
		for i in pts.size():
			if camera.is_position_behind(pts[i]):
				continue
			var sp := camera.unproject_position(pts[i])
			if prev != Vector2.INF and i % 2 == 0:
				draw_line(prev, sp, Color(0.8, 1.0, 0.5, 0.8 - i * 0.02), 3.0)
			prev = sp
	# (sin mira blanca: se apunta con el láser que sale de la boca del cañón)
	_draw_minimap(s)
	if _cinematic > 0.01:
		var h := 60.0 * _cinematic
		draw_rect(Rect2(0, 0, s.x, h), Color(0, 0, 0, 0.9))
		draw_rect(Rect2(0, s.y - h, s.x, h), Color(0, 0, 0, 0.9))
	if _flash > 0.01:
		draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, _flash))

## Minimapa esquemático de la torre: sectores descubiertos, ascensor, escaleras y el jugador.
func _draw_minimap(s: Vector2) -> void:
	if tower == null:
		return
	var w := 200.0
	var h := 150.0
	var o := Vector2(s.x - w - 16, 104)
	if _cinematic_on:
		return
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.02, 0.04, 0.06, 0.75))
	draw_rect(Rect2(o, Vector2(w, h)), Color(0.4, 0.7, 1.0, 0.5), false, 1.0)
	var W := float(tower.data.width)
	var H: float = float(tower.data.floor_h) * (tower.data.floors.size() + 1)
	var to_map := func(x: float, y: float) -> Vector2:
		return o + Vector2(x / W * w, h - y / H * h)
	for r in tower.graph.rooms:
		if not tower.revealed.has(r.id):
			continue
		var p0: Vector2 = to_map.call(float(r.x0), float(r.y))
		var p1: Vector2 = to_map.call(float(r.x1), float(r.y) + float(tower.data.floor_h) * 0.9)
		draw_rect(Rect2(Vector2(p0.x, p1.y), Vector2(p1.x - p0.x, p0.y - p1.y)), Color(0.3, 0.5, 0.7, 0.35))
	for l in tower.data.ladders:
		var a: Vector2 = to_map.call(float(l[0]), float(l[1]))
		var b: Vector2 = to_map.call(float(l[0]), float(l[2]))
		draw_line(a, b, Color(0.3, 0.85, 1.0, 0.8), 2.0)
	var e0: Vector2 = to_map.call(float(tower.data.elevator.x), 0.0)
	var e1: Vector2 = to_map.call(float(tower.data.elevator.x), float(tower.data.floor_h) * 4.0)
	draw_line(e0, e1, Color(1.0, 0.8, 0.2, 0.9), 3.0)
	for z in get_tree().get_nodes_in_group("extraction"):
		draw_circle(to_map.call(z.global_position.x, z.global_position.y), 4.0, Color(0.3, 1.0, 0.4))
	draw_circle(to_map.call(player.global_position.x, player.global_position.y), 4.0, Color(1, 1, 1))


## Botón redondo táctil (lo maneja el HUD para que funcione el multitáctil junto con los joysticks).
class TouchButton extends Control:
	var label := ""
	var radius := 40.0
	var tint := Color.WHITE
	var pressed := false
	var scale_k := 1.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func hit(p: Vector2) -> bool:
		return (p - (global_position + size * 0.5)).length() <= radius * scale_k * 1.1
	func _draw() -> void:
		var c := size * 0.5
		var r := radius * scale_k
		draw_circle(c, r, Color(tint.r, tint.g, tint.b, 0.45 if pressed else 0.18))
		draw_arc(c, r, 0, TAU, 40, Color(tint.r, tint.g, tint.b, 0.8), 2.0, true)
		var f := get_theme_default_font()
		var fs := int(r * (0.55 if label.length() <= 2 else 0.38))
		var ts := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, c - Vector2(ts.x * 0.5, -fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.95))
