class_name Interactable
extends Area3D
## Algo que se puede USAR (botón contextual): contenedores, panel de ascensor, puertas con llave, objetos sueltos,
## zona de extracción. El Actor detecta los Interactable cercanos con su área «reach» (capa 6 = 32).

@export var prompt := "Usar"
@export var radius := 0.9

func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	monitoring = false
	monitorable = true
	if get_child_count() == 0 or not _has_shape():
		var cs := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = radius
		cs.shape = s
		add_child(cs)
	add_to_group("interactables")

func _has_shape() -> bool:
	for c in get_children():
		if c is CollisionShape3D:
			return true
	return false

func can_use(_actor: Actor) -> bool:
	return true

func prompt_for(_actor: Actor) -> String:
	return prompt

func use(_actor: Actor) -> void:
	pass
