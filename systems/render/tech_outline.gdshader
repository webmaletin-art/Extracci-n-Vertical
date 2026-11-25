// Contorno de silueta (casco invertido): la misma malla un poco inflada, dibujada por detrás en tinta. Grosor casi
// constante en pantalla (crece con la distancia a la cámara). Funciona con personajes animados (piel).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
global uniform float tech_line_w;
global uniform float tech_line_k;
void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = max(-vp.z, 0.5);
	VERTEX += normalize(NORMAL) * tech_line_w * 0.0011 * dist;
}
void fragment() {
	if (tech_line_k < 0.02) { discard; }
	ALBEDO = mix(vec3(0.94), vec3(0.13, 0.13, 0.14), tech_line_k);
}
