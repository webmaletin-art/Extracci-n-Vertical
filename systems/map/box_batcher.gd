class_name BoxBatcher
extends RefCounted
## Junta muchas cajas (losas, paredes, escombros) en UNA malla por material: pocas llamadas de dibujo en el teléfono.
## UV en espacio mundo (cada cara se proyecta según su normal), así las texturas tileables no se estiran.

var _st := {}            ## clave de material → SurfaceTool
var _mats := {}
var tris := 0

func add_box(mat_key: String, mat: Material, center: Vector3, size: Vector3, basis := Basis.IDENTITY, uv_scale := 0.5) -> void:
	if not _st.has(mat_key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[mat_key] = st
		_mats[mat_key] = mat
	var st: SurfaceTool = _st[mat_key]
	var h := size * 0.5
	# 6 caras: normal, eje u, eje v
	var faces := [[Vector3.RIGHT, Vector3.BACK, Vector3.UP], [Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.LEFT, Vector3.UP]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var corners := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
		var wn := (basis * n).normalized()
		var pts := []
		var uvs := []
		for p in corners:
			var wp: Vector3 = center + basis * (p as Vector3)
			pts.append(wp)
			# proyección según la cara (mundo)
			var an := wn.abs()
			var uv: Vector2
			if an.x >= an.y and an.x >= an.z:
				uv = Vector2(wp.z, -wp.y)
			elif an.y >= an.z:
				uv = Vector2(wp.x, wp.z)
			else:
				uv = Vector2(wp.x, -wp.y)
			uvs.append(uv * uv_scale)
		# Godot dibuja la cara delantera en sentido horario visto desde afuera
		var order := [0, 2, 1, 0, 3, 2] if u.cross(v).dot(n) > 0.0 else [0, 1, 2, 0, 2, 3]
		for idx in order:
			st.set_normal(wn)
			st.set_uv(uvs[idx])
			st.add_vertex(pts[idx])
		tris += 2

## Crea los MeshInstance3D (uno por material) bajo `parent`.
func commit(parent: Node3D, cast_shadow := true) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for k in _st:
		var st: SurfaceTool = _st[k]
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Batch_" + str(k)
		mi.mesh = mesh
		mi.material_override = _mats[k]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		out.append(mi)
	_st.clear()
	return out
