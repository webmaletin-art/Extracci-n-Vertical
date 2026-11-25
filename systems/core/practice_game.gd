class_name PracticeGame
extends Node3D
## MODO PRÁCTICA: un campo de tiro con maniquíes para ver el daño, las municiones y los rebotes sin riesgo.
##  * Armas y municiones elegibles (cada munición cambia daño, penetración, rebote y velocidad: la «trazadora lenta»
##    deja ver el vuelo de la bala).
##  * Maniquí a la distancia que se quiera, de pie o agachado, mortal o inmortal (acumula heridas), con reaparición.
##  * «Disparar a»: apunta solo a una zona (ojo, cabeza, cuello, corazón, estómago, testículos, rodilla, mano, muslo) y
##    dispara una vez; la cámara sigue la bala y se acerca a la herida con los rayos X, como en una muerte.
##  * Chapas de metal en ángulo, pared de hormigón y piso para probar rebotes.
##  * Cámara lenta fija y grabación de cuadros (user://grabaciones/<fecha>/cuadro_00001.jpg, 30 por segundo) para armar
##    un video (ver docs/MODO_PRACTICA.md).
## Usa los mismos sistemas que la partida (Actor, Ballistics, BulletTime, Anatomía, Sangre); no hay mapa ni IA.

signal match_over(result: Dictionary)

var WEAPONS: Array = []          ## todas las armas de data/weapons.json, ordenadas por clase y precio
const AMMO := {
	"fmj": {"name": "Camisa completa (estándar)", "dmg": 1.0, "pen": 1.0, "ric": 1.0, "speed": 1.0},
	"jhp": {"name": "Punta hueca (se deforma, daña más)", "dmg": 1.3, "pen": 0.45, "ric": 0.5, "speed": 1.0},
	"ap": {"name": "Perforante (atraviesa)", "dmg": 0.85, "pen": 2.6, "ric": 0.6, "speed": 1.08},
	"rico": {"name": "Rebotadora (prueba de rebotes)", "dmg": 1.0, "pen": 0.5, "ric": 3.0, "speed": 1.0},
	"slow": {"name": "Trazadora lenta (ver el vuelo)", "dmg": 1.0, "pen": 1.0, "ric": 1.0, "speed": 0.12},
}
## zona → [grupo anatómico (comienzo del nombre), desplazamiento vertical extra (m)]
const ZONES := {
	"libre": ["", 0.0], "ojo": ["ojo", 0.0], "cabeza": ["cráneo", 0.0], "cuello": ["arterias y venas de cuello", 0.0],
	"corazón": ["corazón", 0.0], "estómago": ["estómago", 0.0], "testículos": ["testículos", 0.0], "rodilla": ["rótula der", 0.0],
	"mano": ["huesos de la mano der", 0.0], "muslo": ["arterias y venas de muslo der", 0.0], "hígado": ["hígado", 0.0],
	"costilla": ["costillas", 0.0], "columna": ["vértebras cervicales", 0.0], "mandíbula": ["mandíbula", 0.0],
	"clavícula": ["clavícula", 0.0], "hombro": ["húmero", 0.08], "pene": ["testículos", 0.0],
	"espalda": ["vértebras torácicas", 0.0], "nuca": ["vértebras cervicales", 0.03],
}
const ARENA_W := 44.0
const BACK_ZONES := ["espalda", "nuca"]       ## se dispara desde atrás: el maniquí se da vuelta

var player: Actor
var controller: PlayerController
var camera: SideCamera
var hud: Hud
var hud_layer: CanvasLayer
var ballistics: Ballistics
var bullet_time: BulletTime
var dummy: Actor
var panel: PanelContainer
var ui: CanvasLayer

var weapon_id := "am4"
var ammo_id := "fmj"
var distance := 6.0
var dummy_char := "vigia"
var crouched := false
var immortal := false
var auto_respawn := true
var inspect := true
var slow := 1.0
var _busy := false
var _saved_bt := 1
var _recording := false
var _rec_dir := ""
var _rec_n := 0
var _rec_acc := 0.0
var _rec_thread: Thread
var _rec_queue: Array = []
var _rec_mutex := Mutex.new()
var _rec_run := false
var _rec_label: Label
var _info: Label
var _respawn_t := -1.0
var _plates: Array[Node3D] = []

