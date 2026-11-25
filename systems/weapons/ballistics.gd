class_name Ballistics
extends Node3D
## Proyectiles físicos (balas, perdigones, flechas). No son nodos sueltos: hay un grupo fijo de registros que se integra
## en _physics_process (velocidad inicial, gravedad, resistencia del aire) con un rayo por tramo para los choques.
## Al chocar: daño a la zona del cuerpo (hitbox), daño a objetos destructibles con penetración configurable, rebote en
## metal con ángulo rasante, efectos y sonido por material, y ruido para la IA.
##
## Capas: 1 mundo, 3 hitbox (zonas del cuerpo, Area3D), 4 destructibles.

signal projectile_hit(index: int, info: Dictionary)

const MAX := 96
const MASK := 1 | 4 | 8
const GRAVITY := 9.8
const MAX_LIFE := 2.5

static var instance: Ballistics

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _dmg := PackedFloat32Array()
var _from := PackedVector3Array()      ## de dónde salió (alcance efectivo)
var _range := PackedFloat32Array()     ## alcance efectivo del arma (m)
var _pellets := PackedInt32Array()     ## perdigones del disparo (escopeta: daño de cerca)
var _pen := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _life := PackedFloat32Array()
var _ric := PackedFloat32Array()
var _alive: Array[bool] = []
var _owner: Array = []
var _exclude: Array = []
var _kind: Array[String] = []
var _tracers: Array[MeshInstance3D] = []
var _next := 0
var tracked := -1                 ## índice seguido por la cámara de bala (BulletTime)
var visual_z: Array = []           ## (cámara de bala) desplazamiento visual en z de la bala seguida
var bullet_model: MeshInstance3D  ## bala 3D (munición de Nexus) que se muestra sólo en cámara lenta
var stats := {"fired": 0, "hits": 0}

func _ready() -> void:
	instance = self
	_pos.resize(MAX); _vel.resize(MAX); _dmg.resize(MAX); _from.resize(MAX); _range.resize(MAX); _pellets.resize(MAX); _pen.resize(MAX); _drag.resize(MAX); _life.resize(MAX); _ric.resize(MAX)
	var tracer_mat := StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.albedo_color = Color(1.0, 0.82, 0.45, 0.85)
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var tm := BoxMesh.new()
	tm.size = Vector3(0.018, 0.018, 1.0)
	for i in MAX:
		_alive.append(false)
		_owner.append(null)
		_exclude.append([])
		_kind.append("bullet")
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = tracer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		_tracers.append(mi)
	bullet_model = MeshInstance3D.new()
	bullet_model.mesh = BulletTime.bullet_mesh(false)          # bala de Blender (tools/ammo/make_bullets.py)
	bullet_model.visible = false
	bullet_model.top_level = true
	add_child(bullet_model)

func _exit_tree() -> void:
	if instance == self:
		instance = null

## Dispara un proyectil. dir en el mundo (se fuerza al plano de juego z = 0). Devuelve el índice.
func fire(from: Vector3, dir: Vector3, speed: float, damage: float, shooter: Node, exclude: Array, opts := {}) -> int:
	var i := _next
	_next = (_next + 1) % MAX
	from.z = 0.0
	dir.z = 0.0
	dir = dir.normalized()
	_pos[i] = from
	_vel[i] = dir * speed
	_dmg[i] = damage
	_from[i] = from
	_range[i] = float(opts.get("range", 0.0))
	_pellets[i] = int(opts.get("pellets", 1))
	_pen[i] = float(opts.get("penetration", 2.0))
	_drag[i] = float(opts.get("drag", 0.05))
	_ric[i] = float(opts.get("ricochet", 0.2))
	_life[i] = MAX_LIFE
	_alive[i] = true
	_owner[i] = shooter
	_exclude[i] = exclude
	_kind[i] = str(opts.get("kind", "bullet"))
	_tracers[i].visible = false
	stats.fired += 1
	return i

func is_alive(i: int) -> bool:
	return i >= 0 and i < MAX and _alive[i]

func position_of(i: int) -> Vector3:
	return _pos[i]

