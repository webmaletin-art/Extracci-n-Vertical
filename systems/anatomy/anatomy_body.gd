class_name AnatomyBody
extends Node
## Anatomía interna de UN personaje: la de Z-Anatomy ajustada a su cuerpo por tools/anatomy/fit_anatomy.gd
## (assets/anatomy/fit/<id>.scn). Son mallas con piel que usan el MISMO esqueleto y los MISMOS pesos que el personaje,
## así que van siempre dentro del cuerpo y se mueven con cualquier animación.
##
##  * trace(): recorre la trayectoria de un proyectil o de una esquirla por adentro del cuerpo y devuelve, en orden, cada
##    estructura que atraviesa (hueso, músculo, órgano, vaso, nervio) con su punto de entrada y salida. Se calcula en el
##    espacio de enlace (el de la malla sin deformar) con el hueso dominante de cada grupo, contra los triángulos reales.
##  * Las heridas se guardan en ese espacio de enlace: quedan pegadas al órgano aunque el cuerpo se mueva.
##  * RAYOS X LOCALIZADOS (como Sniper Elite): el cuerpo y la ropa se siguen viendo; sólo en la zona de la herida se abre
##    una ventana de rayos X (borde azul) y adentro se ve lo que hay ahí: huesos, órganos, arterias y venas, ojos, cerebro,
##    los músculos dañados y el proyectil (en vuelo o alojado y aplastado).
##  * Huesos rotos DE VERDAD: Blender los partió en fragmentos (tools/anatomy/fracture_bones.py). Al quebrarse se ven
##    las grietas entre fragmentos y los más cercanos al impacto se desprenden y salen volando (Gibs).
##  * Shader de heridas sobre la anatomía: túnel de bala, esquirla alojada, estallido. Usa la posición de enlace (CUSTOM0).

const FIT_DIR := "res://assets/anatomy/fit/"
const MAX_WOUNDS := 6
static var only_system := ""          ## (prueba) dibuja sólo ese sistema
static var hide_muscles := true       ## los rayos X no dibujan músculos: huesos, órganos, vasos y ojos (como Sniper Elite)

static var _scenes := {}         ## id → PackedScene
static var _cpu := {}            ## id → {node: {v, i, aabb, label, system, bone, center}}
static var _cpu_frags := {}      ## id → {grupo padre: [{node, mesh, v, i, b, w, center}]}
static var _frag_shader: Shader
static var _zone_skin_shader: Shader
static var _wound_shader: Shader
static var _flash_shader: Shader
static var _skin_shader: Shader

var actor: Actor
var skel: Skeleton3D
var skin: Skin
var mesh_xf := Transform3D.IDENTITY
var groups := {}                 ## node → datos de CPU (compartidos)
var meshes := {}                 ## node → MeshInstance3D (se crean recién cuando hacen falta)
var wounds := {}                 ## node → Array de heridas {pos, dir, r, type, depth}
var _bind_of := {}               ## hueso → índice de enlace
var frags := {}                  ## grupo padre → fragmentos (compartidos)
var broken := {}                 ## grupo padre → {fragmento: true} desprendidos
var frag_meshes := {}            ## fragmento → MeshInstance3D
var lodged: Array = []           ## balas alojadas [{node, pos, dir, mi}]
var zones: Array = []            ## ventanas de rayos X [{node, pos}] (espacio de enlace)
var zone_r := 0.17
var _bone_of_bind := {}
var _show_t := 0.0
var _killcam := false
var _showing := false
var _skin_saved := {}
var _skin_mats: Array[ShaderMaterial] = []
var available := false
var _seq := 0                    ## número de la próxima herida (orden en que la bala las hizo)
var reveal_seq := 1 << 30        ## heridas visibles hasta este número (la repetición lo va subiendo)

static func for_actor(a: Actor) -> AnatomyBody:
	var x := a.get_node_or_null("Anatomia") as AnatomyBody
	if x:
		return x
	x = AnatomyBody.new()
	x.name = "Anatomia"
	x.actor = a
	a.add_child(x)
	x._setup()
	return x

## Arma los datos de CPU (triángulos para el trazado de balas, fragmentos) de un personaje. Es pesado con la anatomía
## de calidad máxima: Game lo adelanta en un hilo al empezar la partida (warm), así el primer disparo no congela el juego.
static func _build_cpu(id: String) -> void:
	var path := FIT_DIR + id + ".scn"
	if not ResourceLoader.exists(path):
		return
	var ps: PackedScene = null
	if _warming.has(id):
		ps = ResourceLoader.load_threaded_get(path)      # ya se cargó en segundo plano (o espera a que termine)
		_warming.erase(id)
	if ps == null:
		ps = load(path)
	_scenes[id] = ps
	var inst: Node = ps.instantiate()
	var data := {}
	var fr := {}
	for mi in inst.get_children():
		if not mi is MeshInstance3D:
			continue
		var m := mi as MeshInstance3D
		if m.has_meta("parent"):
			var list: Array = fr.get(str(m.get_meta("parent")), [])
			list.append({"node": str(m.name), "mesh": m.mesh, "center": m.get_meta("center_bind"),
				"r": m.mesh.get_aabb().size.length() * 0.5})
			fr[str(m.get_meta("parent"))] = list
			continue
		# el trazado de la bala usa un TriangleMesh nativo (con BVH) que se arma recién la primera vez que hace falta
		data[str(m.name)] = {"aabb": m.mesh.get_aabb(), "label": str(m.get_meta("label")), "system": str(m.get_meta("system")),
			"bone": str(m.get_meta("bone")), "center": m.get_meta("center_bind"), "radius": float(m.get_meta("radius", 0.1)),
			"mesh": m.mesh, "tm": null}
	inst.free()
	_cpu[id] = data
	_cpu_frags[id] = fr

