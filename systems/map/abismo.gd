class_name AbismoVertical
extends RefCounted
## Mapa «Abismo Vertical»: instalación subterránea de 8 pisos (Piso −7 abajo del todo … Piso 0 en la superficie) y 120 m de
## ancho, armada con el mismo constructor que la Torre Alfa (TowerBuilder) a partir de DATOS. Se empieza en el fondo, sin
## equipo, y se sube: arriba hay mejores armas y botín, pero también más enemigos.
##
## Mecánicas del mapa (además de las de la Torre):
##   puertas de oficina que se patean o se balean ("door"), paredes de vidrio y tabiques finos que se rompen ("door",
##   "duct") — romperlos hace ruido —, puertas con tarjeta ("locked:<ítem>"), persianas pesadas que abre una palanca
##   ("shutter:<id>" + "levers"), trampas de gas con palanca ("gas_traps"), bóvedas con botín, minas sueltas,
##   dos extracciones: el túnel de evacuación del piso −4 (siempre abierto) y el helicóptero de la superficie (llega a los 4 min).
## Los pisos se rellenan con un generador determinista (misma semilla → mismo mapa): decorado, cajas y enemigos según la
## profundidad; las puertas, llaves y salidas están escritas a mano abajo.

const FLOOR_H := 4.5
const WIDTH := 120.0
const ELEV_X := 60.0
const ELEV_W := 2.4
const SEED := 2024

## Ascensor de piso f al f+1 por escaleras de mano: [x, salida]. Y escaleras inclinadas [x0, x1].
const LADDERS := [[[8.0, 1.0], [100.0, -1.0]], [[112.0, -1.0], [30.0, 1.0]], [[6.0, 1.0], [90.0, -1.0]], [[44.0, 1.0], [86.0, -1.0]],
	[[14.0, 1.0], [80.0, -1.0]], [[104.0, -1.0], [36.0, 1.0]], [[10.0, 1.0], [98.0, -1.0]], [[20.0, 1.0], [104.0, -1.0]]]
const STAIRS := {0: [70.0, 76.6], 3: [24.0, 30.6], 5: [86.0, 92.6]}

const WALLS := [
	[[18.0, "door"], [34.0, "door"], [47.0, "duct"], [53.0, "door"], [67.0, "door"], [80.0, "door"], [90.0, "door"], [108.0, "locked:keycard_c"]],
	[[16.0, "door"], [40.0, "door"], [53.0, "door"], [67.0, "door"], [84.0, "door"], [94.0, "door"], [106.0, "door"]],
	[[14.0, "door"], [22.0, "door"], [46.0, "duct"], [53.0, "door"], [68.0, "door"], [80.0, "shutter:S2"], [100.0, "door"], [108.0, "door"]],
	[[16.0, "door"], [36.0, "door"], [52.0, "door"], [68.0, "duct"], [76.0, "door"], [100.0, "door"]],
	[[22.0, "door"], [38.0, "door"], [52.0, "duct"], [66.0, "door"], [90.0, "locked:keycard_b"], [106.0, "door"]],
	[[24.0, "door"], [46.0, "door"], [54.0, "door"], [66.0, "door"], [96.0, "door"]],
	[[20.0, "duct"], [48.0, "door"], [54.0, "door"], [68.0, "duct"], [78.0, "door"], [112.0, "locked:keycard_vault"]],
	[[30.0, "door"], [46.0, "door"], [53.0, "door"], [67.0, "door"], [84.0, "door"]],
]

const NAMES := ["Piso −7 · Cimientos", "Piso −6 · Depósitos", "Piso −5 · Servicios", "Piso −4 · Túneles", "Piso −3 · Laboratorios",
	"Piso −2 · Oficinas", "Piso −1 · Seguridad", "Piso 0 · Vestíbulo"]
