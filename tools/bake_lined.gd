extends SceneTree
## Genera las versiones «en línea» (assets/lined/) de armas y props.
## Uso: godot --headless --path . --script tools/bake_lined.gd -- weapons|props|all
## Cada malla pierde su textura y su color (queda un tono plano con el shader tech_surface), lleva el contorno de silueta
## (segundo pase) y, si es un objeto fijo (props), también sus aristas dibujadas como una malla hija. Se marca `no_tech`.
var _mats := {}
var _outline: ShaderMaterial
var _flat: ShaderMaterial

func _initialize() -> void:
	var what := "all"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		what = a[0]
	_outline = ShaderMaterial.new()
	_outline.shader = load("res://systems/render/tech_outline.gdshader")
	_flat = ShaderMaterial.new()
	_flat.shader = load("res://systems/render/tech_flat.gdshader")
	var n := 0
	if what in ["weapons", "all"]:
		var w = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
		var done := {}
		for k in w:
			if str(k).begins_with("_") or done.has(w[k].model):
				continue
			done[w[k].model] = true
			var m := str(w[k].model)
			var path := "res://assets/weapons/%s.scn" % m
			if not ResourceLoader.exists(path):
				path = "res://assets/weapons/%s.glb" % m
			var inst := (load(path) as PackedScene).instantiate()
			WeaponMaterials.apply(m, inst)
			n += _bake(inst, "weapons", m, false)
	if what in ["props", "all"]:
		for f in DirAccess.get_files_at("res://assets/props"):
			if f.ends_with(".glb"):
				var id := f.get_basename()
				var inst := (load("res://assets/props/" + f) as PackedScene).instantiate()
				n += _bake(inst, "props", id, true)
	if what in ["characters", "all"]:
		for c in CharacterModel.all():
			var inst := (load(str(c.path)) as PackedScene).instantiate()
			n += _bake(inst, "characters", str(c.id), false, true)
	print("BAKE: %d modelos en línea" % n)
	quit()

func _mat_for(src: Material) -> ShaderMaterial:
	var col := LinedBake.material_color(src)
	var key := col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://systems/render/tech_surface.gdshader")
	m.set_shader_parameter("has_tex", false)
	m.set_shader_parameter("albedo", Color(col.r, col.g, col.b, 1.0))
	m.next_pass = _outline
	_mats[key] = m
	return m

func _bake(root: Node, kind: String, id: String, with_lines: bool, vertex_color := false) -> int:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for n in meshes:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		# el mesh importado puede traer su propio material con texturas externas: se quita (si no, el archivo quedaría atado a ellas)
		if not vertex_color:
			for s in mi.mesh.get_surface_count():
				mi.mesh.surface_set_material(s, null)
		if with_lines:
			# objetos fijos / sueltos del mapa: relleno plano (tech_flat) + aristas dibujadas, igual que el estilo en vivo
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, null)
			mi.material_override = _flat
		elif vertex_color:
			_bake_vertex_colors(mi)
		else:
			# lo que se lleva en la mano o se mueve (armas): tono por pieza + contorno de silueta
			for s in mi.mesh.get_surface_count():
				var src: Material = mi.get_surface_override_material(s)
				if src == null:
					src = mi.mesh.surface_get_material(s)
				mi.set_surface_override_material(s, _mat_for(src))
			mi.material_override = null
		if with_lines:
			var ln := LinedBake.lines_for(mi.mesh)
			if ln:
				var lm := MeshInstance3D.new()
				lm.name = "Lineas"
				lm.mesh = ln
				var lmat := ShaderMaterial.new()
				lmat.shader = load("res://systems/render/tech_lines.gdshader")
				lm.material_override = lmat
				lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				lm.extra_cull_margin = 0.5
				mi.add_child(lm)
	root.set_meta("no_tech", true)
	root.set_meta("lined", true)
	_own(root, root)
	var ps := PackedScene.new()
	if ps.pack(root) != OK:
		push_error("no se pudo empaquetar " + id)
		return 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LinedBake.OUT + kind))
	ResourceSaver.save(ps, LinedBake.OUT + kind + "/" + id + ".scn")
	root.free()
	return 1

func _own(n: Node, owner_: Node) -> void:
	for c in n.get_children():
		c.owner = owner_
		_own(c, owner_)

## Personajes: el color de la textura se hornea en los vértices (COLOR) y el material ya no lleva textura.
func _bake_vertex_colors(mi: MeshInstance3D) -> void:
	var old := mi.mesh
	var nm := ArrayMesh.new()
	var mats := []
	for s in old.get_surface_count():
		var arrays := old.surface_get_arrays(s)
		var src: Material = mi.get_surface_override_material(s)
		if src == null:
			src = old.surface_get_material(s)
		var img: Image = null
		var base := Color(1, 1, 1, 1)
		if src is StandardMaterial3D:
			base = (src as StandardMaterial3D).albedo_color
			var tex := (src as StandardMaterial3D).albedo_texture
			if tex:
				img = tex.get_image()
				if img.is_compressed():
					img.decompress()
		var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv = arrays[Mesh.ARRAY_TEX_UV]
		var cols := PackedColorArray()
		cols.resize(vv.size())
		for k in vv.size():
			var c := Color(1, 1, 1, 1)
			if img and uv != null:
				var u: Vector2 = (uv as PackedVector2Array)[k]
				var x := int(clampf(fposmod(u.x, 1.0), 0.0, 0.9999) * img.get_width())
				var y := int(clampf(fposmod(u.y, 1.0), 0.0, 0.9999) * img.get_height())
				c = img.get_pixel(x, y)
			cols[k] = c
		arrays[Mesh.ARRAY_COLOR] = cols
		var flags := 0
		var bones = arrays[Mesh.ARRAY_BONES]
		if bones != null and (bones as PackedInt32Array).size() == vv.size() * 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		nm.add_surface_from_arrays(old.surface_get_primitive_type(s), arrays, [], {}, flags)
		nm.surface_set_name(nm.get_surface_count() - 1, old.surface_get_name(s))
		var key := "vc|" + base.to_html()
		if not _mats.has(key):
			var m := ShaderMaterial.new()
			m.shader = load("res://systems/render/tech_surface_vc.gdshader")
			m.set_shader_parameter("albedo", Color(base.r, base.g, base.b, 1.0))
			m.next_pass = _outline
			_mats[key] = m
		mats.append(_mats[key])
	mi.mesh = nm
	for s in mats.size():
		mi.set_surface_override_material(s, mats[s])
	mi.material_override = null
