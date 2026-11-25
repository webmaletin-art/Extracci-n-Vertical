extends Node
## Sonido (autoload «Sfx»): efectos 3D con un grupo fijo de reproductores reutilizables, ambiente en bucle y reverberación
## según el lugar (habitación cerrada / cráter abierto). Cada sonido 3D también puede generar ruido para la IA (NoiseBus).
##
## Los archivos están en res://assets/sounds/<nombre>.(ogg|wav). Variantes: <nombre>_0, _1… se eligen al azar.
## Para reemplazar un sonido por una grabación mejor basta dejar un archivo con el mismo nombre.

const DIR := "res://assets/sounds/"
const POOL_3D := 28
const POOL_2D := 8

var _streams := {}            ## nombre → Array[AudioStream] (variantes)
var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _i3 := 0
var _i2 := 0
var _amb := {}                ## nombre → AudioStreamPlayer (ambiente)
var _reverb: AudioEffectReverb
var _room_target := 0.4
var _wet_target := 0.12
var room_closed := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_buses()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 6.0
		p.max_distance = 60.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_p3.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_p2.append(p)

func _make_buses() -> void:
	for bus_name in ["SFX", "Ambiente"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		_reverb = AudioEffectReverb.new()
		_reverb.room_size = 0.4
		_reverb.damping = 0.6
		_reverb.wet = 0.12
		_reverb.dry = 1.0
		AudioServer.add_bus_effect(sfx, _reverb)
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -1.0
		AudioServer.add_bus_effect(sfx, lim)
	else:
		_reverb = AudioServer.get_bus_effect(sfx, 0) as AudioEffectReverb

func _process(delta: float) -> void:
	if _reverb:
		_reverb.room_size = lerpf(_reverb.room_size, _room_target, delta * 2.0)
		_reverb.wet = lerpf(_reverb.wet, _wet_target, delta * 2.0)

## Lugar donde está el oyente: size 0..1 (cuarto chico → cráter enorme), closed = paredes duras alrededor.
var _lowpass: AudioEffectLowPassFilter
## Tímpanos rotos (explosión cerca): todo suena apagado unos segundos.
func set_deaf(seconds: float) -> void:
	var master := AudioServer.get_bus_index("Master")
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(master, _lowpass)
	_lowpass.cutoff_hz = lerpf(20000.0, 450.0, clampf(seconds / 3.0, 0.0, 1.0))

func set_room(size: float, closed: bool) -> void:
	room_closed = closed
	_room_target = clampf(size, 0.05, 1.0)
	_wet_target = 0.22 if closed else 0.08

func has(sound: String) -> bool:
	return not _variants(sound).is_empty()

func _variants(sound: String) -> Array:
	if _streams.has(sound):
		return _streams[sound]
	var out := []
	for ext in ["ogg", "wav", "mp3"]:
		var p: String = DIR + sound + "." + ext
		if ResourceLoader.exists(p):
			out.append(load(p))
	for i in 8:
		for ext in ["ogg", "wav", "mp3"]:
			var p: String = "%s%s_%d.%s" % [DIR, sound, i, ext]
			if ResourceLoader.exists(p):
				out.append(load(p))
	_streams[sound] = out
	return out

func _pick(sound: String) -> AudioStream:
	var v := _variants(sound)
	if v.is_empty():
		return null
	return v[randi() % v.size()]

## Sonido en el mundo. noise > 0 avisa a la IA (radio en metros del ruido).
## Registro de sonidos (sólo para grabar trailers: tools/trailer): cada sonido con su momento (segundos de video), archivo,
## posición, volumen y tono. Con eso se arma el CSV de tiempos y la mezcla de audio.
var log_on := false
var event_log: Array = []

func _log(sound: String, s: AudioStream, pos: Variant, volume_db: float, pitch: float) -> void:
	event_log.append({"t": snappedf(float(Engine.get_frames_drawn()) / 30.0, 0.001), "sound": sound, "file": s.resource_path if s else "",
		"pos": pos, "db": volume_db, "pitch": pitch})

func play(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, noise := 0.0, source: Node = null) -> void:
	if noise > 0.0:
		NoiseBus.emit_noise(pos, noise, source)
	var s := _pick(sound)
	if s == null:
		return
	if log_on:
		_log(sound, s, pos, volume_db, pitch * _time_pitch())
	var p := _p3[_i3]
	_i3 = (_i3 + 1) % POOL_3D
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch * randf_range(0.95, 1.05) * _time_pitch(), 0.05)
	p.play()

## Sonido de interfaz o del propio jugador (sin posición).
func play_ui(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var s := _pick(sound)
	if s == null:
		return
	if log_on:
		_log(sound, s, null, volume_db, pitch)
	var p := _p2[_i2]
	_i2 = (_i2 + 1) % POOL_2D
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

## En cámara lenta los sonidos bajan de tono (sensación de tiempo estirado), con un piso para que se entiendan.
func _time_pitch() -> float:
	return clampf(lerpf(0.55, 1.0, Engine.time_scale), 0.55, 1.0)

func ambient(sound: String, volume_db := -10.0) -> void:
	if _amb.has(sound):
		return
	var s := _pick(sound)
	if s == null:
		return
	if log_on:
		_log(sound + " (ambiente, en bucle)", s, null, volume_db, 1.0)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = (s as AudioStreamWAV).data.size()
	var p := AudioStreamPlayer.new()
	p.bus = "Ambiente"
	p.stream = s
	p.volume_db = volume_db
	add_child(p)
	p.play()
	_amb[sound] = p

func ambient_volume(sound: String, volume_db: float) -> void:
	if _amb.has(sound):
		(_amb[sound] as AudioStreamPlayer).volume_db = volume_db

func stop_ambient() -> void:
	for k in _amb:
		(_amb[k] as AudioStreamPlayer).queue_free()
	_amb.clear()
