// Modo D «Plano dibujado»: sin texturas ni luces. Cada plano en un tono de papel según hacia dónde mira:
// pisos (arriba) casi blancos, paredes de fondo un gris muy claro, costados y techos un poco más grises.
// Las aristas las dibuja tech_lines (geometría de líneas fija). Costo por píxel: casi nulo.
shader_type spatial;
render_mode unshaded, cull_back;
global uniform float tech_shade;
global uniform float tech_contrast;
uniform float bias = 0.0;            // personajes / objetos: un poco más claros u oscuros que el fondo
varying vec3 wn;
void vertex() { wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment() {
	vec3 n = normalize(wn);
	float t;
	if (n.y > 0.6) t = 1.0;                 // piso / tapas
	else if (n.y < -0.6) t = 0.8;           // techos (por debajo)
	else if (abs(n.z) > abs(n.x)) t = 0.93; // paredes de frente / fondo
	else t = 0.86;                          // costados
	t = mix(0.92, t, tech_shade) + bias;
	vec3 paper = vec3(0.97, 0.965, 0.95);
	ALBEDO = mix(vec3(0.85), paper * clamp(t, 0.0, 1.05), tech_contrast);
}
