class_name Specialty
extends RefCounted
## Especialidades del operador (se activan con el botón «ESP»; luego hay que esperar la recarga):
##   radar: 10 s viendo a los enemigos y a qué distancia están · paramédico: cura y cierra heridas · velocista: +50 % de
##   velocidad · escudo: domo que aguanta un par de disparos · cohete: misil que persigue al enemigo · demoledor: minas y granadas.

const DEFS := {
	"radar": {"name": "Radar", "text": "10 s: muestra a los enemigos y su distancia", "cd": 45.0, "label": "RAD", "color": Color(0.3, 0.9, 1.0)},
	"medic": {"name": "Paramédico", "text": "Cura 60 de vida y cierra las hemorragias", "cd": 40.0, "label": "MED", "color": Color(0.4, 1.0, 0.5)},
	"sprint": {"name": "Velocista", "text": "8 s con +50 % de velocidad", "cd": 35.0, "label": "VEL", "color": Color(1.0, 0.85, 0.3)},
	"shield": {"name": "Escudo", "text": "Domo protector: aguanta 160 de daño durante 7 s", "cd": 50.0, "label": "ESC", "color": Color(0.6, 0.8, 1.0)},
	"rocket": {"name": "Cohete", "text": "Lanza un cohete que persigue al enemigo", "cd": 40.0, "label": "COH", "color": Color(1.0, 0.5, 0.3)},
	"demo": {"name": "Demoledor", "text": "Consigue 2 minas y 1 granada", "cd": 60.0, "label": "DEM", "color": Color(1.0, 0.4, 0.4)},
}
const ORDER := ["radar", "medic", "sprint", "shield", "rocket", "demo"]

static func name_of(id: String) -> String:
	return str(DEFS.get(id, DEFS.radar).name)

## Activa la especialidad del actor. Devuelve el texto para el aviso en pantalla.
static func activate(a: Actor) -> String:
	if a.spec_cd > 0.0:
		return "%s: lista en %d s" % [name_of(a.specialty), int(ceil(a.spec_cd))]
	var d: Dictionary = DEFS.get(a.specialty, DEFS.radar)
	a.spec_cd = float(d.cd)
	match a.specialty:
		"radar":
			a.radar_t = 10.0
		"medic":
			a.heal(60.0)
			a.injuries.bleeding = 0.0
		"sprint":
			a.boost_t = 8.0
		"shield":
			a.shield_hp = 160.0
			a.shield_t = 7.0
		"rocket":
			HomingRocket.launch(a)
		"demo":
			a.mines += 2
			a.grenades["frag"] = int(a.grenades.get("frag", 0)) + 1
	Sfx.play("pickup", a.global_position + Vector3.UP, 0.0, 0.7, 6.0, a)
	return "%s activado" % name_of(a.specialty)
