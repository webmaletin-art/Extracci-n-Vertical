// Pasada de pantalla (experimento): líneas por profundidad (siluetas, bordes) y por curvatura de la profundidad
// (pliegues, uniones, escalones), y — si filter > 0 — pasa la imagen a papel blanco en pocos tonos de gris,
// conservando el ROJO (sangre, láser) como acento.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float filter_k = 1.0;       // 1 = pasar a papel / grises (opción A) · 0 = sólo líneas (opción C)
global uniform float tech_line_w;
global uniform float tech_line_k;
global uniform float tech_contrast;
global uniform float tech_red;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
float lin(vec2 uv, mat4 ip) {
	float d = texture(depth_tex, uv).r;
	vec4 v = ip * vec4(uv * 2.0 - 1.0, d * 2.0 - 1.0, 1.0);
	return -v.z / v.w;
}
void fragment() {
	vec2 px = tech_line_w / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	float c = lin(uv, INV_PROJECTION_MATRIX);
	float l = lin(uv - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float r = lin(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float u = lin(uv - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float d = lin(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	// silueta: salto de profundidad relativo
	float jump = max(max(abs(l - c), abs(r - c)), max(abs(u - c), abs(d - c))) / max(c, 0.1);
	float sil = smoothstep(0.012, 0.03, jump);
	// pliegue: cambio de pendiente (segunda derivada) en x o y
	float crease = max(abs(l + r - 2.0 * c), abs(u + d - 2.0 * c)) / max(c, 0.1);
	float cr = smoothstep(0.0035, 0.009, crease) * 0.75;
	float ink = clamp(max(sil, cr), 0.0, 1.0) * tech_line_k;
	if (c > 120.0) { ink = 0.0; }
	vec3 src = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 col = src;
	if (filter_k > 0.0) {
		float lum = dot(src, vec3(0.3, 0.59, 0.11));
		float red = clamp((src.r - max(src.g, src.b) * 1.6) * 5.0, 0.0, 1.0);    // rojo (sangre, láser)
		float t = clamp(0.35 + lum * 1.9 * tech_contrast, 0.0, 1.0);
		t = floor(t * 4.0 + 0.5) / 4.0;                                           // cuatro tonos
		vec3 paper = mix(vec3(0.62, 0.62, 0.61), vec3(0.97, 0.965, 0.95), t);
		vec3 accent = vec3(0.78, 0.06, 0.05) * (0.7 + 0.3 * src.r);
		col = mix(paper, accent, red * tech_red);
		col = mix(src, col, filter_k);
	}
	ALBEDO = mix(col, vec3(0.12, 0.12, 0.13), ink);
}
