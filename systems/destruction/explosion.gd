class_name Explosion
extends Node3D
## Explosión (granadas, C4, barriles). Genera destello, bola de fuego, onda expansiva visible, humo, chispas, fragmentos,
## daño radial con caída por distancia (y menos daño detrás de una pared), empuje a los fragmentos y destructibles
## cercanos, vibración de cámara según la distancia al jugador, sonido con la reverberación del lugar y ruido para la IA.
## Tipos especiales: aturdidora (aturde y encandila), humo (nube que tapa la vista de la IA), incendiaria (fuego que quema).
## Todo escala con Settings.explosions / smoke / particles.

static var _defs := {}

static func defs() -> Dictionary:
	if _defs.is_empty():
		_defs = JSON.parse_string(FileAccess.get_file_as_string("res://data/explosives.json"))
	return _defs

static func spawn(parent: Node, kind: String, pos: Vector3, by: Node = null) -> Explosion:
	if parent == null or not parent.is_inside_tree():
		return null
	var e := Explosion.new()
	parent.add_child(e)
	e.global_position = pos
	e._go(kind, by)
	return e

func _go(kind: String, by: Node) -> void:
	var d: Dictionary = defs().get(kind, defs().frag)
	var pos := global_position
	var radius := float(d.get("radius", 4.0))
	var lvl := Settings.explosions
	match kind:
		"smoke":
			Sfx.play("smoke_hiss", pos, 0.0, 1.0, float(d.noise), by)
			var cloud := SmokeCloud.new()
			cloud.seconds = float(d.smoke)
			get_parent().add_child(cloud)
			cloud.global_position = pos
			queue_free()
			return
		"stun":
			Sfx.play("flashbang", pos, 4.0, 1.0, float(d.noise), by)
			Fx.flash(pos, 16.0, 14.0, 0.25, Color(1, 1, 1))
			for a in get_tree().get_nodes_in_group("actors"):
				var ac := a as Actor
				var dist := ac.global_position.distance_to(pos)
				if dist < radius and _clear(pos, ac.global_position + Vector3.UP * 1.4):
					ac.stun(float(d.stun) * (1.0 - dist / radius * 0.6))
					if ac.is_player:
						get_tree().call_group("hud", "flashbang", 1.0 - dist / radius)
			TimeFx.shake(float(d.shake) * _shake_k(pos))
			queue_free()
			return
	# --- explosión con fuego
	Sfx.play("explosion", pos, 6.0, randf_range(0.9, 1.05), float(d.noise), by)
	Fx.flash(pos + Vector3.UP * 0.4, 12.0 if lvl > 0 else 6.0, radius * 3.0, 0.35, Color(1.0, 0.65, 0.3))
	TechView.shockwave(get_parent(), pos, radius)      # estilo en línea: onda expansiva de líneas, sin fuego ni humo
	Fx.debris(pos + Vector3.UP * 0.2, Color(0.2, 0.19, 0.18), int(d.get("fragments", 8)) / 2, float(d.impulse))
	TimeFx.shake(float(d.shake) * _shake_k(pos))
	# daño radial
	var dmg := float(d.damage)
	for a in get_tree().get_nodes_in_group("actors"):
		var ac := a as Actor
		if ac.is_dead():
			continue
		var chest := ac.global_position + Vector3.UP * 1.1
		var dist := chest.distance_to(pos)
		if dist > radius:
			continue
		var k := pow(1.0 - dist / radius, 1.5)
		if not _clear(pos + Vector3.UP * 0.2, chest):
			k *= 0.25
		var dir := (chest - pos).normalized()
		# lugar cerrado: la onda rebota y pega más fuerte
		var closed := Sfx.room_closed
		ac.take_damage({"damage": dmg * k * (1.25 if closed else 1.0), "type": "blast", "zone": "torso", "bone": "mixamorig_Spine1",
			"point": chest - dir * 0.2, "dir": dir, "shooter": by, "explosion": kind, "distance": dist, "radius": radius, "closed": closed})
		if not ac.is_dead():
			ac.throw(Vector3(dir.x, absf(dir.y) + 0.45, 0) * float(d.impulse) * k * 1.4)
	for o in get_tree().get_nodes_in_group("destructibles"):
		var ds := o as Destructible
		var dist := ds.global_position.distance_to(pos)
		if dist < radius and ds != null:
			ds.apply_damage(dmg * (1.0 - dist / radius), ds.global_position, (ds.global_position - pos).normalized(), "blast", by)
	# esquirlas: proyectiles físicos en todas direcciones del plano (entran al cuerpo y quedan alojadas)
	var nfrag := int(d.get("fragments", 0))
	if nfrag > 0 and Ballistics.instance:
		for i in nfrag:
			var a := TAU * float(i) / nfrag + randf_range(-0.15, 0.15)
			var fd := Vector3(cos(a), sin(a), 0.0)
			Ballistics.instance.fire(pos + Vector3.UP * 0.15 + fd * 0.1, fd, randf_range(160.0, 260.0), randf_range(14.0, 24.0), by, [],
				{"penetration": 1.0, "drag": 1.2, "ricochet": 0.3, "kind": "fragment"})
	if d.has("fire"):
		var f := FireZone.new()
		f.seconds = float(d.fire)
		f.dps = float(d.get("fire_dps", 15.0))
		f.radius = maxf(radius * 0.5, 1.5)
		f.by = by
		get_parent().add_child(f)
		f.global_position = pos
	var t := get_tree().create_timer(1.5)
	t.timeout.connect(queue_free)