func _ready() -> void:
	PlayerController.setup_input_map()
	WEAPONS = Firearm.all_stats().keys()
	_saved_bt = Settings.bullet_time
	Settings.bullet_time = 2           # toma de cerca de cada herida
	Fx.attach(self)
	ballistics = Ballistics.new()
	ballistics.name = "Ballistics"
	add_child(ballistics)
	_build_arena()
	player = Actor.new()
	player.name = "Jugador"
	player.character_id = Settings.character_id if CharacterModel.find(Settings.character_id).id == Settings.character_id else "alfa"
	player.is_player = true
	player.team = 0
	player.max_health = 1000000.0
	player.health = 1000000.0
	add_child(player)
	player.global_position = Vector3(10.0, 0.05, 0.0)
	camera = SideCamera.new()
	camera.target = player
	camera.bounds = Rect2(0, -1, ARENA_W, 12.0)
	add_child(camera)
	camera.make_current()
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	hud = Hud.new()
	hud.player = player
	hud.camera = camera
	hud.game = self
	hud_layer.add_child(hud)
	for k in ["objective", "loot", "floor"]:
		(hud._lbl[k] as Label).visible = false
		(hud._lbl[k] as Label).text = ""
	hud.pause_pressed.connect(_exit)
	controller = PlayerController.new()
	controller.actor = player
	controller.hud = hud
	controller.camera = camera
	add_child(controller)
	bullet_time = BulletTime.new()
	bullet_time.add_to_group("bullet_time")
	add_child(bullet_time)
	# práctica usa EXACTAMENTE la misma cámara de muerte que la partida (plan maestro §17-18)
	bullet_time.setup(camera, player)
	bullet_time.injury_report.connect(func(v, lines): hud.show_injuries(v, lines))
	_equip()
	AnatomyBody.warm(dummy_char)
	_spawn_dummy()
	_build_ui()
	Sfx.ambient("amb_wind", -26.0)

func _exit_tree() -> void:
	Settings.bullet_time = _saved_bt
	_stop_recording()
	Engine.time_scale = 1.0

# ------------------------------------------------------------------------------------------------ escenario

func _build_arena() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.82, 0.84, 0.9)
	e.ambient_light_energy = 0.75
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)
	sun.light_energy = 0.9
	add_child(sun)
	var concrete := _mat(Color(0.34, 0.35, 0.37))
	var floor_m := _mat(Color(0.22, 0.23, 0.25))
	var metal := _mat(Color(0.5, 0.54, 0.6), 0.85, 0.35)
	var wood := _mat(Color(0.45, 0.32, 0.2))
	_box(Vector3(ARENA_W * 0.5, -0.25, -0.3), Vector3(ARENA_W, 0.5, 4.0), "concrete", floor_m)
	_box(Vector3(ARENA_W * 0.5, 5.0, -1.4), Vector3(ARENA_W, 12.0, 0.4), "concrete", concrete)      # pared del fondo (rebote)
	_box(Vector3(-0.2, 5.0, -0.3), Vector3(0.4, 12.0, 4.0), "concrete", concrete)
	_box(Vector3(ARENA_W + 0.2, 5.0, -0.3), Vector3(0.4, 12.0, 4.0), "metal", metal)
	_box(Vector3(ARENA_W * 0.5, 11.2, -0.3), Vector3(ARENA_W, 0.4, 4.0), "concrete", concrete)
	# marcas de distancia en el piso cada 5 m
	for i in range(1, int(ARENA_W / 5.0)):
		var l := Label3D.new()
		l.text = "%d m" % (i * 5)
		l.font_size = 48
		l.modulate = Color(0.9, 0.85, 0.4, 0.8)
		l.position = Vector3(i * 5.0, 0.02, 0.9)
		l.rotation_degrees = Vector3(-90, 0, 0)
		add_child(l)
	# obstáculos para rebotes: chapas de metal en ángulo, bloque de hormigón, caja de madera
	var p1 := _box(Vector3(30.0, 1.4, 0.0), Vector3(0.12, 2.8, 1.6), "metal", metal, Basis(Vector3.BACK, deg_to_rad(28.0)))
	var p2 := _box(Vector3(34.0, 0.9, 0.0), Vector3(0.12, 1.8, 1.6), "metal", metal, Basis(Vector3.BACK, deg_to_rad(-18.0)))
	var p3 := _box(Vector3(26.0, 0.07, 0.0), Vector3(3.0, 0.14, 1.6), "metal", metal, Basis(Vector3.BACK, deg_to_rad(-12.0)))
	_plates = [p1, p2, p3]
	_box(Vector3(38.0, 0.6, 0.0), Vector3(1.2, 1.2, 1.2), "concrete", concrete)
	_box(Vector3(41.0, 0.45, 0.0), Vector3(0.9, 0.9, 0.9), "wood", wood)

