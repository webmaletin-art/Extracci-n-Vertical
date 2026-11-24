extends SceneTree
## Exporta el proyectil de BLACK VEIL (assets/ammo/projectile.mesh) a GLB para trabajarlo en Blender.
## Uso: godot --headless --path . -s tools/ammo/export_projectile.gd -- <salida.glb>
func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://assets/ammo/projectile.mesh")
	var root := Node3D.new()
	root.add_child(mi)
	mi.owner = root
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_node(root, st)
	doc.write_to_filesystem(st, out)
	var a: AABB = mi.mesh.get_aabb()
	print("proyectil: ", a, " triángulos aprox ", mi.mesh.get_faces().size() / 3)
	quit()
