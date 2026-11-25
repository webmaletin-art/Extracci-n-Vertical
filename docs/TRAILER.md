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

## Escenas GLB para Blender (lo principal)
```
tools/trailer/export_scenes.sh            # todas las escenas + la completa
tools/trailer/export_scenes.sh awm fusil  # sólo algunas
```
Cada escena queda en `/tmp/escenas/<escena>/` (`OUT=carpeta` para cambiarla):
* `escena_<escena>.glb` — la escena con su **animación «escena»** (30 cuadros por segundo): el mapa (mallas, materiales
  estándar y texturas), cada personaje (`Actor_N_…`, con esqueleto y la pose de cada hueso en el tiempo), las armas
  (`Arma_N_…`, con cuándo están a la vista), los miembros arrancados (`Miembro_N`, aparecen cuando se desprenden y caen) y
  la cámara del juego (`Camara`). En Blender: importar el GLB, abrir el Action Editor / Timeline y reproducir.
* `escena_<escena>_disparos.json` — cada impacto con su segundo, posición, normal, zona del cuerpo, daño y quién disparó
  (para poner chispas, sangre, humo o destellos en Blender).
* `sonidos.csv` — cada sonido con su segundo exacto, archivo, posición en el mapa, volumen y tono. `audio/` — esos sonidos
  en WAV. `mezcla_audio.wav` — la mezcla completa alineada con la animación (la animación y el audio empiezan juntos en 0 s).
* `trailer_sonidos.json` — el mismo registro en bruto.

Notas para Blender: los materiales son estándar (el estilo «plano dibujado» del juego usa shaders que un GLB no puede llevar;
se aplica de nuevo en Blender con el contorno que se quiera); los efectos de partículas del juego (sangre, humo, chispas) no
viajan en el GLB, por eso están los disparos con posición y el registro de sonidos.

## Video directo (opcional)
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
