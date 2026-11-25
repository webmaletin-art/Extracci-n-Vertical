// Aristas del mapa como cintas finas con grosor constante en PANTALLA (las líneas de OpenGL ES siempre miden 1 px).
// Cada arista es un rectángulo de 4 vértices: VERTEX = un extremo, CUSTOM0.xyz = el otro, CUSTOM0.w = lado (-1 / 1).
// El vértice se corre en pantalla perpendicular a la arista. Las aristas lejanas se aclaran (profundidad).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
global uniform float tech_line_w;
global uniform float tech_line_k;
varying float fade;
void vertex() {
	// en espacio de cámara se acercan un poco hacia la cámara (no quedan escondidas dentro de la cara que bordean)
	vec4 va = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 vb = MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
	va.xyz *= 0.992;
	vb.xyz *= 0.992;
	vec4 a = PROJECTION_MATRIX * va;
	vec4 b = PROJECTION_MATRIX * vb;
	vec2 sa = a.xy / a.w * VIEWPORT_SIZE * 0.5;
	vec2 sb = b.xy / b.w * VIEWPORT_SIZE * 0.5;
	vec2 d = normalize(sb - sa + vec2(1e-5));
	vec2 nrm = vec2(-d.y, d.x) * CUSTOM0.w * tech_line_w * 0.5;
	a.xy += nrm / (VIEWPORT_SIZE * 0.5) * a.w;
	POSITION = a;
	fade = clamp(1.0 - (a.w - 8.0) / 30.0, 0.35, 1.0);
}
void fragment() {
	if (tech_line_k < 0.02) { discard; }
	ALBEDO = mix(vec3(0.97), vec3(0.14, 0.14, 0.15), tech_line_k * fade);
}