func _mat(c: Color, metallic := 0.0, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m

func _box(center: Vector3, size: Vector3, surface: String, mat: Material, basis := Basis.IDENTITY) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("surface", surface)
	sb.transform = Transform3D(basis, center)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)
	add_child(sb)
	return sb

# ------------------------------------------------------------------------------------------------ armas y maniquí

func _equip() -> void:
	var slot := "secondary" if Firearm.all_stats()[weapon_id].hold == "pistol" else "primary"
	for s in ["primary", "secondary"]:
		if player.weapons.has(s):
			(player.weapons[s] as Node).queue_free()
			player.weapons.erase(s)
	var w := player.give_weapon(slot, weapon_id)
	player.equip(slot)
	_apply_ammo(w)

func _apply_ammo(w: Firearm) -> void:
	if w == null:
		return
	var base: Dictionary = Firearm.all_stats()[weapon_id]
	var a: Dictionary = AMMO[ammo_id]
	w.stats = base.duplicate()                     # no tocar los datos compartidos del arma
	w.stats.damage = float(base.damage) * float(a.dmg)
	w.stats.penetration = float(base.penetration) * float(a.pen)
	w.stats.ricochet = minf(float(base.ricochet) * float(a.ric), 0.95)
	w.stats.speed = float(base.speed) * float(a.speed)
	w.mag = int(w.stats.mag)
	w.reserve = 9999

