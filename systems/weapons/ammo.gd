class_name Ammo
extends RefCounted
## Tipos de munición (data/ammo.json). Cada arma usa el calibre que dice weapons.json y puede cargar 6 tipos: estándar, trazante,
## punta hueca, perforante, incendiaria y punta de flor. Cada tipo cambia el daño, la penetración, el rebote, la velocidad y la
## dispersión, y además lo que le pasa al cuerpo: fuerza con que rompe huesos (bone), tamaño del orificio (wound), sangre
## (blood), radio del daño interno en órganos (organ) y si estalla al entrar (burst, incendiaria). Las más poderosas son más caras.

const TYPE_ORDER := ["std", "tr", "hp", "ap", "in", "fl"]
static var _d := {}

static func data() -> Dictionary:
	if _d.is_empty():
		_d = JSON.parse_string(FileAccess.get_file_as_string("res://data/ammo.json"))
	return _d

## Clave de calibre (ammo.json) de un arma.
static func caliber_key(weapon_id: String) -> String:
	var name := str(Firearm.all_stats()[weapon_id].get("caliber", ""))
	for k in data().calibers:
		var cn := str(data().calibers[k].name)
		if cn == name or (cn == "12 ga" and name.begins_with("12 ga")):
			return k
	return "9x19"

static func is_shotgun(weapon_id: String) -> bool:
	return str(Firearm.all_stats()[weapon_id].get("class", "")) == "shotgun"

## Multiplicadores del tipo para esa arma (las escopetas tienen sus propios tipos).
static func mods(weapon_id: String, type: String) -> Dictionary:
	var tbl: Dictionary = data().shotgun_types if is_shotgun(weapon_id) else data().types
	return tbl.get(type, tbl.std)

## Id del objeto de munición (ammo.json items / items.json «ammo_<id>»).
static func item_id(weapon_id: String, type: String) -> String:
	return "%s_%s" % [caliber_key(weapon_id), type]

static func item(weapon_id: String, type: String) -> Dictionary:
	return data().items.get(item_id(weapon_id, type), {})

## Estadísticas del arma con la munición cargada (copia: no toca los datos compartidos).
static func apply(base: Dictionary, weapon_id: String, type: String) -> Dictionary:
	var m := mods(weapon_id, type)
	var st := base.duplicate()
	st.damage = float(base.damage) * float(m.dmg)
	st.penetration = float(base.penetration) * float(m.pen)
	st.ricochet = minf(float(base.ricochet) * float(m.ric), 0.95)
	st.speed = float(base.speed) * float(m.speed)
	st.spread = float(base.spread) * float(m.spread)
	st.noise = float(base.noise) + float(m.noise)
	if is_shotgun(weapon_id) and float(m.dmg) >= 4.0:
		st.pellets = 1                                      # balón: un solo proyectil pesado
	return st

## Lo que el proyectil le hace al cuerpo (viaja en la bala hasta el impacto).
static func fx(weapon_id: String, type: String) -> Dictionary:
	var m := mods(weapon_id, type)
	return {"type": type, "bone": float(m.bone), "wound": float(m.wound), "blood": float(m.blood), "organ": float(m.organ),
		"burst": bool(m.burst), "tracer": type == "tr" or type == "in"}

## Texto corto de un tipo (para menús).
static func label(weapon_id: String, type: String) -> String:
	return str(mods(weapon_id, type).name)
