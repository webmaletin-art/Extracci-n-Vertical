shader_type spatial;
render_mode unshaded, cull_back;
// Dibujo de línea para piezas pequeñas (cartuchos): tono plano por material y contorno de tinta por borde de silueta.
uniform float tone : hint_range(0.0, 1.0) = 0.85;
uniform vec3 ink = vec3(0.07, 0.07, 0.09);
void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float shade = 0.82 + 0.18 * clamp(dot(normalize(NORMAL), normalize(vec3(-0.4, 0.8, 0.5))), -1.0, 1.0);
	vec3 base = vec3(tone * shade);
	float edge = smoothstep(0.07, 0.13, f);
	ALBEDO = mix(ink, base, edge);
}
