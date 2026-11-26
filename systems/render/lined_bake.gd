class_name LinedBake
extends RefCounted
## Versión «en línea» de los modelos, calculada UNA vez (tools/bake_lined.gd) y guardada en assets/lined/: sin texturas ni colores
## originales (un tono plano por pieza, con el mismo shader del estilo «Plano dibujado»), con las aristas ya dibujadas dentro
## del archivo. En el juego se cargan tal cual: no hay conversión al vuelo ni destello de color. Lo que lleva la marca
## `no_tech` no pasa por TechView.

const OUT := "res://assets/lined/"

static var _flat: ShaderMaterial
static var _lines: ShaderMaterial

## ¿La arquitectura se arma ya «en línea»? (no en pruebas sin pantalla: ahí no hay datos de malla para las aristas)
static func native_lines() -> bool:
	return DisplayServer.get_name() != "headless"

static func flat_material() -> ShaderMaterial:
	if _flat == null:
		_flat = ShaderMaterial.new()
		_flat.shader = load("res://systems/render/tech_flat.gdshader")
	return _flat

static func lines_material() -> ShaderMaterial:
	if _lines == null:
		_lines = ShaderMaterial.new()
		_lines.shader = load("res://systems/render/tech_lines.gdshader")
	return _lines

## Ruta de la versión en línea de un modelo (o "" si todavía no existe).
static func lined_path(kind: String, id: String) -> String:
	var p := OUT + kind + "/" + id + ".scn"
	return p if ResourceLoader.exists(p) else ""

## Color medio de un material (albedo × textura media): el tono que tendría el dibujo.
static func material_color(src: Material) -> Color:
	var col := Color(0.8, 0.8, 0.8)
	if src is StandardMaterial3D:
		var sm := src as StandardMaterial3D
		col = sm.albedo_color
		if sm.albedo_texture:
			var img := sm.albedo_texture.get_image()
			if img:
				if img.is_compressed():
					img.decompress()
				img.resize(8, 8)
				var acc := Color(0, 0, 0, 0)
				for y in 8:
					for x in 8:
						acc += img.get_pixel(x, y)
				acc /= 64.0
				col = Color(col.r * acc.r, col.g * acc.g, col.b * acc.b, col.a)
	return col

static func lines_for(mesh: Mesh) -> ArrayMesh:
	var edges := {}          # clave → [a, b, normal, usos]
	var q := func(v: Vector3) -> Vector3i: return Vector3i((v * 500.0).round())
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ii = arr[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = ii if ii != null and (ii as PackedInt32Array).size() > 0 else PackedInt32Array(range(vv.size()))
		if idx.size() > 120000:
			continue                      # malla enorme: no vale la pena (no hay en el mapa)
		for t in range(0, idx.size() - 2, 3):
			var p := [vv[idx[t]], vv[idx[t + 1]], vv[idx[t + 2]]]
			var n: Vector3 = ((p[1] - p[0]) as Vector3).cross(p[2] - p[0])
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			for e in 3:
				var a: Vector3 = p[e]
				var b: Vector3 = p[(e + 1) % 3]
				var ka: Vector3i = q.call(a)
				var kb: Vector3i = q.call(b)
				var key := [ka, kb] if str(ka) < str(kb) else [kb, ka]
				var ks := str(key)
				if edges.has(ks):
					var ed: Array = edges[ks]
					ed[3] = int(ed[3]) + 1
					if absf((ed[2] as Vector3).dot(n)) < 0.9:
						ed[4] = true      # pliegue
				else:
					edges[ks] = [a, b, n, 1, false]
	var verts := PackedVector3Array()
	var custom := PackedFloat32Array()
	var ind := PackedInt32Array()
	for ks in edges:
		var ed: Array = edges[ks]
		if int(ed[3]) >= 2 and not ed[4]:
			continue                      # arista interna de una cara plana (diagonal de un rectángulo): no se dibuja
		var a: Vector3 = ed[0]
		var b: Vector3 = ed[1]
		var base := verts.size()
		for c in [[a, b, -1.0], [a, b, 1.0], [b, a, 1.0], [b, a, -1.0]]:
			verts.append(c[0])
			var o: Vector3 = c[1]
			custom.append_array([o.x, o.y, o.z, float(c[2])])
		ind.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if verts.is_empty():
		return null
	var la := []
	la.resize(Mesh.ARRAY_MAX)
	la[Mesh.ARRAY_VERTEX] = verts
	la[Mesh.ARRAY_CUSTOM0] = custom
	la[Mesh.ARRAY_INDEX] = ind
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, la, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return am
