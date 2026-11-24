extends Node
## Configuración del jugador (autoload «Settings»): calidad gráfica, efectos, audio, controles y cámara lenta.
## Se guarda en user://settings.cfg. Los sistemas leen los valores y escuchan «changed» para reaplicarlos.
##
## Niveles: 0 = BAJA, 1 = MEDIA, 2 = ALTA. preset() fija todo de una vez; cualquier cambio suelto pasa a «Personalizada».

signal changed

const PATH := "user://settings.cfg"
const LEVELS := ["Baja", "Media", "Alta"]
const PRESETS := ["Baja", "Media", "Alta", "Personalizada"]

## ---------- gráficos ----------
var quality_preset := 1             ## 0..2, 3 = personalizada
var render_scale := 1.0             ## resolución 3D relativa a 720p de alto (1.0 = 720p, 0.75 = 540p, 1.25 = 900p); el HUD siempre a resolución completa
var shadows := 1                    ## 0 sin sombras · 1 sombra simple (círculo bajo cada personaje, casi gratis) · 2 sombras reales de la luna sobre personajes
var lights := 1                     ## luces REALES sobre personajes y objetos: 0 ninguna (el escenario ya trae la luz pintada) · 1 dos · 2 cuatro (siguen al jugador)
var msaa := 0                       ## 0 · 1 = 2x · 2 = 4x
var fxaa := false
var particles := 1                  ## chispas, polvo, sangre, fragmentos
var smoke := 1                      ## humo de granadas, explosiones y ambiente
var explosions := 1                 ## destello, bola de fuego, onda, escombros
var decor := 1                      ## densidad de decoración (props que no se usan para jugar)
var background := 1                 ## 0 fondo plano · 1 fachadas lejanas · 2 fachadas + niebla con profundidad
var view_floors := 1                ## pisos vecinos visibles además del actual (0..2): oclusión por sector
var fps_target := 30                ## 30 o 60
var xray := 2                       ## rayos X en la cámara lenta: 0 apagado · 1 sólo huesos · 2 huesos, órganos y vasos
var bullet_time := 1                ## 0 nunca · 1 tiros decisivos · 2 siempre que el disparo hiere
var camera_shake := 1.0             ## 0..1
var blood := true                   ## la sangre está siempre (decisión de diseño); queda por compatibilidad
var laser := true                   ## láser del arma del jugador
var laser_enemies := true           ## láser de los enemigos (delata su puntería)
## ---------- audio ----------
var vol_master := 0.9
var vol_sfx := 1.0
var vol_ambient := 0.7
## ---------- controles ----------
var joystick_size := 1.0            ## escala de los joysticks virtuales
var aim_sensitivity := 1.0
var auto_fire_stick := false        ## dispara al llevar el joystick derecho al borde (además del botón)
var show_fps := false
var character_id := "alfa"

## Lo que cambia cada nivel de calidad (BAJA / MEDIA / ALTA).
const PRESET_VALUES := {
	"render_scale": [0.75, 1.0, 1.25],
	"shadows": [1, 1, 2],
	"lights": [0, 1, 2],
	"msaa": [0, 0, 1],
	"fxaa": [false, true, false],
	"particles": [0, 1, 2],
	"smoke": [0, 1, 2],
	"explosions": [0, 1, 2],
	"decor": [0, 1, 2],
	"background": [0, 1, 2],
	"view_floors": [0, 1, 2],
	"fps_target": [30, 30, 60],
	"xray": [1, 2, 2],
}

## Multiplicadores que usan los efectos (cantidad de partículas, vida del humo…).
static func level_mult(level: int) -> float:
	return [0.35, 0.7, 1.0][clampi(level, 0, 2)]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()

func preset(level: int) -> void:
	level = clampi(level, 0, 2)
	for k in PRESET_VALUES:
		set(k, PRESET_VALUES[k][level])
	quality_preset = level
	apply()
	save_settings()

## Cambia un valor suelto (desde el menú). Los valores de calidad marcan el preset como personalizado.
func set_value(key: String, value) -> void:
	set(key, value)
	if PRESET_VALUES.has(key):
		quality_preset = _detect_preset()
	apply()
	save_settings()

func _detect_preset() -> int:
	for level in 3:
		var ok := true
		for k in PRESET_VALUES:
			if get(k) != PRESET_VALUES[k][level]:
				ok = false
				break
		if ok:
			return level
	return 3

## Detecta un punto de partida razonable la primera vez (teléfono con poca memoria de video → BAJA).
func autodetect() -> int:
	var name := RenderingServer.get_video_adapter_name().to_lower()
	var mobile := OS.has_feature("mobile")
	if not mobile:
		return 2
	for weak in ["mali-4", "mali-t", "adreno (tm) 3", "adreno (tm) 50", "powervr", "mali-g5"]:
		if weak in name:
			return 0
	return 1

## Escala 3D real: se calcula contra el alto de la pantalla para que 1.0 sea siempre 720p (un teléfono de 1080×2400 no
## dibuja 2,5 veces más píxeles de los que hacen falta). Nunca agranda por encima de la resolución nativa.
func effective_scale() -> float:
	var h := float(maxi(DisplayServer.window_get_size().y, 1))
	return clampf(720.0 * render_scale / h, 0.3, 1.0)

func apply() -> void:
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = effective_scale()
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][clampi(msaa, 0, 2)]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	Engine.max_fps = fps_target
	Engine.physics_ticks_per_second = 60
	_apply_audio()
	changed.emit()

func _apply_audio() -> void:
	var set_db := func(bus_name: String, v: float) -> void:
		var i := AudioServer.get_bus_index(bus_name)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	set_db.call("Master", vol_master)
	set_db.call("SFX", vol_sfx)
	set_db.call("Ambiente", vol_ambient)

const KEYS := ["quality_preset", "render_scale", "shadows", "lights", "msaa", "fxaa", "particles", "smoke", "explosions",
	"decor", "background", "view_floors", "fps_target", "xray", "bullet_time", "camera_shake", "blood", "laser", "laser_enemies", "vol_master",
	"vol_sfx", "vol_ambient", "joystick_size", "aim_sensitivity", "auto_fire_stick", "show_fps", "character_id"]

func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in KEYS:
		cf.set_value("ajustes", k, get(k))
	cf.save(PATH)

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		var lv := autodetect()
		for k in PRESET_VALUES:
			set(k, PRESET_VALUES[k][lv])
		quality_preset = lv
		return
	for k in KEYS:
		if cf.has_section_key("ajustes", k):
			set(k, cf.get_value("ajustes", k))
