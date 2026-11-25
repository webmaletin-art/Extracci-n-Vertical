class_name Injuries
extends RefCounted
## Trauma de un personaje: decide QUÉ se rompe con cada golpe (usando la anatomía real, AnatomyBody) y qué efecto tiene.
## Efectos por estructura en data/anatomy_damage.json (vida al instante, hemorragia por segundo, efecto, qué la cura).
##
## Por tipo de daño (calibrado con referencias reales, ver docs/ANATOMIA.md):
##  * bala: recorre la trayectoria dentro del cuerpo; cada hueso que cruza se fractura y cada órgano / vaso / músculo /
##    nervio queda perforado. En cabeza, cuello y miembros la bala sale; en el torso se queda adentro salvo calibres
##    potentes. Un hueso quebrado puede clavar una astilla en un órgano vecino (clavícula → arteria, costilla → pulmón,
##    cráneo → cerebro).
##  * esquirla (granada): entra y queda alojada a pocos centímetros.
##  * cuchillo: herida profunda (≈12 cm) en la dirección del golpe.
##  * onda expansiva cerca: revienta pulmones e intestinos (lesión primaria), rompe tímpanos (sordera); ser lanzado
##    contra una pared o el piso fractura costillas, brazos o cráneo según la velocidad (lesión terciaria).
##  * caída: de pie desde > 3,6 m talón y huesos del pie; desde 5 m tibia y fémur; desde 8 m pelvis, columna y órganos;
##    caer mal (de costado, de espalda, lanzado) suma cráneo y órganos.
##  * puñetazo: sólo vida (no rompe huesos); a la cabeza puede derribar y, con poca vida, matar. Patada al torso: puede
##    fisurar costillas (≈ 20 %).

signal changed

var leg_broken := false
var paralysis := false
var arm := 0.0            ## 0..1 brazo
var hand := 0.0           ## 0..1 mano
var head := 0.0           ## 0..1 cabeza / ojos
var breath := false       ## pulmón / tráquea: no corre
var deaf := 0.0           ## segundos de sordera (tímpanos)
var bleeds: Array = []    ## [{rate, treat, text, src: Blood.BleedSource}]
var _actor: Actor
var _anat: AnatomyBody
var _sources := {}        ## hueso → Blood.BleedSource
var log: Array[String] = []
var bleeding: float:
	get:
		var s := 0.0
		for b in bleeds:
			s += float(b.rate)
		return s

static var _table := {}
static var _keys: Array = []

static func table() -> Dictionary:
	if _table.is_empty():
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/anatomy_damage.json"))
		for k in d:
			if not str(k).begins_with("_"):
				_table[k] = d[k]
		_keys = _table.keys()
		_keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
	return _table

static func effect_of(label: String) -> Dictionary:
	table()
	for k in _keys:
		if label.begins_with(str(k)):
			return _table[k]
	return {"hp": 3, "bleed": 0.2, "effect": "", "treat": "bandage"}

