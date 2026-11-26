// Igual que tech_surface pero el color original viene HORNEADO en los vértices (COLOR): el personaje ya no lleva texturas.
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 albedo : source_color = vec4(1.0);
global uniform float tech_shade;
global uniform float tech_detail;
global uniform float tech_contrast;
varying vec3 wn;
varying vec3 vcol;
void vertex() {
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR.rgb;
}
void fragment() {
	vec3 n = normalize(wn);
	vec3 L = normalize(vec3(-0.45, 0.75, 0.6));
	float d = dot(n, L);
	float tone = d > 0.55 ? 1.0 : (d > 0.15 ? 0.87 : (d > -0.25 ? 0.76 : 0.66));
	if (n.y > 0.7) tone = 1.0;
	tone = mix(0.84, tone, tech_shade);
	vec3 c = albedo.rgb * vcol;
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float det = mix(1.0, 0.72 + 0.45 * clamp(lum * 1.6, 0.0, 1.0), tech_detail);
	vec3 paper = vec3(0.965, 0.958, 0.94);
	vec3 col = paper * clamp(tone * det, 0.0, 1.0);
	col = mix(vec3(0.82), col, tech_contrast);
	ALBEDO = col;
}