func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _shake_k(pos: Vector3) -> float:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return 0.5
	return clampf(1.0 - p.global_position.distance_to(pos) / 25.0, 0.0, 1.0)

## Onda expansiva visible: esfera transparente que crece y se desvanece.
func _shockwave(radius: float) -> void:
	var mi := MeshInstance3D.new()
	mi.set_meta("no_tech", true)
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.7, 0.4, 0.18)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.scale = Vector3.ONE * 0.2
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.25)


## Nube de humo (granada de humo): emite humo durante `seconds` y tapa la vista de la IA (grupo «smoke»).
class SmokeCloud extends Node3D:
	var seconds := 12.0
	var radius := 3.5
	var _t := 0.0
	var _emit_t := 0.0
	func _ready() -> void:
		add_to_group("smoke")
	func _process(delta: float) -> void:
		_t += delta
		_emit_t -= delta
		if _emit_t <= 0.0 and _t < seconds:
			_emit_t = 0.9
			Fx.smoke(global_position + Vector3(randf_range(-1.5, 1.5), randf_range(0.2, 1.5), 0), 2.2)
		if _t > seconds + 4.0:
			queue_free()
	func blocks(a: Vector3, b: Vector3) -> bool:
		if _t > seconds + 2.0:
			return false
		var c := global_position + Vector3.UP
		var ab := b - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		return (a + ab * t).distance_to(c) < radius


## Fuego en el piso (incendiaria, barril): quema a quien esté adentro.
class FireZone extends Node3D:
	var seconds := 6.0
	var dps := 15.0
	var radius := 2.0
	var by: Node
	var _t := 0.0
	var _tick := 0.0
	var _p: CPUParticles3D
	var _light: OmniLight3D
	func _ready() -> void:
		_p = Fx.emit("fire", global_position, Vector3.UP, 1.0)
		if _p:
			_p.emission_box_extents = Vector3(radius, 0.05, 0.4)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.5, 0.15)
		_light.light_energy = 1.5
		_light.omni_range = radius * 3.0
		_light.position.y = 0.6
		add_child(_light)
		Sfx.play("fire_loop", global_position, -2.0, 1.0, 10.0)
	func _process(delta: float) -> void:
		_t += delta
		_light.light_energy = 1.2 + sin(_t * 23.0) * 0.3 + randf() * 0.2
		_tick -= delta
		if _tick <= 0.0 and _t < seconds:
			_tick = 0.5
			for a in get_tree().get_nodes_in_group("actors"):
				var ac := a as Actor
				if not ac.is_dead() and absf(ac.global_position.x - global_position.x) < radius and absf(ac.global_position.y - global_position.y) < 1.0:
					ac.take_damage({"damage": dps * 0.5, "type": "fire", "zone": "leg", "point": ac.global_position + Vector3.UP * 0.4, "dir": Vector3.UP, "shooter": by})
		if _t >= seconds:
			if _p:
				_p.emitting = false
			_light.visible = false
		if _t >= seconds + 1.0:
			queue_free()
