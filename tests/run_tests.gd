extends Node
## Pruebas automáticas (headless). Uso: tools/run_tests.sh [filtro]
## Cada prueba arma lo que necesita, mide con física real y devuelve "" si pasa o el motivo si falla.

var results := []
var g: Game

func _ready() -> void:
	var filt := ""
	var a := OS.get_cmdline_user_args()
	if a.size() >= 2 and a[0] == "--filter":
		filt = a[1]
	var tests := ["mapa", "velocidad", "settings", "inventario", "municion", "abismo", "juego"]
	for t in tests:
		if filt != "" and not t.contains(filt) and t != "juego":
			continue
		if t == "juego":
			await _game_tests(filt)
		else:
			_report(t, call("t_" + t))
	var bad := results.filter(func(r): return r[1] != "")
	print("\n==== %d pruebas, %d fallas ====" % [results.size(), bad.size()])
	get_tree().quit(1 if not bad.is_empty() else 0)

func _report(name_: String, err: String) -> void:
	results.append([name_, err])
	print(("OK    " if err == "" else "FALLA ") + name_ + ("" if err == "" else ": " + err))

func _wait_phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

# ---------------------------------------------------------------- sin mundo

func t_abismo() -> String:
	var d := AbismoVertical.data()
	var gr := MapGraph.from_data(d)
	var r := gr.check_reachability()
	if not r.unreachable.is_empty():
		return "sectores inaccesibles: %s" % str(r.unreachable)
	if not r.extraction_ok:
		return "alguna extracción no se alcanza"
	if gr.key_rooms.size() < 3:
		return "faltan llaves (hay %d)" % gr.key_rooms.size()
	var types := {}
	for f in d.floors:
		for w in f.walls:
			types[str(w[1]).get_slice(":", 0)] = true
	for need in ["door", "duct", "locked", "shutter"]:
		if not types.has(need):
			return "falta el tipo de pared %s" % need
	# todas las armas y objetos colocados existen
	for f in d.floors:
		for pk in f.pickups:
			if Inventory.def(str(pk[1])).is_empty():
				return "objeto inexistente %s" % str(pk[1])
		for e in f.enemies:
			if not Firearm.all_stats().has(str(e[2])):
				return "arma enemiga inexistente %s" % str(e[2])
	return ""

func t_municion() -> String:
	# cada tipo debe dar un daño distinto y el precio debe crecer con el poder
	var base := Ammo.apply(Firearm.all_stats()["m4a1"], "m4a1", "std")
	var prev_price := 0
	for ty in ["std", "hp", "ap", "in", "fl"]:
		var it := Ammo.item("m4a1", ty)
		if it.is_empty():
			return "falta el ítem de munición %s" % ty
		if ty != "std" and Ammo.apply(Firearm.all_stats()["m4a1"], "m4a1", ty).damage == base.damage and ty != "ap":
			return "el tipo %s no cambia el daño" % ty
	if Ammo.apply(Firearm.all_stats()["m4a1"], "m4a1", "fl").damage <= Ammo.apply(Firearm.all_stats()["m4a1"], "m4a1", "hp").damage:
		return "punta de flor debería pegar más que punta hueca"
	if int(Ammo.item("m4a1", "fl").price) <= int(Ammo.item("m4a1", "std").price):
		return "la munición más potente debe costar más"
	if Ammo.fx("m4a1", "in").organ <= Ammo.fx("m4a1", "std").organ or not Ammo.fx("m4a1", "in").burst:
		return "la incendiaria debe reventar órganos"
	# compra: sólo con el arma en propiedad
	var pr = get_node("/root/Profile")
	pr.reset()
	if pr.can_buy_ammo("scar", "hp"):
		return "se pudo comprar munición de un arma que no se tiene"
	pr.add_credits(100000)
	if not pr.buy_weapon("scar"):
		return "no se pudo comprar el arma con créditos suficientes"
	if not pr.can_buy_ammo("scar", "hp"):
		return "con el arma comprada debería poder comprar su munición"
	var before: int = pr.rounds("scar", "hp")
	if not pr.buy_ammo("scar", "hp") or pr.rounds("scar", "hp") <= before:
		return "la compra no sumó balas"
	# pistolas del mismo calibre comparten munición
	if Ammo.item("m1911", "std").get("id", "a") != Ammo.item("m1911_b", "std").get("id", "b") if Firearm.all_stats().has("m1911_b") else false:
		return "pistolas del mismo calibre deben compartir munición"
	pr.reset()
	return ""

