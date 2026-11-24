extends Node
## Pantalla principal: JUGAR (Torre Alfa), CONFIGURACIÓN, ANALIZAR RENDIMIENTO, SALIR; y el resumen al terminar.
## Argumentos (para pruebas y capturas): -- --play  (entra directo a la partida) · --probe [--quick] (corre el captador y sale)
## · --baja / --media / --alta (fuerza ese preset de calidad)

var game: Game
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
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var v := VBoxContainer.new()
	v.position = Vector2(80, 70)
	v.add_theme_constant_override("separation", 14)
	menu.add_child(v)
	var t := Label.new()
	t.text = "EXTRACCIÓN\nVERTICAL"
	t.add_theme_font_size_override("font_size", 72)
	t.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	v.add_child(t)
	var s := Label.new()
	s.text = "EXPLORA · SAQUEA · SOBREVIVE · EXTRAE"
	s.add_theme_font_size_override("font_size", 24)
	s.add_theme_color_override("font_color", Color(0.95, 0.25, 0.2))
	v.add_child(s)
	if not result.is_empty():
		var r := Label.new()
		match str(result.get("result", "")):
			"extraido":
				r.text = "EXTRACCIÓN EXITOSA (%s)\nBotín: $%d · Bajas: %d · Tiempo: %d s" % [result.get("where", ""), result.value, result.kills, int(result.time)]
				r.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
			"muerto":
				r.text = "CAÍSTE EN LA TORRE\nBotín perdido: $%d · Bajas: %d" % [result.get("lost", 0), result.kills]
				r.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
			_:
				r.text = "Partida abandonada"
		r.add_theme_font_size_override("font_size", 26)
		v.add_child(r)
	for d in [["JUGAR · Torre Alfa", start_game], ["CONFIGURACIÓN", _settings], ["ANALIZAR RENDIMIENTO", _probe], ["SALIR", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = d[0]
		b.custom_minimum_size = Vector2(380, 64)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(d[1])
		v.add_child(b)
	var credits := Label.new()
	credits.text = "Animaciones: Mixamo · Personajes y armas: Operación Nexus · Anatomía: BodyParts3D (DBCLS, CC BY 4.0) · Modelos: bibliotecas libres de Sweet Home 3D"
	credits.add_theme_font_size_override("font_size", 13)
	credits.add_theme_color_override("font_color", Color(0.5, 0.52, 0.55))
	credits.position = Vector2(80, 680)
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
