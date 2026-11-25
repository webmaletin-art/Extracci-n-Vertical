extends Node
## Rebotes: dispara 40 veces a la chapa inclinada del campo de práctica y cuenta cuántas balas rebotan.
func _ready() -> void:
	var pg := PracticeGame.new()
	add_child(pg)
	for i in 30:
		await get_tree().process_frame
	pg.controller.set_physics_process(false)
	var b := Ballistics.instance
	var rico := 0
	for k in 40:
		var i := b.fire(Vector3(22.0, 1.2, 0), Vector3(1, 0, 0), 340.0, 30.0, pg.player, [], {"ricochet": 0.25, "penetration": 6})
		for f in 20:
			await get_tree().physics_frame
			if b._kind[i] == "ricochet":
				rico += 1
				break
	print("REBOTES ", rico, " de 40 (munición normal contra la chapa a 65°)")
	get_tree().quit()