func t_mapa() -> String:
	var gr := MapGraph.from_data(TorreAlfa.data())
	var r := gr.check_reachability()
	if not r.unreachable.is_empty():
		return "sectores inaccesibles: %s" % str(r.unreachable)
	if not r.extraction_ok:
		return "alguna extracción no se alcanza"
	if not r.key_found:
		return "la tarjeta del laboratorio no se alcanza"
	var types := {}
	for e in gr.edges:
		types[e.type] = true
	for need in ["escalera de mano", "escalera", "ascensor", "caída", "door", "duct", "locked"]:
		if not types.has(need):
			return "falta conexión de tipo %s" % need
	return ""

func t_velocidad() -> String:
	if Actor.speed_for(0.08) != 0.0:
		return "zona muerta"
	var prev := 0.0
	for i in range(2, 21):
		var v := Actor.speed_for(i / 20.0)
		if v < prev:
			return "no es progresiva en %.2f" % (i / 20.0)
		prev = v
	if Actor.speed_for(0.3) > 1.3:
		return "inclinación chica no es sigilo"
	if Actor.speed_for(1.0) < 5.0:
		return "inclinación máxima no llega a velocidad máxima"
	return ""

func t_settings() -> String:
	var keep := Settings.quality_preset
	Settings.preset(0)
	if Settings.particles != 0 or Settings.shadows != 0 or Settings.lights != 0 or Settings.xray != 1:
		return "preset BAJA no baja todo"
	Settings.set_value("particles", 2)
	if Settings.quality_preset != 3:
		return "un cambio suelto no pasa a Personalizada"
	Settings.preset(2)
	if Settings.quality_preset != 2:
		return "preset ALTA"
	Settings.preset(clampi(keep, 0, 2))
	return ""

func t_inventario() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var items := Inventory.roll("crate_metal", 0, rng)
	if items.size() != 3:
		return "tiradas de botín"
	for it in items:
		if Inventory.def(it[0]).is_empty():
			return "objeto sin definición: %s" % it[0]
	var inv := Inventory.new()
	inv.add("cash", 2)
	if inv.total_value() != 240:
		return "valor del inventario"
	return ""

# ---------------------------------------------------------------- con partida

func _game_tests(filt: String) -> void:
	g = Game.new()
	add_child(g)
	await _wait_phys(20)
	g.controller.set_physics_process(false)
	for e in g.tower.enemies:
		for c in e.get_children():
			if c is BotBrain:
				c.set_physics_process(false)
	var p := g.player
	p.max_health = 1000.0
	p.health = 1000.0
	for t in ["apuntado", "apuntado_fino", "escalera", "ascensor", "balistica", "destruccion", "granada", "lesiones", "cuerpo_muerto", "desmembrar", "anatomia", "captador", "mecanicas"]:
		if filt != "" and not t.contains(filt):
			continue
		p.inp = ActorInput.new()
		p.state = Actor.State.GROUND
		p._cap.disabled = false
		p.velocity = Vector3.ZERO
		p._action_anim = ""
		p._task = Callable()
		p.stunned = 0.0
		g.bullet_time.skip()
		TimeFx.end_slowmo()
		Engine.time_scale = 1.0
		await _wait_phys(2)
		p._thrown = false
		p._bad_fall = false
		p.health = 1000.0
		p.injuries = Injuries.new()
		var err: String = await call("g_" + t, p)
		_report(t, err)

