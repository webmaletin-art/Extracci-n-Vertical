# Modo práctica

Menú principal → **MODO PRÁCTICA** (o `-- --practica` por línea de comandos). Campo de tiro con un maniquí (`PracticeGame`, `systems/core/practice_game.gd`).

* Botón **PRÁCTICA ▸** (arriba): arma (5), munición (estándar, punta hueca, perforante, rebotadora, trazadora lenta), personaje del maniquí, distancia, velocidad del juego, de pie / agachado, inmortal (acumula heridas), reaparición.
* **Disparar a**: ojo, cabeza, cuello, corazón, estómago, testículos, rodilla, mano, muslo, hígado. Apunta solo, sin dispersión, dispara una vez; la cámara sigue la bala y se acerca a la herida con los rayos X (ventana más chica y cámara más cerca en ojo / testículos / estómago: `BulletTime.CLOSEUPS`).
* Chapas de metal en ángulo, bloque de hormigón y pared del fondo para probar **rebotes**.
* **GRABAR ●**: guarda 30 cuadros por segundo en `user://grabaciones/<fecha>/cuadro_00001.jpg`. Para armar el video: `ffmpeg -framerate 30 -i cuadro_%05d.jpg -c:v libx264 -pix_fmt yuv420p video.mp4`.
* Pruebas: `tests/practice_shots.tscn` (capturas por zona) y `tests/zone_probe.tscn` (lista las estructuras dañadas por zona).

Nota: en práctica la esfera de impacto de la cabeza es algo más grande (para que el ojo quede adentro).