func velocity_of(i: int) -> Vector3:
	return _vel[i]

func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in MAX:
		if not _alive[i]:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_kill(i)
			continue
		var p0 := _pos[i]
		var v := _vel[i]
		v.y -= GRAVITY * delta
		v *= maxf(1.0 - _drag[i] * delta, 0.0)
		var p1 := p0 + v * delta
		_vel[i] = v
		_step(i, space, p0, p1)
		if _alive[i]:
			_draw_tracer(i, p0)

func _step(i: int, space: PhysicsDirectSpaceState3D, p0: Vector3, p1: Vector3) -> void:
	var from := p0
	for bounce in 4:
		var q := PhysicsRayQueryParameters3D.create(from, p1, MASK)
		q.collide_with_areas = true
		q.exclude = _exclude[i]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			_pos[i] = p1
			return
		var col: Object = hit.collider
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var dir := _vel[i].normalized()
		# alcance efectivo del arma: pasado el alcance el daño baja hasta la mitad a 2× el alcance
		if _range[i] > 0.0:
			var dd := point.distance_to(_from[i])
			if dd > _range[i]:
				_dmg[i] *= lerpf(1.0, 0.5, clampf((dd - _range[i]) / _range[i], 0.0, 1.0))
				_range[i] = 0.0
		var info := {"distance": point.distance_to(_from[i]), "pellets": _pellets[i], "point": point, "normal": normal, "dir": dir, "damage": _dmg[i], "shooter": _owner[i], "kind": _kind[i],
			"speed": _vel[i].length(), "index": i}
		stats.hits += 1
		if col is Area3D and (col as Area3D).has_meta("actor"):
			var actor: Node = (col as Area3D).get_meta("actor")
			if actor == _owner[i] or (_owner[i] is Actor and is_instance_valid(_owner[i]) and actor is Actor and (_owner[i] as Actor).team == (actor as Actor).team and (_owner[i] as Actor).team != 0):
				_exclude[i] = _exclude[i] + [hit.rid]
				from = point + dir * 0.01
				continue
			info["zone"] = (col as Area3D).get_meta("zone", "torso")
			info["bone"] = (col as Area3D).get_meta("bone", "")
			info["type"] = "fragment" if _kind[i] == "fragment" else "bullet"
			info["ricochet"] = _kind[i] == "ricochet"
			info["penetration"] = _pen[i]
			projectile_hit.emit(i, info)
			if is_instance_valid(actor) and actor.has_method("take_damage"):
				actor.take_damage(info)
			Fx.impact(point, -dir, "flesh")
			Sfx.play("impact_flesh", point, -2.0)
			# la bala atraviesa las partes finas (cabeza, cuello, brazos, piernas, manos, pies) y sigue; el torso sólo
			# lo atraviesan los calibres potentes
			var thin: bool = str(info.zone) in ["head", "neck", "arm", "leg", "hand", "foot"]
			if _kind[i] != "fragment" and thin and _pen[i] >= 2.5:
				_pen[i] -= 2.5
				_dmg[i] *= 0.6
				_exclude[i] = _exclude[i] + [hit.rid]
				from = point + dir * 0.03
				continue
			if _pen[i] >= 10.0 and _kind[i] != "fragment":
				_pen[i] -= 10.0
				_dmg[i] *= 0.5
				_exclude[i] = _exclude[i] + [hit.rid]
				from = point + dir * 0.05
				continue
			_kill(i)
			return
		var surface := "concrete"
		if col is Node and (col as Node).has_meta("surface"):
			surface = str((col as Node).get_meta("surface"))
		var thickness := 999.0
		if col is Node and (col as Node).has_meta("thickness_cm"):
			thickness = float((col as Node).get_meta("thickness_cm"))
		if col is Node and (col as Node).has_method("apply_damage"):
			(col as Node).apply_damage(_dmg[i], point, dir, "bullet", _owner[i])
		Fx.impact(point, normal, surface)
		Sfx.play("impact_" + ("concrete" if surface == "glass" else surface), point, -6.0, 1.0, 6.0)
		projectile_hit.emit(i, info)
		if _pen[i] >= thickness:
			_pen[i] -= thickness
			_dmg[i] *= 0.7
			_exclude[i] = _exclude[i] + [hit.rid]
			from = point + dir * 0.02
			continue
		# rebote: en metal con ángulo rasante y en pisos / paredes de hormigón casi de costado. La bala sigue
		# deformada y girando: si después pega en alguien abre una herida más ancha (info.ricochet)
		var graze := -dir.dot(normal)
		var chance := 0.0
		# (graze = coseno con la normal: 1 = de frente · 0 = paralela). En metal rebota hasta ~33° de la superficie y es más
		# probable cuanto más rasante; en hormigón / madera hasta ~17°.
		if surface == "metal" and graze < 0.55:
			chance = _ric[i] * 1.6 * (1.25 - graze / 0.55)
		elif surface in ["concrete", "wood"] and graze < 0.3:
			chance = _ric[i] * (1.4 if normal.y > 0.7 else 0.8) * (1.2 - graze / 0.3)
		if _kind[i] != "fragment" and randf() < chance:
			var r := dir.bounce(normal).rotated(Vector3.BACK, randf_range(-0.15, 0.15))
			r.z = 0.0
			_vel[i] = r.normalized() * _vel[i].length() * randf_range(0.45, 0.7)
			_dmg[i] *= 0.6
			_pos[i] = point + normal * 0.02
			_kind[i] = "ricochet"
			Fx.emit("spark", point, r)
			Sfx.play("impact_metal", point, -4.0, randf_range(1.2, 1.5), 8.0)
			return
		_kill(i)
		return
	_pos[i] = p1