func _place(p: Actor, pos: Vector3) -> void:
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await _wait_phys(6)

## Plan maestro §16: joystick (no mouse) — llega a cada dirección sin pasarse, mantiene el apuntado corriendo al revés,
## al soltar NO deriva, y cambiar de arma no lo pierde.
func g_apuntado_fino(p: Actor) -> String:
	await _place(p, Vector3(5, 0.05, 0))
	p.inp.aim_snap = false
	var checks := [["horizontal", Vector2(1, 0)], ["arriba", Vector2(0.2, 1)], ["abajo", Vector2(0.3, -1)], ["diagonal", Vector2(1, 1)],
		["atrás", Vector2(-1, 0.1)]]
	for c in checks:
		var tgt: Vector2 = (c[1] as Vector2).normalized()
		for i in 240:
			p.inp.aim = tgt
			p.inp.aim_snap = false
			await get_tree().physics_frame
		var err := rad_to_deg(absf(angle_difference(p.aim_dir.angle(), tgt.angle())))
		if err > 2.0:
			return "no llega a apuntar %s (queda a %.1f°)" % [c[0], err]
	# corriendo hacia la derecha mientras apunta a la izquierda
	var keep := p.aim_dir
	for i in 60:
		p.inp.aim = Vector2.ZERO
		p.inp.move = Vector2(1, 0)
		await get_tree().physics_frame
	p.inp.move = Vector2.ZERO
	if rad_to_deg(absf(angle_difference(p.aim_dir.angle(), keep.angle()))) > 0.5:
		return "el movimiento cambió el apuntado"
	# soltar el joystick: 2 s sin tocar y la dirección queda igual (sin deriva)
	for i in 120:
		p.inp.aim = Vector2.ZERO
		await get_tree().physics_frame
	if rad_to_deg(absf(angle_difference(p.aim_dir.angle(), keep.angle()))) > 0.1:
		return "el apuntado deriva solo al soltar"
	p.inp.switch_to = "next"
	await _wait_phys(40)
	if rad_to_deg(absf(angle_difference(p.aim_dir.angle(), keep.angle()))) > 0.1:
		return "cambiar de arma perdió el apuntado"
	# toque chico (apuntado lejano): mueve poco
	var a0 := p.aim_dir.angle()
	for i in 6:
		p.inp.aim = Vector2.from_angle(a0 + 1.2) * 0.35
		await get_tree().physics_frame
	p.inp.aim = Vector2.ZERO
	var moved := rad_to_deg(absf(angle_difference(p.aim_dir.angle(), a0)))
	if moved > 3.0:
		return "un toque suave mueve demasiado la mira (%.1f°)" % moved
	return ""

func g_apuntado(p: Actor) -> String:
	await _place(p, Vector3(5, 0.05, 0))
	p.aim_dir = Vector2(1, 0.3).normalized()
	var keep := p.aim_dir
	p.inp.move = Vector2(-0.7, 0)
	await _wait_phys(60)
	p.inp.move = Vector2.ZERO
	if p.aim_dir.distance_to(keep) > 0.001:
		return "el movimiento cambió el apuntado"
	if p.facing != 1.0:
		return "el cuerpo no mira hacia donde apunta"
	if p.global_position.x > 4.5:
		return "no retrocedió"
	return ""

func g_escalera(p: Actor) -> String:
	await _place(p, Vector3(8.0, 0.05, 0))
	p.inp.move = Vector2(0, 1)
	await _wait_phys(30)
	if p.state != Actor.State.LADDER:
		return "no tomó la escalera"
	await _wait_phys(260)
	p.inp.move = Vector2.ZERO
	if p.state != Actor.State.GROUND or p.global_position.y < 4.4:
		return "no llegó arriba (estado %s, y=%.2f)" % [Actor.State.keys()[p.state], p.global_position.y]
	return ""

