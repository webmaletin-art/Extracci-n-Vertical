class_name WorldInteractables
extends RefCounted
## Interactuables simples del mapa: objeto suelto, puerta con llave, zona de extracción.


## Objeto en el piso (arma que soltó un enemigo, munición, botín suelto).
class Pickup extends Interactable:
	var item_id := "coins"
	var amount := 1
	var visual: Node3D
	func _ready() -> void:
		radius = 0.8
		super._ready()
		if visual == null:
			var d := Inventory.def(item_id)
			if str(d.get("type", "")) == "arma":
				var f := Firearm.create(str(d.weapon))
				f.rotation = Vector3(0, PI * 0.5, PI * 0.5)
				visual = f
			else:
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.22, 0.14, 0.16)
				mi.mesh = bm
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.25, 0.3, 0.2)
				m.emission_enabled = true
				m.emission = Color(0.9, 0.75, 0.2)
				m.emission_energy_multiplier = 0.25
				mi.material_override = m
				visual = mi
			visual.position.y = 0.12
			add_child(visual)
	func _process(delta: float) -> void:
		if visual:
			visual.rotation.y += delta * 1.2
	func prompt_for(_actor: Actor) -> String:
		return "Recoger %s" % Inventory.def(item_id).get("name", item_id)
	func use(actor: Actor) -> void:
		var msg := Inventory.apply_pickup(actor, item_id, amount)
		Sfx.play("pickup", global_position, -4.0)
		if actor.is_player:
			actor.get_tree().call_group("hud", "toast", msg)
		queue_free()


## Puerta bloqueada: se abre con una llave del inventario (p. ej. la tarjeta del laboratorio del P4).
class LockedDoor extends Interactable:
	var key_item := "keycard_lab"
	var body: StaticBody3D
	var panel: MeshInstance3D
	var opened := false
	var height := 2.4
	func _ready() -> void:
		radius = 1.2
		super._ready()
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.set_meta("surface", "metal")
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.2, height, 2.0)
		cs.shape = b
		cs.position.y = height * 0.5
		body.add_child(cs)
		panel = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		panel.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/hazard.png")
		m.uv1_scale = Vector3(1, 2, 1)
		m.metallic = 0.4
		panel.material_override = m
		panel.position.y = height * 0.5
		body.add_child(panel)
		add_child(body)
		var light := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.06
		lm.height = 0.12
		light.mesh = lm
		var lmat := StandardMaterial3D.new()
		lmat.emission_enabled = true
		lmat.emission = Color(1, 0.1, 0.05)
		lmat.emission_energy_multiplier = 3.0
		light.material_override = lmat
		light.position = Vector3(0.3, height + 0.2, -0.9)
		light.name = "Lamp"
		add_child(light)
	func can_use(_actor: Actor) -> bool:
		return not opened
	func prompt_for(actor: Actor) -> String:
		return "Abrir puerta (tarjeta)" if actor.inventory.count(key_item) > 0 else "Puerta bloqueada: falta la tarjeta del laboratorio"
	func use(actor: Actor) -> void:
		if actor.inventory.count(key_item) <= 0:
			Sfx.play("denied", global_position, -4.0)
			return
		opened = true
		Sfx.play("door_open", global_position, 0.0, 0.8, 12.0, actor)
		var tw := create_tween()
		tw.tween_property(body, "position:y", height - 0.15, 1.2).set_trans(Tween.TRANS_SINE)
		var lamp := get_node_or_null("Lamp") as MeshInstance3D
		if lamp:
			(lamp.material_override as StandardMaterial3D).emission = Color(0.1, 1.0, 0.2)


## Persiana pesada: no se abre con tarjeta sino con una palanca del mismo id (en otra parte del piso).
class Shutter extends Node3D:
	var lever_id := ""
	var height := 4.0
	var body: StaticBody3D
	var opened := false
	func _ready() -> void:
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.set_meta("surface", "metal")
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.2, height, 2.0)
		cs.shape = b
		cs.position.y = height * 0.5
		body.add_child(cs)
		var panel := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		panel.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/hazard.png")
		m.uv1_scale = Vector3(1, 3, 1)
		panel.material_override = m
		panel.position.y = height * 0.5
		body.add_child(panel)
		add_child(body)
		add_to_group("shutters")
	func open() -> void:
		if opened:
			return
		opened = true
		Sfx.play("door_open", global_position + Vector3.UP, 2.0, 0.6, 22.0)
		var tw := create_tween()
		tw.tween_property(body, "position:y", height - 0.2, 2.2).set_trans(Tween.TRANS_SINE)