func _draw_tracer(i: int, prev: Vector3) -> void:
	var t := _tracers[i]
	var seg := _pos[i] - prev
	var l := seg.length()
	if l < 0.001:
		return
	var vis_len := clampf(l, 0.05, 2.5)
	var d := seg / l
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	t.global_transform = Transform3D(Basis.looking_at(d, up).scaled_local(Vector3(1, 1, vis_len)), _pos[i] - d * vis_len * 0.5)
	t.visible = true
	if i == tracked and bullet_model:
		bullet_model.visible = true
		# el modelo trae el origen corrido ~0,9 m: se centra en la posición real del proyectil
		var mc := bullet_model.mesh.get_aabb().get_center() if bullet_model.mesh else Vector3.ZERO
		# la bala física viaja en el plano z = 0; la que se VE sale de la boca del cañón y llega a la profundidad del
		# cuerpo al que va a pegar (visual_z = [x inicio, z inicio, x impacto, z impacto])
		var vp := _pos[i]
		if visual_z.size() == 4:
			var u := clampf(inverse_lerp(float(visual_z[0]), float(visual_z[2]), vp.x), 0.0, 1.0)
			vp.z = lerpf(float(visual_z[1]), float(visual_z[3]), u)
		bullet_model.global_transform = Transform3D(Basis.looking_at(d, up).scaled(Vector3.ONE * 4.0), vp) * Transform3D(Basis.IDENTITY, -mc)

func _kill(i: int) -> void:
	_alive[i] = false
	_tracers[i].visible = false
	if i == tracked:
		bullet_model.visible = false

## Recorre la trayectoria sin efectos para saber qué va a pasar (lo usa la cámara de bala ANTES del impacto).
## Devuelve {} si no pega en nadie, o {"collider", "point", "time"}.
func predict(from: Vector3, vel: Vector3, drag: float, exclude: Array, max_time := 1.5) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var p := from
	var v := vel
	var t := 0.0
	var dt := 1.0 / 60.0
	while t < max_time:
		v.y -= GRAVITY * dt
		v *= maxf(1.0 - drag * dt, 0.0)
		var p1 := p + v * dt
		var q := PhysicsRayQueryParameters3D.create(p, p1, MASK)
		q.collide_with_areas = true
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return {"collider": hit.collider, "point": hit.position, "time": t}
		p = p1
		t += dt
	return {}
