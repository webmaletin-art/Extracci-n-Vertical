class_name Firearm
extends Node3D
## Arma de fuego en mano: modelo 3D (de Operación Nexus) + estado (cargador, reserva, cadencia, recarga) + datos de
## data/weapons.json. No decide hacia dónde se dispara: recibe la dirección de apuntado del Actor (apuntado persistente)
## y pide los proyectiles a Ballistics. Marcadores del modelo (espacio del arma, -Z adelante): Grip, Support, Muzzle, Sight.

signal fired(shots: int)
signal reloaded

var id := ""
var stats := {}
var model: Node3D
var grip := Vector3.ZERO
var support := Vector3.ZERO
var extended := false                ## subfusil sin culata: brazos estirados (como pistola) con las dos manos
var support_kind := "rail"            ## "rail" guardamanos (palma arriba) · "vgrip" empuñadura vertical · "pistol"
var muzzle := Vector3.ZERO
var butt := Vector3.ZERO
var length := 0.7
var mag := 0
var reserve := 0
var is_pistol := false
var reloading := false
var reload_t := 0.0
var _next_shot := 0.0
var _trigger_was := false
var ammo_type := "std"          ## tipo de munición cargada (Ammo.TYPE_ORDER)
var reserves := {}               ## tipo de munición → cartuchos de reserva (con más de un tipo a mano)
var ammo_fx := {}                ## lo que el proyectil le hace al cuerpo (Ammo.fx)
var cycle_left := 0.0          ## cerrojo / corredera de bombeo (escopeta, francotirador)

static var _all := {}
static var _models := {}

static func all_stats() -> Dictionary:
	if _all.is_empty():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
		for k in d:
			if not str(k).begins_with("_"):
				_all[k] = d[k]
	return _all

## Resumen de capacidades de un arma (para el modo práctica y la tienda): calibre, daño, cadencia, DPS, alcance, cargador, recarga.
## Cambia el tipo de munición cargada (recalcula daño, penetración, rebote, velocidad y dispersión).
func set_ammo(type: String) -> void:
	reserves[ammo_type] = reserve                  # lo que quedaba del tipo anterior
	ammo_type = type
	reserve = int(reserves.get(type, 0))
	stats = Ammo.apply(all_stats()[id], id, type)
	ammo_fx = Ammo.fx(id, type)

static func summary(stats: Dictionary) -> String:
	var pellets := int(stats.get("pellets", 1))
	var dmg := float(stats.get("damage", 0))
	var rpm := float(stats.get("rpm", 0))
	var dps := dmg * pellets * rpm / 60.0
	var dmg_txt := ("%d×%d" % [int(dmg), pellets]) if pellets > 1 else str(int(dmg))
	var ttk := int(ceil(100.0 / maxf(dmg * (pellets if pellets > 1 else 1), 1.0)))
	return "%s · daño %s · %d disp/min (%s) · DPS %d · %d tiros p/ 100 de vida\nalcance %d m · cargador %d · recarga %.1f s · dispersión %.1f° · retroceso %.1f°" % [
		str(stats.get("caliber", "—")), dmg_txt, int(rpm), "auto" if bool(stats.get("auto", false)) else "semi", int(dps), ttk,
		int(stats.get("range", 0)), int(stats.get("mag", 0)), float(stats.get("reload", 0)), float(stats.get("spread", 0)), float(stats.get("recoil", 0))]

static func models() -> Dictionary:
	if _models.is_empty():
		_models = JSON.parse_string(FileAccess.get_file_as_string("res://assets/weapons/models.json"))
	return _models

