class_name Game
extends Node3D
## Una partida en la Torre Alfa: arma el mapa, el jugador, la cámara, el HUD, la cámara lenta y el captador de
## rendimiento; revela sectores, oculta pisos lejanos (ahorro de dibujo), ajusta la reverberación según el lugar,
## registra tirones y termina con la extracción o la muerte.

signal match_over(result: Dictionary)

var map_id := "torre"             ## "torre" (Torre Alfa) o "abismo" (Abismo Vertical)
var tower: TowerBuilder
var overlay: NoiseOverlay
var player: Actor
var controller: PlayerController
var camera: SideCamera
var hud: Hud
var hud_layer: CanvasLayer
var bullet_time: BulletTime
var ballistics: Ballistics
var probe: PerfProbe
var pause_menu: Control
var settings_menu: SettingsMenu
var _player_floor := -1
var _room := ""
var _t := 0.0
var _kills := 0
var probe_mode := false
var injury_stats: Array = []          ## lesiones causadas y recibidas (para estadísticas)
var over := false

func _ready() -> void:
	PlayerController.setup_input_map()
	Fx.attach(self)
	ballistics = Ballistics.new()
	ballistics.name = "Ballistics"
	add_child(ballistics)
	tower = TowerBuilder.new()
	tower.name = "TorreAlfa"
	add_child(tower)
	tower.build(AbismoVertical.data() if map_id == "abismo" else TorreAlfa.data())
	tower.extracted.connect(_on_extracted)
	_spawn_player()
	# la anatomía de calidad máxima se prepara en segundo plano (un hilo por tipo de personaje)
	var ids := {player.character_id: true}
	for e in tower.enemies:
		ids[e.character_id] = true
	for id in ids:
		AnatomyBody.warm(str(id))
	camera = SideCamera.new()
	camera.target = player
	camera.bounds = Rect2(0, -1, float(tower.data.width), float(tower.data.floor_h) * float(tower.data.floors.size() + 1))
	add_child(camera)
	camera.make_current()
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	hud = Hud.new()
	hud.player = player
	hud.tower = tower
	hud.camera = camera
	hud.game = self
	hud_layer.add_child(hud)
	overlay = NoiseOverlay.new()
	overlay.player = player
	overlay.camera = camera
	hud_layer.add_child(overlay)
	hud.pause_pressed.connect(toggle_pause)
	hud.inventory_pressed.connect(toggle_pause)
	controller = PlayerController.new()
	controller.actor = player
	controller.hud = hud
	controller.camera = camera
	add_child(controller)
	bullet_time = BulletTime.new()
	bullet_time.add_to_group("bullet_time")
	add_child(bullet_time)
	bullet_time.setup(camera, player)
	# las lesiones no se muestran en pantalla durante la partida: se guardan para las estadísticas del jugador
	bullet_time.injury_report.connect(func(v, lines): injury_stats.append({"t": _t, "victim": str(v.name), "lines": lines}))
	probe = PerfProbe.new()
	probe.game = self
	add_child(probe)
	for e in tower.enemies:
		e.died.connect(func(info):
			if info.get("shooter") == player:
				_kills += 1)
	Settings.changed.connect(func(): tower.apply_settings(maxi(_player_floor, 0)); hud._layout())
	tower.apply_settings(0)
	Sfx.ambient("amb_generator", -18.0)
	Sfx.ambient("amb_wind", -22.0)
	Sfx.ambient("amb_rain", -28.0)

func _spawn_player() -> void:
	player = Actor.new()
	player.name = "Jugador"
	player.character_id = Settings.character_id if CharacterModel.find(Settings.character_id).id == Settings.character_id else "alfa"
	player.is_player = true
	player.team = 0
	player.max_health = 100.0
	add_child(player)
	player.global_position = tower.data.start
	for slot in ["primary", "secondary"]:
		var wid := str(Profile.equipped.get(slot, "m4a1" if slot == "primary" else "m1911"))
		Profile.load_weapon(player.give_weapon(slot, wid))        # arma y munición del perfil (Armería)
	player.equip("primary")
	player.specialty = Profile.specialty
	player.mines = 2
	player.add_to_group("perf_personajes_jugador")
	player.died.connect(_on_player_died)

