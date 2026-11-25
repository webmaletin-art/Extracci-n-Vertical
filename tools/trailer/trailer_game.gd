class_name TrailerGame
extends Game
## ESCENAS DE TRAILER (sólo para armar animaciones para Blender; no es parte del juego). Un piloto automático hace el recorrido
## en la Torre Alfa con el gameplay real (pistolas → caja con escopeta → escalera → escopeta → fusil → .50 → helicóptero) y
## TrailerExport lo guarda como un GLB con animación (mapa, personajes, armas, miembros, sangre, anatomía, cámara) más los
## sonidos con su segundo. Uso: tools/trailer/export_scenes.sh (ver docs/TRAILER.md).

const FPS := 30.0
var vt := 0.0                         ## segundos de video
var cam_focus_fn: Callable
var cap_layer: CanvasLayer
var cap_title: Label
var cap_sub: Label
var fade: ColorRect
var heli: Node3D
var only := ""                         ## (pruebas) sólo esta escena
var _quit_called := false
var no_map := false                     ## (GLB) la escena no lleva el mapa: se exporta aparte con --only=mapa
var export_glb := ""                   ## si no está vacío: exporta la escena como GLB con animaciones (ver TrailerExport)
const Exporter := preload("res://tools/trailer/trailer_export.gd")   # (tools/ no registra class_name)
var rec

func _ready() -> void:
	Settings.fog_war = false
	Settings.particles = 2
	Settings.xray = 2
	Settings.bullet_time = 1
	Settings.laser = true
	super._ready()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		if a == "--nomap":
			no_map = true
		if a.begins_with("--glb="):
			export_glb = a.substr(6)
	controller.set_process(false)
	controller.set_physics_process(false)
	controller.set_process_input(false)
	controller.set_process_unhandled_input(false)
	hud.touch_mode = true               # controles táctiles a la vista, con la disposición normal del juego
	cam_focus_fn = func(): return player.global_position + Vector3(0, 1.3, 0)
	cap_layer = CanvasLayer.new()
	cap_layer.layer = 20
	add_child(cap_layer)
	cap_title = _label(54, Color(1, 1, 1), 0.30)
	cap_sub = _label(26, Color(1.0, 0.85, 0.35), 0.40)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap_layer.add_child(fade)
	Sfx.log_on = true
	Sfx.event_log.clear()
	Sfx.log_t0 = Engine.get_frames_drawn()
	if export_glb != "":
		TechView.set_mode.call_deferred(0)            # materiales originales (el estilo plano usa shaders que el GLB no puede llevar)
	player.max_health = 500.0
	player.health = 500.0
	_find_heli()
	_run.call_deferred()

