class_name Destructible
extends StaticBody3D
## Objeto rompible con estados INTACTO → DAÑADO → ROTO. Separa lo destructible de lo estructural: paredes, pisos y vigas
## NO son Destructible (decisión de diseño: el edificio no se cae); sí lo son cajas, barriles, vidrios, paneles y
## coberturas livianas.
##   * Cajas de madera: se agrietan (oscurecen y se tuercen), se rompen en astillas y fragmentos y sueltan su botín.
##   * Cajas metálicas: aguantan balas (×0,3), se abollan; sólo ceden a explosiones o muchos golpes.
##   * Barriles: con daño pierden y explotan (Explosion «barrel»), dañando lo cercano.
##   * Vidrio: se fractura al primer impacto y estalla en fragmentos al segundo.
##   * Paneles de chapa: se deforman y al romperse se desprenden y caen.
## Optimizado para teléfonos: fragmentos de un grupo fijo (Fx.debris), sin destrucción física ilimitada.

signal broken(by: Node)

enum Phase { INTACT, DAMAGED, BROKEN }

@export var kind := "crate_wood"
@export var max_health := 60.0
var health := 60.0
var phase := Phase.INTACT
var visual: Node3D
var size := Vector3.ONE
var loot: LootContainer           ## contenedor asociado (se rompe → suelta el botín como objetos sueltos)
var _base_color := Color(0.5, 0.36, 0.2)
var _tint_mats: Array[StandardMaterial3D] = []

const DEFS := {
	"crate_wood": {"hp": 60.0, "surface": "wood", "thickness": 2.0, "bullet": 1.0, "melee": 1.0, "blast": 2.0, "color": Color(0.55, 0.38, 0.2)},
	"crate_metal": {"hp": 220.0, "surface": "metal", "thickness": 999.0, "bullet": 0.3, "melee": 0.4, "blast": 1.6, "color": Color(0.32, 0.36, 0.3)},
	"barrel": {"hp": 45.0, "surface": "metal", "thickness": 999.0, "bullet": 1.0, "melee": 0.3, "blast": 3.0, "color": Color(0.6, 0.12, 0.08)},
	"glass": {"hp": 8.0, "surface": "glass", "thickness": 1.0, "bullet": 1.0, "melee": 1.0, "blast": 5.0, "color": Color(0.7, 0.85, 0.95)},
	"panel_metal": {"hp": 120.0, "surface": "metal", "thickness": 3.0, "bullet": 0.5, "melee": 0.5, "blast": 2.0, "color": Color(0.35, 0.37, 0.4)},
	"door": {"hp": 70.0, "surface": "wood", "thickness": 4.0, "bullet": 0.6, "melee": 2.2, "blast": 4.0, "color": Color(0.46, 0.34, 0.22)},
	"drywall": {"hp": 170.0, "surface": "wood", "thickness": 6.0, "bullet": 0.5, "melee": 0.8, "blast": 4.0, "color": Color(0.82, 0.82, 0.8)},
	"cardboard": {"hp": 15.0, "surface": "wood", "thickness": 1.0, "bullet": 1.0, "melee": 1.5, "blast": 3.0, "color": Color(0.6, 0.48, 0.3)},
}

func _ready() -> void:
	var d: Dictionary = DEFS.get(kind, DEFS.crate_wood)
	max_health = float(d.hp)
	health = max_health
	collision_layer = 8
	collision_mask = 0
	set_meta("surface", d.surface)
	set_meta("thickness_cm", d.thickness)
	_base_color = d.color
	add_to_group("destructibles")

## Arma el cuerpo: caja de colisión + modelo (un GLB de la galería o una caja con textura).
func setup(kind_: String, size_: Vector3, model_path := "") -> void:
	kind = kind_
	size = size_
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position.y = size.y * 0.5
	add_child(cs)
	if model_path != "":
		var lp := LinedBake.lined_path("props", model_path.get_file().get_basename())
		if lp != "":
			model_path = lp
	if model_path != "" and ResourceLoader.exists(model_path):
		visual = (load(model_path) as PackedScene).instantiate()
		_fit(visual, size)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		var d: Dictionary = DEFS.get(kind, DEFS.crate_wood)
		m.albedo_color = d.color
		if kind == "glass":
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.6, 0.8, 0.9, 0.25)
			m.metallic = 0.6
			m.roughness = 0.05
		elif kind in ["panel_metal", "crate_metal"]:
			m.albedo_texture = load("res://assets/textures/metal_panel.png")
			m.metallic = 0.6
			m.roughness = 0.5
		elif kind == "barrel":
			m.albedo_color = Color(0.62, 0.13, 0.08)
			m.metallic = 0.4
		mi.material_override = m
		mi.position.y = size.y * 0.5
		visual = mi
		if kind == "barrel":
			var cm := CylinderMesh.new()
			cm.top_radius = size.x * 0.5
			cm.bottom_radius = size.x * 0.5
			cm.height = size.y
			cm.radial_segments = 14
			mi.mesh = cm
	add_child(visual)
	_collect_mats()

static func _fit(n: Node3D, target: Vector3) -> void:
	var aabb := _aabb(n, Transform3D.IDENTITY)
	if aabb.size.length() < 0.001:
		return
	var s := minf(minf(target.x / maxf(aabb.size.x, 0.01), target.y / maxf(aabb.size.y, 0.01)), target.z / maxf(aabb.size.z, 0.01))
	n.scale = Vector3.ONE * s
	n.position = Vector3(-aabb.get_center().x * s, -aabb.position.y * s, -aabb.get_center().z * s)

