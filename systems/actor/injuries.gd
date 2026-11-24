class_name Injuries
extends RefCounted
## Lesiones con efecto en el juego (salen de los rayos X: XRayAnatomy.injuries_at):
##  * PIERNA FRACTURADA (fémur, tibia, rótula, pie): no puede correr (renguea con la animación de herido de Mixamo),
##    salta menos, no se sube a cajas altas, trepa y sube escaleras más lento. Dura hasta usar una VENDA (entablillar)
##    o un BOTIQUÍN.
##  * BRAZO HERIDO (húmero, radio/cúbito, mano, clavícula, escápula): más dispersión, el arma tiembla y recarga lento.
##  * GOLPE EN LA CABEZA (cráneo, mandíbula, cerebro): la puntería oscila.
##  * HEMORRAGIA (órganos perforados, vasos): pierde vida por segundo y gotea sangre hasta vendarse.
## Venda: corta la hemorragia, entablilla la pierna y cura un poco. Botiquín: cura todo y bastante vida.

signal changed

var leg_broken := false
var arm := 0.0            ## 0..1
var head := 0.0           ## 0..1
var bleeding := 0.0       ## vida por segundo
var log: Array[String] = []

const LEG := ["fémur", "tibia", "rótula", "pie"]
const ARM := ["húmero", "radio", "mano", "clavícula", "escápula"]
const HEAD := ["cráneo", "mandíbula", "cerebro", "cerebelo"]

func apply(list: Array, type: String) -> void:
	var any := false
	for i in list:
		var lab := str(i.label)
		var sev := float(i.severity)
		var sys := str(i.system)
		if sys == "hueso":
			if _starts(lab, LEG) and (sev >= 15.0 or type == "fall"):
				leg_broken = true
				any = true
			elif _starts(lab, ARM) and sev >= 10.0:
				arm = minf(arm + 0.5, 1.0)
				any = true
			elif _starts(lab, HEAD):
				head = minf(head + 0.5, 1.0)
				any = true
		elif sys in ["organo", "vaso"] and type in ["bullet", "knife", "blast"]:
			bleeding = minf(bleeding + clampf(sev * 0.04, 0.6, 2.5), 5.0)
			any = true
		elif sys == "nervio":
			head = 1.0
			any = true
		log.append(str(i.text))
	if any:
		changed.emit()

static func _starts(lab: String, keys: Array) -> bool:
	for k in keys:
		if lab.begins_with(k):
			return true
	return false

func any() -> bool:
	return leg_broken or arm > 0.0 or head > 0.0 or bleeding > 0.0

## Usar una venda o un botiquín. Devuelve la vida que cura.
func treat(item: String) -> float:
	match item:
		"bandage":
			bleeding = 0.0
			leg_broken = false
			arm = maxf(arm - 0.5, 0.0)
			changed.emit()
			return 15.0
		"medkit":
			bleeding = 0.0
			leg_broken = false
			arm = 0.0
			head = 0.0
			changed.emit()
			return 60.0
	return 0.0

## Factor de dispersión y temblor del apuntado.
func aim_penalty() -> float:
	return 1.0 + arm * 1.6 + head * 1.0

func summary() -> String:
	var parts: Array[String] = []
	if leg_broken:
		parts.append("PIERNA FRACTURADA")
	if arm > 0.0:
		parts.append("BRAZO HERIDO")
	if head > 0.0:
		parts.append("CONMOCIÓN")
	if bleeding > 0.0:
		parts.append("HEMORRAGIA")
	return " · ".join(parts)
