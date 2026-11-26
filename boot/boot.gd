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
const PROBE := "res://assets/lined/characters/alfa.scn"

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
	if ResourceLoader.exists(PROBE) and not OS.has_feature("android") and OS.get_environment("EV_FORZAR_DESCARGA") == "":
		_go()
		return
	_apk = int(_read_json("res://boot/local_version.json").get("apk", 0))
	_installed = _read_json(INSTALLED)
	DirAccess.make_dir_recursive_absolute(CONTENT_DIR)
	_check()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.97, 0.97, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# imagen de carga: la escena de la portada (tirador, municiones atravesando el cuerpo, letrero), todo en línea
	var pic := TextureRect.new()
	pic.texture = load("res://boot/carga.png")
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(pic)
	var band := ColorRect.new()
	band.color = Color(1, 1, 1, 0.82)
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -150
	add_child(band)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	v.offset_top = -140
	v.offset_left = 120
	v.offset_right = -120
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.07, 0.07, 0.09))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(600, 26)
	_bar.visible = false
	v.add_child(_bar)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 16)
	_sub.add_theme_color_override("font_color", Color(0.35, 0.35, 0.38))
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
	if OS.get_environment("EV_MANIFEST_URL") != "":
		url = OS.get_environment("EV_MANIFEST_URL")      # (pruebas) servidor local
	if url == "":
		_finish_offline()
		return
	_http.download_file = ""
	_http.timeout = 30.0
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

## Los paquetes se bajan por PARTES de 16 MB (pedido con Range): cada parte se guarda aparte, se reintenta sola si se
## corta o se traba, y al volver a abrir el juego se sigue desde la última parte completa. Sin límite de tiempo total.
const SEG := 16 * 1048576
const MAX_TRIES := 6
var _seg := 0
var _tries := 0
var _stall_t := 0.0
var _last_bytes := -1

func _seg_path(k: int) -> String:
	return "%s/%s.seg%03d" % [CONTENT_DIR, _cur.name, k]

func _segs() -> int:
	return maxi(1, ceili(float(_cur.get("size", SEG)) / SEG))

func _next() -> void:
	if _queue.is_empty():
		_go()
		return
	_cur = _queue.pop_front()
	_seg = 0
	_tries = 0
	# partes ya bajadas en una vez anterior (del mismo archivo): se saltean
	while _seg < _segs() and FileAccess.file_exists(_seg_path(_seg)) and _seg_ok(_seg):
		_seg += 1
	_say("Descargando %s" % str(_cur.get("desc", _cur.name)), "%.0f MB · una sola vez; después sólo se baja lo que cambie" % (float(_cur.get("size", 0)) / 1048576.0))
	_bar.visible = true
	_bar.max_value = 1.0
	_request_seg()

func _seg_len(k: int) -> int:
	return mini(SEG, int(_cur.get("size", 0)) - k * SEG)

func _seg_ok(k: int) -> bool:
	var f := FileAccess.open(_seg_path(k), FileAccess.READ)
	if f == null:
		return false
	var ok := int(f.get_length()) == _seg_len(k)
	f.close()
	var tag := "%s/%s.ver" % [CONTENT_DIR, _cur.name]
	return ok and FileAccess.file_exists(tag) and FileAccess.get_file_as_string(tag) == str(_cur.get("sha256", ""))

func _request_seg() -> void:
	if _seg >= _segs():
		_assemble()
		return
	var tag := FileAccess.open("%s/%s.ver" % [CONTENT_DIR, _cur.name], FileAccess.WRITE)
	tag.store_string(str(_cur.get("sha256", "")))
	tag.close()
	var a := _seg * SEG
	var b := a + _seg_len(_seg) - 1
	_http.cancel_request()
	_http.timeout = 0.0                         # sin límite: lo controla el vigilante de traba (_process)
	_http.download_file = _seg_path(_seg)
	_stall_t = 0.0
	_last_bytes = -1
	_http.request_completed.connect(_on_seg, CONNECT_ONE_SHOT)
	if _http.request(str(_cur.url), ["Range: bytes=%d-%d" % [a, b]]) != OK:
		_http.request_completed.disconnect(_on_seg)
		_retry_seg("no se pudo iniciar")

func _process(d: float) -> void:
	if _bar.visible and _cur.size() > 0:
		var got := _http.get_downloaded_bytes()
		var total := float(maxi(_total_bytes, 1))
		var now := _done_bytes + _seg * SEG + got
		_bar.value = clampf(now / total, 0.0, 1.0)
		_sub.text = "%.1f / %.1f MB%s" % [now / 1048576.0, total / 1048576.0, ("  · reintento %d" % _tries) if _tries > 0 else ""]
		# vigilante: si no llega nada en 30 s, se corta y se reintenta esa parte
		if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			if got == _last_bytes:
				_stall_t += d
				if _stall_t > 30.0:
					_http.cancel_request()
					if _http.request_completed.is_connected(_on_seg):
						_http.request_completed.disconnect(_on_seg)
					_retry_seg("sin datos 30 s")
			else:
				_stall_t = 0.0
				_last_bytes = got

func _on_seg(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or not (code == 206 or code == 200):
		_retry_seg("error %d/%d" % [result, code])
		return
	if code == 200:
		# el servidor ignoró el Range y mandó el archivo entero: listo de una vez
		var final_part := "%s/%s.pck.part" % [CONTENT_DIR, _cur.name]
		DirAccess.rename_absolute(_seg_path(_seg), final_part)
		_verify_and_install(final_part)
		return
	_tries = 0
	_seg += 1
	_request_seg()

func _retry_seg(why: String) -> void:
	_tries += 1
	if _tries > MAX_TRIES:
		_fail("La descarga se cortó (%s)" % why)
		return
	await get_tree().create_timer(minf(2.0 * _tries, 10.0)).timeout
	_request_seg()

## Une las partes en el .pck, lo verifica y lo instala.
func _assemble() -> void:
	_say("Uniendo y verificando…")
	await get_tree().process_frame
	var part := "%s/%s.pck.part" % [CONTENT_DIR, _cur.name]
	var out := FileAccess.open(part, FileAccess.WRITE)
	for k in _segs():
		var f := FileAccess.open(_seg_path(k), FileAccess.READ)
		if f == null:
			out.close()
			_fail("Falta una parte de la descarga")
			return
		while f.get_position() < f.get_length():
			out.store_buffer(f.get_buffer(4 * 1048576))
		f.close()
	out.close()
	_verify_and_install(part)

func _verify_and_install(part: String) -> void:
	var sha := FileAccess.get_sha256(part)
	for k in _segs():
		DirAccess.remove_absolute(_seg_path(k))
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
	_say(msg, "Revisá la conexión y tocá Reintentar: sigue desde la última parte completa.")
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