const TEX := ["concrete", "metal_panel", "concrete", "metal_panel", "concrete", "metal_panel", "concrete", "metal_panel"]
const ENEMY_N := [2, 3, 3, 4, 4, 5, 5, 6]
const CHARS := ["vigia", "doc", "fantasma", "mortero", "zapador"]
const WEAPONS := [["m1911", "pistol_1", "revolver_1", "mp5_1"], ["m1911_1", "pistol_2", "mp5_1", "shotgun_1"],
	["mp5_1", "smg_1", "shotgun_1", "m16", "ar_1"], ["smg_2", "shotgun_2", "m16_1", "ak47", "ar_2"],
	["m4a1", "ak47", "scar", "p90", "sniper_1"], ["scar", "g36c", "mp7", "sniper_2", "shotgun_3"],
	["scarh", "aug", "vector", "m4dmr", "sniper_4"], ["scarh", "aug", "vector", "m4dmr", "sniper_5", "shotgun_3"]]
const PROPS := [
	[["shelf_steel_shelves", 0, "decor"], ["crate_pallet", 0, "decor"], ["crate_plastic_storage_box", 0, "decor"], ["trash_wheelie_bin", 0, "decor"], ["truck_fork_lift", 0, "cover"]],
	[["shelf_steel_shelves", 0, "decor"], ["crate_cart", 0, "decor"], ["shelf_pinewood_rack_full_height", 0, "decor"], ["crate_shipping_container", 0.55, "cover"], ["crate_pallet", 0, "decor"]],
	[["table_workbench", 0, "decor"], ["table_workbench_2", 0, "decor"], ["sf_wall_panel", 0, "decor"], ["prop_monitor_lcd", 0, "decor"], ["cabinet_filing_cabinet", 0, "decor"]],
	[["sf_vent_grill", 0, "decor"], ["crate_cart", 0, "decor"], ["table_workbench", 0, "decor"], ["crate_shipping_container", 0.5, "cover"], ["trash_wheelie_bin", 0, "decor"]],
	[["sf_portable_lab_computer", 0, "decor"], ["sf_main_laboratory_computer_bank", 0.5, "decor"], ["sf_sickbay_or_table", 0, "decor"], ["sf_sickbay_wall_monitor_0", 0, "decor"]],
	[["cabinet_filing_cabinet", 0, "decor"], ["prop_monitor_lcd", 0, "decor"], ["table_workbench_2", 0, "decor"], ["shelf_pinewood_rack_full_height", 0, "decor"], ["sc_cctv", 0, "decor"]],
	[["sc_cctv", 0, "decor"], ["prop_locked_locker", 0, "decor"], ["sf_transporter_console_best", 0.55, "decor"], ["cabinet_filing_cabinet", 0, "decor"], ["sf_light_fixture", 0, "decor"]],
	[["sc_cctv", 0, "decor"], ["prop_locked_locker", 0, "decor"], ["sf_main_laboratory_computer_bank", 0.5, "decor"], ["table_workbench", 0, "decor"], ["sf_wall_panel", 0, "decor"]],
]
const COVERS := [["crate_shipping_container", 0.5, "cover"], ["truck_fork_lift", 0, "cover"], ["crate_shipping_container", 0.4, "cover"]]
const CRATES := [["crate_wood", "crate_wood"], ["crate_wood", "crate_wood"], ["crate_wood", "crate_wood"], ["crate_metal", "crate_metal"],
	["crate_metal", "crate_metal"], ["suitcase", "suitcase"], ["suitcase", "suitcase"], ["lab_case", "lab_case"]]

static func ladders_flat() -> Array:
	var out := []
	for f in LADDERS.size():
		for l in LADDERS[f]:
			out.append([float(l[0]), float(f) * FLOOR_H, float(f + 1) * FLOOR_H, float(l[1])])
	# entrepisos: escalerita al lado de cada tarima alta
	out.append([19.6, 2.0 * FLOOR_H, 2.0 * FLOOR_H + 2.2, 1.0])
	out.append([69.6, 5.0 * FLOOR_H, 5.0 * FLOOR_H + 2.2, 1.0])
	return out