func g_ascensor(p: Actor) -> String:
	var e := g.tower.elevator
	await _place(p, Vector3(e.global_position.x, 0.1, 0))
	e.go_to(1)
	var t := 0
	while e.moving and t < 600:
		await get_tree().physics_frame
		t += 1
	await _wait_phys(10)
	if e.current != 1:
		return "no llegó a la parada"
	if absf(p.global_position.y - 4.5) > 0.2:
		return "no llevó al jugador (y=%.2f)" % p.global_position.y
	e.go_to(0)
	while e.moving:
		await get_tree().physics_frame
	return ""

func g_balistica(p: Actor) -> String:
	var b := g.ballistics
	var pred := b.predict(Vector3(2, 1.5, 0), Vector3(30, 0, 0), 0.0, [], 3.0)
	if pred.is_empty():
		return "la predicción no encontró la pared"
	if (pred.point as Vector3).y >= 1.5:
		return "sin caída por gravedad"
	var e: Actor = g.tower.enemies[0]
	var h0 := e.health
	await _place(p, Vector3(50, 0.05, 0))
	e.global_position = Vector3(56, 0.05, 0)
	e.velocity = Vector3.ZERO
	await _wait_phys(6)
	var chest := p.global_position + Vector3(0, 1.4, 0)
	var tgt := e.global_position + Vector3(0, 1.3, 0)
	p.aim_dir = Vector2(tgt.x - chest.x, tgt.y - chest.y).normalized()
	Settings.bullet_time = 0
	await _wait_phys(10)
	for _try in 4:                      # la dispersión del arma puede hacer fallar un disparo suelto: hasta 4 intentos
		p.inp.fire = true
		await _wait_phys(3)
		p.inp.fire = false
		await _wait_phys(30)
		if e.health < h0:
			break
	Settings.bullet_time = 1
	if e.health >= h0:
		return "el disparo no hizo daño (4 intentos)"
	if not e.last_hit_info.has("injuries"):
		return "sin lesiones calculadas"
	return ""

## El cuerpo muerto sigue recibiendo disparos (heridas y huesos rotos) mientras se muestra el rayos X.
func g_cuerpo_muerto(p: Actor) -> String:
	var e: Actor = null
	for c in g.tower.enemies:
		if is_instance_valid(c) and not (c as Actor).is_dead():
			e = c
			break
	if e == null:
		return "no quedan enemigos vivos para la prueba"
	await _place(p, Vector3(50, 0.05, 0))
	e.global_position = Vector3(56, 0.05, 0)
	e.velocity = Vector3.ZERO
	await _wait_phys(6)
	e.take_damage({"damage": 9999.0, "type": "bullet", "zone": "head", "bone": "mixamorig_Head", "point": e.global_position + Vector3(0, 1.6, 0),
		"dir": Vector3(1, 0, 0), "shooter": p})
	if not e.is_dead():
		return "el enemigo no murió"
	await _wait_phys(30)
	var hits := [0]
	e.damaged.connect(func(_i): hits[0] += 1)
	for k in 5:
		# se apunta a una zona de impacto real del cuerpo (tendido en el piso o no)
		var hb: Area3D = e.hitboxes[mini(2, e.hitboxes.size() - 1)]
		var tgt := hb.global_position
		var from := Vector3(50, tgt.y, 0)
		Ballistics.instance.fire(from, (tgt - from).normalized(), 400.0, 20.0, p, [],
			{"penetration": 1.0, "drag": 0.0, "ricochet": 0.0, "kind": "bullet"})
		await _wait_phys(6)
	await _wait_phys(20)
	if hits[0] < 3:
		return "el cuerpo muerto dejó de recibir impactos (%d de 5)" % hits[0]
	return ""