static var _warming := {}
## Empieza a cargar en segundo plano la anatomía de un personaje (se llama al cargar la partida).
static func warm(id: String) -> void:
	if _cpu.has(id) or _warming.has(id):
		return
	var path := FIT_DIR + id + ".scn"
	if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
		_warming[id] = true

func _setup() -> void:
	skel = actor.skel
	for c in skel.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).skin:
			skin = (c as MeshInstance3D).skin
			mesh_xf = (c as MeshInstance3D).transform
	if skin == null:
		return
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			b = skel.find_bone(str(skin.get_bind_name(i)).replace(":", "_"))
		_bind_of[b] = i
		_bone_of_bind[i] = b
	var id := actor.character_id
	var path := FIT_DIR + id + ".scn"
	if not ResourceLoader.exists(path):
		push_warning("Sin anatomía ajustada para " + id + " (correr tools/anatomy/fit_anatomy.gd)")
		return
	if not _cpu.has(id):
		_build_cpu(id)
	groups = _cpu[id]
	frags = _cpu_frags[id]
	available = true

## Divide los triángulos en trozos de ~1500 con su caja: el trazado de la bala sólo prueba los trozos que cruza
## (las mallas de calidad máxima tienen decenas de miles de triángulos).
static func _make_chunks(v: PackedVector3Array, idx: PackedInt32Array) -> Array:
	var out := []
	var step := 1500 * 3
	var a := 0
	while a < idx.size():
		var b := mini(a + step, idx.size())
		var box := AABB(v[idx[a]], Vector3.ZERO)
		for k in range(a, b):
			box = box.expand(v[idx[k]])
		out.append({"aabb": box, "a": a, "b": b})
		a = b
	return out

# ---------------------------------------------------------------- espacios

## Matriz de piel (enlace → esqueleto) del hueso en la pose actual.
func _skin_mat(bone_name: String) -> Transform3D:
	var b := skel.find_bone(bone_name)
	if b < 0 or not _bind_of.has(b):
		return Transform3D.IDENTITY
	return skel.get_bone_global_pose(b) * skin.get_bind_pose(_bind_of[b])

func world_to_bind(node: String, p: Vector3) -> Vector3:
	var m := _skin_mat(groups[node].bone) * mesh_xf
	return m.affine_inverse() * (skel.global_transform.affine_inverse() * p)

func bind_to_world(node: String, p: Vector3) -> Vector3:
	return skel.global_transform * (_skin_mat(groups[node].bone) * mesh_xf) * p

func dir_to_bind(node: String, d: Vector3) -> Vector3:
	var m := (_skin_mat(groups[node].bone) * mesh_xf).basis
	return (m.inverse() * (skel.global_transform.basis.inverse() * d)).normalized()

func find_group(label_prefix: String, near_world := Vector3.INF) -> String:
	var best := ""
	var bd := INF
	for n in groups:
		if not str(groups[n].label).begins_with(label_prefix):
			continue
		var d := 0.0
		if near_world != Vector3.INF:
			d = bind_to_world(n, groups[n].center).distance_to(near_world)
		if d < bd:
			bd = d
			best = n
	return best

# ---------------------------------------------------------------- trayectorias

## Estructuras que atraviesa un segmento (mundo): [{node, label, system, t_in, t_out, p_in, p_out (enlace), dir (enlace)}]
## ordenadas por distancia de entrada. max_depth: cuánto entra (esquirla / cuchillo); INF = lo atraviesa.
func trace(origin: Vector3, dir: Vector3, length: float, max_depth := INF) -> Array:
	var out := []
	if not available:
		return out
	dir = dir.normalized()
	var first_t := INF
	for n in groups:
		var g: Dictionary = groups[n]
		var a := world_to_bind(n, origin)
		var b := world_to_bind(n, origin + dir * length)
		var aabb: AABB = (g.aabb as AABB).grow(0.01)
		if not aabb.intersects_segment(a, b) and not aabb.has_point(a):
			continue
		var tmin := INF
		var tmax := -INF
		var seg := b - a
		var sl := seg.length()
		# búsqueda nativa (BVH): primera superficie desde la entrada y desde la salida = dónde entra y dónde sale
		if g.tm == null:
			g.tm = (g.mesh as Mesh).generate_triangle_mesh()
		var tm: TriangleMesh = g.tm
		var hin: Dictionary = tm.intersect_segment(a, b)
		if not hin.is_empty():
			var hout: Dictionary = tm.intersect_segment(b, a)
			tmin = a.distance_to(hin.position) / maxf(sl, 1e-6) * length
			tmax = a.distance_to(hout.position) / maxf(sl, 1e-6) * length if not hout.is_empty() else tmin
		if tmin == INF:
			continue
		if tmax - tmin < 0.004:
			tmax = tmin + 0.004
		out.append({"node": n, "label": g.label, "system": g.system, "t_in": tmin, "t_out": tmax,
			"p_in": a + seg / sl * (tmin / length * sl), "p_out": a + seg / sl * (tmax / length * sl), "dir": seg / sl})
		first_t = minf(first_t, tmin)
	out.sort_custom(func(x, y): return x.t_in < y.t_in)
	if max_depth < INF and first_t < INF:
		out = out.filter(func(x): return x.t_in <= first_t + max_depth)
		for x in out:
			if x.t_out > first_t + max_depth:
				x.t_out = first_t + max_depth
				x["lodged"] = true
	return out

