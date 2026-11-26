class_name NoiseOverlay
extends Control
## Indicadores de pantalla: de dónde viene el RUIDO (ondas en la dirección del sonido: arriba/abajo, izquierda/derecha, más
## fuertes cuanto más cerca) y el RADAR de la especialidad (puntos blancos con la distancia a cada enemigo).

var player: Actor
var camera: Camera3D
const SHOW_T := 2.6

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(_d: float) -> void:
	queue_redraw()

func _draw() -> void:
	if player == null or not is_instance_valid(player) or player.is_dead():
		return
	var s := size
	var c := s * 0.5 + Vector2(0, -s.y * 0.06)
	var rx := s.y * 0.36
	var now := Time.get_ticks_msec()
	var font := ThemeDB.fallback_font
	for e in NoiseBus.last_events:
		if e.source == player:
			continue
		var age := float(now - int(e.t)) / 1000.0
		if age > SHOW_T:
			continue
		var d3: Vector3 = (e.pos as Vector3) - player.global_position
		var dist := d3.length()
		if dist > float(e.radius) or dist < 1.0:
			continue
		var k := (1.0 - dist / float(e.radius)) * (1.0 - age / SHOW_T)
		var ang := atan2(-d3.y, d3.x)               # y de la pantalla crece hacia abajo
		for i in 3:
			var rr := rx * (0.9 + 0.12 * i) + age * 24.0
			var a := clampf(k * (1.0 - i * 0.28), 0.0, 1.0)
			draw_arc(c, rr, ang - 0.22 - i * 0.04, ang + 0.22 + i * 0.04, 14, Color(0.07, 0.07, 0.09, a), 3.0 - i * 0.6, true)
		var tip := c + Vector2(cos(ang), sin(ang)) * (rx * 0.82)
		draw_circle(tip, 4.0 + 5.0 * k, Color(0.07, 0.07, 0.09, clampf(k * 1.4, 0.0, 1.0)))
		if absf(d3.y) > 2.6:
			draw_string(font, tip + Vector2(8, 5), "▲" if d3.y > 0 else "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.07, 0.07, 0.09, clampf(k * 1.4, 0.0, 1.0)))
	# radar de la especialidad
	if player.radar_t > 0.0:
		var rc := Vector2(s.x * 0.5, s.y - 150.0) if false else Vector2(s.x - 120.0, s.y * 0.5 + 20.0)
		var rr := 92.0
		draw_circle(rc, rr, Color(1, 1, 1, 0.82))
		draw_arc(rc, rr, 0, TAU, 48, Color(0.07, 0.07, 0.09), 2.0, true)
		draw_arc(rc, rr * 0.5, 0, TAU, 32, Color(0.07, 0.07, 0.09, 0.35), 1.0, true)
		draw_line(rc - Vector2(rr, 0), rc + Vector2(rr, 0), Color(0.07, 0.07, 0.09, 0.25), 1.0)
		draw_line(rc - Vector2(0, rr), rc + Vector2(0, rr), Color(0.07, 0.07, 0.09, 0.25), 1.0)
		draw_circle(rc, 4.0, Color(0.07, 0.07, 0.09))
		var rng := 45.0
		for n in get_tree().get_nodes_in_group("actors"):
			var a := n as Actor
			if a == null or a == player or a.is_dead() or a.team == player.team:
				continue
			var d := a.global_position - player.global_position
			if d.length() > rng:
				continue
			var p := rc + Vector2(d.x, -d.y) / rng * rr
			draw_circle(p, 5.0, Color(0.8, 0.1, 0.08))
			draw_string(font, p + Vector2(7, 4), "%d m" % int(d.length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.07, 0.07, 0.09))
		draw_string(font, rc + Vector2(-rr, -rr - 6), "RADAR %d s" % int(ceil(player.radar_t)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.07, 0.07, 0.09))