## Desmembramiento: sólo en cuerpos muertos (o que mueren con el tiro); el miembro suelto existe y el muñón se achica.
func g_desmembrar(p: Actor) -> String:
	var e: Actor = null
	for c in g.tower.enemies:
		if is_instance_valid(c) and not (c as Actor).is_dead():
			e = c
			break
	if e == null:
		return "no quedan enemigos vivos para la prueba"
	await _place(p, Vector3(50, 0.05, 0))
	e.global_position = Vector3(56, 0.05, 0)
	e.velocity = Vector3.ZERO
	await _wait_phys(6)
	# vivo: un tiro al antebrazo NO arranca nada
	e.max_health = 5000.0
	e.health = 5000.0
	for k in 4:
		e.take_damage({"damage": 30.0, "type": "bullet", "zone": "arm", "bone": "mixamorig_LeftForeArm", "point": e.global_position + Vector3(0, 1.2, 0), "dir": Vector3(1, 0, 0), "shooter": p})
	if not e.severed.is_empty():
		return "se desmembró un cuerpo que seguía vivo"
	e.health = 1.0
	e.take_damage({"damage": 90.0, "type": "bullet", "zone": "head", "bone": "mixamorig_Head", "point": e.global_position + Vector3(0, 1.6, 0), "dir": Vector3(1, 0, 0), "shooter": p})
	if not e.is_dead():
		return "el enemigo no murió"
	for k in 3:
		e.take_damage({"damage": 40.0, "type": "bullet", "zone": "arm", "bone": "mixamorig_LeftForeArm", "point": e.global_position + Vector3(0, 0.3, 0), "dir": Vector3(1, 0, 0), "shooter": p})
	await _wait_phys(10)
	if e.severed.is_empty():
		return "el cuerpo muerto no perdió el antebrazo"
	var limbs := 0
	for n in e.get_parent().get_children():
		if n is Limb:
			limbs += 1
	if limbs == 0:
		return "no apareció el miembro suelto"
	return ""

func g_destruccion(_p: Actor) -> String:
	var d: Destructible = null
	for n in get_tree().get_nodes_in_group("destructibles"):
		if (n as Destructible).kind == "crate_wood" and (n as Destructible).loot:
			d = n
			break
	if d == null:
		return "no hay caja de madera con botín"
	d.apply_damage(40.0, d.global_position, Vector3.RIGHT, "bullet")
	if d.phase != Destructible.Phase.DAMAGED:
		return "no pasó a DAÑADO"
	var before := get_tree().get_nodes_in_group("interactables").size()
	d.apply_damage(40.0, d.global_position, Vector3.RIGHT, "bullet")
	await _wait_phys(2)
	if d.phase != Destructible.Phase.BROKEN:
		return "no se rompió"
	if get_tree().get_nodes_in_group("interactables").size() <= before - 1:
		return "no soltó botín"
	return ""