func _spawn_dummy() -> void:
	if dummy and is_instance_valid(dummy):
		dummy.queue_free()
	dummy = Actor.new()
	dummy.name = "Maniqui"
	dummy.character_id = dummy_char
	dummy.team = 1
	dummy.max_health = 1000000.0 if immortal else 100.0
	add_child(dummy)
	dummy.global_position = Vector3(player.global_position.x + distance, 0.05, 0.0)
	dummy.facing = -1.0
	dummy.aim_dir = Vector2(-1, 0)
	dummy.add_to_group("enemies")
	dummy.inp.crouch = crouched
	for a in dummy.hitboxes:
		if str(a.get_meta("zone", "")) == "head":
			((a.get_child(0) as CollisionShape3D).shape as SphereShape3D).radius = 0.17     # práctica: la cabeza se acierta con holgura (los ojos quedan adentro)
		elif str(a.get_meta("zone", "")) == "pelvis":
			var cap := (a.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
			if cap:
				cap.radius = 0.2                       # práctica: la ingle (testículos) entra en la pelvis
	bullet_time.watch(dummy)
	dummy.died.connect(func(_i):
		if auto_respawn:
			_respawn_t = 3.5)
	_respawn_t = -1.0

func _process(delta: float) -> void:
	# misma cámara que la partida (distancia, altura, suavizado… de Configuración); sólo se corre el encuadre para ver
	# también al maniquí
	camera.look_offset_x = clampf(distance * 0.5 - 1.0, 0.0, 4.0)
	if not _busy and (Input.is_action_pressed("fire") or hud.hold.fire):
		bullet_time.focus_label = ""            # disparo libre: la cámara vuelve a enfocar la herida más grave
	if _respawn_t > 0.0:
		_respawn_t -= delta / maxf(Engine.time_scale, 0.05)
		if _respawn_t <= 0.0:
			_spawn_dummy()
	if dummy and is_instance_valid(dummy):
		dummy.inp.crouch = crouched
	if _info and player:
		var w := player.weapon()
		_info.text = "%s · %s%s\nManiquí a %.0f m · %s" % [
			Firearm.all_stats()[weapon_id].name, AMMO[ammo_id].name, ("  [%d/%d]" % [w.mag, int(w.stats.mag)]) if w else "",
			distance, "inmortal" if immortal else "mortal"]
	if w_valid():
		var w2 := player.weapon()
		if w2.mag <= 2:
			w2.mag = int(w2.stats.mag)
	_record(delta)

func w_valid() -> bool:
	return player != null and is_instance_valid(player) and player.weapon() != null

# ------------------------------------------------------------------------------------------------ tiro dirigido

## Apunta sola a una zona del maniquí y dispara una vez (la cámara sigue la bala y muestra la herida).
func shoot_zone(zone: String) -> void:
	if _busy or dummy == null or not is_instance_valid(dummy) or dummy.is_dead() or not w_valid():
		return
	_busy = true
	controller.set_physics_process(false)
	player.inp = ActorInput.new()
	# el tirador se pone frente al maniquí a la distancia elegida, de cara a él
	player.global_position = Vector3(dummy.global_position.x - distance, 0.05, 0.0)
	player.velocity = Vector3.ZERO
	player.facing = 1.0
	# disparos por la espalda: el maniquí mira para el otro lado
	dummy.facing = 1.0 if zone in BACK_ZONES else -1.0
	dummy.aim_dir = Vector2(dummy.facing, 0)
	await _frames(30 if zone in BACK_ZONES else 6)
	var target := _zone_point(zone)
	if zone != "libre":
		# la bala viaja en el plano z = 0: se corre el modelo del maniquí para que la zona elegida quede justo en ese plano
		for k in 3:
			dummy.plane_shift.z -= target.z
			await _frames(10)
			target = _zone_point(zone)
	bullet_time.focus_label = str((ZONES.get(zone, ZONES["libre"]) as Array)[0])
	var w := player.weapon()
	for i in 20:
		var mz := w.muzzle_world()
		player.aim_dir = Vector2(target.x - mz.x, target.y - mz.y).normalized()
		await get_tree().physics_frame
	var spread_was: float = float(w.stats.spread)
	w.stats.spread = 0.0                         # tiro dirigido: sin dispersión (va exactamente a la zona)
	player.inp.fire = true
	await get_tree().physics_frame
	player.inp.fire = false
	w.stats.spread = spread_was
	await _frames(30)
	controller.set_physics_process(true)
	_busy = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Punto del mundo (centro del grupo anatómico) al que hay que apuntar.
func _zone_point(zone: String) -> Vector3:
	var anat := AnatomyBody.for_actor(dummy)
	var spec: Array = ZONES.get(zone, ZONES["libre"])
	var chest := dummy.global_position + Vector3(0, 1.35, 0)
	if str(spec[0]) == "" or not anat.available:
		return chest
	# entre los grupos con ese nombre (izq / der) el que queda más cerca del plano de tiro z = 0
	var best := Vector3.INF
	for n in anat.groups:
		if not str(anat.groups[n].label).begins_with(str(spec[0])):
			continue
		var c := anat.bind_to_world(n, anat.groups[n].center)
		if best == Vector3.INF or absf(c.z) < absf(best.z):
			best = c
	if best == Vector3.INF:
		return chest
	return best + Vector3(0, float(spec[1]), 0)

# ------------------------------------------------------------------------------------------------ interfaz

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	var toggle := Button.new()
	toggle.text = "PRÁCTICA ▸"
	toggle.add_theme_font_size_override("font_size", 22)
	toggle.position = Vector2(560, 6)
	toggle.size = Vector2(190, 44)
	ui.add_child(toggle)
	_info = Label.new()
	_info.position = Vector2(80, 8)
	_info.add_theme_font_size_override("font_size", 20)
	_info.add_theme_color_override("font_color", Color(0.95, 0.9, 0.6))
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 6)
	ui.add_child(_info)
	_rec_label = Label.new()
	_rec_label.position = Vector2(80, 76)
	_rec_label.add_theme_font_size_override("font_size", 22)
	_rec_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	_rec_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_rec_label.add_theme_constant_override("outline_size", 6)
	ui.add_child(_rec_label)
	panel = PanelContainer.new()
	panel.position = Vector2(900, 54)
	panel.custom_minimum_size = Vector2(360, 0)
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.88)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	ui.add_child(panel)
	toggle.pressed.connect(func():
		panel.visible = not panel.visible
		toggle.text = "PRÁCTICA ▾" if panel.visible else "PRÁCTICA ▸")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_option(v, "Arma", WEAPONS.map(func(k): return Firearm.all_stats()[k].name), WEAPONS.find(weapon_id), func(i):
		weapon_id = WEAPONS[i]
		_equip())
	var ammo_keys := AMMO.keys()
	_option(v, "Munición", ammo_keys.map(func(k): return AMMO[k].name), ammo_keys.find(ammo_id), func(i):
		ammo_id = ammo_keys[i]
		_apply_ammo(player.weapon()))
	var chars: Array = []
	for c in CharacterModel.all():
		chars.append(str(c.id))
	_option(v, "Maniquí", chars, maxi(chars.find(dummy_char), 0), func(i):
		dummy_char = chars[i]
		_spawn_dummy())
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var dl := Label.new()
	dl.text = "Dist. %d m" % int(distance)
	dl.custom_minimum_size = Vector2(120, 0)
	hb.add_child(dl)
	var sl := HSlider.new()
	sl.min_value = 3
	sl.max_value = 30
	sl.step = 1
	sl.value = distance
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(150, 36)
	sl.value_changed.connect(func(x):
		distance = x
		dl.text = "Dist. %d m" % int(x)
		if dummy and is_instance_valid(dummy):
			dummy.global_position.x = player.global_position.x + distance)
	hb.add_child(sl)
	var hs := HBoxContainer.new()
	v.add_child(hs)
	var sl2 := Label.new()
	sl2.text = "Veloc. ×%.2f" % slow
	sl2.custom_minimum_size = Vector2(120, 0)
	hs.add_child(sl2)
	var sl3 := HSlider.new()
	sl3.min_value = 0.05
	sl3.max_value = 1.0
	sl3.step = 0.05
	sl3.value = slow
	sl3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl3.custom_minimum_size = Vector2(150, 36)
	sl3.value_changed.connect(func(x):
		slow = x
		sl2.text = "Veloc. ×%.2f" % x
		Engine.time_scale = x)
	hs.add_child(sl3)
	var zone_keys := ZONES.keys().filter(func(k): return k != "libre")
	var zrow := _option(v, "Disparar a", zone_keys, 0, func(_i): pass)
	var fire := Button.new()
	fire.text = "DISPARAR ▶"
	fire.custom_minimum_size = Vector2(0, 52)
	fire.add_theme_font_size_override("font_size", 24)
	fire.pressed.connect(func(): shoot_zone(str(zone_keys[zrow.selected])))
	v.add_child(fire)
	_check(v, "Maniquí agachado", func(on): crouched = on)
	_check(v, "Maniquí inmortal (acumula heridas)", func(on):
		immortal = on
		_spawn_dummy())
	_check(v, "Reaparece solo al morir", func(on): auto_respawn = on, true)
	_check(v, "Toma de cerca de cada herida", func(on): Settings.bullet_time = 2 if on else 1, true)
	var row := HBoxContainer.new()
	v.add_child(row)
	for d in [["NUEVO", func(): _spawn_dummy()], ["GRABAR ●", null], ["VOLVER A LA LOBBY", func(): _exit()]]:
		var b := Button.new()
		b.text = d[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 18)
		if d[1] == null:
			b.pressed.connect(func():
				if _recording:
					_stop_recording()
					b.text = "GRABAR ●"
				else:
					_start_recording()
					b.text = "PARAR ■")
		else:
			b.pressed.connect(d[1])
		row.add_child(b)
	# configuración REAL del juego (la misma que usa la partida): se aplica en vivo y se guarda
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	for d in [["CÁMARA Y CONTROLES", func(): _open_settings()], ["GUARDAR", func():
			Settings.save_settings()
			hud.toast("Configuración guardada: se usa también en la partida")],
			["RESTABLECER", func():
			Settings.reset_camera_aim()
			hud.toast("Cámara y apuntado restablecidos")]]:
		var b2 := Button.new()
		b2.text = d[0]
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.custom_minimum_size = Vector2(0, 46)
		b2.add_theme_font_size_override("font_size", 15)
		b2.pressed.connect(d[1])
		row2.add_child(b2)
	for c in panel.find_children("*", "Label", true, false):
		(c as Label).add_theme_font_size_override("font_size", 18)