static func data() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var elev_hole := [ELEV_X - ELEV_W * 0.5 - 0.05, ELEV_X + ELEV_W * 0.5 + 0.05]
	var floors := []
	for f in 8:
		var holes := []
		var forbid := [[ELEV_X - 3.0, ELEV_X + 3.0]]
		if f > 0:
			holes.append(elev_hole)
			for l in LADDERS[f - 1]:
				holes.append([float(l[0]) - 0.45, float(l[0]) + 0.45])
				forbid.append([float(l[0]) - 2.5, float(l[0]) + 2.5])
			if STAIRS.has(f - 1):
				var s: Array = STAIRS[f - 1]
				holes.append([float(s[1]) - 3.3, float(s[1])])
				forbid.append([float(s[0]) - 1.0, float(s[1]) + 1.0])
		for l in LADDERS[f]:
			forbid.append([float(l[0]) - 2.5, float(l[0]) + 2.5])
		if STAIRS.has(f):
			forbid.append([float(STAIRS[f][0]) - 1.0, float(STAIRS[f][1]) + 1.0])
		var walls: Array = WALLS[f]
		for w in walls:
			forbid.append([float(w[0]) - 1.4, float(w[0]) + 1.4])
		var platforms := []
		var extra_h := {}
		if f == 2:
			platforms.append([20.0, 28.0, 2.2, "entrepiso"])
		if f == 5:
			platforms.append([70.0, 78.0, 2.2, "entrepiso"])
		if f == 1:
			platforms.append([88.0, 93.0, 1.0, "tarima"])
		if f == 3:
			platforms.append([56.0, 58.5, 1.2, "tarima"])
		var props := []
		var crates := []
		var enemies := []
		var lamps := []
		var x := 6.0
		while x < WIDTH - 4.0:
			lamps.append(x)
			x += 14.0
		var rooms := _rooms(walls)
		for r in rooms:
			var x0: float = r[0]
			var x1: float = r[1]
			var np := int((x1 - x0) / 7.0)
			for i in np:
				var px := _free_x(rng, x0 + 1.0, x1 - 1.0, forbid)
				if px < 0.0:
					continue
				var pd: Array = PROPS[f][rng.randi() % PROPS[f].size()]
				if rng.randf() < 0.4:
					pd = COVERS[rng.randi() % COVERS.size()]          # obstáculos para cubrirse y trepar
				props.append([px, pd[0], pd[1], pd[2]])
				forbid.append([px - 1.3, px + 1.3])
			var nc := 1 + int((x1 - x0) / 14.0)
			for i in nc:
				var cx := _free_x(rng, x0 + 1.0, x1 - 1.0, forbid)
				if cx < 0.0:
					continue
				var cd: Array = CRATES[clampi(f + (rng.randi() % 2) - (rng.randi() % 2), 0, 7)]
				var kind: String = cd[0]
				if rng.randf() < 0.22:
					kind = "barrel"
					crates.append([cx, "barrel", "", 0.0])
				elif rng.randf() < 0.15:
					crates.append([cx, "cardboard", "", 0.0])
				else:
					crates.append([cx, kind, cd[1], 0.0])
				forbid.append([cx - 0.8, cx + 0.8])
		for i in ENEMY_N[f]:
			var ex := _free_x(rng, 22.0 if f == 0 else 8.0, WIDTH - 6.0, [[ELEV_X - 2.0, ELEV_X + 2.0]])
			if ex >= 0.0:
				var wl: Array = WEAPONS[f]
				enemies.append([ex, CHARS[rng.randi() % CHARS.size()], wl[rng.randi() % wl.size()]])
		var fd := {"id": f, "name": NAMES[f], "tag": str(f - 7) if f < 7 else "0", "wall_tex": TEX[f], "holes": holes, "walls": walls,
			"platforms": platforms, "props": props, "crates": crates, "enemies": enemies, "lamps": lamps, "pickups": [],
			"elev_name": str(f - 7)}
		floors.append(fd)
	_hand_placed(floors)
	return {
		"name": "Abismo Vertical", "objective": "subí desde el Piso −7; salida fija en el Piso −4 o helicóptero en la superficie (4 min)", "width": WIDTH, "floor_h": FLOOR_H, "start": Vector3(3.0, 0.05, 0.0), "floors": floors,
		"roof": {"y": FLOOR_H * 8.0, "holes": [[19.55, 20.45], [103.55, 104.45]], "extraction": [60.0, "Helicóptero (llega a los 4 min)", 240.0]},
		"ladders": ladders_flat(), "stairs": [[70.0, 76.6, 0], [24.0, 30.6, 3], [86.0, 92.6, 5]], "crater": [], "jumps": [],
		"elevator": {"x": ELEV_X, "width": ELEV_W, "stops": [0, 1, 2, 3, 4, 5, 6, 7]},
	}