## Grupos cuyo centro está a menos de radius (mundo).
func near(point: Vector3, radius: float, system := "") -> Array:
	var out := []
	for n in groups:
		if system != "" and groups[n].system != system:
			continue
		var c := bind_to_world(n, groups[n].center)
		var d := c.distance_to(point)
		if d < radius:
			out.append([d, n])
	out.sort_custom(func(x, y): return x[0] < y[0])
	return out.map(func(x): return x[1])

# ---------------------------------------------------------------- heridas

## type: 0 fractura · 1 túnel (bala/cuchillo) · 2 estallido (onda expansiva) · 3 esquirla alojada · 4 contusión
## Repetición: muestra sólo lo que la bala ya hizo hasta la herida número `s` (INF = todo).
func set_reveal(s: int) -> void:
	if s == reveal_seq:
		return
	reveal_seq = s
	for n in meshes:
		if wounds.has(n):
			_update_material(n)
	_flush_gibs()
	if _showing:
		_refresh_visible()

## Avanza el número de herida (lo llama Injuries en cada estructura que cruza la bala, en orden).
func next_seq() -> int:
	_seq += 1
	return _seq

func add_wound(node: String, pos_bind: Vector3, dir_bind: Vector3, r: float, type: int, depth := 1.0) -> void:
	var arr: Array = wounds.get(node, [])
	if arr.size() >= MAX_WOUNDS:
		arr.pop_front()
	arr.append({"pos": pos_bind, "dir": dir_bind.normalized(), "r": r, "type": type, "depth": depth, "seq": _seq})
	wounds[node] = arr
	if meshes.has(node):
		_update_material(node)

## Hueso que se quiebra en `pos_bind`. Hasta acá el hueso se ve ENTERO (malla original); desde ahora se dibujan sus
## fragmentos de Blender: los cercanos al impacto se abren, se corren y muestran el corte (hueso esponjoso con sangre),
## los lejanos quedan en su lugar y no se nota que el hueso está partido. Sólo esquirlas CHICAS se desprenden.
## strength: 0 = sólo fisura (caída), 1 = bala, 2 = bala potente / explosión.
var break_hits := {}             ## hueso → [{pos (enlace), dir (mundo), s, seq}]
func break_bone(node: String, pos_bind: Vector3, dir_world: Vector3, strength: float) -> void:
	if not frags.has(node):
		return
	var det: Dictionary = broken.get(node, {})
	broken[node] = det
	var hits: Array = break_hits.get(node, [])
	hits.append({"pos": pos_bind, "dir": dir_world.normalized(), "s": strength, "seq": _seq})
	break_hits[node] = hits
	if strength <= 0.0:
		return
	# esquirlas: los fragmentos chicos pegados al impacto (1, o 2 si es potente o el hueso ya recibió varios tiros)
	var list: Array = frags[node]
	var order := []
	for f in list:
		if not det.has(f.node):
			order.append([(f.center as Vector3).distance_to(pos_bind), f])
	order.sort_custom(func(x, y): return x[0] < y[0])
	var n := 1 if strength < 1.5 and hits.size() < 3 else 2
	var wound_w := bind_to_world(node, pos_bind)
	var done := 0
	for o in order:
		if done >= n or o[0] > 0.035:
			break
		var f: Dictionary = o[1]
		if float(f.get("r", 1.0)) > 0.022 + 0.008 * strength:
			continue                     # los trozos grandes no salen volando: se abren en su lugar
		det[f.node] = true
		_pending_gibs.append({"f": f, "w": wound_w, "d": dir_world, "s": strength, "seq": _seq})
		done += 1
	_flush_gibs()

var _pending_gibs: Array = []
## Las esquirlas salen cuando la bala pasa por ahí (en la repetición), o en seguida si no hay repetición.
func _flush_gibs() -> void:
	var keep := []
	for g in _pending_gibs:
		if int(g.seq) <= reveal_seq:
			_spawn_gib(g.f, g.w, g.d, g.s)
		else:
			keep.append(g)
	_pending_gibs = keep

## Desplazamiento y apertura de cada fragmento de un hueso roto según la cercanía a los impactos ya revelados.
func _frag_state(node: String, f: Dictionary) -> Array:
	var k := 0.0
	var push := Vector3.ZERO
	for h in break_hits.get(node, []):
		if int(h.seq) > reveal_seq:
			continue
		var d := (f.center as Vector3).distance_to(h.pos)
		var rr := 0.025 + 0.025 * float(h.s)
		var kk := clampf(1.0 - d / rr, 0.0, 1.0)
		if kk <= 0.0:
			continue
		k = maxf(k, kk)
		var out := ((f.center as Vector3) - (h.pos as Vector3)).normalized()
		push += out * kk * 0.0025 * (0.5 + float(h.s)) + dir_to_bind(node, h.dir) * kk * 0.002 * float(h.s)
	return [k, push]

