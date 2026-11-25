# Escenas del juego como animación GLB (para renderizar en Blender)

Herramienta aparte del juego (carpeta `tools/trailer/`). Un piloto automático juega la Torre Alfa (movimiento, disparos,
muertes, rayos X, miembros arrancados) y `trailer_export.gd` guarda lo que pasa como **un GLB con una animación**: no es un
video, es la escena animada para abrir en Blender y renderizar con mejor calidad que una grabación de pantalla.

## Escenas
`intro` · `pistolas` · `caja` · `escalera` · `escopeta` · `fusil` · `awm` (calibre .50) · `extraccion` · `final` · `completa` (todas seguidas).
Se agregan o se cambian en `trailer_game.gd` (una función `_nombre()` y una línea en `_run()`).

## Cómo exportar
```
tools/trailer/export_scenes.sh pistolas        # una escena (por defecto: todas)
OUT=carpeta JOBS=3 tools/trailer/export_scenes.sh
```
Cada escena sale en `$OUT/<escena>/` (por defecto `/tmp/escenas`):
* `escena_<escena>.glb` — **un solo GLB** con el mapa, los personajes (esqueleto + pose de cada hueso en el tiempo), las armas, los
  miembros arrancados, la **sangre** (gotas con caída y manchas), la **anatomía** (huesos, órganos y vasos, que aparece mientras el
  juego muestra los rayos X de la muerte y esconde el traje) y la **cámara del gameplay**. Animación «escena», 30 cuadros por
  segundo. Todo en blanco / gris, sin texturas: las líneas se agregan en Blender (Freestyle o contorno de Workbench).
* `escena_<escena>_disparos.json` — cada impacto con su segundo, posición, zona, daño y quién disparó.
* `sonidos.csv`, `audio/` y `mezcla_audio.wav` — cada sonido con su segundo exacto, los WAV usados y la mezcla completa alineada
  con la animación (empieza en el segundo 0 junto con ella).

`--nomap` (argumento de la escena) deja el mapa afuera; `--only=mapa` exporta sólo el mapa.

## Notas
* Se necesita un renderizador real (el script usa `xvfb-run` con OpenGL por software): con el modo sin pantalla de Godot no hay
  datos de mallas para exportar.
* Los enemigos de la escena usan dos tipos de personaje para compartir la anatomía dentro del GLB (peso ≈ 100 MB por escena).
* `tests/glb_check.tscn` abre un GLB exportado, lista sus animaciones y guarda capturas en los momentos en que aparece la anatomía.
* El helicóptero (`assets/props/military_helicopter.glb`) es parte del mapa (`TowerBuilder._helicopter`), reutilizable en mapas con IA.