func _label(size: int, col: Color, ypos: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.anchor_top = ypos
	l.anchor_bottom = ypos
	l.offset_left = 20
	l.offset_right = -20
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap_layer.add_child(l)
	return l

func _find_heli() -> void:
	for n in tower.find_children("*", "Node3D", true, false):
		if n.get_parent() and n.get_parent().name == "Azotea" and n.get_child_count() > 0 and n.get_child(0).scene_file_path.ends_with("military_helicopter.glb"):
			heli = n
			break

# ------------------------------------------------------------------------------------------------ cámara y overlays

func _process(delta: float) -> void:
	vt += 1.0 / FPS
	super._process(delta)
	if is_instance_valid(player) and player.health < 60.0 and not over:
		player.health = 60.0                       # el piloto automático nunca muere (recibe impactos, no se acaba el video)
	if not camera.override_active:
		# como en el juego, pero el encuadre se corre hacia donde está la acción (entre el jugador y el enemigo)
		var f: Vector3 = cam_focus_fn.call()
		camera.look_offset_x = lerpf(camera.look_offset_x, clampf(f.x - player.global_position.x, -7.0, 7.0), clampf(4.0 / FPS, 0.0, 1.0))
	_mirror_inputs()
	if rec != null:
		rec.capture(vt)

var _press := {}                       ## botón → segundos que sigue iluminado (pulsaciones de un cuadro: recargar, usar, cambiar arma)

## Ilumina un botón táctil un momento: se ve que el piloto «toca» los controles de verdad.
func press(n: String, secs := 0.3) -> void:
	_press[n] = secs

## Los controles táctiles se mueven y se iluminan como si alguien jugara (el trailer muestra que es un juego táctil).
func _mirror_inputs() -> void:
	var inp := player.inp
	var ls := hud.left_stick
	var rs := hud.right_stick
	ls.active = inp.move.length() > 0.05
	ls._center = ls._rest
	ls.value = Vector2(inp.move.x, -inp.move.y)
	ls._knob = ls.value * ls.radius() * 0.8
	ls.queue_redraw()
	rs.value = Vector2(inp.aim.x, -inp.aim.y)
	rs.queue_redraw()
	rs.active = inp.aim.length() > 0.05
	rs._center = rs._rest
	rs._knob = rs.value * rs.radius() * 0.8
	var held := {"fire": inp.fire, "jump": inp.jump_held, "crouch": inp.crouch, "melee": inp.melee, "use": inp.interact_held}
	for n in hud.buttons:
		var t: float = _press.get(n, 0.0)
		_press[n] = maxf(t - 1.0 / FPS, 0.0)
		(hud.buttons[n] as Control).set("pressed", bool(held.get(n, false)) or t > 0.0)
		(hud.buttons[n] as Control).queue_redraw()

func title(t: String, sub := "", secs := 2.5) -> void:
	cap_title.text = t
	cap_sub.text = sub
	cap_title.modulate.a = 1.0
	cap_sub.modulate.a = 1.0
	if secs > 0.0:
		var tw := create_tween()
		tw.tween_interval(secs)
		tw.tween_property(cap_title, "modulate:a", 0.0, 0.5)
		tw.parallel().tween_property(cap_sub, "modulate:a", 0.0, 0.5)

func fade_to(a: float, secs: float) -> void:
	create_tween().tween_property(fade, "color:a", a, secs)

# ------------------------------------------------------------------------------------------------ piloto automático

func wait_s(sec: float) -> void:
	for i in int(sec * FPS):
		await get_tree().process_frame

func put(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.inp.move = Vector2.ZERO
	reveal_all_near(pos)
	camera.look_offset_x = 0.0
	camera.global_position = Vector3(pos.x, pos.y + Settings.cam_height, Settings.camera_distance)
	player.health = 500.0

func walk_to(x: float, speed := 1.0, tol := 0.35, timeout := 10.0) -> void:
	var n := 0
	while absf(player.global_position.x - x) > tol and n < int(timeout * FPS):
		player.inp.move.x = signf(x - player.global_position.x) * speed
		await get_tree().process_frame
		n += 1
	player.inp.move = Vector2.ZERO

func face(dirx: float) -> void:
	player.inp.aim_snap = true
	player.inp.aim = Vector2(signf(dirx), 0.05).normalized()

## Dispara al objetivo hasta que muera o se acabe el tiempo. head = apunta a la cabeza.
func fight(target: Actor, secs: float, head := false, auto := false, on := 3, off := 9) -> void:
	var n := 0
	while is_instance_valid(target) and not target.is_dead() and n < int(secs * FPS):
		var f := player.weapon()
		if f and f.mag <= 0 and not f.reloading:
			player.inp.reload = true
			press("reload", 0.6)
		var pt := target.global_position + Vector3(0, 1.62 if head else 1.2, 0)
		var from := player.global_position + Vector3(0, 1.45, 0)
		player.inp.aim_snap = true
		player.inp.aim = Vector2(pt.x - from.x, pt.y - from.y).normalized()
		player.inp.fire = auto or (n % (on + off)) < on
		await get_tree().process_frame
		n += 1
	player.inp.fire = false

func spawn_enemy(x: float, y: float, char_id: String, weapon_id: String, floor_i: int) -> Actor:
	char_id = "vigia" if int(x) % 2 == 0 else "zapador"      # dos tipos de enemigo: la anatomía del GLB se comparte
	tower._enemy(tower.floors_nodes[floor_i], Vector3(x, y, 0), char_id, weapon_id, floor_i)
	var e: Actor = tower.enemies.back()
	for c in e.get_children():
		if c is BotBrain:
			c.set_physics_process(false)          # los enemigos esperan: el trailer decide cuándo y cómo reciben y devuelven los golpes
	e.facing = -1.0
	e.aim_dir = Vector2(-1, 0)
	e.died.connect(func(info):
		if info.get("shooter") == player:
			_kills += 1)
	bullet_time.watch(e)                       # sus muertes disparan la toma de rayos X como en la partida
	if rec != null:
		rec.add_actor(e, vt)
	return e

## El jugador recibe un impacto escenificado (se sacude, sangra, baja la vida) sin lesiones graves.
func take_hit(dmg := 9.0, from_dir := Vector3.LEFT) -> void:
	var p := player.global_position + Vector3(0, 1.3, 0)
	player.take_damage({"damage": dmg, "type": "punch", "zone": "torso", "point": p, "dir": -from_dir, "force": 0.0})
	if Blood.instance:
		Blood.instance.spray(p, -from_dir, false, false, 1.4)
	Sfx.play("impact_flesh", p, 2.0)

func arm(slot: String, id: String) -> void:
	press("swap", 0.4)
	player.give_weapon(slot, id)
	player.equip(slot)

func target_cam(fn: Callable, _dist := 0.0, _fov := 0.0, _dy := 0.0, _dx := 0.0) -> void:
	cam_focus_fn = fn

func _mid(e: Actor) -> Callable:
	return func():
		if is_instance_valid(e):
			return (player.global_position + e.global_position) * 0.5 + Vector3(0, 1.3, 0)
		return player.global_position + Vector3(0, 1.3, 0)

func _on(name_: String) -> bool:
	return only == "" or name_ in only.split(",")

func _run() -> void:
	await wait_s(0.3)
	if export_glb != "":
		TechView.set_mode(0)                          # materiales originales (los shaders del estilo plano no caben en un GLB)
		await wait_s(0.3)
		var acts: Array = [player]
		for e in tower.enemies:
			if is_instance_valid(e):
				acts.append(e)
		rec = Exporter.new()
		rec.begin(self, acts)
	if only == "mapa":
		await wait_s(1.0)
	if _on("intro"):
		await _intro()
	if _on("pistolas"):
		await _pistolas()
	if _on("caja"):
		await _caja()
	if _on("escalera"):
		await _escalera()
	if _on("escopeta"):
		await _escopeta()
	if _on("fusil"):
		await _fusil()
	if _on("awm"):
		await _awm()
	if _on("extraccion"):
		await _extraccion()
	if _on("final"):
		await _final()
	_finish()

func _finish() -> void:
	if _quit_called:
		return
	_quit_called = true
	if rec != null:
		var base := export_glb
		rec.export_to(ProjectSettings.globalize_path(base))
		var hf := FileAccess.open(base.get_basename() + "_disparos.json", FileAccess.WRITE)
		hf.store_string(JSON.stringify(rec.hits, "\t"))
		hf.close()
	var f := FileAccess.open((export_glb.get_basename() + "_sonidos.json") if export_glb != "" else "user://trailer_sonidos.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"fps": FPS, "seconds": vt, "events": Sfx.event_log}, "\t"))
	f.close()
	print("TRAILER_LISTO ", vt, " s · sonidos ", Sfx.event_log.size())
	get_tree().quit()

# ------------------------------------------------------------------------------------------------ escenas

func _intro() -> void:
	hud.visible = false
	var roof_y: float = tower.data.roof.y
	var hx: float = float(tower.data.roof.extraction[0])
	player.global_position = Vector3(hx - 10.0, roof_y + 0.05, 0)
	reveal_all_near(player.global_position)
	camera.override_active = true
	camera.override_fov = 55.0
	camera.global_position = Vector3(hx - 14.0, roof_y + 2.0, 15.0)
	camera.override_pos = camera.global_position
	camera.override_look = Vector3(hx, roof_y + 4.0, 0)
	fade.color.a = 1.0
	fade_to(0.0, 1.0)
	title("EXTRACCIÓN VERTICAL", "Shooter táctico de extracción", 4.5)
	await wait_s(2.0)
	camera.override_pos = Vector3(hx + 3.0, roof_y + 3.0, 12.0)
	camera.override_look = Vector3(hx, roof_y + 4.0, 0)
	await wait_s(3.5)
	camera.override_active = false
	camera.fov = camera.base_fov
	hud.visible = true

func _pistolas() -> void:
	arm("secondary", "browning")
	player.weapons.erase("primary")
	player.equip("secondary")
	put(Vector3(4.0, 0.05, 0))
	face(1.0)
	target_cam(func(): return player.global_position + Vector3(2.5, 1.3, 0), 8.5, 58.0, 0.6)
	title("PISTOLAS", "Empezás con lo justo", 2.5)
	await wait_s(1.0)
	var e1 := spawn_enemy(11.5, 0.05, "vigia", "browning", 0)
	var e2 := spawn_enemy(14.5, 0.05, "zapador", "browning", 0)
	await walk_to(6.5, 0.7)
	target_cam(_mid(e1), 9.5, 58.0, 0.6)
	await fight(e1, 6.0, true, false, 3, 10)
	await wait_s(0.8)
	await fight(e2, 7.0, false, false, 3, 9)
	await wait_s(1.5)

func _caja() -> void:
	put(Vector3(4.2, 0.05, 0))
	player.equip("secondary")
	face(1.0)
	title("BOTÍN", "Rompé cajas y encontrá armas", 3.0)
	target_cam(func(): return player.global_position + Vector3(1.8, 1.2, 0), 7.0, 56.0, 0.5)
	await walk_to(5.4, 0.6)
	press("use", 0.8)
	await wait_s(0.5)
	player.inp.melee = true
	press("melee", 0.5)
	await wait_s(0.5)
	for d in get_tree().get_nodes_in_group("destructibles"):
		if is_instance_valid(d) and absf((d as Node3D).global_position.x - 6.2) < 0.6 and absf((d as Node3D).global_position.y) < 1.0:
			(d as Destructible).apply_damage(999.0, (d as Node3D).global_position, Vector3.RIGHT, "melee", player)
			break
	await wait_s(0.6)
	arm("primary", "remington")
	hud.toast("ESCOPETA REMINGTON encontrada")
	title("¡ESCOPETA!", "Remington · 12 perdigones", 2.5)
	await wait_s(2.5)

func _escalera() -> void:
	put(Vector3(8.0, 0.05, 0))
	target_cam(func(): return player.global_position + Vector3(0, 2.2, 0), 9.0, 62.0, 0.5)
	title("ESCALÁ LA TORRE", "5 pisos · cada uno peor que el anterior", 3.0)
	await wait_s(0.5)
	player.inp.move = Vector2(0, 1)
	var n := 0
	while player.global_position.y < 4.3 and n < int(9.0 * FPS):
		await get_tree().process_frame
		n += 1
	player.inp.move = Vector2.ZERO
	await wait_s(0.5)

## Dispara a una parte del cuerpo (hueso) de un personaje, aunque ya esté en el piso.
func shoot_bone(target: Actor, bone: String, secs: float, on := 2, off := 12) -> void:
	var area: Area3D = null
	for h in target.hitboxes:
		if str(h.get_meta("bone", "")) == "mixamorig_" + bone:
			area = h
	if area == null:
		return
	var n := 0
	while is_instance_valid(target) and n < int(secs * FPS):
		var pt := area.global_position
		var from := player.global_position + Vector3(0, 1.45, 0)
		player.inp.aim_snap = true
		player.inp.aim = Vector2(pt.x - from.x, pt.y - from.y).normalized()
		player.inp.fire = (n % (on + off)) < on
		var f := player.weapon()
		if f and f.mag <= 0 and not f.reloading:
			player.inp.reload = true
			press("reload", 0.6)
		await get_tree().process_frame
		n += 1
	player.inp.fire = false

func _escopeta() -> void:
	arm("primary", "remington")
	put(Vector3(10.0, 4.55, 0))
	face(1.0)
	title("ESCOPETA", "A quemarropa: huesos, sangre y miembros", 2.5)
	target_cam(func(): return player.global_position + Vector3(2.0, 1.3, 0), 8.0, 58.0, 0.6)
	var es: Array[Actor] = []
	es.append(spawn_enemy(15.0, 4.55, "mortero", "am4", 1))
	es.append(spawn_enemy(19.0, 4.55, "vigia", "mp5", 1))
	es.append(spawn_enemy(23.0, 4.55, "fantasma", "browning", 1))
	await wait_s(0.6)
	var bones := ["LeftForeArm", "RightUpLeg", "LeftLeg"]
	for i in es.size():
		var e := es[i]
		await walk_to(e.global_position.x - 2.4, 0.7, 0.5, 6.0)
		target_cam(_mid(e), 8.5, 58.0, 0.6)
		await fight(e, 6.0, false, false, 2, 12)
		await wait_s(0.8)
		await shoot_bone(e, bones[i], 3.0)           # el cuerpo muerto sigue recibiendo: se arranca el miembro
		await wait_s(1.4)
	await wait_s(1.5)

func _fusil() -> void:
	arm("primary", "am4")
	put(Vector3(8.0, 9.05, 0))
	face(1.0)
	title("FUSILES", "Ráfagas, cobertura y sangre", 2.5)
	target_cam(func(): return player.global_position + Vector3(3.0, 1.3, 0), 10.0, 58.0, 0.7)
	var es: Array[Actor] = []
	for x in [16.0, 19.0, 23.0, 26.0]:
		es.append(spawn_enemy(x, 9.05, ["zapador", "mortero", "doc", "vigia"][es.size()], ["mp5", "am4", "browning", "am4"][es.size()], 2))
	await wait_s(0.4)
	for e in es:
		target_cam(_mid(e), 10.0, 58.0, 0.7)
		await fight(e, 6.0, false, true)
		await wait_s(0.4)
	await wait_s(1.5)

func _awm() -> void:
	arm("primary", "awm")
	put(Vector3(8.0, 13.55, 0))
	face(1.0)
	title("CALIBRE .50", "Atraviesa y arranca", 2.5)
	target_cam(func(): return player.global_position + Vector3(4.0, 1.3, 0), 11.0, 58.0, 0.7)
	var es: Array[Actor] = []
	for x in [17.0, 22.0, 27.0]:
		es.append(spawn_enemy(x, 13.55, ["vigia", "doc", "fantasma"][es.size()], "am4", 3))
	await wait_s(0.4)
	for e in es:
		target_cam(_mid(e), 11.5, 58.0, 0.7)
		await fight(e, 7.0, es.find(e) == 1, false, 2, 22)
		await wait_s(0.6)
	await wait_s(1.5)

func _extraccion() -> void:
	arm("primary", "awm")
	var roof_y: float = tower.data.roof.y
	var hx: float = float(tower.data.roof.extraction[0])
	put(Vector3(hx - 14.0, roof_y + 0.05, 0))
	face(1.0)
	title("EXTRACCIÓN", "Llegá al helicóptero con vida", 3.0)
	target_cam(func(): return player.global_position + Vector3(4.0, 2.0, 0), 12.0, 60.0, 1.0)
	await walk_to(hx, 1.0, 0.5, 14.0)
	await wait_s(2.0)

func _final() -> void:
	hud.visible = false
	title("EXTRACCIÓN VERTICAL", "Ya disponible para Android", 0.0)
	await wait_s(4.0)
	fade_to(1.0, 1.0)
	await wait_s(1.2)