## Palanca de pared: abre la persiana con su mismo id.
class Lever extends Interactable:
	var lever_id := ""
	var pulled := false
	var arm: MeshInstance3D
	func _ready() -> void:
		radius = 0.9
		super._ready()
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.5, 0.08)
		base.mesh = bm
		base.position.y = 1.2
		add_child(base)
		arm = MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.05, 0.4, 0.05)
		arm.mesh = am
		arm.position = Vector3(0, 1.3, 0.07)
		arm.rotation.z = 0.6
		add_child(arm)
	func can_use(_a: Actor) -> bool:
		return not pulled
	func prompt_for(_a: Actor) -> String:
		return "Accionar la palanca"
	func use(a: Actor) -> void:
		pulled = true
		create_tween().tween_property(arm, "rotation:z", -0.6, 0.3)
		Sfx.play("door_open", global_position, -4.0, 1.4, 14.0, a)
		for sh in a.get_tree().get_nodes_in_group("shutters"):
			if (sh as Shutter).lever_id == lever_id:
				(sh as Shutter).open()
		if a.is_player:
			a.get_tree().call_group("hud", "toast", "Se oyó una persiana pesada abrirse")


## Trampa de gas: la palanca suelta una nube tóxica durante unos segundos (daña a TODOS, también a quien la activa).
class GasTrap extends Interactable:
	var x0 := 0.0
	var x1 := 6.0
	var _t := -1.0
	var used := false
	func _ready() -> void:
		radius = 0.9
		super._ready()
		var base := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.5, 0.08)
		base.mesh = bm
		base.position.y = 1.2
		add_child(base)
	func can_use(_a: Actor) -> bool:
		return not used
	func prompt_for(_a: Actor) -> String:
		return "Soltar el gas (trampa)"
	func use(a: Actor) -> void:
		used = true
		_t = 7.0
		Sfx.play("steam_burst", global_position + Vector3.UP, 2.0, 0.7, 30.0, a)
	func _process(delta: float) -> void:
		if _t < 0.0:
			return
		_t -= delta
		if randf() < 0.6:
			Fx.smoke(Vector3(randf_range(x0, x1), global_position.y + randf_range(0.2, 2.0), 0), 0.7)
		for ac in get_tree().get_nodes_in_group("actors"):
			var a := ac as Actor
			if a and not a.is_dead() and a.global_position.x > x0 and a.global_position.x < x1 and absf(a.global_position.y - global_position.y) < 2.5:
				a.take_damage({"damage": 9.0 * delta, "type": "fire", "zone": "torso", "point": a.global_position + Vector3.UP, "dir": Vector3.UP})


## Zona de extracción: quedarse adentro unos segundos (con riesgo) termina la partida llevando el botín.
class ExtractionZone extends Area3D:
	signal extracted(actor: Actor)
	var seconds := 6.0
	var label := "Extracción"
	var size := Vector3(3.0, 2.6, 3.0)
	var _t := 0.0
	var inside: Actor = null
	var opens_at := 0.0                ## segundos desde que empieza la partida; 0 = siempre abierta
	var _age := 0.0
	var _lab: Label3D
	func is_open() -> bool:
		return _age >= opens_at
	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		monitoring = true
		add_to_group("extraction")
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
		cs.position.y = size.y * 0.5
		add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x, 0.04, size.z)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.1, 1.0, 0.35, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		mi.position.y = 0.03
		add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = Color(0.2, 1.0, 0.4)
		l.light_energy = 1.5
		l.omni_range = 5.0
		l.position.y = 2.0
		add_child(l)
	func progress() -> float:
		return clampf(_t / seconds, 0.0, 1.0)
	func _physics_process(delta: float) -> void:
		inside = null
		var was := is_open()
		_age += delta
		if not was and is_open():
			Sfx.play("extract_beep", global_position + Vector3.UP, 2.0, 0.7, 40.0)
			get_tree().call_group("hud", "toast", "%s: ¡ya se puede extraer!" % label)
		if not is_open():
			return
		for b in get_overlapping_bodies():
			if b is Actor and (b as Actor).is_player and not (b as Actor).is_dead():
				inside = b
		if inside:
			var before := _t
			_t += delta
			if int(before) != int(_t):
				Sfx.play("extract_beep", global_position + Vector3.UP, -4.0, 1.0 + _t * 0.05)
			if _t >= seconds:
				_t = -999.0
				extracted.emit(inside)
		elif _t > 0.0:
			_t = maxf(_t - delta * 2.0, 0.0)
