extends Node
## Ruido para la IA (autoload «NoiseBus»). Todo lo que suena fuerte (pasos al correr, disparos, golpes, cajas forzadas,
## ascensor, explosiones) llama emit_noise(posición, radio, fuente). Los oyentes (bots) reciben el evento si están dentro
## del radio, atenuado por las paredes que hay en el medio: cada pared atraviesa resta OCCLUSION_LOSS del radio.
## Así el sigilo sale solo: caminar despacio casi no se oye, correr sí, y una pared de por medio ayuda.

signal heard(pos: Vector3, loudness: float, source: Node)

const OCCLUSION_LOSS := 0.45     ## fracción del radio que se pierde por cada pared en el camino
const MAX_WALLS := 2

var _listeners: Array = []          ## Node3D o cualquier nodo con global_position, get_world_3d() y on_noise()
var last_events: Array = []      ## [{pos, radius, t}] para el indicador de ruido del HUD y las pruebas

func register(listener: Node) -> void:
	if not listener in _listeners:
		_listeners.append(listener)

func unregister(listener: Node) -> void:
	_listeners.erase(listener)

func emit_noise(pos: Vector3, radius: float, source: Node = null) -> void:
	if radius <= 0.0:
		return
	last_events.append({"pos": pos, "radius": radius, "t": Time.get_ticks_msec(), "source": source})
	if last_events.size() > 16:
		last_events.pop_front()
	heard.emit(pos, radius, source)
	for item in _listeners.duplicate():
		if not is_instance_valid(item):
			_listeners.erase(item)
			continue
		var l = item
		if l == source:
			continue
		var lp: Vector3 = l.global_position
		var d := lp.distance_to(pos)
		if d > radius:
			continue
		var eff := radius * _occlusion(l, pos)
		if d <= eff and l.has_method("on_noise"):
			l.on_noise(pos, 1.0 - d / maxf(eff, 0.01), source)

## Cuánto del ruido llega (1 = libre, menos si hay paredes del mundo entre la fuente y el oyente).
func _occlusion(l, pos: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = l.get_world_3d().direct_space_state
	var from := pos + Vector3.UP * 0.5
	var to: Vector3 = l.global_position + Vector3.UP * 1.2
	var k := 1.0
	var exclude: Array[RID] = []
	for i in MAX_WALLS:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		k *= 1.0 - OCCLUSION_LOSS
		exclude.append(hit.rid)
	return k
