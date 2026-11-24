class_name PerfProbe
extends Node
## CAPTADOR DE RENDIMIENTO (se lanza desde CONFIGURACIÓN → Rendimiento → «Analizar rendimiento»).
## Recorre la torre con la cámara (varias estaciones por piso) y en cada una:
##   1. mide la línea base (ms por cuadro, FPS, llamadas de dibujo, primitivas, objetos visibles);
##   2. HACE DESAPARECER una categoría por vez (luces, sombras, decorado, tuberías, fondo, velos, cajas, personajes,
##      escombros, carteles, estructura, partículas, niebla/brillo, escala de render) y vuelve a medir;
##   3. al final prueba uno por uno los OBJETOS más pesados (por triángulos) apagándolos frente a la cámara.
## Con la diferencia arma un ranking «qué pesa más» con recomendaciones, lo muestra, lo guarda en
## user://informe_rendimiento.txt (+ .json) y lo copia al portapapeles. Incluye los tirones registrados durante el juego.
## Durante la medición se desactivan VSync y el tope de FPS (si no, todo mediría 33 ms o 16 ms) y se restauran después.

signal progress(text: String, k: float)
signal finished(report: String)

var game: Node                         ## Game (tiene tower, camera, player)
var frames_per_sample := 40
var warmup_frames := 8
var quick := false                     ## pruebas automáticas: menos cuadros y estaciones
var results := {}                      ## categoría → {ms: [], dc: [], prim: []}
var objects := []                      ## [{name, tris, ms, dc}]
var baseline := {"ms": [], "dc": [], "prim": [], "obj": []}
var hitches: Array = []                ## [{t, ms, info}] tirones durante el juego (Game los registra)
var running := false
var report_text := ""

const CATEGORIES := [
	["Luces dinámicas (lámparas)", "perf_luces"],
	["Sombras", "_shadows"],
	["Decorado (galería de modelos)", "perf_decorado"],
	["Tuberías y cables del fondo", "perf_tuberias"],
	["Fondo lejano (fachadas)", "perf_fondo"],
	["Velos de sectores sin descubrir", "perf_cubiertas"],
	["Cajas, barriles y vidrios", "perf_destructibles"],
	["Personajes (enemigos)", "perf_personajes"],
	["Escombros del cráter", "perf_escombros"],
	["Carteles (B0..B4)", "perf_carteles"],
	["Estructura (losas y paredes)", "perf_estructura"],
	["Partículas y fragmentos", "_fx"],
	["Niebla y brillo", "_env"],
	["Resolución 3D (→ 60 % de la actual)", "_scale"],
]

func _measure(frames: int) -> Dictionary:
	for i in warmup_frames:
		await get_tree().process_frame
	var ms := []
	var dc := []
	var prim := []
	var objs := []
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
		dc.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prim.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	return {"ms": _median(ms), "dc": _avg(dc), "prim": _avg(prim), "obj": _avg(objs)}

static func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / a.size()

static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])

func _stations() -> Array:
	var t: TowerBuilder = game.tower
	var out := []
	var fh := float(t.data.floor_h)
	var xs := [12.0, 30.0, 48.0] if not quick else [30.0]
	var floors_n: int = t.data.floors.size() if not quick else 1
	for f in floors_n:
		for x in xs:
			out.append(Vector3(x, f * fh + 1.6, 0))
	return out

func _set_category(cat: String, hidden: bool) -> void:
	var tree := get_tree()
	match cat:
		"_shadows":
			for l in tree.get_nodes_in_group("blob_shadow"):
				(l as Node3D).visible = not hidden and Settings.shadows >= 1
			var moon: DirectionalLight3D = game.tower.moon
			if hidden:
				moon.set_meta("probe_shadow", moon.shadow_enabled)
				moon.shadow_enabled = false
			else:
				moon.shadow_enabled = bool(moon.get_meta("probe_shadow", false))
		"_fx":
			var pool: Node = game.tower.get_parent().get_node_or_null("FxPool")
			if pool:
				(pool as Node3D).visible = not hidden
		"_env":
			var env: Environment = game.tower.world_env.environment
			if hidden:
				env.set_meta("probe", [env.fog_enabled, env.glow_enabled])
				env.fog_enabled = false
				env.glow_enabled = false
			elif env.has_meta("probe"):
				var p: Array = env.get_meta("probe")
				env.fog_enabled = p[0]
				env.glow_enabled = p[1]
		"_scale":
			get_viewport().scaling_3d_scale = 0.6 * Settings.effective_scale() if hidden else Settings.effective_scale()
		_:
			for n in tree.get_nodes_in_group(cat):
				if n is Node3D:
					if hidden:
						n.set_meta("probe_vis", (n as Node3D).visible)
						(n as Node3D).visible = false
					else:
						(n as Node3D).visible = bool(n.get_meta("probe_vis", true))

