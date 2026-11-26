extends Node
## Perfil del jugador (autoload «Profile»): créditos, armas compradas y equipadas, munición por tipo y tipo elegido por arma. Se guarda en
## user://perfil.json. Es una capa local: más adelante `ProfileStore` puede sincronizarla con un servidor (sin credenciales inventadas).
## Reglas: la munición sólo se compra para un arma que ya se tiene; las armas y la munición se pagan con créditos (una sola moneda).

signal changed

const PATH := "user://perfil.json"
const START_CREDITS := 6000

var credits := START_CREDITS
var owned: Array = ["m1911", "m4a1"]
var equipped := {"primary": "m4a1", "secondary": "m1911"}
var ammo := {}                    ## "<calibre>_<tipo>" → cartuchos en el depósito
var selected := {}                ## arma → tipo de munición elegido

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_profile()

func reset() -> void:
	credits = START_CREDITS
	owned = ["m1911", "m4a1"]
	equipped = {"primary": "m4a1", "secondary": "m1911"}
	ammo = {"45acp_std": 96, "556_std": 180}
	selected = {}
	save()
	changed.emit()

func has_weapon(id: String) -> bool:
	return owned.has(id)

func weapon_price(id: String) -> int:
	return int(Firearm.all_stats()[id].get("price", 0))

func can_buy_weapon(id: String) -> bool:
	return not has_weapon(id) and credits >= weapon_price(id)

func buy_weapon(id: String) -> bool:
	if not can_buy_weapon(id):
		return false
	credits -= weapon_price(id)
	owned.append(id)
	save()
	changed.emit()
	return true

func slot_for(id: String) -> String:
	return "secondary" if str(Firearm.all_stats()[id].get("hold", "rifle")) == "pistol" else "primary"

func equip(id: String) -> void:
	if not has_weapon(id):
		return
	equipped[slot_for(id)] = id
	save()
	changed.emit()

func ammo_type(weapon_id: String) -> String:
	return str(selected.get(weapon_id, "std"))

func select_ammo(weapon_id: String, type: String) -> void:
	selected[weapon_id] = type
	save()
	changed.emit()

func rounds(weapon_id: String, type: String) -> int:
	return int(ammo.get(Ammo.item_id(weapon_id, type), 0))

## ¿Se puede comprar esa munición para esa arma? (hay que tener el arma y alcanzar los créditos)
func can_buy_ammo(weapon_id: String, type: String) -> bool:
	return has_weapon(weapon_id) and credits >= int(Ammo.item(weapon_id, type).get("price", 1 << 30))

func buy_ammo(weapon_id: String, type: String) -> bool:
	if not can_buy_ammo(weapon_id, type):
		return false
	var it := Ammo.item(weapon_id, type)
	credits -= int(it.price)
	var key := Ammo.item_id(weapon_id, type)
	ammo[key] = int(ammo.get(key, 0)) + int(it.box)
	save()
	changed.emit()
	return true

func add_rounds(weapon_id: String, type: String, n: int) -> void:
	var key := Ammo.item_id(weapon_id, type)
	ammo[key] = maxi(int(ammo.get(key, 0)) + n, 0)

func add_credits(n: int) -> void:
	credits = maxi(credits + n, 0)
	save()
	changed.emit()

func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"credits": credits, "owned": owned, "equipped": equipped, "ammo": ammo, "selected": selected}, "\t"))

func load_profile() -> void:
	if not FileAccess.file_exists(PATH):
		reset()
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary:
		credits = int(d.get("credits", START_CREDITS))
		owned = (d.get("owned", ["m1911", "m4a1"]) as Array).filter(func(x): return Firearm.all_stats().has(str(x)))
		equipped = d.get("equipped", equipped)
		ammo = d.get("ammo", {})
		selected = d.get("selected", {})
		for slot in ["primary", "secondary"]:
			if not Firearm.all_stats().has(str(equipped.get(slot, ""))) or not owned.has(equipped.get(slot, "")):
				equipped[slot] = "m4a1" if slot == "primary" else "m1911"
		if not owned.has("m1911"):
			owned.append("m1911")
		if not owned.has("m4a1"):
			owned.append("m4a1")

## Carga un arma de la partida con lo que hay en el depósito: hasta 5 cargadores por tipo salen con el jugador.
func load_weapon(w: Firearm) -> void:
	if w == null:
		return
	var id := w.id
	var per_mag := int(Firearm.all_stats()[id].mag)
	w.reserves.clear()
	w.reserve = 0
	w.ammo_type = "std"
	var first := ""
	for t in Ammo.TYPE_ORDER:
		var carry := mini(rounds(id, t), per_mag * (8 if Ammo.is_shotgun(id) else 5))
		if carry > 0:
			w.reserves[t] = carry
			add_rounds(id, t, -carry)
			if first == "":
				first = t
	var want := ammo_type(id)
	w.set_ammo(want if w.reserves.has(want) else (first if first != "" else "std"))
	save()

## Al extraer, lo que sobró vuelve al depósito (si se muere, se pierde).
func store_weapon(w: Firearm) -> void:
	if w == null:
		return
	w.reserves[w.ammo_type] = w.reserve + w.mag
	for t in w.reserves:
		add_rounds(w.id, str(t), int(w.reserves[t]))
	w.reserves.clear()
	save()
