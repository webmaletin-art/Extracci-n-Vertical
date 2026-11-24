## Origen: Operación Nexus (player/weapon_materials.gd).
class_name WeaponMaterials
extends RefCounted
## Materiales de las armas: se arman al cargar a partir de assets/weapons/models.json,
## así se puede cambiar la calidad o las texturas sin volver a exportar los modelos.

const DIR := "res://assets/weapons/"
static var _cache := {}
static var _catalog := {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		var p := DIR + "models.json"
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if d is Dictionary:
				_catalog = d
	return _catalog

static func get_material(weapon_id: String, surface_name: String) -> Material:
	var key := weapon_id + "/" + surface_name
	if _cache.has(key):
		return _cache[key]
	var spec: Dictionary = catalog().get(weapon_id, {}).get("materials", {}).get(surface_name, {})
	var m := StandardMaterial3D.new()
	m.roughness = float(spec.get("roughness", 0.7))
	m.metallic = float(spec.get("metallic", 0.0))
	if spec.has("color"):
		m.albedo_color = Color(spec.color[0], spec.color[1], spec.color[2])
	elif not spec.has("albedo"):
		m.albedo_color = Color(0.16, 0.16, 0.17)
	if spec.has("albedo"):
		m.albedo_texture = load(DIR + spec.albedo)
	if spec.has("normal"):
		m.normal_enabled = true
		m.normal_texture = load(DIR + spec.normal)
	if spec.has("orm"):
		var t: Texture2D = load(DIR + spec.orm)
		m.roughness_texture = t
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		if spec.get("metallic", 0.0) > 0.0:
			m.metallic_texture = t
			m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		if spec.get("use_ao", false):
			m.ao_enabled = true
			m.ao_texture = t
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_cache[key] = m
	return m

## Asigna los materiales a todas las mallas de un arma instanciada.
static func apply(weapon_id: String, root: Node) -> void:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh is ArrayMesh:
		var mi := root as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, get_material(weapon_id, mi.mesh.surface_get_name(s)))
	for c in root.get_children():
		apply(weapon_id, c)