## El fragmento se vuelve un trozo suelto: se calcula su forma ACTUAL (piel por CPU con la pose del momento).
func _spawn_gib(f: Dictionary, wound_w: Vector3, dir_world: Vector3, strength: float) -> void:
	if Gibs.instance == null:
		return
	var farr := (f.mesh as Mesh).surface_get_arrays(0)
	var v: PackedVector3Array = farr[Mesh.ARRAY_VERTEX]
	var b: PackedInt32Array = farr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = farr[Mesh.ARRAY_WEIGHTS]
	var mats := {}
	var pts := PackedVector3Array()
	pts.resize(v.size())
	var center := Vector3.ZERO
	for i in v.size():
		var t := Transform3D()
		t.basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		t.origin = Vector3.ZERO
		for k in 4:
			var ww := w[i * 4 + k]
			if ww <= 0.0:
				continue
			var bi := b[i * 4 + k]
			if not mats.has(bi):
				mats[bi] = skel.global_transform * skel.get_bone_global_pose(_bone_of_bind.get(bi, 0)) * skin.get_bind_pose(bi) * mesh_xf
			var m: Transform3D = mats[bi]
			t.basis.x += m.basis.x * ww
			t.basis.y += m.basis.y * ww
			t.basis.z += m.basis.z * ww
			t.origin += m.origin * ww
		pts[i] = t * v[i]
		center += pts[i]
	center /= maxf(v.size(), 1)
	var arr := (f.mesh as Mesh).surface_get_arrays(0)
	var local := PackedVector3Array()
	local.resize(pts.size())
	for i in pts.size():
		local[i] = pts[i] - center
	var na := []
	na.resize(Mesh.ARRAY_MAX)
	na[Mesh.ARRAY_VERTEX] = local
	na[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	na[Mesh.ARRAY_COLOR] = arr[Mesh.ARRAY_COLOR]
	var st := SurfaceTool.new()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	st.create_from(am, 0)
	st.generate_normals()
	var out := (center - wound_w).normalized() if center.distance_to(wound_w) > 0.001 else dir_world
	var vel := dir_world.normalized() * randf_range(0.5, 1.4) * (0.6 + strength * 0.4) + out * randf_range(0.2, 0.7) + Vector3.UP * randf_range(0.05, 0.4)
	vel.z = clampf(vel.z, -0.6, 1.2)
	var spin := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(4.0, 10.0)
	Gibs.instance.spawn(st.commit(), Transform3D(Basis.IDENTITY, center), vel, spin)

## Bala que quedó adentro del cuerpo, aplastada (en hongo). Se ve en los rayos X.
func add_lodged(node: String, pos_bind: Vector3, dir_bind: Vector3) -> void:
	lodged.append({"node": node, "pos": pos_bind, "dir": dir_bind.normalized(), "mi": null, "seq": _seq})
	if lodged.size() > 6:
		var old: Dictionary = lodged.pop_front()
		if old.mi:
			(old.mi as Node).queue_free()

# ---------------------------------------------------------------- mallas

func _mesh(node: String) -> MeshInstance3D:
	if meshes.has(node):
		return meshes[node]
	var mi := _skinned(groups[node].mesh)
	meshes[node] = mi
	_update_material(node)
	return mi

func _frag_mesh(f: Dictionary) -> MeshInstance3D:
	if frag_meshes.has(f.node):
		return frag_meshes[f.node]
	var mi := _skinned(f.mesh)
	var m := ShaderMaterial.new()
	m.shader = _fshader()
	m.set_shader_parameter("center", f.center)
	mi.material_override = m
	frag_meshes[f.node] = mi
	return mi

func _skinned(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.skin = skin
	mi.transform = mesh_xf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	skel.add_child(mi)
	mi.skeleton = mi.get_path_to(skel)
	return mi

## Colores realistas (como un atlas de anatomía): hueso marfil, músculo rojo con fibras, vasos rojo oscuro.
const SYS_COLOR := {"hueso": Color(0.86, 0.8, 0.66), "musculo": Color(0.55, 0.09, 0.07), "organo": Color(0.62, 0.2, 0.2),
	"vaso": Color(0.5, 0.02, 0.04), "nervio": Color(0.9, 0.78, 0.55), "oreja": Color(0.8, 0.55, 0.48)}

## Colores por órgano (un atlas): así se distinguen unos de otros y de los huesos.
const ORGAN_COLOR := {"pulmón": Color(0.85, 0.5, 0.52), "corazón": Color(0.75, 0.1, 0.12), "hígado": Color(0.5, 0.2, 0.12),
	"estómago": Color(0.85, 0.55, 0.45), "intestinos": Color(0.9, 0.6, 0.5), "riñón": Color(0.45, 0.15, 0.2), "bazo": Color(0.4, 0.12, 0.25),
	"páncreas": Color(0.9, 0.7, 0.5), "vejiga": Color(0.9, 0.8, 0.5), "testículos": Color(0.8, 0.6, 0.55), "vesícula": Color(0.3, 0.5, 0.2)}

func _update_material(node: String) -> void:
	var mi: MeshInstance3D = meshes[node]
	var m := ShaderMaterial.new()
	m.shader = _wshader()
	var g: Dictionary = groups[node]
	var aabb: AABB = g.aabb
	var axis := Vector3.UP
	if aabb.size.x >= aabb.size.y and aabb.size.x >= aabb.size.z:
		axis = Vector3.RIGHT
	elif aabb.size.z >= aabb.size.y:
		axis = Vector3.BACK
	m.set_shader_parameter("axis", axis)
	var bc: Color = SYS_COLOR.get(g.system, Color.WHITE)
	if g.system == "organo":
		for k in ORGAN_COLOR:
			if str(g.label).begins_with(k):
				bc = ORGAN_COLOR[k]
	m.set_shader_parameter("base_color", bc)
	m.set_shader_parameter("is_muscle", 1.0 if g.system == "musculo" else 0.0)
	m.set_shader_parameter("kind", {"organo": 1.0, "vaso": 2.0, "nervio": 3.0}.get(g.system, 0.0))
	if str(g.label).begins_with("ojo"):
		m.set_shader_parameter("kind", 4.0)
		m.set_shader_parameter("eye_c", aabb.get_center())
		m.set_shader_parameter("eye_r", maxf(aabb.size.x, aabb.size.y) * 0.5)
	var an := axis.normalized()
	var ext := [aabb.position.dot(an), aabb.end.dot(an)]
	m.set_shader_parameter("ax_lo", minf(ext[0], ext[1]))
	m.set_shader_parameter("ax_hi", maxf(ext[0], ext[1]))
	var ps := PackedVector4Array()
	var ds := PackedVector4Array()
	var arr: Array = (wounds.get(node, []) as Array).filter(func(w): return int(w.get("seq", 0)) <= reveal_seq)
	for w in arr:
		ps.append(Vector4(w.pos.x, w.pos.y, w.pos.z, w.r))
		ds.append(Vector4(w.dir.x, w.dir.y, w.dir.z, float(w.type) + clampf(float(w.depth), 0.0, 0.99)))
	while ps.size() < MAX_WOUNDS:
		ps.append(Vector4(0, -100, 0, 0))
		ds.append(Vector4(0, 1, 0, 0))
	m.set_shader_parameter("w_pos", ps)
	m.set_shader_parameter("w_dir", ds)
	m.set_shader_parameter("w_count", arr.size())
	mi.material_override = m

# ---------------------------------------------------------------- rayos X localizados

## Abre las ventanas de rayos X en las heridas. kill = toma de muerte (más grande y más tiempo).
func show_xray(zone_list: Array, seconds: float, kill: bool, radius := 0.0) -> void:
	if not available or Settings.xray == 0 or zone_list.is_empty():
		return
	zones = zone_list.slice(0, 4)
	zone_r = radius if radius > 0.0 else (0.24 if kill else 0.15)
	_killcam = kill
	_show_t = seconds
	_showing = true
	_apply_skin()
	_refresh_visible()

## Toma de muerte con todas las heridas (la principal primero).
func show_killcam(main := "", radius := 0.0) -> void:
	var zl := []
	if main != "" and wounds.has(main):
		var w: Dictionary = wounds[main][-1]
		zl.append({"node": main, "pos": w.pos})
	for n in wounds:
		if zl.size() >= 4:
			break
		if n == main:
			continue
		var w: Dictionary = wounds[n][-1]
		var dup := false
		for z in zl:
			if bind_to_world(z.node, z.pos).distance_to(bind_to_world(n, w.pos)) < 0.12:
				dup = true
		if not dup:
			zl.append({"node": n, "pos": w.pos})
	show_xray(zl, 99.0, true, radius)

## Destello en el juego (heridas graves que no matan).
func show_flash(nodes: Array, seconds := 0.9) -> void:
	var zl := []
	for n in nodes:
		if wounds.has(n) and zl.size() < 3:
			zl.append({"node": n, "pos": wounds[n][-1].pos})
	show_xray(zl, seconds, false)

func hide_all() -> void:
	_killcam = false
	_showing = false
	_show_t = 0.0
	for n in meshes:
		(meshes[n] as MeshInstance3D).visible = false
	for n in frag_meshes:
		(frag_meshes[n] as MeshInstance3D).visible = false
	for l in lodged:
		if l.mi:
			(l.mi as MeshInstance3D).visible = false
	for mi in _skin_saved:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_override = _skin_saved[mi]
	_skin_saved.clear()

func _zone_world() -> PackedVector4Array:
	var out := PackedVector4Array()
	for z in zones:
		var p := bind_to_world(z.node, z.pos)
		out.append(Vector4(p.x, p.y, p.z, 0))
	while out.size() < 4:
		out.append(Vector4(0, -1000, 0, 0))
	return out

## Qué se dibuja: todo lo que cae en las ventanas (huesos, órganos, vasos, nervios, ojos, orejas) y los músculos (en
## anillo alrededor del centro, como en Sniper Elite). Los huesos rotos, como sus fragmentos.
## Qué se dibuja (sin músculos): huesos ENTEROS cerca de las ventanas (el esqueleto sigue continuo bajo la ropa), vasos,
## ojos, órganos principales. El cerebro sólo si el cráneo o el cerebro están heridos; las partes blandas sueltas de la
## cabeza / nervios sólo si fueron dañadas. Un hueso roto se dibuja con sus fragmentos.
func _refresh_visible() -> void:
	for n in meshes:
		(meshes[n] as MeshInstance3D).visible = false
	for n in frag_meshes:
		(frag_meshes[n] as MeshInstance3D).visible = false
	var zw := _zone_world()
	var skull_hit := false
	for n in groups:
		if str(groups[n].label).begins_with("cráneo") and (broken.has(n) or wounds.has(n)):
			skull_hit = true
	for n in groups:
		var g: Dictionary = groups[n]
		var lab := str(g.label)
		var hurt := wounds.has(n) and not (wounds[n] as Array).filter(func(w): return int(w.get("seq", 0)) <= reveal_seq).is_empty()
		if Settings.xray == 1 and g.system != "hueso" and not hurt:
			continue
		if hide_muscles and g.system == "musculo":
			continue
		if only_system != "" and g.system != only_system:
			continue
		if (lab.begins_with("cerebro") or lab.begins_with("cerebelo")) and not (skull_hit or hurt):
			continue
		if g.system == "nervio" and not lab.begins_with("ojo") and not hurt:
			continue
		if lab.begins_with("órganos de") and not hurt:
			continue
		var reach := zone_r * (1.9 if g.system == "hueso" else 1.25)
		var c := bind_to_world(n, g.center)
		var near := false
		for i in zones.size():
			var z := Vector3(zw[i].x, zw[i].y, zw[i].z)
			if c.distance_to(z) < reach + float(g.radius) * 0.7:
				near = true
		if not near:
			continue
		var bh: Array = (break_hits.get(n, []) as Array).filter(func(h): return int(h.seq) <= reveal_seq)
		if frags.has(n) and (not bh.is_empty() or g.mesh == null):
			var det: Dictionary = broken.get(n, {})
			for f in frags[n]:
				if det.has(f.node) and _gib_done(f.node):
					continue
				var fm := _frag_mesh(f)
				fm.visible = true
				var st := _frag_state(n, f)
				var sm := fm.material_override as ShaderMaterial
				sm.set_shader_parameter("crack", float(st[0]) * 0.035)
				sm.set_shader_parameter("push", st[1])
				sm.set_shader_parameter("open", float(st[0]))
			continue
		_mesh(n).visible = true

func _gib_done(frag_node: String) -> bool:
	for g in _pending_gibs:
		if str(g.f.node) == frag_node:
			return false
	return true

func _apply_skin() -> void:
	if not _skin_saved.is_empty():
		return
	_skin_mats.clear()
	for mi in actor.model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.has_meta("actor_mesh"):
			continue
		_skin_saved[m] = m.material_override
		var src: Material = m.material_override if m.material_override else (m.mesh.surface_get_material(0) if m.mesh else null)
		var zm := ShaderMaterial.new()
		zm.shader = _zshader()
		if src is StandardMaterial3D:
			zm.set_shader_parameter("albedo_tex", (src as StandardMaterial3D).albedo_texture)
			zm.set_shader_parameter("albedo_color", (src as StandardMaterial3D).albedo_color)
		m.material_override = zm
		_skin_mats.append(zm)

func _process(delta: float) -> void:
	if not _showing:
		return
	_show_t -= delta / maxf(Engine.time_scale, 0.05)
	if _show_t <= 0.0:
		hide_all()
		return
	var zw := _zone_world()
	var k := 1.0 if _killcam else clampf(_show_t / 0.3, 0.0, 1.0)
	var r := zone_r * k
	for zm in _skin_mats:
		zm.set_shader_parameter("zone_c", zw)
		zm.set_shader_parameter("zone_n", zones.size())
		zm.set_shader_parameter("zone_r", r)
		var cam := get_viewport().get_camera_3d()
		if cam:
			zm.set_shader_parameter("cam_pos", cam.global_position)
	# lo que queda ENTRE la cámara y la herida principal se vuelve transparente (no tapa el daño)
	var cam3 := get_viewport().get_camera_3d()
	var cp := cam3.global_position if cam3 else Vector3(0, 0, 100)
	var main_node := str(zones[0].node) if not zones.is_empty() else ""
	var fp := Vector3(zw[0].x, zw[0].y, zw[0].z) if not zones.is_empty() else Vector3.ZERO
	for coll in [meshes, frag_meshes]:
		for n in coll:
			var mi: MeshInstance3D = coll[n]
			if mi.visible:
				var sm := mi.material_override as ShaderMaterial
				sm.set_shader_parameter("zone_c", zw)
				sm.set_shader_parameter("zone_n", zones.size())
				sm.set_shader_parameter("zone_r", r)
				sm.set_shader_parameter("cam_pos", cp)
				sm.set_shader_parameter("focus_p", fp)
				sm.set_shader_parameter("is_focus", 1.0 if (str(n) == main_node or str(n).begins_with(main_node + "_f")) else 0.0)
	# balas alojadas
	for l in lodged:
		if l.mi == null and Gibs.instance:
			var mi := MeshInstance3D.new()
			mi.mesh = BulletTime.bullet_mesh(true)                  # bala de Blender aplastada en hongo
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.85, 0.48, 0.25)
			mat.metallic = 0.6
			mat.roughness = 0.3
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.18, 0.08)
			mat.no_depth_test = true                                   # se ve dentro del hueso / órgano
			mat.render_priority = 9
			mi.material_override = mat
			mi.top_level = true
			add_child(mi)
			l.mi = mi
		if l.mi:
			var p := bind_to_world(l.node, l.pos)
			var d: Vector3 = (_skin_mat(groups[l.node].bone).basis * l.dir).normalized() if groups.has(l.node) else Vector3.RIGHT
			var lmc := (l.mi as MeshInstance3D).mesh.get_aabb().get_center()
			(l.mi as MeshInstance3D).global_transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).scaled(Vector3.ONE * 1.3), p) * Transform3D(Basis.IDENTITY, -lmc)
			(l.mi as MeshInstance3D).visible = int(l.get("seq", 0)) <= reveal_seq

