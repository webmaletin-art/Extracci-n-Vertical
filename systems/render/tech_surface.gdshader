// Visualización técnica 3D (experimento): superficie de «ilustración técnica». Papel blanco con 4 tonos según hacia dónde
// mira la cara (luz fija tipo dibujo, las caras de arriba más claras), un poco del dibujo original para separar piezas.
// Sin luces reales ni sombras: unshaded. La sangre / láser / efectos no usan este material (quedan rojos).
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
global uniform float tech_shade;     // 0 = plano · 1 = cuatro tonos marcados
global uniform float tech_detail;    // cuánto del color original se conserva (para distinguir piezas)
global uniform float tech_contrast;  // contraste general
varying vec3 wn;
void vertex() { wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	vec3 n = normalize(wn);
	vec3 L = normalize(vec3(-0.45, 0.75, 0.6));
	float d = dot(n, L);
	float tone = d > 0.55 ? 1.0 : (d > 0.15 ? 0.87 : (d > -0.25 ? 0.76 : 0.66));
	if (n.y > 0.7) tone = 1.0;
	tone = mix(0.84, tone, tech_shade);
	vec3 c = albedo.rgb;
	if (has_tex) c *= texture(albedo_tex, UV).rgb;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float det = mix(1.0, 0.72 + 0.45 * clamp(lum * 1.6, 0.0, 1.0), tech_detail);
	vec3 paper = vec3(0.965, 0.958, 0.94);
	vec3 col = paper * clamp(tone * det, 0.0, 1.0);
	col = mix(vec3(0.82), col, tech_contrast);
	ALBEDO = col;
}
