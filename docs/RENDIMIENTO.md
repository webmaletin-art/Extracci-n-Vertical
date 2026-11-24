# Rendimiento y configuración gráfica

Objetivo: 1280×720, **30 FPS mínimo** en Android de gama baja, 60 en los que puedan.

## Presets (CONFIGURACIÓN → Calidad gráfica)

| Ajuste | BAJA | MEDIA | ALTA |
|---|---|---|---|
| Resolución 3D (1,00 = 720p de alto, sin importar el teléfono) | 540p | 720p | 900p |
| Sombras | círculo simple bajo cada personaje | ídem | + sombra real de la luna sobre personajes |
| Luces reales sobre personajes (siguen al jugador) | ninguna | 2 | 4 |
| Antialiasing | — | FXAA | MSAA 2x |
| Partículas / humo / explosiones | bajo (35 %) | medio (70 %) | alto |
| Decorado | sólo lo necesario | medio | todo |
| Fondo | plano | fachadas | fachadas + niebla |
| Pisos vecinos visibles | actual | ±1 | ±2 |
| FPS | 30 | 30 | 60 |
| Rayos X | sólo huesos | completo | completo |

El primer arranque elige el preset según el teléfono (`Settings.autodetect`). Cualquier cambio suelto pasa a
«Personalizada».

## Optimizaciones ya hechas

* Geometría fija juntada en una malla por material y por piso (`BoxBatcher`): ~10 llamadas de dibujo por piso.
* Pisos lejanos ocultos según «Pisos vecinos visibles»; lámparas sólo cerca del jugador en MEDIA.
* Proyectiles sin nodos (registros en arreglos), partículas y fragmentos de grupos fijos, sin crear/destruir en combate.
* Anatomía de rayos X cargada sólo cuando se usa, ~63 k triángulos, nunca en dos personajes a la vez.
* Texturas tileables de 512 px, compresión ETC2/ASTC.

## Captador de rendimiento

CONFIGURACIÓN → **Rendimiento** → «ANALIZAR RENDIMIENTO» (también en la pausa y en el menú principal).
Recorre la torre (3 estaciones por piso) y en cada una mide la línea base y vuelve a medir **haciendo desaparecer** una
categoría por vez: luces, sombras, decorado, tuberías, fondo, velos, cajas/barriles, personajes, escombros del cráter,
carteles, estructura, partículas, niebla/brillo y escala de render. Después apaga uno por uno los 12 objetos con más
triángulos frente a la cámara. Resultado: ranking «qué pesa más» (ms ganados, % del cuadro, dibujos y primitivas
ahorrados), objetos más pesados, recomendaciones y los tirones (>50 ms) registrados durante el juego con su contexto.
Se guarda en `user://informe_rendimiento.txt` y `.json` y se copia al portapapeles.

Nota: la corrida de prueba de este repositorio se hizo con renderizado por software (llvmpipe, ~3 FPS), así que sus
números sólo validan el procedimiento; los valores reales hay que tomarlos en el teléfono.


## Primer informe en teléfono real (Mali-G57, ALTA, antes de esta pasada)

238 ms por cuadro (4 FPS), 507 llamadas de dibujo, 281 000 primitivas. Reparto: lámparas 62 %, píxeles 53 %,
estructura 48 %, sombras 27 %, niebla y brillo 17 %. Causas y arreglos:

| Causa | Arreglo |
|---|---|
| ~30 luces reales: cada una se recalcula sobre todo lo que toca (pisos y paredes incluidos) | Pisos y paredes usan `systems/map/fast_surface.gdshader`: **sin luces reales**, la luz de las lámparas está pintada (suma de focos con caída suave, una sola pasada). Quedan 0 / 2 / 4 luces reales que siguen al jugador y sólo afectan personajes y objetos |
| Dibujaba a la resolución nativa del teléfono (≈ 2,5 veces los píxeles de 720p) | La resolución 3D se calcula contra el alto de la pantalla: 1,00 = 720p siempre |
| Sombras reales de todo | Estructura y objetos no proyectan; círculo de sombra simple bajo cada personaje; sombra real de la luna sólo en ALTA y sólo personajes |
| Niebla y brillo (pasadas de pantalla completa) | Eliminados |
| Tuberías, cables y manchas como geometría | Pintados en el shader de la pared (sin geometría) |
| Pisos de 3 m de profundidad | 1,95 m (alcanza para pisar) |
| Velos de sectores en todos los pisos | Sólo los del piso actual y vecinos |

Resultado medido con el mismo captador en ALTA (renderizado por software, sólo valen las cuentas, no los ms):
**507 → 196 llamadas de dibujo y 281 000 → 136 000 primitivas.**