# ---------------------------------------------------------------- shaders

const _ZONE_FUNC := """
uniform vec3 cam_pos = vec3(0.0, 0.0, 100.0);
uniform vec3 focus_p = vec3(0.0);
uniform float is_focus = 0.0;
// ¿este punto tapa la herida principal? (entre la cámara y la herida, cerca de la línea de visión)
float occluder(vec3 p) {
	if (is_focus > 0.5) return 0.0;
	vec3 v = focus_p - cam_pos;
	float len = length(v);
	vec3 d = v / max(len, 0.0001);
	float t = dot(p - cam_pos, d);
	if (t <= 0.0 || t > len - 0.015) return 0.0;
	float r = length(cross(p - cam_pos, d));
	return 1.0 - smoothstep(0.035, 0.07, r);
}
uniform vec4 zone_c[4];
uniform int zone_n = 0;
uniform float zone_r = 0.2;
float zone_d(vec3 wp) {
	float d = 1e6;
	for (int i = 0; i < 4; i++) { if (i >= zone_n) break; d = min(d, distance(wp, zone_c[i].xyz)); }
	return d;
}
"""

## Anatomía: realista y recortada a las ventanas; los músculos sólo en el anillo de afuera (se ve el hueso al centro).
static func _wshader() -> Shader:
	if _wound_shader == null:
		_wound_shader = Shader.new()
		_wound_shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec3 axis = vec3(0.0, 1.0, 0.0);