## Lo escrito a mano: llaves, bóvedas, palancas, trampas, armas sueltas, extracción fija.
static func _hand_placed(fl: Array) -> void:
	# P−7: arranque sin equipo útil: una pistola y una mina al comienzo; bóveda de la derecha (tarjeta amarilla)
	fl[0].pickups.append([4.2, "w_m1911"])
	fl[0].pickups.append([6.0, "mine"])
	fl[0].crates.append_array([[112.0, "lab_case", "lab_case", 0.0], [115.0, "lab_case", "lab_case", 0.0], [118.0, "suitcase", "suitcase", 0.0]])
	fl[0].pickups.append([110.5, "w_deagle"])
	# P−6: la tarjeta amarilla en una caja (abre la bóveda del P−7)
	fl[1].crates.append([26.0, "crate_wood", "key:keycard_c", 0.0])
	fl[1].pickups.append([58.0, "mine"])
	# P−5: palanca que abre la persiana (x = 80) del cuarto con la escalera; tarima con cajas
	fl[2].levers = [[10.0, "S2"]]
	fl[2].crates.append_array([[22.0, "crate_metal", "crate_metal", 2.2], [26.0, "crate_wood", "key:keycard_b", 2.2]])
	fl[2].pickups.append([86.0, "w_mp7"])
	# P−4: túnel de evacuación (siempre abierto), trampa de gas en el pasillo central
	fl[3].extraction = [114.0, "Túnel de evacuación (fijo)"]
	fl[3].gas_traps = [[54.0, 38.0, 51.0]]
	fl[3].pickups.append([20.0, "w_ak47"])
	# P−3: laboratorio con bóveda (tarjeta azul): armas de alto nivel
	fl[4].crates.append_array([[96.0, "lab_case", "lab_case", 0.0], [100.0, "lab_case", "lab_case", 0.0], [104.0, "lab_case", "lab_case", 0.0]])
	fl[4].pickups.append_array([[112.0, "w_scarh"], [114.0, "mine"]])
	fl[4].hazard = [70.0, 74.5]
	# P−2: la tarjeta roja
	fl[5].crates.append([30.0, "suitcase", "key:keycard_vault", 0.0])
	fl[5].pickups.append([72.0, "w_p90"])
	# P−1: bóveda final (tarjeta roja)
	fl[6].crates.append_array([[114.0, "lab_case", "lab_case", 0.0], [117.0, "lab_case", "lab_case", 0.0]])
	fl[6].pickups.append_array([[115.5, "w_aug"], [113.0, "w_sniper_5"]])
	fl[6].hazard = [88.0, 91.0]
	# P0: vestíbulo
	fl[7].pickups.append([40.0, "w_vector"])

static func _rooms(walls: Array) -> Array:
	var xs := [0.0]
	for w in walls:
		xs.append(float(w[0]))
	xs.append(WIDTH)
	var out := []
	for i in xs.size() - 1:
		out.append([xs[i], xs[i + 1]])
	return out

static func _free_x(rng: RandomNumberGenerator, a: float, b: float, forbid: Array) -> float:
	if b <= a:
		return -1.0
	for t in 24:
		var x := rng.randf_range(a, b)
		var ok := true
		for fb in forbid:
			if x > float(fb[0]) and x < float(fb[1]):
				ok = false
				break
		if ok:
			return snappedf(x, 0.1)
	return -1.0
