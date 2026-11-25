class_name TorreAlfa
extends RefCounted
## Mapa de prueba «Torre Alfa» como DATOS (lo arma TowerBuilder). Cinco niveles irregulares, P0..P4, más la azotea.
## Ejes: x horizontal (0..60 m), y vertical. Altura de piso 4,5 m. Profundidad del plano de juego: z = 0.
##
## Cada piso define:
##   holes:   huecos en la losa de ESE piso [x0, x1] (trampillas de escaleras, hueco del ascensor, cráter, escalera)
##   walls:   tabiques [x, tipo] tipo: "door" (paso libre bajo dintel) · "solid" · "duct" (conducto: sólo agachado)
##            · "locked" (puerta con tarjeta) · "breakable" (panel de chapa que se rompe: ruta secreta)
##   platforms: [x0, x1, altura sobre el piso, "nombre"] tarimas y entrepisos
##   props:   [x, id del modelo de assets/props, escala o 0, "decor"|"cover"] decorado y coberturas
##   crates:  [x, tipo, tabla de botín o "", altura extra] cajas rompibles / contenedores con cuchillo
##   enemies: [x, id personaje, arma]
## Conexiones verticales (todas entran al grafo de conectividad del mapa):
##   ladders: [x, piso desde, piso hasta, salida arriba ±1]
##   stairs:  [x inicio, x fin, piso] rampa con escalones del piso al de arriba
##   crater:  bloques de escombro escalables [x0, x1, y_top]
##   elevator: x del centro y paradas

const FLOOR_H := 4.5
const WIDTH := 60.0
const SLAB := 0.3
const ELEV_X := 29.2
const ELEV_W := 2.4