## Procesa un golpe. Devuelve {hp: vida extra perdida, texts: [..], nodes: [grupos dañados], death: bool, main: grupo principal}
func process(actor: Actor, info: Dictionary) -> Dictionary:
	var res := {"hp": 0.0, "texts": [], "nodes": [], "death": false, "main": "", "main_w": -1.0, "applied": {}}
	var anat := AnatomyBody.for_actor(actor)
	_actor = actor
	_anat = anat
	var t := str(info.get("type", "bullet"))
	var point: Vector3 = info.get("point", actor.global_position + Vector3.UP * 1.2)
	var dir: Vector3 = info.get("dir", Vector3(-actor.facing, 0, 0))
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var zone := str(info.get("zone", "torso"))
	# 2.5D: los proyectiles viajan en z = 0 pero el cuerpo tiene volumen; la trayectoria se pasa a la profundidad del
	# hueso golpeado para que cruce de verdad la anatomía de esa zona
	var bi := actor.skel.find_bone(str(info.get("bone", "")))
	if bi >= 0:
		var bw := actor.skel.global_transform * actor.skel.get_bone_global_pose(bi)
		var kids := actor.skel.get_bone_children(bi)
		var mid := bw.origin
		if not kids.is_empty():
			mid = (bw.origin + (actor.skel.global_transform * actor.skel.get_bone_global_pose(kids[0])).origin) * 0.5
		point.z = mid.z
		if zone == "head":
			var eye_z := point.z
			if t == "bullet" and absf(dir.x) > 0.6:
				eye_z = _snap_to_eye(anat, point, dir, point.z)       # antes de acotar la altura: el ojo está bajo el centro de la cabeza
			if eye_z == point.z:
				point.y = clampf(point.y, mid.y - 0.06, mid.y + 0.08)
			else:
				point.z = eye_z
		elif zone == "pelvis" and t == "bullet" and absf(dir.x) > 0.6:
			# igual que el ojo: los genitales están adelante de la pelvis, fuera del plano del hueso
			var gn := anat.find_group("testículos")
			if gn != "":
				var gc := anat.bind_to_world(gn, anat.groups[gn].center)
				if absf(gc.y - point.y) < 0.05 and (gc.x - actor.global_position.x) * dir.x < 0.0:
					point.z = gc.z
	match t:
		"bullet", "fragment", "knife":
			var max_depth := INF
			if t == "fragment":
				max_depth = randf_range(0.04, 0.12)
			elif t == "knife":
				max_depth = 0.13
			elif zone in ["torso", "pelvis"] and float(info.get("penetration", 6.0)) < 10.0:
				max_depth = randf_range(0.14, 0.26)     # la bala se frena adentro del torso
			var ricochet := bool(info.get("ricochet", false))
			if ricochet:
				max_depth = randf_range(0.05, 0.14)     # rebotada: llega deformada, gira y se frena antes
			var r := 0.007 if t != "knife" else 0.004
			if float(info.get("pellets", 1)) > 1:
				r = 0.005
			if ricochet:
				r *= 2.0                                 # la bala deformada abre una herida más ancha
			_strength = clampf(float(info.get("damage", 30.0)) / 30.0, 0.6, 2.5) * (1.4 if ricochet else 1.0)
			if t == "fragment":
				_strength = 0.6
			# recorrido por dentro: al pegar en un hueso duro la bala puede desviarse y seguir rompiendo en otra dirección
			var o := point - dir * 0.3
			var d := dir
			var left_depth := max_depth
			var length := 0.9
			var seen := {}
			var last_hit := {}
			res["path"] = []                 # recorrido de la bala por dentro (para la repetición en cámara lenta)
			res["seq0"] = anat._seq + 1
			for leg in 3:
				var path := anat.trace(o, d, length, left_depth)
				path = path.filter(func(x): return not seen.has(x.node))
				if leg == 0 and path.is_empty():
					for n in anat.near(point, 0.07):
						path.append({"node": n, "label": anat.groups[n].label, "system": anat.groups[n].system,
							"p_in": anat.world_to_bind(n, point), "p_out": anat.world_to_bind(n, point + dir * 0.02), "dir": anat.dir_to_bind(n, dir), "t_in": 0.0, "t_out": 0.02})
						break
				var deflect := {}
				var events := []
				for h in path:
					seen[h.node] = true
					var sq := anat.next_seq()
					_hit_structure(anat, actor, h, t, r, res, o, d)
					if (res.path as Array).is_empty():
						res.path.append({"node": h.node, "p": h.p_in - (h.dir as Vector3) * 0.35, "seq": -1})
					events.append({"t": float(h.t_in), "node": h.node, "p": h.p_in, "seq": sq, "sys": h.system})
					events.append({"t": float(h.t_out), "node": h.node, "p": h.p_out, "seq": sq, "sys": h.system})
					last_hit = h
					if t == "bullet" and h.system == "hueso" and leg < 2 and randf() < DEFLECT.get(_bone_key(str(h.label)), 0.0):
						deflect = h
						break
				events.sort_custom(func(x, y): return x.t < y.t)
				if not deflect.is_empty():
					events = events.filter(func(e): return e.t <= float(deflect.t_out) + 0.0001)
					if not events.is_empty():
						events[-1]["deflect"] = true
				res.path.append_array(events)
				if deflect.is_empty():
					break
				# la bala se desvía en el hueso: nueva dirección y sigue desde la salida
				var exit_w := anat.bind_to_world(str(deflect.node), deflect.p_out)
				var ang := deg_to_rad(randf_range(15.0, 45.0)) * (1.0 if randf() < 0.5 else -1.0)
				d = d.rotated(Vector3.BACK, ang).normalized()
				o = exit_w
				length = 0.45
				if left_depth < INF:
					left_depth = maxf(left_depth - float(deflect.t_out), 0.04)
				res.texts.append("La bala se desvió en %s" % deflect.label)
			# la bala que quedó adentro: aplastada en hongo, alojada al final del recorrido
			if not last_hit.is_empty() and not (res.path as Array).is_empty():
				if max_depth < INF:
					res.path[-1]["lodged"] = true
				else:
					res.path.append({"node": last_hit.node, "p": last_hit.p_out + (last_hit.dir as Vector3) * 0.35, "seq": -1, "exit": true})
			res["seq1"] = anat._seq
			if t in ["bullet", "fragment"] and max_depth < INF and not last_hit.is_empty():
				var ln := str(last_hit.node)
				anat.add_lodged(ln, last_hit.p_out, last_hit.dir)
				res.texts.append(("Bala aplastada alojada en %s" if t == "bullet" else "Esquirla alojada en %s") % last_hit.label)
		"punch":
			if zone in ["head", "neck"] and randf() < 0.2:
				res.texts.append("Conmoción por golpe en la cabeza")
				head = minf(head + 0.3, 1.0)
		"kick":
			if zone in ["torso", "pelvis"] and randf() < 0.2:
				_fracture_by_label(anat, actor, "costillas", point, dir, res, 0.006, "Fisura de costillas por patada")
		"blast":
			var dist := float(info.get("distance", 3.0))
			var radius := float(info.get("radius", 5.0)) * (1.4 if info.get("closed", false) else 1.0)
			if dist < radius * 0.5:
				deaf = maxf(deaf, 8.0)
				res.texts.append("Tímpanos rotos por la onda expansiva")
				for lab in ["pulmón der", "pulmón izq", "intestinos"]:
					if randf() < (0.9 if dist < radius * 0.3 else 0.5):
						var n := anat.find_group(lab)
						if n != "":
							anat.add_wound(n, anat.groups[n].center, Vector3.UP, 0.05, 2)
							_apply_effect(lab, "Estallido de %s por la onda expansiva" % lab, res, 0.6, _loc(n, anat.groups[n].center, Vector3.UP))
							res.nodes.append(n)
		"impact":
			# lanzado por la explosión contra pared / piso
			var sp := float(info.get("speed", 6.0))
			var k := clampf((sp - 5.0) / 10.0, 0.0, 1.0)
			for pair in [["costillas", 0.25 + k * 0.5], ["cráneo", 0.05 + k * 0.3], ["húmero", 0.1 + k * 0.3], ["radio", 0.1 + k * 0.3], ["fémur", k * 0.3]]:
				if randf() < float(pair[1]):
					_fracture_by_label(anat, actor, pair[0], point, dir, res, 0.008, "Fractura de %s al ser lanzado" % pair[0])
		"fall":
			_fall(anat, actor, info, res)
	if not res.texts.is_empty():
		log.append_array(res.texts)
		changed.emit()
	return res

