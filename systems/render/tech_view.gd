extends Node
## Estilo en línea del juego (autoload «TechView»). El juego es SIEMPRE blanco con líneas: los modelos (armas, personajes,
## props) y la arquitectura nacen ya en línea (ver LinedBake y tools/bake_lined.gd); lo que arma el código se pinta al
## crearlo con LinedBake.style_tree. Este nodo sólo guarda los parámetros globales de las líneas (grosor, intensidad,
## contraste, sombreado) que leen los shaders, y dos efectos propios del estilo: el láser en tinta y la onda expansiva.
## La anatomía (rayos X), la sangre, las heridas y el fogonazo conservan su aspecto original.

signal changed

var mode := 4                ## siempre «plano dibujado»: se mantiene por compatibilidad con el código que lo consulta
var line_w := 1.6            ## grosor de las líneas (px)
var line_k := 1.0            ## intensidad de las líneas
var shade := 1.0             ## intensidad del sombreado de 4 tonos
var detail := 0.25           ## cuánto del color original (grabado en el modelo) se conserva
var contrast := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in [["tech_line_w", line_w], ["tech_line_k", line_k], ["tech_shade", shade], ["tech_detail", detail],
			["tech_contrast", contrast], ["tech_xray", 0.0], ["tech_on", 1.0]]:
		RenderingServer.global_shader_parameter_add(str(p[0]), RenderingServer.GLOBAL_VAR_TYPE_FLOAT, float(p[1]))

func set_param(key: String, v: float) -> void:
	set(key, v)
	var g := {"line_w": "tech_line_w", "line_k": "tech_line_k", "shade": "tech_shade", "detail": "tech_detail", "contrast": "tech_contrast"}
	if g.has(key):
		RenderingServer.global_shader_parameter_set(g[key], v)

## Color del láser: tinta (casi negro) sobre papel.
func laser_color(player: bool) -> Color:
	return Color(0.08, 0.08, 0.09, 0.95) if player else Color(0.35, 0.3, 0.25, 0.75)

## Explosión en el estilo técnico: una onda expansiva de LÍNEAS (anillos que crecen y rayas radiales), no fuego.
func shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.6, radius * 2.6)
	mi.mesh = qm
	mi.set_meta("no_tech", true)
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform float t = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float ink = 0.0;
	for (int i = 0; i < 3; i++) {
		float rr = t * (1.0 - float(i) * 0.18);
		float w = 0.012 + 0.01 * float(i);
		ink = max(ink, (1.0 - smoothstep(w * 0.5, w, abs(r - rr))) * (1.0 - float(i) * 0.3));
	}
	float rays = step(0.82, fract(a * 4.77)) * smoothstep(t * 0.35, t * 0.6, r) * (1.0 - smoothstep(t * 0.75, t * 0.95, r));
	ink = max(ink, rays * 0.8);
	float fade = 1.0 - smoothstep(0.65, 1.0, t);
	ALBEDO = vec3(0.1, 0.1, 0.11);
	ALPHA = ink * fade;
}"""
	m.shader = sh
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.6, 0.4)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("t", v), 0.0, 1.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(mi.queue_free)