## Los objetos con más triángulos (mallas sueltas o juntadas) para probarlos uno por uno.
func _heavy_objects(limit: int) -> Array:
	var out := []
	for mi in game.tower.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var tris := 0
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		out.append({"node": m, "tris": tris, "name": _pretty(m)})
	out.sort_custom(func(a, b): return a.tris > b.tris)
	return out.slice(0, limit)

static func _pretty(n: Node) -> String:
	var p := n
	var parts := []
	for i in 3:
		if p == null:
			break
		parts.push_front(str(p.name))
		p = p.get_parent()
	return "/".join(parts)

func run() -> void:
	if running:
		return
	running = true
	results.clear()
	objects.clear()
	var cam: SideCamera = game.camera
	var old_vsync := DisplayServer.window_get_vsync_mode()
	var old_fps := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_tree().paused = false
	game.set_probe_mode(true)
	var stations := _stations()
	var total := stations.size() * (CATEGORIES.size() + 1) + (12 if not quick else 3)
	var step := 0
	var base_all := []
	for st in stations:
		cam.override_target(st + Vector3(0, 0, cam.distance), st, cam.base_fov)
		cam.global_position = st + Vector3(0, 0, cam.distance)
		game.reveal_all_near(st)
		var b: Dictionary = await _measure(frames_per_sample)
		base_all.append(b)
		step += 1
		progress.emit("Línea base %s" % _fmt_station(st), float(step) / total)
		for c in CATEGORIES:
			_set_category(c[1], true)
			var m: Dictionary = await _measure(frames_per_sample)
			_set_category(c[1], false)
			var r: Dictionary = results.get(c[0], {"ms": [], "dc": [], "prim": []})
			r.ms.append(b.ms - m.ms)
			r.dc.append(b.dc - m.dc)
			r.prim.append(b.prim - m.prim)
			results[c[0]] = r
			step += 1
			progress.emit("Sin «%s» · %s" % [c[0], _fmt_station(st)], float(step) / total)
	for k in ["ms", "dc", "prim", "obj"]:
		baseline[k] = _avg(base_all.map(func(x): return x[k]))
	# objetos individuales: cámara frente a cada uno, se apaga y se mide
	for o in _heavy_objects(12 if not quick else 3):
		var n: MeshInstance3D = o.node
		if not is_instance_valid(n):
			continue
		var c := n.global_transform * n.get_aabb().get_center()
		var st := Vector3(c.x, c.y, 0)
		cam.override_target(st + Vector3(0, 0, cam.distance), st, cam.base_fov)
		cam.global_position = st + Vector3(0, 0, cam.distance)
		var b: Dictionary = await _measure(frames_per_sample)
		n.visible = false
		var m: Dictionary = await _measure(frames_per_sample)
		n.visible = true
		objects.append({"name": o.name, "tris": o.tris, "ms": b.ms - m.ms, "dc": b.dc - m.dc})
		step += 1
		progress.emit("Objeto %s" % o.name, float(step) / total)
	cam.release_override()
	game.set_probe_mode(false)
	DisplayServer.window_set_vsync_mode(old_vsync)
	Engine.max_fps = old_fps
	Settings.apply()
	report_text = _report()
	_save(report_text)
	running = false
	finished.emit(report_text)

func _fmt_station(st: Vector3) -> String:
	return "P%d x=%d" % [int(st.y / 4.5), int(st.x)]