func _process(delta: float) -> void:
	_t += delta
	if player == null:
		return
	var rd := delta / maxf(Engine.time_scale, 0.05)
	if rd > 0.05 and _t > 3.0 and not probe_mode:
		probe.hitches.append({"t": _t, "ms": rd * 1000.0, "info": _hitch_context()})
		if probe.hitches.size() > 200:
			probe.hitches.pop_front()
	if probe_mode:
		return
	var room := tower.room_id_at(player.global_position + Vector3.UP * 0.5)
	tower.update_covers(room, rd)
	if room != _room:
		_room = room
		var r := tower.graph.room(room)
		var w := float(r.get("x1", 10.0)) - float(r.get("x0", 0.0))
		var in_crater := room in ["1:3", "2:3", "3:3"]
		Sfx.set_room(clampf(w / 20.0, 0.15, 1.0) if not in_crater else 0.95, not in_crater and int(r.get("floor", 0)) < 5)
	var pf := tower.floor_at(player.global_position.y + 0.5)
	if pf != _player_floor:
		_player_floor = pf
		_update_floor_visibility()
		tower.apply_settings(pf)

func _hitch_context() -> String:
	var ex := get_tree().get_nodes_in_group("smoke").size()
	return "piso %d · %d proyectiles · %d efectos · humo activo %d · %d dibujos" % [_player_floor, ballistics.stats.fired, Fx.stats.emitted, ex,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]

## Oclusión por piso: sólo se dibujan el piso actual y los vecinos que pide la configuración.
func _update_floor_visibility() -> void:
	var keep := Settings.view_floors + 1
	for i in tower.floors_nodes.size():
		var n := tower.floors_nodes[i]
		var vis := absi(i - _player_floor) <= keep or (i == _player_floor + 1)
		n.visible = vis
		for c in n.get_children():
			if c is Actor and c != player:
				# enemigos de pisos que no se ven: dormidos (sin IA, sin animación, sin física propia)
				(c as Actor).process_mode = Node.PROCESS_MODE_INHERIT if vis else Node.PROCESS_MODE_DISABLED

func reveal_all_near(pos: Vector3) -> void:
	var room := tower.room_id_at(pos)
	for i in 30:
		tower.update_covers(room, 0.1)
	_player_floor = tower.floor_at(pos.y)
	for n in tower.floors_nodes:
		n.visible = true
	tower.apply_settings(_player_floor)

func set_probe_mode(on: bool) -> void:
	probe_mode = on
	hud.visible = not on
	controller.set_physics_process(not on)
	for e in tower.enemies:
		if is_instance_valid(e):
			e.set_physics_process(not on)
			var b := e.get_node_or_null("BotBrain")
			for c in e.get_children():
				if c is BotBrain:
					c.set_physics_process(not on)
	player.set_physics_process(not on)
	if not on:
		_player_floor = -1

func toggle_pause() -> void:
	if over:
		return
	if pause_menu and is_instance_valid(pause_menu):
		pause_menu.queue_free()
		pause_menu = null
		get_tree().paused = false
		return
	get_tree().paused = true
	pause_menu = _make_pause()
	hud_layer.add_child(pause_menu)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
		toggle_pause()
	elif event.is_action_pressed("perf_overlay"):
		Settings.set_value("show_fps", not Settings.show_fps)

