extends Node
## Pantalla principal: JUGAR (Torre Alfa), CONFIGURACIÓN, ANALIZAR RENDIMIENTO, SALIR; y el resumen al terminar.
## Argumentos (para pruebas y capturas): -- --play  (entra directo a la partida) · --probe [--quick] (corre el captador y sale) · --practica (modo práctica)
## · --baja / --media / --alta (fuerza ese preset de calidad)

var game: Game
var practice: PracticeGame
var menu: Control
var ui: CanvasLayer

func _ready() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var args := OS.get_cmdline_user_args()
	for lv in ["baja", "media", "alta"]:
		if "--" + lv in args:
			Settings.preset(["baja", "media", "alta"].find(lv))
	if "--practica" in args:
		start_practice()
		return
	if "--play" in args or "--probe" in args:
		start_game()
		if "--probe" in args:
			await get_tree().create_timer(1.0).timeout
			game.probe.quick = "--quick" in args
			await game.probe.run()
			print(game.probe.report_text)
			get_tree().quit()
		return
	show_menu()

func show_menu(result := {}) -> void:
	if menu:
		menu.queue_free()
	menu = Control.new()
	menu.theme = UiTheme.make()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	# la torre en corte, a la derecha
	var tw := MenuTower.new()
	tw.anchor_left = 0.0
	tw.anchor_right = 1.0
	tw.anchor_top = 0.0
	tw.anchor_bottom = 1.0
	menu.add_child(tw)
	# columna izquierda: título y botones
	var shade := ColorRect.new()
	shade.color = Color(1, 1, 1, 0.82)
	shade.anchor_right = 0.36
	shade.anchor_bottom = 1.0
	menu.add_child(shade)
	var stripe := ColorRect.new()
	stripe.color = UiTheme.ACCENT
	stripe.anchor_left = 0.36
	stripe.anchor_right = 0.36
	stripe.anchor_bottom = 1.0
	stripe.offset_right = 4
	menu.add_child(stripe)
	var v := VBoxContainer.new()
	v.position = Vector2(56, 44)
	v.custom_minimum_size = Vector2(400, 0)
	v.add_theme_constant_override("separation", 12)
	menu.add_child(v)
	var t := Label.new()
	t.text = "EXTRACCIÓN\nVERTICAL"
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", UiTheme.TEXT)
	v.add_child(t)
	var s := Label.new()
	s.text = "EXPLORA · SAQUEA · SOBREVIVE · EXTRAE"
	s.add_theme_font_size_override("font_size", 17)
	s.add_theme_color_override("font_color", UiTheme.MUTED)
	v.add_child(s)
	if not result.is_empty():
		var r := Label.new()
		match str(result.get("result", "")):
			"extraido":
				r.text = "EXTRACCIÓN EXITOSA (%s)\nBotín: $%d · Bajas: %d · Tiempo: %d s" % [result.get("where", ""), result.value, result.kills, int(result.time)]
				r.add_theme_color_override("font_color", Color(0.1, 0.45, 0.2))
			"muerto":
				r.text = "CAÍSTE EN LA TORRE\nBotín perdido: $%d · Bajas: %d" % [result.get("lost", 0), result.kills]
				r.add_theme_color_override("font_color", Color(0.7, 0.12, 0.1))
			_:
				r.text = ""
		r.add_theme_font_size_override("font_size", 20)
		v.add_child(r)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	var items := [["JUGAR · Torre Alfa", start_game, true], ["ARMERÍA", _armory, false], ["MODO PRÁCTICA", start_practice, false], ["CONFIGURACIÓN", _settings, false],
		["ANALIZAR RENDIMIENTO", _probe, false], ["SALIR", func(): get_tree().quit(), false]]
	for d in items:
		var b := Button.new()
		b.text = d[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(380, 54)
		b.add_theme_font_size_override("font_size", 24)
		if d[2]:
			b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.TEXT, 10, UiTheme.TEXT, 2))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
			b.add_theme_stylebox_override("hover", UiTheme.box(Color(0.25, 0.25, 0.28), 10, UiTheme.TEXT, 2))
		b.pressed.connect(d[1])
		v.add_child(b)
	var credits := Label.new()
	credits.text = "Animaciones: Mixamo · Personajes y armas: Operación Nexus · Anatomía: BodyParts3D (DBCLS, CC BY 4.0) · Modelos: bibliotecas libres de Sweet Home 3D"
	credits.add_theme_font_size_override("font_size", 12)
	credits.add_theme_color_override("font_color", UiTheme.MUTED)
	credits.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	credits.position = Vector2(20, 696)
	menu.add_child(credits)

func start_game() -> void:
	if menu:
		menu.queue_free()
		menu = null
	if game:
		game.queue_free()
	game = Game.new()
	add_child(game)
	game.match_over.connect(func(r: Dictionary):
		get_tree().paused = false
		Engine.time_scale = 1.0
		Sfx.stop_ambient()
		game.queue_free()
		game = null
		show_menu(r))

func start_practice() -> void:
	if menu:
		menu.queue_free()
		menu = null
	if practice:
		practice.queue_free()
	practice = PracticeGame.new()
	add_child(practice)
	practice.match_over.connect(func(_r: Dictionary):
		get_tree().paused = false
		Engine.time_scale = 1.0
		Sfx.stop_ambient()
		practice.queue_free()
		practice = null
		show_menu())

func _armory() -> void:
	var a := Armory.new()
	ui.add_child(a)
	a.closed.connect(func():
		a.queue_free()
		show_menu())

func _settings() -> void:
	var sm := SettingsMenu.new()
	ui.add_child(sm)
	sm.closed.connect(sm.queue_free)
	sm.probe_requested.connect(func():
		sm.queue_free()
		_probe())

func _probe() -> void:
	start_game()
	await get_tree().create_timer(1.0).timeout
	game.run_probe()