func _fall(anat: AnatomyBody, actor: Actor, info: Dictionary, res: Dictionary) -> void:
	var h := float(info.get("fall_height", 4.0))
	var bad := bool(info.get("bad_landing", false))
	var side := "izq" if randf() < 0.5 else "der"
	var foot := actor.global_position + Vector3.UP * 0.05
	var chances := []
	if h > 3.6:
		chances.append(["huesos del pie " + side, 0.45 if h < 5.0 else 0.85, foot])
		chances.append(["tibia " + side, 0.15 if h < 5.0 else 0.55, foot + Vector3.UP * 0.3])
	if h > 5.0:
		chances.append(["fémur " + side, 0.2 if h < 8.0 else 0.5, foot + Vector3.UP * 0.6])
		chances.append(["vértebras lumbares", 0.15 if h < 8.0 else 0.35, foot + Vector3.UP * 1.0])
		chances.append(["pelvis", 0.1 if h < 8.0 else 0.35, foot + Vector3.UP * 0.9])
	if h > 8.0 or bad:
		chances.append(["hígado", 0.25 * (2.0 if bad else 1.0), foot + Vector3.UP * 1.1])
		chances.append(["riñón " + side, 0.15 * (2.0 if bad else 1.0), foot + Vector3.UP * 1.05])
		chances.append(["costillas", 0.3 * (2.0 if bad else 1.0), foot + Vector3.UP * 1.2])
	if bad and h > 4.0:
		chances.append(["cráneo", 0.25, foot + Vector3.UP * 1.6])
	for c in chances:
		if randf() < float(c[1]):
			var lab := str(c[0])
			var n := anat.find_group(lab, c[2])
			if n == "":
				continue
			var g: Dictionary = anat.groups[n]
			if g.system == "hueso":
				anat.add_wound(n, g.center, Vector3.UP, 0.01, 0)
				anat.break_bone(n, g.center, Vector3.DOWN, 0.0 if h < 9.0 else 0.6)
				_apply_effect(g.label, "Fractura de %s por la caída" % g.label, res, 1.0, _loc(n, g.center, Vector3.DOWN))
			else:
				anat.add_wound(n, g.center, Vector3.UP, 0.035, 2)
				_apply_effect(g.label, "Rotura de %s por el impacto" % g.label, res, 1.0, _loc(n, g.center, Vector3.DOWN))
			res.nodes.append(n)