func _make_pause() -> Control:
	var p := PanelContainer.new()
	p.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.82)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	h.add_child(v)
	var t := Label.new()
	t.text = "PAUSA"
	t.add_theme_font_size_override("font_size", 40)
	v.add_child(t)
	for d in [["Continuar", toggle_pause], ["Configuración", open_settings], ["Analizar rendimiento", func():
			toggle_pause()
			run_probe()], ["Abandonar partida", func():
			get_tree().paused = false
			match_over.emit({"result": "abandono"})]]:
		var b := Button.new()
		b.text = d[0]
		b.custom_minimum_size = Vector2(320, 58)
		b.add_theme_font_size_override("font_size", 24)
		b.pressed.connect(d[1])
		v.add_child(b)
	# inventario
	var inv := VBoxContainer.new()
	h.add_child(inv)
	var it := Label.new()
	it.text = "INVENTARIO · valor $%d" % player.inventory.total_value()
	it.add_theme_font_size_override("font_size", 26)
	inv.add_child(it)
	for id in player.inventory.items:
		var row := HBoxContainer.new()
		var d := Inventory.def(id)
		var icon_path := "res://assets/icons/%s.png" % d.get("icon", "")
		if ResourceLoader.exists(icon_path):
			var tr := TextureRect.new()
			tr.texture = load(icon_path)
			tr.custom_minimum_size = Vector2(40, 40)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(tr)
		var l := Label.new()
		l.text = "%s ×%d  ($%d)" % [d.get("name", id), player.inventory.items[id], int(d.get("value", 0)) * int(player.inventory.items[id])]
		l.add_theme_font_size_override("font_size", 20)
		row.add_child(l)
		if str(d.get("type", "")) == "medico":
			var use := Button.new()
			use.text = "Usar"
			var item_id: String = id
			use.pressed.connect(func():
				toggle_pause()
				player.use_medical(item_id))
			row.add_child(use)
		inv.add_child(row)
	var g := Label.new()
	g.text = "Granadas: " + ", ".join(player.grenades.keys().filter(func(k): return int(player.grenades[k]) > 0).map(func(k): return "%s ×%d" % [Explosion.defs()[k].name, player.grenades[k]]))
	g.add_theme_font_size_override("font_size", 18)
	inv.add_child(g)
	var gk := Button.new()
	gk.text = "Cambiar tipo de granada (%s)" % Explosion.defs().get(player.grenade_kind, {}).get("name", "")
	gk.pressed.connect(func():
		var kinds: Array = player.grenades.keys().filter(func(k): return int(player.grenades[k]) > 0)
		if not kinds.is_empty():
			player.grenade_kind = kinds[(kinds.find(player.grenade_kind) + 1) % kinds.size()]
		toggle_pause()
		toggle_pause())
	inv.add_child(gk)
	return p

func open_settings() -> void:
	if settings_menu and is_instance_valid(settings_menu):
		return
	settings_menu = SettingsMenu.new()
	settings_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	hud_layer.add_child(settings_menu)
	settings_menu.closed.connect(func():
		settings_menu.queue_free()
		settings_menu = null)
	settings_menu.probe_requested.connect(func():
		settings_menu.queue_free()
		settings_menu = null
		if pause_menu:
			toggle_pause()
		run_probe())

func run_probe() -> void:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.position = Vector2(30, 30)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 6)
	hud_layer.add_child(lbl)
	probe.progress.connect(func(t: String, k: float): lbl.text = "CAPTADOR DE RENDIMIENTO %d%%\n%s" % [int(k * 100.0), t])
	await probe.run()
	lbl.queue_free()
	open_settings()
	settings_menu.set_report(probe.report_text)
	settings_menu.set_probe_status("Informe listo (copiado al portapapeles y guardado en informe_rendimiento.txt)")

func _on_extracted(a: Actor, label: String) -> void:
	if over:
		return
	over = true
	for slot in player.weapons:
		Profile.store_weapon(player.weapons[slot] as Firearm)        # lo que sobró de munición vuelve al depósito
	Sfx.play_ui("ui_confirm", 0.0)
	match_over.emit({"result": "extraido", "where": label, "value": a.inventory.total_value(), "kills": _kills, "time": _t,
		"items": a.inventory.items.duplicate()})

func _on_player_died(info: Dictionary) -> void:
	if over:
		return
	over = true
	await get_tree().create_timer(2.5).timeout
	match_over.emit({"result": "muerto", "cause": str(info.get("type", "")), "value": 0, "kills": _kills, "time": _t,
		"lost": player.inventory.total_value()})