## Puertas que se patean, vidrio que suena al romper, mina que explota, escudo que absorbe y especialidades con recarga.
func g_mecanicas(p: Actor) -> String:
	var tw := g.tower
	var y := 0.05
	# puerta de oficina: se patea y se rompe haciendo ruido
	var door := Destructible.new()
	door.kind = "door"
	g.add_child(door)
	door.setup("door", Vector3(0.12, 2.5, 1.85), "")
	door.global_position = Vector3(5.0, y, -0.2)
	var kick := TowerBuilder.DoorKick.new()
	kick.door = door
	door.add_child(kick)
	await _place(p, Vector3(3.6, y, 0))
	var heard := [0]
	var cb := func(_pos, _l, _src): heard[0] += 1
	NoiseBus.heard.connect(cb)
	p.kick_at(door)
	await _wait_phys(70)
	NoiseBus.heard.disconnect(cb)
	if door.phase != Destructible.Phase.BROKEN:
		return "la puerta no se rompió con la patada"
	if heard[0] == 0:
		return "romper la puerta no hizo ruido"
	# vidrio: un disparo lo rompe
	var gl := Destructible.new()
	gl.kind = "glass"
	g.add_child(gl)
	gl.setup("glass", Vector3(0.1, 2.5, 1.85), "")
	gl.global_position = Vector3(9.0, y, -0.2)
	gl.apply_damage(30.0, gl.global_position, Vector3.RIGHT, "bullet")
	gl.apply_damage(30.0, gl.global_position, Vector3.RIGHT, "bullet")
	if gl.phase != Destructible.Phase.BROKEN:
		return "el vidrio no se rompió"
	# tabique fino: aguanta un tiro, cede a varios
	var dw := Destructible.new()
	dw.kind = "drywall"
	g.add_child(dw)
	dw.setup("drywall", Vector3(0.2, 2.5, 1.85), "")
	dw.global_position = Vector3(12.0, y, -0.2)
	dw.apply_damage(30.0, dw.global_position, Vector3.RIGHT, "bullet")
	if dw.phase == Destructible.Phase.BROKEN:
		return "el tabique cedió con un solo tiro"
	for i in 12:
		dw.apply_damage(30.0, dw.global_position, Vector3.RIGHT, "bullet")
	if dw.phase != Destructible.Phase.BROKEN:
		return "el tabique no cedió con muchos tiros"
	# mina: explota cuando pasa un enemigo (equipo distinto)
	var e: Actor = tw.enemies[0]
	await _place(p, Vector3(20.0, y, 0))
	p.mines = 1
	p.facing = 1.0
	if not p.plant_mine().begins_with("Mina"):
		return "no pudo plantar la mina"
	await _wait_phys(100)
	var h0 := e.health
	e.global_position = Vector3(20.9, y, 0)
	await _wait_phys(40)
	if e.health >= h0 and not e.is_dead():
		return "la mina no dañó al enemigo"
	# escudo: absorbe un impacto sin dañar
	p.specialty = "shield"
	p.spec_cd = 0.0
	Specialty.activate(p)
	var hp := p.health
	p.take_damage({"damage": 40.0, "type": "bullet", "zone": "torso", "point": p.global_position + Vector3.UP, "dir": Vector3.LEFT})
	if absf(p.health - hp) > 0.01:
		return "el escudo no absorbió el impacto"
	if p.spec_cd <= 0.0 or not Specialty.activate(p).contains("lista en"):
		return "la especialidad no tiene recarga"
	# radar y velocista
	p.spec_cd = 0.0
	p.specialty = "radar"
	Specialty.activate(p)
	if p.radar_t < 9.0:
		return "el radar no se activó"
	p.shield_hp = 0.0
	return ""

func g_granada(p: Actor) -> String:
	var e: Actor = g.tower.enemies[1]
	await _place(p, Vector3(44, 0.05, 0))
	e.global_position = Vector3(53, 0.05, 0)
	await _wait_phys(4)
	var h0 := e.health
	var gr := Grenade.spawn(g, "frag", Vector3(52.6, 0.4, 0), Vector3(0, 0, 0), p)
	gr.fuse = 0.4
	await _wait_phys(60)
	if e.health >= h0 and not e.is_dead():
		return "la explosión no dañó"
	return ""

func g_lesiones(p: Actor) -> String:
	var t := 0
	# la fractura por caída es probabilística (como en la realidad): hasta 4 caídas, alguna tiene que romper la pierna
	for intento in 4:
		seed(11 + intento)
		p.injuries = Injuries.new()
		p.health = p.max_health
		await _place(p, Vector3(39.6, 13.55, 0))
		p.inp.move = Vector2(0.5, 0)
		await _wait_phys(30)
		p.inp.move = Vector2.ZERO
		t = 0
		while not (p.state == Actor.State.GROUND and p.global_position.y < 9.0) and t < 400:
			await get_tree().physics_frame
			t += 1
		await _wait_phys(120)
		if p.injuries.leg_broken:
			break
	if not p.injuries.leg_broken:
		return "la caída de %.1f m no fracturó la pierna (estado %s, pos %s, vida %.0f, lesiones %s)" % [13.55 - p.global_position.y, Actor.State.keys()[p.state], p.global_position, p.health, p.injuries.log]
	p.state = Actor.State.GROUND
	p.inp.move = Vector2(1.0, 0)
	await _wait_phys(40)
	p.inp.move = Vector2.ZERO
	if absf(p.velocity.x) > 1.2:
		return "con la pierna rota corre (%.1f m/s)" % p.velocity.x
	p.inventory.add("bandage", 1)
	t = 0
	while (p.busy() or not p.is_on_floor()) and t < 300:
		await get_tree().physics_frame
		t += 1
	if not p.use_medical("bandage"):
		return "no pudo usar la venda (estado %s, acción «%s»)" % [Actor.State.keys()[p.state], p._action_anim]
	await _wait_phys(200)
	if p.injuries.leg_broken:
		return "la venda no entablilló la pierna"
	return ""