func _fracture_by_label(anat: AnatomyBody, actor: Actor, lab: String, point: Vector3, dir: Vector3, res: Dictionary, r: float, text: String) -> void:
	var n := anat.find_group(lab, point)
	if n == "":
		return
	anat.add_wound(n, anat.groups[n].center, anat.dir_to_bind(n, dir), r, 0)
	anat.break_bone(n, anat.groups[n].center, dir, 0.0)
	_apply_effect(anat.groups[n].label, text, res, 0.7, _loc(n, anat.groups[n].center, dir))
	res.nodes.append(n)

var _strength := 1.0
## Probabilidad de que una bala se desvíe al pegar en cada hueso (los densos desvían más).
const DEFLECT := {"cráneo": 0.35, "fémur": 0.4, "húmero": 0.35, "tibia": 0.35, "pelvis": 0.35, "vértebras": 0.3,
	"mandíbula": 0.3, "escápula": 0.25, "clavícula": 0.25, "costillas": 0.2, "esternón": 0.2}

static func _bone_key(label: String) -> String:
	for k in DEFLECT:
		if label.begins_with(k):
			return k
	return ""

func _hit_structure(anat: AnatomyBody, actor: Actor, h: Dictionary, t: String, r: float, res: Dictionary, point: Vector3, dir: Vector3) -> void:
	var n := str(h.node)
	var lab := str(h.label)
	var sys := str(h.system)
	var lodged := bool(h.get("lodged", false)) or t in ["fragment", "knife"]
	if sys == "hueso":
		anat.add_wound(n, h.p_in, h.dir, r * 1.6, 0)
		# rotura real (fragmentos de Blender): los más cercanos se desprenden
		anat.break_bone(n, h.p_in, dir, _strength if t != "knife" else 0.3)
		var txt := ("Fractura expuesta de %s" if t == "bullet" else "Fractura de %s") % lab
		_apply_effect(lab, txt, res, 1.0, _loc(n, h.p_in, dir))
		# astilla de hueso hacia un órgano vecino
		var fx := effect_of(lab)
		for sh in fx.get("shard", []):
			if randf() < float(sh[1]):
				var target := anat.find_group(str(sh[0]), anat.bind_to_world(n, h.p_in))
				if target != "" and target != n:
					var tc: Vector3 = anat.groups[target].center
					anat.add_wound(target, tc, anat.dir_to_bind(target, dir), 0.006, 3, 0.4)
					_apply_effect(str(anat.groups[target].label), "Astilla de %s perforó %s" % [lab, anat.groups[target].label], res, 1.0, _loc(target, tc, dir))
					res.nodes.append(target)
					break
	else:
		var depth := (float(h.t_out) - float(h.t_in)) / 0.25
		anat.add_wound(n, h.p_in, h.dir, r, 3 if lodged else 1, clampf(depth, 0.05, 0.99))
		var verb := "Esquirla alojada en" if t == "fragment" else ("Puñalada en" if t == "knife" else "Perforación de")
		var detail := str(effect_of(lab).get("text", ""))
		_apply_effect(lab, detail if detail != "" and t == "bullet" else "%s %s" % [verb, lab], res, 1.0, _loc(n, h.p_in, dir))
	res.nodes.append(n)
	# estructura «principal» (la que enfoca la cámara): la que más daño hace, no la primera que cruzó la bala
	var fxm := effect_of(lab)
	var wgt := float(fxm.get("hp", 0)) + float(fxm.get("bleed", 0)) * 4.0 + (50.0 if str(fxm.get("effect", "")) == "death" else 0.0)
	if res.main == "" or wgt > float(res.main_w) + 0.01:
		res.main = n
		res.main_w = wgt