static func create(weapon_id: String) -> Firearm:
	var f := Firearm.new()
	f.id = weapon_id
	f.name = weapon_id
	f.stats = all_stats()[weapon_id]
	f.ammo_fx = Ammo.fx(weapon_id, "std")
	var mpath := "res://assets/weapons/%s.scn" % f.stats.model
	if not ResourceLoader.exists(mpath):
		mpath = "res://assets/weapons/%s.glb" % f.stats.model        # armas nuevas (tools/weapons/convert_fbx.py)
	var lp := LinedBake.lined_path("weapons", str(f.stats.model))
	if lp != "":
		f.model = (load(lp) as PackedScene).instantiate()          # ya en línea (sin texturas ni colores): no se convierte al vuelo
	else:
		f.model = (load(mpath) as PackedScene).instantiate()
		WeaponMaterials.apply(str(f.stats.model), f.model)
	f.add_child(f.model)
	_set_shadow(f.model)
	var mk: Dictionary = models().get(str(f.stats.model), {}).get("markers", {})
	f.grip = _marker(f.model, "Grip", mk)
	f.support = _marker(f.model, "Support", mk)
	f.muzzle = _marker(f.model, "Muzzle", mk)
	f.support_kind = str(models().get(str(f.stats.model), {}).get("support_kind", "rail"))
	f.length = float(models().get(str(f.stats.model), {}).get("length", 0.8))
	f.butt = Vector3(0.0, f.muzzle.y - 0.045, f.muzzle.z + f.length - 0.015)
	f.is_pistol = str(f.stats.hold) == "pistol"
	# sin culata (la empuñadura está en el último cuarto del arma): se sostiene con los brazos estirados, no al hombro
	f.extended = not f.is_pistol and bool(models().get(str(f.stats.model), {}).get("stockless", false))
	f.mag = int(f.stats.mag)
	f.reserve = int(f.stats.reserve)
	return f

static func _marker(m: Node3D, n: String, mk: Dictionary) -> Vector3:
	var node := m.get_node_or_null(n) as Node3D
	if node:
		return node.position
	var a: Array = mk.get(n, [0, 0, 0])
	return Vector3(a[0], a[1], a[2])

static func _set_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_shadow(c)

func display_name() -> String:
	return str(stats.get("name", id))

func muzzle_world() -> Vector3:
	return global_transform * muzzle

func interval() -> float:
	return 60.0 / maxf(float(stats.rpm), 1.0)

## Gatillo: devuelve true si salió un disparo este cuadro. now = segundos de juego.
func trigger(down: bool, now: float) -> bool:
	var pressed := down and not _trigger_was
	_trigger_was = down
	if reloading or not down:
		return false
	if not bool(stats.auto) and not pressed:
		return false
	if now < _next_shot or cycle_left > 0.0:
		return false
	if mag <= 0:
		if pressed:
			Sfx.play("bv_dry_fire", global_position, -6.0)
		return false
	mag -= 1
	_next_shot = now + interval()
	if stats.has("cycle_sound"):
		cycle_left = interval() * 0.8
	fired.emit(int(stats.pellets))
	return true

func can_reload() -> bool:
	return not reloading and mag < int(stats.mag) and reserve > 0

func start_reload() -> bool:
	if not can_reload():
		return false
	reloading = true
	reload_t = float(stats.reload)
	var holder := get_parent()
	while holder and not holder is Actor:
		holder = holder.get_parent()
	if holder and (holder as Actor).injuries.arm > 0.0:
		reload_t *= 1.0 + (holder as Actor).injuries.arm * 0.6     # brazo herido: recarga más lenta
	Sfx.play(str(stats.get("reload_sound", "mag_out")), global_position, -4.0, 1.0, 6.0, get_parent())
	return true

func cancel_reload() -> void:
	reloading = false

func tick(delta: float) -> void:
	if cycle_left > 0.0:
		var before := cycle_left
		cycle_left -= delta
		if before > interval() * 0.4 and cycle_left <= interval() * 0.4:
			Sfx.play(str(stats.cycle_sound), global_position, -5.0)
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			reloading = false
			var need := int(stats.mag) - mag
			var take := mini(need, reserve)
			mag += take
			reserve -= take
			reloaded.emit()
