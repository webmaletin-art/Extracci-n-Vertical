class_name MapGraph
extends RefCounted
## Representación esquemática del mapa: sectores (habitaciones por piso) y conexiones (puertas, conductos, escaleras de
## mano, escalera inclinada, ascensor, cráter, caídas por huecos, puertas con llave). Sirve para:
##   * comprobar que no quedan sectores inaccesibles por error (check_reachability, lo corre la prueba «mapa»);
##   * dibujar el minimapa y el esquema de rutas (docs/MAPA_TORRE_ALFA.md se genera de acá).
## Se arma desde los mismos datos que el constructor (TorreAlfa.data()), no desde la geometría.

var rooms: Array = []        ## [{id, floor, x0, x1, y, name}]
var edges: Array = []        ## [{a, b, type, oneway, key}]
var start_room := ""
var key_room := ""
var key_rooms := {}          ## ítem de llave → sector donde está (cajas con tabla "key" o "key:<ítem>")
var extraction_rooms: Array = []
var floor_h := 4.5

static func from_data(d: Dictionary) -> MapGraph:
	var g := MapGraph.new()
	g.floor_h = float(d.floor_h)
	var w := float(d.width)
	var nf: int = d.floors.size()
	for f in d.floors:
		var xs := [0.0]
		for wl in f.walls:
			xs.append(float(wl[0]))
		xs.append(w)
		for k in xs.size() - 1:
			g.rooms.append({"id": "%d:%d" % [f.id, k], "floor": int(f.id), "x0": xs[k], "x1": xs[k + 1], "y": f.id * g.floor_h,
				"name": "%s · sector %d" % [f.tag, k + 1]})
		for i in f.walls.size():
			var wl: Array = f.walls[i]
			var t := str(wl[1])
			if t == "solid":
				continue
			g.edges.append({"a": "%d:%d" % [f.id, i], "b": "%d:%d" % [f.id, i + 1], "type": t, "oneway": false,
				"key": (t.get_slice(":", 1) if ":" in t else "keycard_lab") if t.begins_with("locked") else ""})
		for h in f.holes:
			var cx := (float(h[0]) + float(h[1])) * 0.5
			if f.id > 0:
				g._add(g.room_at(f.id, cx), g.room_at(f.id - 1, cx), "caída", true)
		for c in f.get("crates", []):
			if str(c[2]) == "key" or str(c[2]).begins_with("key:"):
				g.key_room = g.room_at(f.id, float(c[0]))
				g.key_rooms[str(c[2]).get_slice(":", 1) if ":" in str(c[2]) else "keycard_lab"] = g.key_room
		if f.has("extraction"):
			g.extraction_rooms.append(g.room_at(f.id, float(f.extraction[0])))
	# azotea (exterior)
	g.rooms.append({"id": "%d:0" % nf, "floor": nf, "x0": 0.0, "x1": w, "y": nf * g.floor_h, "name": "Azotea"})
	if d.roof.has("extraction"):
		g.extraction_rooms.append("%d:0" % nf)
	for l in d.ladders:
		var f0 := int(round(float(l[1]) / g.floor_h))
		var f1 := int(round(float(l[2]) / g.floor_h))
		if f0 != f1:
			g._add(g.room_at(f0, float(l[0])), g.room_at(f1, float(l[0])), "escalera de mano", false)
	for s in d.stairs:
		g._add(g.room_at(int(s[2]), float(s[0]) + 0.2), g.room_at(int(s[2]) + 1, float(s[1]) - 0.2), "escalera", false)
	var ex := float(d.elevator.x)
	var stops: Array = d.elevator.stops
	for i in stops.size() - 1:
		g._add(g.room_at(int(stops[i]), ex), g.room_at(int(stops[i + 1]), ex), "ascensor", false)
	# cráter: desde el fondo (P1) se trepa al borde del P2 (izquierda) y por los pilares altos al borde del P3 (derecha)
	if not d.crater.is_empty():
		var first: Array = d.crater[0]
		var last: Array = d.crater[-1]
		g._add(g.room_at(1, float(first[0]) - 0.3), g.room_at(2, float(first[0]) - 0.5), "cráter (trepar)", false)
		g._add(g.room_at(1, float(first[0]) - 0.3), g.room_at(3, float(last[1]) + 0.6), "cráter (pilares)", false)
	g.start_room = g.room_at(0, float((d.start as Vector3).x))
	return g

func _add(a: String, b: String, type: String, oneway: bool, key := "") -> void:
	if a == "" or b == "" or a == b:
		return
	edges.append({"a": a, "b": b, "type": type, "oneway": oneway, "key": key})

func room_at(floor_i: int, x: float) -> String:
	for r in rooms:
		if int(r.floor) == floor_i and x >= float(r.x0) - 0.001 and x <= float(r.x1) + 0.001:
			return str(r.id)
	return ""

func room(id: String) -> Dictionary:
	for r in rooms:
		if r.id == id:
			return r
	return {}

## Recorre el grafo desde el inicio. La llave se obtiene al llegar a su sector; con ella se abren las puertas bloqueadas.
## Devuelve {reached: [ids], unreachable: [ids], extraction_ok: bool, key_found: bool}.
func check_reachability() -> Dictionary:
	var have := {}
	var seen := {start_room: true}
	var changed := true
	while changed:
		changed = false
		for k in key_rooms:
			if seen.has(key_rooms[k]) and not have.has(k):
				have[k] = true
				changed = true
		for e in edges:
			if e.key != "" and not have.has(e.key):
				continue
			if seen.has(e.a) and not seen.has(e.b):
				seen[e.b] = true
				changed = true
			if not e.oneway and seen.has(e.b) and not seen.has(e.a):
				seen[e.a] = true
				changed = true
	var unreachable := []
	for r in rooms:
		if not seen.has(r.id):
			unreachable.append(r.id)
	var ext_ok := true
	for x in extraction_rooms:
		ext_ok = ext_ok and seen.has(x)
	return {"reached": seen.keys(), "unreachable": unreachable, "extraction_ok": ext_ok, "key_found": not have.is_empty()}

## Texto del esquema (para docs y para el registro).
func describe() -> String:
	var lines := []
	for e in edges:
		lines.append("%s %s %s  [%s]%s" % [room(e.a).get("name", e.a), "→" if e.oneway else "↔", room(e.b).get("name", e.b), e.type,
			" (requiere %s)" % e.key if e.key != "" else ""])
	return "\n".join(lines)