## El disparo viaja en el plano z = 0 pero los ojos están a los lados de la cara: si la bala viene de frente y pasa a
## menos de 2,4 cm de altura de un ojo, la trayectoria se pasa a la profundidad de ese ojo (le pega al globo ocular).
func _snap_to_eye(anat: AnatomyBody, point: Vector3, dir: Vector3, z: float) -> float:
	var best := z
	var bd := 0.024
	for lab in ["ojo der", "ojo izq"]:
		var n := anat.find_group(lab)
		if n == "":
			continue
		var c := anat.bind_to_world(n, anat.groups[n].center)
		var toward: float = (c.x - _actor.global_position.x) * dir.x          # el ojo mira hacia el tirador
		var d := absf(c.y - point.y)
		if toward < 0.0 and d < bd:
			bd = d
			best = c.z
	return best

## Ubicación (mundo) de una herida para la hemorragia: hueso que la mueve, punto y dirección de salida.
func _loc(node: String, p_bind: Vector3, dir: Vector3) -> Dictionary:
	if _anat == null or not _anat.groups.has(node):
		return {}
	return {"bone": str(_anat.groups[node].bone), "point": _anat.bind_to_world(node, p_bind), "dir": dir}

const ARTERIAL := ["corazón", "aorta", "arterias y venas de cuello", "arterias y venas de muslo", "arterias y venas de brazo",
	"arterias y venas de tórax", "arterias y venas de abdomen", "arterias y venas de pelvis"]

