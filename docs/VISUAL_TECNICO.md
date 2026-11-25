# Visualización técnica 3D — informe del experimento

## Qué es la referencia (github.com/wheresryan22/anatomy)
No es un motor de juego: es una herramienta (MIT) que construye ilustraciones isométricas proyectando piezas 3D y
dibujándolas como **polígonos SVG**: cada cara rellena con **4 tonos** según hacia dónde mira (luz fija a la cámara, las
caras de arriba más claras), **trazo fino oscuro (0,6 px)** en siluetas y pliegues, costuras en tono tenue, papel
blanco y **un solo color de acento**; fuego, humo y agua van en un shader WebGL encima. El «3D» suyo re-proyecta y
re-sombrea ~90 piezas por cuadro en la CPU con orden de pintor: sirve para una figura, no para un juego con física y
cientos de objetos. **No se puede usar tal cual**, pero el ASPECTO se imita en Godot con nuestros mismos modelos.

## ¿Hay que rehacer los modelos o quitar polígonos?
**No.** Las líneas salen de la geometría que ya existe (silueta y pliegues): no hace falta rehacer personajes, armas,
mapa ni anatomía, ni bajar polígonos. Menos detalle de textura sí ayuda: el estilo descarta las texturas de pared y
piso (por eso puede ser más liviano en la GPU de un teléfono).

## Las cuatro opciones (Modo práctica › VISUALIZACIÓN TÉCNICA 3D, reversible, no se guarda)
| Opción | Cómo funciona | Ventaja | Contra |
|---|---|---|---|
| **A · Filtro** | una pasada de pantalla: líneas por salto de profundidad (siluetas) y por cambio de pendiente (pliegues), y la imagen pasada a papel en 4 tonos de gris; el rojo (sangre, láser, tuberías) se conserva | no cambia ningún material, cero llamadas de dibujo extra | depende de la imagen original (las texturas oscuras dejan manchas grises) |
| **B · Materiales técnicos** | reemplaza temporalmente los materiales por un sombreado de 4 tonos sin luces + contorno de silueta (casco invertido) | personajes y armas muy limpios | sin líneas en paredes y pisos grandes; casi duplica las llamadas de dibujo (el contorno es una segunda pasada) |
| **C · Híbrido** | B (contorno sólo en objetos chicos) + líneas interiores de pantalla de A, sin filtro de color | el más parecido a la referencia | el más caro de los tres en este equipo |
| **D · Plano dibujado** | sin texturas ni luces: tonos planos blanco/gris según la orientación (piso, techo, paredes) y líneas de tinta en bordes y pliegues (>25°) extraídas una vez por malla; las del mapa fijo se agrupan en tramos de 15 m (≈90 nodos). Láser negro, explosión = onda de líneas | el más liviano: menos llamadas y primitivas que el juego actual, no hay luces ni sombras | estilo definitivo distinto (todo blanco); las líneas son geometría (grosor ajustable en pantalla) |

Rayos X (muerte, cámara normal del juego): **realista**, **técnico gris** (anatomía blanca, vasos y heridas en rojo,
contorno en tinta) y **técnico con colores** (la anatomía dibujada con líneas conservando sus colores).

## Mediciones (misma escena: Torre Alfa piso 0, jugador frente a un enemigo, misma cámara)
* Desactivada: 106.4 ms/cuadro (software) · 122 llamadas de dibujo · 165382 primitivas
* A · Filtro sobre el juego: 122.7 ms/cuadro (software) · 123 llamadas de dibujo · 165384 primitivas
* B · Materiales técnicos: 122.9 ms/cuadro (software) · 203 llamadas de dibujo · 325822 primitivas
* C · Híbrido (B + líneas): 131.5 ms/cuadro (software) · 181 llamadas de dibujo · 324794 primitivas
* D · Plano dibujado: 91.3 ms/cuadro (software) · 99 llamadas de dibujo · 142752 primitivas (≈ −19 % llamadas, −14 % primitivas y −14 % tiempo frente al juego actual)

**Atención:** estos ms son de un render POR SOFTWARE (sin GPU) en el servidor: sirven para comparar entre sí, NO dicen
cuánto rinde un Mali-G57. Las llamadas de dibujo y primitivas sí son las reales del juego. Lo que se ve:
* A no agrega llamadas de dibujo; su costo es una pasada de pantalla (5 lecturas de profundidad + 1 de color por píxel).
* B/C quitan la luz y las texturas de los materiales (más barato por píxel) pero el contorno por casco invertido suma
  ~60–80 llamadas y duplica las primitivas.
* Medición en el teléfono: Modo práctica › «▶ TEST DE RENDIMIENTO DE ESTILOS (≈1 min)» dispara, tira una granada y
  mide FPS medio, 1 % más bajo y llamadas de dibujo de cada estilo (≈10 s por estilo); el informe se puede copiar y
  queda en user://rendimiento_estilos.txt.

## Recomendación inicial (antes de D)
* **Android:** A (filtro) o C con contorno sólo en personajes y armas; bajar «Grosor de líneas» a 1,2–1,6 a 720p.
* **PC:** C con rayos X técnico con colores.
* Si se adopta el estilo de forma definitiva, conviene materiales técnicos nativos (sin la pasada de conversión),
  líneas de pliegue «horneadas» en las paredes del mapa (no por pantalla) y contorno por casco invertido sólo en lo que
  se mueve: así se ahorran las luces pintadas, las texturas grandes y la pasada de pantalla.

Nada de esto cambia la balística, la física, las animaciones ni los recursos originales.

## Modo D: daño y efectos asociados
* La colisión no depende del dibujo: las líneas son sólo imagen; la física usa las mismas formas que antes.
* Explosión en estilos técnicos: onda expansiva de anillos y rayos de tinta (sin fuego ni humo).
* Daño por potencia del arma: más sangre y un orificio desgarrado pegado al hueso (hasta 10 por cuerpo); la escopeta
  rompe más huesos cuanto más cerca (fuerza 2,4 → 0,6 según la distancia).
* Los impactos sobre el cuerpo durante la cámara de muerte se ven (sangre, herida y ventana de rayos X).
* Rebotes: metal con ángulo rasante < ~57°, hormigón/madera < ~17°; probado 5 de 40 contra una placa a 65°.