uniform vec4 base_color : source_color = vec4(0.9, 0.9, 0.8, 1.0);
uniform float is_muscle = 0.0;
uniform float kind = 0.0;      // 0 hueso · 1 órgano · 2 vaso · 3 nervio / ojo
uniform vec3 eye_c = vec3(0.0);
uniform float eye_r = 0.012;
uniform float ax_lo = 0.0;
uniform float ax_hi = 1.0;
uniform vec4 w_pos[6];
uniform vec4 w_dir[6];
uniform int w_count = 0;
""" + _ZONE_FUNC + """
varying vec3 lp;
varying vec3 wp;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	lp = CUSTOM0.xyz;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float zd = zone_d(wp);
	if (is_muscle > 0.5 && (zd > zone_r || zd < zone_r * 0.62)) { discard; }   // (músculos: anillo; hoy no se dibujan)
	float rim = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= w_count) break;
		vec3 c = w_pos[i].xyz;
		float r = w_pos[i].w;
		vec3 dir = w_dir[i].xyz;
		int t = int(floor(w_dir[i].w));
		float depth = fract(w_dir[i].w);
		float along = dot(lp - c, dir);
		float dl = length(cross(lp - c, dir));
		bool inside_len = (t == 1) || (t == 0) || (along > -r && along < depth * 0.25);
		if (t == 2) {
			float d = length(lp - c);
			if (d < r && hash(floor(lp * 120.0)) > 0.45) { discard; }
			rim = max(rim, 1.0 - smoothstep(r * 0.6, r * 1.8, d));
		} else {
			if (dl < r && inside_len) { discard; }
			if (inside_len) { rim = max(rim, 1.0 - smoothstep(r, r * 3.0, dl)); }
		}
	}
	vec3 col = base_color.rgb;
	float shine = 0.0;
	float relief = 0.0;
	if (is_muscle > 0.5) {
		// músculo: haces de fibras (ruido estirado a lo largo del eje), vetas de fascia / grasa y tendón pálido en las puntas
		vec3 ax = normalize(axis);
		float along = dot(lp, ax);
		vec3 perp = lp - ax * along;
		float bun = vnoise(perp * 95.0 + ax * along * 9.0);
		float fib = vnoise(perp * 520.0 + ax * along * 38.0) * 0.6 + vnoise(perp * 1100.0 + ax * along * 70.0) * 0.4;
		col = mix(vec3(0.34, 0.035, 0.03), vec3(0.66, 0.11, 0.08), bun);
		col = mix(col, vec3(0.86, 0.26, 0.18), smoothstep(0.55, 0.95, fib) * 0.55);
		float fat = smoothstep(0.80, 0.92, vnoise(perp * 48.0 + ax * along * 5.0));
		col = mix(col, vec3(0.90, 0.68, 0.55), fat * 0.5);
		float u = clamp((along - ax_lo) / max(ax_hi - ax_lo, 0.001), 0.0, 1.0);
		float tend = smoothstep(0.80, 0.97, abs(u - 0.5) * 2.0);
		col = mix(col, vec3(0.90, 0.84, 0.72) * (0.85 + 0.15 * fib), tend);
		relief = (fib - 0.5) * 0.9 + (bun - 0.5) * 0.5;
		shine = 0.55 + fat * 0.3;
	} else if (kind > 0.5 && kind < 1.5) {
		// vísceras: manchas húmedas y vetas finas de capilares
		float m1 = vnoise(lp * 38.0);
		float m2 = vnoise(lp * 150.0);
		col = mix(col * 0.72, col * 1.25 + vec3(0.06, 0.02, 0.02), m1);
		col = mix(col, vec3(0.78, 0.40, 0.34), smoothstep(0.72, 0.9, m2) * 0.5);
		relief = (m2 - 0.5) * 0.5;
		shine = 0.8;
	} else if (kind > 1.5 && kind < 2.5) {
		col *= 0.8 + 0.4 * vnoise(lp * 300.0);
		shine = 0.9;
	} else if (kind > 3.5) {
		// globo ocular: esclerótica blanca con venitas rojas, iris y pupila hacia delante (+Z), nervio óptico amarillento atrás
		vec3 d = lp - eye_c;
		float dl = length(d);
		float front = d.z / max(dl, 0.0001);
		float veins = smoothstep(0.72, 0.9, vnoise(lp * 900.0 + vec3(0.0, 3.0, 0.0)));
		col = mix(vec3(0.93, 0.90, 0.86), vec3(0.78, 0.18, 0.15), veins * 0.55);
		float iris = smoothstep(0.80, 0.84, front);
		float fibers = vnoise(vec3(atan(d.y, d.x) * 9.0, front * 40.0, 0.0)) * 0.5 + 0.5;
		col = mix(col, mix(vec3(0.15, 0.30, 0.45), vec3(0.45, 0.62, 0.72), fibers), iris);
		col = mix(col, vec3(0.01), smoothstep(0.955, 0.965, front));
		col = mix(col, vec3(0.80, 0.68, 0.40), smoothstep(-0.7, -0.95, front));
		shine = 1.0;
	} else if (kind > 2.5) {
		col *= 0.9 + 0.2 * vnoise(lp * 200.0);
		shine = 0.7;
	}
	// sangre manchando lo que está cerca de la herida y salpicaduras
	float splat = step(0.82, hash(floor(lp * 90.0))) * 0.35;
	col = mix(col, vec3(0.35, 0.01, 0.01), clamp(rim * 1.2 + splat * rim, 0.0, 0.9));
	// luz propia de la toma (cálida, desde la cámara): no la tiñen las luces de colores del escenario
	vec3 L = normalize(VIEW + vec3(0.35, 0.6, 0.0));
	float nl = clamp(dot(NORMAL, L) + relief * 0.35, 0.0, 1.0);
	float edge = 1.0 - smoothstep(zone_r * 0.9, zone_r * 2.2, zd) * 0.55;   // lo que sigue bajo la ropa se oscurece de a poco
	// brillo húmedo (carne mojada): reflejo estrecho + borde de Fresnel
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float spec = pow(clamp(dot(NORMAL, normalize(L + VIEW)), 0.0, 1.0), 48.0) * shine;
	// órganos como cristal rojizo: se ven los huesos que están detrás
	ALPHA = (kind > 0.5 && kind < 1.5) ? 0.38 : 1.0;
	ALPHA = mix(ALPHA, min(ALPHA, 0.18), occluder(wp));
	ALBEDO = col * 0.12;
	ROUGHNESS = 0.3;
	SPECULAR = 0.5;
	EMISSION = (col * (0.22 + 0.9 * nl) * vec3(1.0, 0.96, 0.9) + vec3(0.6, 0.02, 0.0) * rim * 0.5 + vec3(1.0, 0.85, 0.8) * (spec * 0.55 + fres * shine * 0.12)) * edge;
}
"""
	return _wound_shader

## Fragmento de hueso roto (de Blender): color por vértice (hueso / médula en el corte) y un poco encogido hacia su centro
## para que se vean las grietas entre fragmentos.
static func _fshader() -> Shader:
	if _frag_shader == null:
		_frag_shader = Shader.new()
		_frag_shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec3 center;
uniform float crack = 0.0;      // cuánto se encoge el fragmento hacia su centro (abre la grieta)
uniform vec3 push = vec3(0.0);   // cuánto se corre (espacio del hueso)
uniform float open = 0.0;        // 0 = lejos del impacto (no se nota el corte) · 1 = al lado del impacto
""" + _ZONE_FUNC + """
varying vec3 wp;
varying vec3 lp;
varying float cutv;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	lp = CUSTOM0.xyz;
	cutv = step(COLOR.g, 0.5);
	VERTEX -= (CUSTOM0.xyz - center) * crack;
	VERTEX += push;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 L = normalize(VIEW + vec3(0.35, 0.6, 0.0));
	float nl = clamp(dot(NORMAL, L), 0.0, 1.0);
	float cav = 0.72 + 0.28 * vnoise(lp * 520.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	float spec = pow(clamp(dot(NORMAL, normalize(L + VIEW)), 0.0, 1.0), 40.0);
	// hueso: marfil con poros y vetas suaves
	float pores = vnoise(lp * 260.0) * 0.5 + vnoise(lp * 70.0) * 0.5;
	vec3 bone = mix(vec3(0.80, 0.72, 0.58), vec3(0.95, 0.91, 0.82), pores);
	// corte: hueso esponjoso (trabéculas) empapado de sangre; lejos del impacto el corte no se ve (queda adentro)
	float trab = smoothstep(0.35, 0.65, vnoise(lp * 900.0)) * 0.6 + vnoise(lp * 300.0) * 0.4;
	vec3 sponge = mix(vec3(0.42, 0.05, 0.04), vec3(0.88, 0.7, 0.55), trab);
	vec3 col = mix(bone, sponge, cutv * clamp(open * 1.6, 0.0, 1.0));
	// sangre en los bordes de la fractura
	col = mix(col, vec3(0.35, 0.02, 0.02), open * 0.35 * step(0.6, vnoise(lp * 160.0)));
	ALBEDO = col * 0.12;
	ROUGHNESS = 0.55;
	SPECULAR = 0.5;
	EMISSION = col * (0.12 + 1.0 * nl * nl) * cav + vec3(1.0, 0.95, 0.85) * (fres * 0.22 + spec * 0.2);
	ALPHA = 1.0 - 0.82 * occluder(wp);
}
"""
	return _frag_shader