func _apply_effect(label: String, text: String, res: Dictionary, k: float, loc := {}) -> void:
	res.texts.append(text)
	# la misma estructura dañada dos veces en un golpe (astilla + bala) cuenta una sola vez
	if res.applied.has(label):
		return
	res.applied[label] = true
	var fx := effect_of(label)
	res.hp += float(fx.get("hp", 0)) * k
	var b := float(fx.get("bleed", 0)) * k
	if b > 0.0:
		var entry := {"rate": b, "treat": str(fx.get("treat", "bandage")), "text": label, "src": null}
		# sangre líquida que sale de esa herida y sigue al cuerpo: chorro pulsátil (arterias) o mana / gotea (vísceras)
		# (una sola fuente por hueso: si ya sangra ahí, se suma; con que una sea arteria, el chorro es pulsátil)
		if not loc.is_empty() and _actor and is_instance_valid(_actor) and Blood.instance:
			var art := false
			for a in ARTERIAL:
				if label.begins_with(a):
					art = true
			var src: Blood.BleedSource = _sources.get(str(loc.bone))
			if src == null or not is_instance_valid(src):
				src = Blood.BleedSource.new()
				src.rate = 0.0
				src.setup(_actor, str(loc.bone), loc.point, loc.dir)
				_sources[str(loc.bone)] = src
			src.arterial = src.arterial or art
			src.rate += b
			entry.src = src
		bleeds.append(entry)
	var st := float(fx.get("stun", 0.0))
	if st > 0.0 and _actor and is_instance_valid(_actor):
		_actor.stun(st)                   # dolor que paraliza un momento (ojo, testículos)
	match str(fx.get("effect", "")):
		"death":
			res.death = true
		"leg":
			leg_broken = true
		"paralysis":
			paralysis = true
			leg_broken = true
		"arm":
			arm = minf(arm + 0.5, 1.0)
		"hand":
			hand = minf(hand + 0.7, 1.0)
		"aim":
			head = minf(head + 0.5, 1.0)
		"breath":
			breath = true

func any() -> bool:
	return leg_broken or arm > 0.0 or hand > 0.0 or head > 0.0 or breath or not bleeds.is_empty()

## Venda: corta hemorragias chicas, frena a la mitad las grandes, entablilla la pierna.
## Botiquín: corta todas, recupera brazo/mano/cabeza/respiración y la pierna (no la parálisis).
func treat(item: String) -> float:
	match item:
		"bandage":
			var keep := []
			for b in bleeds:
				if str(b.treat) == "bandage":
					_stop(b)
					continue
				b.rate = float(b.rate) * 0.5
				if b.src and is_instance_valid(b.src):
					b.src.rate = b.rate
				keep.append(b)
			bleeds = keep
			if not paralysis:
				leg_broken = false
			arm = maxf(arm - 0.3, 0.0)
			changed.emit()
			return 15.0
		"medkit":
			for b in bleeds:
				_stop(b)
			bleeds.clear()
			if not paralysis:
				leg_broken = false
			arm = 0.0
			hand = 0.0
			head = 0.0
			breath = false
			changed.emit()
			return 60.0
	return 0.0

func _stop(b: Dictionary) -> void:
	if b.src and is_instance_valid(b.src):
		b.src.rate -= float(b.rate)
		if b.src.rate <= 0.05:
			b.src.queue_free()

## Al morir: los chorros se apagan (sin pulso) y después de un rato se cortan; queda el charco.
func on_death() -> void:
	for b in bleeds:
		if b.src and is_instance_valid(b.src):
			b.src.arterial = false
			b.src.rate = minf(float(b.rate), 1.5)
			var s: Node = b.src
			s.get_tree().create_timer(6.0).timeout.connect(func(): if is_instance_valid(s): s.queue_free())

func aim_penalty() -> float:
	return 1.0 + arm * 1.6 + hand * 2.4 + head * 1.0

func summary() -> String:
	var parts: Array[String] = []
	if paralysis:
		parts.append("PARÁLISIS")
	elif leg_broken:
		parts.append("PIERNA ROTA")
	if arm > 0.0:
		parts.append("BRAZO")
	if hand > 0.0:
		parts.append("MANO")
	if head > 0.0:
		parts.append("CONMOCIÓN")
	if breath:
		parts.append("PULMÓN")
	if not bleeds.is_empty():
		parts.append("HEMORRAGIA %.1f/s" % bleeding)
	if deaf > 0.0:
		parts.append("SORDO")
	return " · ".join(parts)