func _report() -> String:
	var lines := []
	lines.append("EXTRACCIÓN VERTICAL · INFORME DE RENDIMIENTO")
	lines.append("Fecha: %s · Equipo: %s · %s" % [Time.get_datetime_string_from_system(), OS.get_model_name(), RenderingServer.get_video_adapter_name()])
	lines.append("Calidad: %s · alto de la imagen 3D %d px · sombras %d · luces %d · partículas %d · humo %d · explosiones %d · decorado %d" % [
		Settings.PRESETS[Settings.quality_preset], int(Settings.effective_scale() * DisplayServer.window_get_size().y), Settings.shadows, Settings.lights, Settings.particles,
		Settings.smoke, Settings.explosions, Settings.decor])
	var bms := float(baseline.ms)
	lines.append("Línea base (promedio de estaciones): %.2f ms/cuadro (%.0f FPS) · %.0f llamadas de dibujo · %.0f primitivas · %.0f objetos" % [
		bms, 1000.0 / maxf(bms, 0.01), baseline.dc, baseline.prim, baseline.obj])
	lines.append("")
	lines.append("QUÉ PESA MÁS (cuánto se gana al hacerlo desaparecer):")
	var rows := []
	for k in results:
		var r: Dictionary = results[k]
		rows.append([k, _avg(r.ms), _avg(r.dc), _avg(r.prim), _max(r.ms)])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var i := 1
	for r in rows:
		lines.append("%2d. %-36s %6.2f ms (%4.1f%%) · peor estación %5.2f ms · −%4.0f dibujos · −%7.0f prim." % [i, r[0], r[1],
			100.0 * r[1] / maxf(bms, 0.01), r[4], r[2], r[3]])
		i += 1
	lines.append("")
	lines.append("OBJETOS INDIVIDUALES MÁS PESADOS:")
	objects.sort_custom(func(a, b): return a.ms > b.ms)
	for o in objects:
		lines.append(" · %-46s %7d triángulos · %5.2f ms · −%3.0f dibujos" % [o.name, o.tris, o.ms, o.dc])
	lines.append("")
	lines.append("RECOMENDACIONES:")
	var recs := _recommend(rows, bms)
	for r in recs:
		lines.append(" → " + r)
	if not hitches.is_empty():
		lines.append("")
		lines.append("TIRONES REGISTRADOS DURANTE EL JUEGO (cuadros > 50 ms):")
		for h in hitches.slice(maxi(0, hitches.size() - 15)):
			lines.append(" · t=%.1fs %.0f ms — %s" % [h.t, h.ms, h.info])
	return "\n".join(lines)

static func _max(a: Array) -> float:
	var m := -INF
	for v in a:
		m = maxf(m, float(v))
	return m if m > -INF else 0.0

func _recommend(rows: Array, bms: float) -> Array:
	var out := []
	for r in rows:
		var pct: float = 100.0 * r[1] / maxf(bms, 0.01)
		if pct < 8.0:
			continue
		match r[0]:
			"Luces dinámicas (lámparas)":
				out.append("Las lámparas cuestan %.0f%%: Configuración → Luces = Baja (sólo luz emisiva) o Media." % pct)
			"Sombras":
				out.append("Las sombras cuestan %.0f%%: Sombras = Sin sombras en gama baja." % pct)
			"Decorado (galería de modelos)":
				out.append("El decorado cuesta %.0f%%: Decorado = Bajo, o simplificar/hornear esos modelos en Blender." % pct)
			"Escala de render (→ 60 %)":
				out.append("El costo está en los píxeles (%.0f%%): bajar Escala de render a 60-70%%." % pct)
			"Personajes (enemigos)":
				out.append("Los personajes cuestan %.0f%%: menos enemigos por piso o LOD de los modelos (~20k triángulos c/u)." % pct)
			_:
				out.append("«%s» cuesta %.0f%%: revisar esa categoría." % [r[0], pct])
	if out.is_empty():
		out.append("Ninguna categoría pasa del 8%% del cuadro: el límite está repartido (o es la CPU/física).")
	if bms > 33.3:
		out.append("Promedio por debajo de 30 FPS: probar el preset BAJA.")
	return out

func _save(text: String) -> void:
	var f := FileAccess.open("user://informe_rendimiento.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	var j := FileAccess.open("user://informe_rendimiento.json", FileAccess.WRITE)
	if j:
		j.store_string(JSON.stringify({"baseline": baseline, "categories": results, "objects": objects, "hitches": hitches}, "  "))
		j.close()
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
