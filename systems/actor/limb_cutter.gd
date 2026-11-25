class_name LimbCutter
extends SkeletonModifier3D
## Miembro cortado: los huesos de la lista se achican a casi cero DESPUÉS de cada animación, así el brazo / pierna / cabeza
## (traje, huesos y órganos, que usan el mismo esqueleto) desaparece del cuerpo y queda sólo el muñón. Se usa 0,001 y no 0
## para que las matrices de los huesos sigan siendo invertibles (el trazado de balas las invierte).

var cut := PackedInt32Array()

func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for b in cut:
		sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)