static func data() -> Dictionary:
	var elev_hole := [ELEV_X - ELEV_W * 0.5 - 0.05, ELEV_X + ELEV_W * 0.5 + 0.05]
	return {
		"name": "Torre Alfa",
		"width": WIDTH,
		"floor_h": FLOOR_H,
		"start": Vector3(3.0, 0.05, 0.0),
		"floors": [
			{   # ------------------------------------------------ P0
				"id": 0, "name": "P0 · Acceso / Extracción", "tag": "B0", "wall_tex": "concrete",
				"holes": [],
				"walls": [[10.0, "door"], [21.0, "door"], [35.5, "door"], [49.0, "door"]],
				"platforms": [[44.0, 46.5, 1.0, "tarima"]],
				"props": [[5.5, "crate_pallet", 0, "decor"], [7.0, "shelf_steel_shelves", 0, "decor"], [13.0, "truck_fork_lift", 0, "cover"],
					[24.0, "crate_shipping_container", 0.55, "cover"], [31.8, "cabinet_filing_cabinet", 0, "decor"], [38.5, "table_workbench", 0, "decor"],
					[41.5, "shelf_pinewood_rack_full_height", 0, "decor"], [52.0, "sc_cctv", 0, "decor"], [16.5, "trash_wheelie_bin", 0, "decor"]],
				"crates": [[6.2, "crate_wood", "crate_wood", 0.0], [17.8, "crate_wood", "crate_wood", 0.0], [18.6, "crate_wood", "", 0.0],
					[33.6, "crate_wood", "", 0.0], [34.4, "crate_wood", "", 0.0], [33.6, "crate_wood", "", 0.62], [34.4, "crate_wood", "", 0.62],
					[45.2, "crate_metal", "crate_metal", 1.0], [27.0, "barrel", "", 0.0]],
				"enemies": [[40.0, "zapador", "m1911"]],
				"lamps": [5.0, 15.5, 28.0, 42.0, 54.0],
				"extraction": [56.0, "Extracción P0 (salida)"],
				"pickups": [[4.2, "w_m1911"]],
			},
			{   # ------------------------------------------------ P1
				"id": 1, "name": "P1 · Depósitos", "tag": "B1", "wall_tex": "metal_panel",
				"holes": [[7.55, 8.45], [15.3, 18.6], elev_hole, [34.1, 34.9]],
				"walls": [[11.5, "door"], [24.5, "duct"], [37.0, "door"], [49.5, "door"]],
				"platforms": [[50.5, 52.6, 1.3, "plataforma"], [54.6, 57.0, 2.5, "plataforma alta"]],
				"props": [[3.0, "shelf_steel_shelves", 0, "decor"], [5.0, "crate_plastic_storage_box", 0, "decor"], [13.5, "shelf_pinewood_rack_full_height", 0, "decor"],
					[20.0, "crate_cart", 0, "decor"], [27.0, "cabinet_filing_cabinet", 0, "decor"], [31.5, "shelf_steel_shelves", 0, "decor"],
					[44.0, "crate_pallet", 0, "decor"], [58.5, "trash_wheelie_bin", 0, "decor"]],
				"crates": [[2.0, "crate_wood", "crate_wood", 0.0], [21.5, "crate_wood", "crate_wood", 0.0], [22.3, "crate_wood", "", 0.0],
					[30.5, "suitcase", "suitcase", 0.0], [55.5, "crate_metal", "crate_metal", 2.5], [46.0, "barrel", "", 0.0], [12.6, "cardboard", "", 0.0]],
				"enemies": [[19.0, "mortero", "m4a1"], [44.0, "vigia", "m1911"]],
				"lamps": [4.0, 14.0, 22.0, 30.0, 43.0, 53.0],
				"pickups": [],
			},
			{   # ------------------------------------------------ P2
				"id": 2, "name": "P2 · Servicios / Cráter", "tag": "B2", "wall_tex": "concrete",
				"holes": [elev_hole, [38.4, 47.0], [58.55, 59.45]],
				"walls": [[12.0, "door"], [24.0, "door"], [34.0, "door"], [50.0, "door"]],
				"platforms": [[4.0, 9.5, 2.2, "entrepiso"], [14.0, 18.0, 1.2, "tarima"]],
				"props": [[2.0, "shelf_steel_shelves", 0, "decor"], [10.5, "sf_wall_panel", 0, "decor"], [16.0, "table_workbench_2", 0, "decor"],
					[26.5, "prop_monitor_lcd", 0, "decor"], [31.5, "crate_container", 0, "decor"], [52.5, "cabinet_filing_cabinet", 0, "decor"],
					[57.5, "shelf_pinewood_rack_full_height", 0, "decor"]],
				"crates": [[6.5, "crate_metal", "crate_metal", 2.2], [8.0, "crate_wood", "key", 2.2], [27.5, "crate_wood", "crate_wood", 0.0],
					[28.2, "barrel", "", 0.0], [52.0, "suitcase", "suitcase", 0.0], [16.0, "crate_wood", "crate_wood", 1.2]],
				"enemies": [[27.0, "fantasma", "m4a1"], [53.0, "doc", "m1911"]],
				"lamps": [6.0, 18.0, 29.0, 42.5, 54.0],
				"pickups": [[19.5, "w_mp5_1"]],
			},
			{   # ------------------------------------------------ P3
				"id": 3, "name": "P3 · Almacén / Taller", "tag": "B3", "wall_tex": "metal_panel",
				"holes": [[6.0, 12.0], [20.55, 21.45], elev_hole, [40.0, 46.0]],
				"walls": [[14.0, "door"], [25.0, "door"], [37.0, "door"], [48.0, "door"]],
				"platforms": [],
				"props": [[2.5, "truck_fork_lift", 0, "cover"], [16.5, "table_workbench", 0, "decor"], [18.5, "shelf_steel_shelves", 0, "decor"],
					[23.0, "crate_shipping_container", 0.5, "cover"], [36.0, "crate_pallet", 0, "decor"], [49.5, "sc_cardboard_box", 0, "decor"]],
				"crates": [[15.0, "crate_metal", "crate_metal", 0.0], [17.5, "barrel", "", 0.0], [18.2, "barrel", "", 0.0], [27.0, "crate_wood", "crate_wood", 0.0],
					[31.0, "crate_metal", "crate_metal", 0.0], [36.5, "barrel", "", 0.0], [47.0, "crate_wood", "crate_wood", 0.0]],
				"enemies": [[17.0, "zapador", "mp5_1"], [31.5, "mortero", "m16_1"], [50.0, "vigia", "m4a1"]],
				"lamps": [4.0, 16.0, 22.0, 31.0, 43.0, 51.0],
				"moving_platform": [6.2, 11.8, -0.05],
				"pickups": [[27.8, "w_scar"]],
			},
			{   # ------------------------------------------------ P4
				"id": 4, "name": "P4 · Laboratorio", "tag": "B4", "wall_tex": "concrete",
				"holes": [elev_hole, [30.05, 30.95]],
				"walls": [[10.0, "door"], [22.0, "door"], [33.0, "locked"], [46.0, "door"]],
				"platforms": [[40.0, 44.0, 1.0, "consola"]],
				"props": [[3.0, "sf_main_laboratory_computer_bank", 0.5, "decor"], [14.0, "sf_sickbay_or_table", 0, "decor"], [17.5, "sf_portable_lab_computer", 0, "decor"],
					[26.0, "sf_transporter_console_best", 0.55, "decor"], [36.0, "sf_sickbay_wall_monitor_0", 0, "decor"], [38.0, "sf_main_laboratory_computer_bank", 0.5, "decor"],
					[50.5, "prop_locked_locker", 0, "decor"], [55.0, "sf_light_fixture", 0, "decor"]],
				"crates": [[6.5, "crate_metal", "crate_metal", 0.0], [20.0, "suitcase", "suitcase", 0.0], [41.0, "lab_case", "lab_case", 1.0],
					[43.0, "lab_case", "lab_case", 1.0], [52.0, "crate_metal", "crate_metal", 0.0], [12.0, "glass", "", 0.0]],
				"enemies": [[16.0, "fantasma", "m4a1"], [39.0, "doc", "mp5_1"], [53.0, "mortero", "m16_1"]],
				"lamps": [5.0, 16.0, 28.0, 39.5, 52.0],
				"hazard": [24.0, 27.5],
				"pickups": [[44.5, "w_m4dmr"]],
			},
		],
		"roof": {"y": FLOOR_H * 5.0, "holes": [[57.55, 58.45]], "extraction": [50.0, "Extracción superior (helicóptero)"]},
		"ladders": [   # [x, y desde, y hasta, salida arriba ±1] (metros)
			[8.0, 0.0, 4.5, 1.0], [59.0, 4.5, 9.0, -1.0], [21.0, 9.0, 13.5, 1.0], [30.5, 13.5, 18.0, -1.0], [58.0, 18.0, 22.5, -1.0],
			[34.5, 0.0, 4.5, -1.0],   # ruta secreta: detrás de la pila de cajas del P0 (hay que romperlas o saltarlas)
			[3.6, 9.0, 11.2, 1.0],    # escalera en la pared del fondo hasta el entrepiso del P2
		],
		"stairs": [[12.0, 18.6, 0]],
		# cráter: pilares de escombro desde el fondo (P1, y = 4,5) hasta y_top; se suben con el botón de salto (cajas) y
		# agarrándose de los bordes; del pilar de 6,8 m se alcanza el borde del P2 (x = 38) y del de 11,6 m el del P3 (x = 46)
		"crater": [[38.4, 39.6, 5.6], [39.6, 40.8, 6.8], [40.8, 42.0, 8.0], [42.0, 43.2, 9.2], [43.2, 44.4, 10.4], [44.4, 45.6, 11.6]],
		"jumps": [[52.6, 54.6, 1]],
		"elevator": {"x": ELEV_X, "width": ELEV_W, "stops": [0, 1, 2, 3, 4]},
	}
