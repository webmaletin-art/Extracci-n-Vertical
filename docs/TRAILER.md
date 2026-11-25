# Trailer vertical (video de promoción)

Herramienta aparte del juego (carpeta `tools/trailer/`): corre la Torre Alfa real con un piloto automático, graba video
**vertical** (540×960 por defecto, 720×1280 opcional) a 30 cuadros por segundo con audio, y deja los datos para rehacerlo
en Blender.

## Escenas (en orden)
| Escena | Qué muestra |
|---|---|
| `intro` | azotea con el helicóptero, título |
| `pistolas` | arranca con la Browning, mata a 2 (uno de cabeza) |
| `caja` | rompe una caja y encuentra la escopeta Remington |
| `escalera` | sube la escalera al piso siguiente |
| `escopeta` | 3 enemigos de cerca: miembros arrancados |
| `fusil` | AM4 en ráfaga contra 4 enemigos |
| `awm` | calibre .50: tiros a la cabeza y miembros arrancados |
| `extraccion` | corre al helicóptero de la azotea |
| `final` | tarjeta final |

El HUD táctil (palancas y botones) se ve y se mueve como si alguien jugara. Si en el video hace falta otra cosa, se pide
la escena y se agrega en `trailer_game.gd` (una función `_nombre()` más una línea en `_run()`).

## Cómo grabar
```
tools/trailer/render_trailer.sh            # trailer completo (≈ 3 min de video)
tools/trailer/render_trailer.sh pistolas   # una escena
tools/trailer/render_trailer.sh "" 720 1280
```
Salida en `/tmp/trailer` (`OUT=carpeta` para cambiarla):
* `trailer_vertical.mp4` — video H.264 con el audio del juego.
* `trailer_sonidos.json` / `sonidos.csv` — cada sonido con su segundo exacto, archivo, posición, volumen y tono.
* `audio/` — los sonidos usados, en WAV. `mezcla_audio.wav` — la mezcla completa, alineada con el video.

El render usa el renderizador por software del servidor: tarda varias veces la duración del video.

## Notas
* El piloto automático no puede morir (la salud no baja de 60) y las colisiones, la balística, la sangre, los rayos X y el
  desmembramiento son los del juego.
* El helicóptero (`assets/props/military_helicopter.glb`) es parte del mapa: los mapas con IA pueden reutilizarlo como
  punto de extracción (`TowerBuilder._helicopter`).
* Sólo para grabar: nada de esto entra en las partidas.
