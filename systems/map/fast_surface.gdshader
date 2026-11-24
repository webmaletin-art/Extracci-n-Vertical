shader_type spatial;
// Superficie liviana del escenario (pisos, paredes, tarimas, escombros). SIN luces reales: la luz de las lámparas está
// «pintada» (suma de focos con caída suave, calculada en una sola pasada) y los tubos, cables, manchas y zócalos de la
// pared son dibujos procedurales sobre la propia pared (sin geometría). Una sola pasada por superficie: en el teléfono
// cuesta una fracción de lo que cuestan N luces reales sobre cada pieza.
render_mode unshaded, cull_back;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 1.0;
uniform float ambient = 0.30;
uniform int paint = 0;                 // 0 liso · 1 pared (tubos, cables, manchas, zócalo) · 2 piso (desgaste)
uniform float floor_h = 4.5;
uniform vec4 lamp_p[8];                // xyz = posición, w = alcance al cuadrado
uniform vec4 lamp_c[8];                // rgb = color × intensidad
global uniform vec4 flash_p;           // explosiones / fogonazos: xyz, w = alcance
global uniform vec4 flash_c;

varying vec3 wp;
varying vec3 wn;

float hash11(float p) { return fract(sin(p * 127.1) * 43758.5453); }

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 base = texture(tex, UV * uv_scale).rgb * tint.rgb;
	float fy = mod(wp.y, floor_h);
	float dirt = texture(tex, wp.xy * 0.045).g;          // manchas grandes de suciedad (misma textura, otra escala)
	if (paint == 1 && abs(wn.z) > 0.7) {
		// zócalo oscuro abajo y franja de peligro apenas arriba
		base *= mix(0.55, 1.0, smoothstep(0.0, 0.35, fy));
		// tubo grueso gris cerca del techo
		float pipe = smoothstep(0.09, 0.0, abs(fy - 3.62) - 0.07);
		float shade = 1.0 - abs(fy - 3.62) / 0.16;           // brillo de cilindro: más claro al centro
		base = mix(base, vec3(0.30, 0.32, 0.33) * (0.55 + 0.7 * shade), pipe);
		// tubo rojo fino
		float rp = smoothstep(0.06, 0.0, abs(fy - 3.33) - 0.045);
		base = mix(base, vec3(0.50, 0.07, 0.05) * (0.6 + 0.6 * (1.0 - abs(fy - 3.33) / 0.1)), rp);
		// cable que cae en curvas
		float cab = smoothstep(0.03, 0.0, abs(fy - (3.05 + 0.16 * sin(wp.x * 0.55) - 0.1 * sin(wp.x * 1.7))) - 0.012);
		base = mix(base, vec3(0.05), cab);
		// tubos verticales (posición por hash del tramo)
		float seg = floor(wp.x / 9.0);
		float vx = (seg + 0.15 + 0.7 * hash11(seg + floor(wp.y / floor_h) * 3.0)) * 9.0;
		float vp = smoothstep(0.1, 0.0, abs(wp.x - vx) - 0.06) * step(0.35, fy) * step(fy, 3.9);
		base = mix(base, vec3(0.28, 0.30, 0.31) * (0.6 + 0.8 * (1.0 - abs(wp.x - vx) / 0.12)), vp);
		base *= 0.72 + 0.4 * dirt;
	} else if (paint == 2) {
		base *= 0.75 + 0.45 * dirt;
	}
	// luz: ambiente + focos
	vec3 light = vec3(ambient);
	for (int i = 0; i < 8; i++) {
		vec3 d = lamp_p[i].xyz - wp;
		float d2 = dot(d, d);
		float att = 1.0 / (1.0 + d2 * 0.065);
		att *= clamp(1.0 - d2 / lamp_p[i].w, 0.0, 1.0);
		float ndl = clamp(dot(normalize(d), wn) * 0.5 + 0.55, 0.0, 1.0);
		light += lamp_c[i].rgb * att * ndl;
	}
	vec3 fd = flash_p.xyz - wp;
	light += flash_c.rgb / (1.0 + dot(fd, fd) / max(flash_p.w * flash_p.w, 0.01) * 4.0);
	ALBEDO = base * light;
}
