extends Control
## Lanzador (cliente liviano). La APK trae el motor y el código; los personajes, armas, anatomía, sonidos y cada mapa
## (assets) viajan en paquetes .pck que se descargan al abrir el juego, se verifican (SHA-256) y se montan encima.
##
## Flujo: lee el manifiesto (boot/update_config.json → manifest_url) → por cada paquete obligatorio compara su versión con la
## instalada (user://content/instalado.json) → descarga sólo lo que falta o cambió → monta todos → abre el menú.
## Sin internet: sigue con lo que ya tenga descargado (si falta algo, avisa y deja reintentar).
## Si el contenido ya está dentro del proyecto (editor, PC, compilaciones completas), no descarga nada.
##
## La firma de la APK es siempre la misma: instalar una APK nueva encima conserva los datos del juego (ajustes, etc.).

const CONTENT_DIR := "user://content"
const INSTALLED := "user://content/instalado.json"
const NEXT_SCENE := "res://scenes/main.tscn"
const PROBE := "res://assets/characters/alfa/alfa.glb"

var _label: Label
var _sub: Label
var _bar: ProgressBar
var _retry: Button
var _skip: Button
var _http: HTTPRequest
var _manifest := {}
var _installed := {}
var _queue: Array = []
var _cur: Dictionary = {}
var _total_bytes := 0
var _done_bytes := 0
var _apk := 0

func _ready() -> void:
	_build_ui()
	# contenido ya presente (editor / PC / compilación completa): nada que descargar
	if ResourceLoader.exists(PROBE) and not OS.has_feature("android"):
		_go()
		return
	_apk = int(_read_json("res://boot/local_version.json").get("apk", 0))
	_installed = _read_json(INSTALLED)
	DirAccess.make_dir_recursive_absolute(CONTENT_DIR)
	_check()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-300, -110)
	v.custom_minimum_size = Vector2(600, 220)
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var t := Label.new()
	t.text = "EXTRACCIÓN\nVERTICAL"
	t.add_theme_font_size_override("font_size", 54)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(600, 26)
	_bar.visible = false
	v.add_child(_bar)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sub)
	_retry = Button.new()
	_retry.text = "Reintentar"
	_retry.custom_minimum_size = Vector2(240, 56)
	_retry.add_theme_font_size_override("font_size", 22)
	_retry.visible = false
	_retry.pressed.connect(func():
		_retry.visible = false
		_check())
	v.add_child(_retry)
	_skip = Button.new()
	_skip.text = "Continuar con lo que tengo"
	_skip.custom_minimum_size = Vector2(320, 56)
	_skip.add_theme_font_size_override("font_size", 20)
	_skip.visible = false
	_skip.pressed.connect(_go)
	v.add_child(_skip)
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	add_child(_http)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}

func _say(t: String, sub := "") -> void:
	_label.text = t
	_sub.text = sub

# ---------------------------------------------------------------- manifiesto

func _check() -> void:
	_say("Buscando novedades…")
	var url := str(_read_json("res://boot/update_config.json").get("manifest_url", ""))
	if url == "":
		_finish_offline()
		return
	_http.download_file = ""
	_http.request_completed.connect(_on_manifest, CONNECT_ONE_SHOT)
	if _http.request(url) != OK:
		_http.request_completed.disconnect(_on_manifest)
		_finish_offline()

func _on_manifest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish_offline()
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary:
		_finish_offline()
		return
	_manifest = d
	if int(_manifest.get("min_apk", 0)) > _apk:
		# el contenido nuevo necesita código nuevo: no se baja (podría no funcionar con esta APK)
		_say("Hay una versión nueva del juego", "Instalá la APK más reciente (se instala encima y no pierde tus datos):\n" + str(_read_json("res://boot/update_config.json").get("apk_url", "")))
		_skip.visible = true
		return
	_queue.clear()
	_total_bytes = 0
	_done_bytes = 0
	for p in _manifest.get("packs", []):
		var inst: Dictionary = _installed.get(str(p.name), {})
		var have := FileAccess.file_exists("%s/%s.pck" % [CONTENT_DIR, p.name]) and str(inst.get("version", "")) == str(p.version)
		if not have and bool(p.get("required", true)):
			_queue.append(p)
			_total_bytes += int(p.get("size", 0))
	_next()

func _finish_offline() -> void:
	# sin conexión: se usa lo ya descargado; si falta algo imprescindible se avisa
	for name_ in ["personajes", "mapa_torre_alfa"]:
		if not FileAccess.file_exists("%s/%s.pck" % [CONTENT_DIR, name_]):
			_say("Falta descargar el contenido del juego", "Conectate a internet (mejor con Wi-Fi) y tocá Reintentar.")
			_retry.text = "Reintentar"
			_retry.visible = true
			return
	_go()

# ---------------------------------------------------------------- descarga

func _next() -> void:
	if _queue.is_empty():
		_go()
		return
	_cur = _queue.pop_front()
	var part := "%s/%s.pck.part" % [CONTENT_DIR, _cur.name]
	_say("Descargando %s" % str(_cur.get("desc", _cur.name)), "%.0f MB · una sola vez; después sólo se baja lo que cambie" % (float(_cur.get("size", 0)) / 1048576.0))
	_bar.visible = true
	_bar.max_value = 1.0
	_http.download_file = part
	_http.request_completed.connect(_on_pack, CONNECT_ONE_SHOT)
	if _http.request(str(_cur.url)) != OK:
		_http.request_completed.disconnect(_on_pack)
		_fail("No se pudo iniciar la descarga")

func _process(_d: float) -> void:
	if _bar.visible and _cur.size() > 0:
		var got := _http.get_downloaded_bytes()
		var total := float(maxi(_total_bytes, 1))
		_bar.value = clampf((_done_bytes + got) / total, 0.0, 1.0)
		_sub.text = "%.1f / %.1f MB" % [(_done_bytes + got) / 1048576.0, total / 1048576.0]

func _on_pack(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	var part := "%s/%s.pck.part" % [CONTENT_DIR, _cur.name]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_fail("La descarga se cortó (%d)" % code)
		return
	_say("Verificando…")
	var sha := FileAccess.get_sha256(part)
	if str(_cur.get("sha256", "")) != "" and sha != str(_cur.sha256):
		DirAccess.remove_absolute(part)
		_fail("El archivo descargado no coincide (se descartó)")
		return
	var final := "%s/%s.pck" % [CONTENT_DIR, _cur.name]
	if FileAccess.file_exists(final):
		DirAccess.remove_absolute(final)
	DirAccess.rename_absolute(part, final)
	_installed[str(_cur.name)] = {"version": str(_cur.version), "sha256": sha}
	var f := FileAccess.open(INSTALLED, FileAccess.WRITE)
	f.store_string(JSON.stringify(_installed))
	f.close()
	_done_bytes += int(_cur.get("size", 0))
	_next()

func _fail(msg: String) -> void:
	_bar.visible = false
	_say(msg, "Revisá la conexión y tocá Reintentar (lo ya descargado no se vuelve a bajar).")
	_retry.text = "Reintentar"
	_retry.visible = true

# ---------------------------------------------------------------- montar y arrancar

func _go() -> void:
	var dir := DirAccess.open(CONTENT_DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".pck"):
				ProjectSettings.load_resource_pack("%s/%s" % [CONTENT_DIR, f], false)   # false: no pisa el índice propio de la APK
	_say("Listo")
	get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