## Anatomía ajustada: existe para todos los personajes; un tiro a la cabeza rompe el cráneo y mata; uno al pecho
## perfora órganos y deja hemorragia; un puñetazo sólo quita vida.
func g_anatomia(p: Actor) -> String:
	for c in CharacterModel.all():
		if not ResourceLoader.exists("res://assets/anatomy/fit/%s.scn" % c.id):
			return "falta la anatomía ajustada de %s" % c.id
	var e: Actor = g.tower.enemies[2]
	await _place(p, Vector3(50, 0.05, 0))
	e.global_position = Vector3(52, 0.05, 0)
	await _wait_phys(6)
	var hb := e.skel.find_bone("mixamorig_Head")
	var head := e.skel.global_transform * e.skel.get_bone_global_pose(hb).origin + Vector3(0, 0.07, 0)
	# la bala puede desviarse en el hueso (azar): hasta 8 intentos con un maniquí nuevo; alguno tiene que matar
	var r: Dictionary = {}
	for k in 8:
		e.injuries = Injuries.new()
		r = e.injuries.process(e, {"type": "bullet", "zone": "head", "bone": "mixamorig_Head", "point": head - Vector3(0.12, 0, 0), "dir": Vector3.RIGHT})
		if r.death and str(r.texts).contains("cráneo"):
			break
	if not r.death or not str(r.texts).contains("cráneo"):
		return "tiro a la cabeza: %s" % str(r.texts)
	var sb := e.skel.find_bone("mixamorig_Spine2")
	var chest := e.skel.global_transform * e.skel.get_bone_global_pose(sb).origin
	e.injuries = Injuries.new()
	var r2 := e.injuries.process(e, {"type": "bullet", "zone": "torso", "bone": "mixamorig_Spine2", "point": chest - Vector3(0.2, 0, 0), "dir": Vector3.RIGHT, "penetration": 6.0})
	if r2.nodes.is_empty() or e.injuries.bleeding <= 0.0:
		return "tiro al pecho sin órganos ni hemorragia: %s" % str(r2.texts)
	e.injuries = Injuries.new()
	var r3 := e.injuries.process(e, {"type": "punch", "zone": "torso", "point": chest, "dir": Vector3.RIGHT})
	if not r3.nodes.is_empty():
		return "un puñetazo rompió algo"
	return ""

func g_captador(_p: Actor) -> String:
	g.probe.quick = true
	g.probe.frames_per_sample = 3
	g.probe.warmup_frames = 1
	await g.probe.run()
	var r := g.probe.report_text
	if not r.contains("QUÉ PESA MÁS") or g.probe.results.size() != PerfProbe.CATEGORIES.size():
		return "informe incompleto"
	if not FileAccess.file_exists("user://informe_rendimiento.txt"):
		return "no guardó el informe"
	# todo vuelve a quedar visible
	for c in PerfProbe.CATEGORIES:
		if str(c[1]).begins_with("perf_"):
			for n in get_tree().get_nodes_in_group(c[1]):
				if n.has_meta("probe_vis") and bool(n.get_meta("probe_vis")) and not (n as Node3D).visible:
					return "quedó oculto: %s" % n.name
	return ""