func _option(parent: Control, title: String, items: Array, selected: int, cb: Callable) -> OptionButton:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(110, 0)
	hb.add_child(l)
	var ob := OptionButton.new()
	ob.clip_text = true
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(0, 44)
	ob.add_theme_font_size_override("font_size", 18)
	for it in items:
		ob.add_item(str(it))
	ob.selected = clampi(selected, 0, maxi(items.size() - 1, 0))
	ob.item_selected.connect(cb)
	hb.add_child(ob)
	return ob

func _check(parent: Control, text: String, cb: Callable, on := false) -> void:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 17)
	c.toggled.connect(cb)
	parent.add_child(c)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_exit()

func _open_settings() -> void:
	var sm := SettingsMenu.new()
	sm.probe_available = false
	ui.add_child(sm)
	sm.closed.connect(sm.queue_free)

func _exit() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	match_over.emit({"result": "practica"})

# ------------------------------------------------------------------------------------------------ grabación

func _start_recording() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_rec_dir = "user://grabaciones/%s" % stamp
	DirAccess.make_dir_recursive_absolute(_rec_dir)
	_rec_n = 0
	_rec_acc = 0.0
	_recording = true
	_rec_run = true
	_rec_thread = Thread.new()
	_rec_thread.start(_rec_worker)

