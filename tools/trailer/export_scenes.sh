#!/usr/bin/env bash
# Exporta las escenas del trailer como GLB con animaciones (+ sonidos): tools/trailer/export_scenes.sh [escena ...]
#   sin argumentos: todas (intro pistolas caja escalera escopeta fusil awm extraccion final) y la completa (todo).
#   Salida: $OUT (por defecto /tmp/escenas)/<escena>/escena_<escena>.glb, escena_<escena>_disparos.json, sonidos.csv,
#           audio/ y mezcla_audio.wav. Ver docs/TRAILER.md.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT="${OUT:-/tmp/escenas}"
NAME=$(grep -oP 'config/name="\K[^"]+' project.godot)
UD="$HOME/.local/share/godot/app_userdata/$NAME"
SCENES=("$@")
[ ${#SCENES[@]} -eq 0 ] && SCENES=(intro pistolas caja escalera escopeta fusil awm extraccion final completa)
for S in "${SCENES[@]}"; do
	D="$OUT/$S"
	mkdir -p "$D"
	rm -f "$UD/trailer_sonidos.json"
	ARGS=("--glb=$D/escena_$S.glb")
	[ "$S" != "completa" ] && ARGS+=("--only=$S")
	timeout 3000 xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 tools/trailer/trailer.tscn -- "${ARGS[@]}" > "$D/log.txt" 2>&1
	grep -E "TRAILER_LISTO|EXPORT glb|SCRIPT ERROR" "$D/log.txt" | head -5
	if [ -f "$UD/trailer_sonidos.json" ]; then
		cp "$UD/trailer_sonidos.json" "$D/trailer_sonidos.json"
		python3 tools/trailer/audio_pack.py "$D" || true
	fi
done
echo "Listo: $OUT"
