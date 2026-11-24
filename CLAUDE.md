# Extracción Vertical — instrucciones para Claude Code

Shooter táctico de extracción 2.5D para Android: Godot 4.7.2, GDScript, GL Compatibility, Jolt a 60 Hz.

1. Leer `README.md` (estado) y `docs/ARQUITECTURA.md` (sistemas, dependencias, números fijos) antes de tocar código.
2. Cambio mínimo en el sistema que corresponde; datos de balance en `data/*.json` o en las constantes de cada clase.
3. Correr `tools/run_tests.sh` (debe terminar con 0 fallas y sin `SCRIPT ERROR`). Para revisar la imagen:
   `xvfb-run -a godot --path . --rendering-driver opengl3 tests/shots.tscn -- <carpeta> [escenario]`.
4. Actualizar la documentación del sistema tocado y `docs/CHANGELOG.md`.

Reglas: no inventar resultados de pruebas; plano de juego z = 0 (X horizontal, Y arriba); el apuntado (`Actor.aim_dir`)
nunca lo cambia el movimiento; no destruir estructura (losas, paredes); efectos siempre desde los grupos fijos de `Fx`.
Recursos: no modificar `mixamo-respaldo` ni Operación Nexus; anotar procedencia en `docs/RECURSOS.md`. ElevenLabs:
`tools/sfx/elevenlabs_sfx.py` anota cada gasto en `docs/audio/elevenlabs_ledger.jsonl`; nunca escribir claves en el repo.