func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	_rec_run = false
	if _rec_thread:
		_rec_thread.wait_to_finish()
		_rec_thread = null
	if _rec_label:
		_rec_label.text = "Grabado: %d cuadros en %s" % [_rec_n, ProjectSettings.globalize_path(_rec_dir)]

func _record(delta: float) -> void:
	if not _recording:
		return
	_rec_acc += delta / maxf(Engine.time_scale, 0.001)          # tiempo real: la cámara lenta queda en el video
	_rec_label.text = "● REC  %d cuadros" % _rec_n
	if _rec_acc < 1.0 / 30.0:
		return
	_rec_acc = fmod(_rec_acc, 1.0 / 30.0)
	var img := get_viewport().get_texture().get_image()
	_rec_n += 1
	_rec_mutex.lock()
	_rec_queue.append([_rec_dir + "/cuadro_%05d.jpg" % _rec_n, img])
	if _rec_queue.size() > 90:
		_rec_queue.pop_front()                                  # si el disco no da abasto, se pierden cuadros viejos
	_rec_mutex.unlock()

func _rec_worker() -> void:
	while true:
		_rec_mutex.lock()
		var item = _rec_queue.pop_front() if not _rec_queue.is_empty() else null
		_rec_mutex.unlock()
		if item == null:
			if not _rec_run:
				return
			OS.delay_msec(8)
			continue
		(item[1] as Image).save_jpg(item[0], 0.88)
