class_name LootContainer
extends Interactable
## Contenedor de botín (caja de madera, caja metálica, maletín, caja del laboratorio).
## Tres formas de abrir, con ruido distinto para la IA:
##  * ABRIR EN SILENCIO con el cuchillo: el personaje se arrodilla y fuerza la cerradura (open_time s). Suenan metal
##    rozando, madera que cruje y la cerradura que cede; poco ruido.
##  * FORZAR sin cuchillo (a golpes con la mano): la mitad de tiempo pero mucho más ruido.
##  * DESTRUIR: si el contenedor es rompible (Destructible) se puede romper a tiros o golpes y suelta el botín.
## Al abrirse la tapa se levanta (animación), aparecen los objetos y entran al inventario.

signal opened(by: Actor)

@export var table := "crate_wood"
@export var open_time := 2.6
@export var floor_bonus := 0
var is_open := false
var lid: Node3D
var _rng := RandomNumberGenerator.new()
var _last_sfx := 0.0

func _ready() -> void:
	super._ready()
	prompt = "Abrir con cuchillo"

func can_use(actor: Actor) -> bool:
	return not is_open and actor.state == Actor.State.GROUND

func prompt_for(actor: Actor) -> String:
	return "Abrir con cuchillo (silencioso)" if actor.has_knife else "Forzar (ruidoso)"

func use(actor: Actor) -> void:
	if is_open:
		return
	var quiet := actor.has_knife
	var secs := open_time if quiet else open_time * 0.55
	if quiet and actor.current != "knife":
		actor.equip("knife")
	var metal := table in ["crate_metal", "lab_case", "suitcase"]
	_last_sfx = 0.0
	actor.facing = signf(global_position.x - actor.global_position.x) if absf(global_position.x - actor.global_position.x) > 0.05 else actor.facing
	Sfx.play("knife_insert" if quiet else "crate_force", global_position, -4.0, 1.0, 3.0 if quiet else 16.0, actor)
	actor.begin_task("kneel_work", secs, func(): _open(actor), func(k: float):
		# sonidos realistas mientras se fuerza: rasguño de metal / crujido de madera / cerradura
		if k - _last_sfx > (0.22 if quiet else 0.15):
			_last_sfx = k
			var s := ("metal_scrape" if metal else "wood_creak") if randf() < 0.7 else "lock_rattle"
			Sfx.play(s, global_position, -8.0 if quiet else 0.0, randf_range(0.9, 1.1), 3.5 if quiet else 15.0, actor))

func _open(actor: Actor) -> void:
	if is_open:
		return
	is_open = true
	Sfx.play("lock_open", global_position, -2.0, 1.0, 4.0, actor)
	Sfx.play("lid_open", global_position, -2.0, 1.0, 4.0, actor)
	if lid:
		var tw := create_tween()
		tw.tween_property(lid, "rotation:x", deg_to_rad(-105.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	give_loot(actor)
	opened.emit(actor)

## Entrega el botín (también lo llama Destructible al romperse un contenedor).
func give_loot(actor: Actor) -> Array:
	is_open = true
	_rng.randomize()
	var items := Inventory.roll(table, floor_bonus, _rng)
	var msgs := []
	if actor and is_instance_valid(actor):
		for it in items:
			msgs.append(Inventory.apply_pickup(actor, it[0], it[1]))
		if actor.is_player and actor.has_signal("damaged"):
			for m in msgs:
				actor.get_tree().call_group("hud", "toast", m)
	Fx.emit("spark", global_position + Vector3.UP * 0.3, Vector3.UP, 0.3)
	Sfx.play("pickup", global_position, -4.0)
	return items
