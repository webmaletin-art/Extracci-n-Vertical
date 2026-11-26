class_name Inventory
extends RefCounted
## Inventario del jugador: objetos por id (data/items.json) con cantidad. Al extraer se suma el valor.
## Las armas, la munición y las granadas que se recogen se aplican al Actor (Inventory.apply_pickup).

signal changed

static var _items := {}
var items := {}          ## id → cantidad

static func defs() -> Dictionary:
	if _items.is_empty():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
		for k in d:
			if not str(k).begins_with("_"):
				_items[k] = d[k]
	return _items

static func def(id: String) -> Dictionary:
	return defs().get(id, {"name": id, "type": "componente", "value": 0})

func add(id: String, n := 1) -> void:
	items[id] = int(items.get(id, 0)) + n
	changed.emit()

func remove(id: String, n := 1) -> bool:
	if int(items.get(id, 0)) < n:
		return false
	items[id] = int(items[id]) - n
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	return true

func count(id: String) -> int:
	return int(items.get(id, 0))

func total_value() -> int:
	var v := 0
	for id in items:
		v += int(def(id).get("value", 0)) * int(items[id])
	return v

## Aplica un objeto recogido al personaje (munición al arma que corresponde, armas al slot, granadas a la riñonera).
## Devuelve el texto para el aviso del HUD.
static func apply_pickup(actor: Actor, id: String, n: int) -> String:
	var d := def(id)
	match str(d.get("type", "")):
		"municion":
			var amount := int(d.get("amount", 10)) * n
			for slot_name in actor.weapons:
				var w: Firearm = actor.weapons[slot_name]
				if w.id in d.get("ammo_for", []):
					w.reserve += amount
					return "+%d %s" % [amount, d.name]
			actor.inventory.add(id, n)
			return "%s (guardada)" % d.name
		"arma":
			var wid := str(d.weapon)
			var slot_name := "secondary" if Firearm.all_stats()[wid].hold == "pistol" else "primary"
			if actor.weapons.has(slot_name) and (actor.weapons[slot_name] as Firearm).id == wid:
				(actor.weapons[slot_name] as Firearm).reserve += int(Firearm.all_stats()[wid].mag)
				return "+munición %s" % d.name
			if actor.weapons.has(slot_name):
				actor.inventory.add("w_" + (actor.weapons[slot_name] as Firearm).id, 1)
			actor.give_weapon(slot_name, wid)
			actor.equip(slot_name)
			return "Nueva arma: %s" % d.name
		"mina":
			actor.mines += n
			return "+%d %s" % [n, d.name]
		"explosivo":
			var g := str(d.grenade)
			actor.grenades[g] = int(actor.grenades.get(g, 0)) + n
			return "+%d %s" % [n, d.name]
		_:
			actor.inventory.add(id, n)
			return "+%d %s" % [n, d.name] if n > 1 else str(d.name)

## Tira objetos de una tabla de botín (data/loot_tables.json). Devuelve [[id, cantidad], …].
static var _tables := {}
static func roll(table: String, bonus := 0, rng: RandomNumberGenerator = null) -> Array:
	if _tables.is_empty():
		_tables = JSON.parse_string(FileAccess.get_file_as_string("res://data/loot_tables.json"))
	var t: Dictionary = _tables.get(table, {})
	if t.is_empty():
		return []
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var out := []
	var total := 0
	for e in t.items:
		total += int(e[1])
	for r in int(t.rolls) + bonus:
		var x := rng.randi_range(0, total - 1)
		for e in t.items:
			x -= int(e[1])
			if x < 0:
				out.append([str(e[0]), rng.randi_range(int(e[2]), int(e[3]))])
				break
	return out