## Piel / ropa del personaje: normal afuera; dentro de la ventana desaparece y queda la silueta oscura (caras de atrás).
static func _zshader() -> Shader:
	if _zone_skin_shader == null:
		_zone_skin_shader = Shader.new()
		_zone_skin_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_color : source_color = vec4(1.0);
""" + _ZONE_FUNC + """
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
// la ropa también desaparece en el «túnel» entre la cámara y la herida: nada tapa la vista
bool tunnel(vec3 p) {
	for (int i = 0; i < 4; i++) {
		if (i >= zone_n) break;
		vec3 c = zone_c[i].xyz;
		vec3 v = c - cam_pos;
		float len = length(v);
		vec3 d = v / max(len, 0.0001);
		float t = dot(p - cam_pos, d);
		if (t < len + zone_r * 0.5 && t > 0.0 && length(cross(p - cam_pos, d)) < zone_r * 1.25) { return true; }
	}
	return false;
}
void fragment() {
	float zd = zone_d(wp);
	if (zd < zone_r || tunnel(wp)) {
		discard;                                 // la ropa desaparece por completo en la zona: queda sólo la anatomía
	} else {
		if (!FRONT_FACING) { discard; }
		vec4 t = texture(albedo_tex, UV) * albedo_color;
		// borde quemado alrededor del corte, como en Sniper Elite
		float edge = 1.0 - smoothstep(zone_r, zone_r * 1.12, zd);
		ALBEDO = mix(t.rgb, vec3(0.05, 0.0, 0.0), edge * 0.85);
		ROUGHNESS = 0.85;
	}
}
"""
	return _zone_skin_shader
