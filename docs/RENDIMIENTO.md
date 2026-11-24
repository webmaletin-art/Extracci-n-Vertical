# Rendimiento y configuración gráfica

Objetivo: 1280×720, **30 FPS mínimo** en Android de gama baja, 60 en los que puedan.

## Presets (CONFIGURACIÓN → Calidad gráfica)

| Ajuste | BAJA | MEDIA | ALTA |
|---|---|---|---|
| Calidad de render (escala 3D) | 60 % | 85 % | 100 % |
| Sombras | ninguna | sólo luna | luna + lámparas del piso |
| Luces dinámicas | sólo emisivas | piso actual ±1 | todas |
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