static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var x := xf * ((n as Node3D).transform if n is Node3D else Transform3D.IDENTITY)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a := x * (n as MeshInstance3D).mesh.get_aabb()
		out = a
		first = false
	for c in n.get_children():
		var ca := _aabb(c, x)
		if ca.size.length() > 0.0:
			out = ca if first else out.merge(ca)
			first = false
	return out

func _collect_mats() -> void:
	_tint_mats.clear()
	for mi in visual.find_children("*", "MeshInstance3D", true, false) + ([visual] if visual is MeshInstance3D else []):
		var m := mi as MeshInstance3D
		if m.material_override is StandardMaterial3D:
			_tint_mats.append(m.material_override)

func apply_damage(amount: float, point: Vector3, dir: Vector3, type: String, by: Node = null) -> void:
	if phase == Phase.BROKEN:
		return
	var d: Dictionary = DEFS.get(kind, DEFS.crate_wood)
	var mult := float(d.get(type, 1.0)) if type in ["bullet", "melee", "blast"] else 1.0
	health -= amount * mult
	if kind == "barrel" and type == "bullet":
		Fx.emit("spark", point, -dir, 0.6)
	if health <= 0.0:
		_break(by, dir)
	elif phase == Phase.INTACT and health < max_health * 0.6:
		_set_damaged(dir)
	elif kind == "glass" and phase == Phase.INTACT:
		_set_damaged(dir)

func _set_damaged(dir: Vector3) -> void:
	phase = Phase.DAMAGED
	if visual:
		visual.rotation.z += randf_range(-0.05, 0.05)
		visual.rotation.y += randf_range(-0.04, 0.04)
		if kind == "panel_metal" or kind == "crate_metal":
			visual.scale *= Vector3(1.0, 0.97, 1.0 - 0.06 * signf(dir.x))   # abolladura
	for m in _tint_mats:
		m.albedo_color = m.albedo_color.darkened(0.25)
	match kind:
		"crate_wood", "cardboard":
			Sfx.play("wood_crack", global_position + Vector3.UP * size.y * 0.5, -2.0, 1.0, 10.0)
		"glass":
			Sfx.play("glass_crack", global_position + Vector3.UP * size.y * 0.5, -2.0, 1.0, 10.0)
		"barrel":
			Sfx.play("impact_metal", global_position, -2.0)
			Fx.smoke(global_position + Vector3.UP * size.y, 0.4)
		_:
			Sfx.play("impact_metal", global_position, -2.0)

func _break(by: Node, dir: Vector3) -> void:
	phase = Phase.BROKEN
	var c := global_position + Vector3.UP * size.y * 0.5
	var d: Dictionary = DEFS.get(kind, DEFS.crate_wood)
	for ch in get_children():
		if ch is CollisionShape3D:
			(ch as CollisionShape3D).set_deferred("disabled", true)
	match kind:
		"crate_wood", "cardboard":
			Sfx.play("wood_break", c, 2.0, 1.0, 22.0, by)
			Fx.emit("splinter", c, Vector3.UP, 1.5)
			Fx.emit("dust", c, Vector3.UP, 1.2)
			Fx.debris(c, d.color, 8, 4.0, Vector3(size.x * 0.45, 0.04, 0.1))
		"glass":
			Sfx.play("glass_break", c, 2.0, 1.0, 22.0, by)
			Fx.emit("glass", c, dir, 1.5)
		"door":
			Sfx.play("wood_break", c, 3.0, 0.8, 28.0, by)
			Fx.emit("splinter", c, Vector3(dir.x, 0.3, 0), 2.0)
			Fx.debris(c, d.color, 10, 5.0, Vector3(size.x * 0.5, size.y * 0.4, 0.2))
		"drywall":
			Sfx.play("wood_break", c, 0.0, 0.6, 24.0, by)
			Fx.emit("dust", c, Vector3.UP, 2.0)
			Fx.debris(c, d.color, 8, 4.0, Vector3(size.x * 0.5, size.y * 0.4, 0.2))
		"barrel":
			Explosion.spawn(get_parent(), "barrel", c, by)
		"panel_metal":
			Sfx.play("metal_fall", c, 0.0, 1.0, 20.0, by)
			Fx.debris(c, d.color, 2, 3.0, Vector3(size.x * 0.8, size.y * 0.5, 0.04))
		_:
			Sfx.play("impact_metal", c, 2.0, 0.7, 20.0, by)
			Fx.debris(c, d.color, 5, 3.0, Vector3(0.2, 0.05, 0.2))
			Fx.emit("spark", c, Vector3.UP)
	if visual:
		visual.visible = false
	if loot and not loot.is_open:
		_drop_loot(c)
	broken.emit(by)

## Al romper un contenedor el botín cae como objetos sueltos (se recogen con USAR).
func _drop_loot(c: Vector3) -> void:
	var items := Inventory.roll(loot.table, loot.floor_bonus)
	loot.is_open = true
	var i := 0
	for it in items:
		var p := WorldInteractables.Pickup.new()
		p.item_id = it[0]
		p.amount = it[1]
		get_parent().add_child(p)
		p.global_position = Vector3(c.x + (i - items.size() * 0.5) * 0.35, global_position.y + 0.05, 0.0)
		i += 1
