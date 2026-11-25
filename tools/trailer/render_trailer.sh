#!/usr/bin/env bash
# Graba el trailer vertical (video + audio) y arma el paquete para Blender: tools/trailer/render_trailer.sh [escena] [ancho alto]
#   escena: intro | pistolas | caja | escalera | escopeta | fusil | awm | extraccion | final   (vacío = todas)
#   tamaño: 1600 720 (por defecto, como el teléfono) · otro: ancho alto
set -euo pipefail
cd "$(dirname "$0")/../.."
ONLY="${1:-}"
W="${2:-1600}"
H="${3:-720}"
OUT="${OUT:-/tmp/trailer}"
mkdir -p "$OUT"
rm -f "$OUT/trailer.avi"
# el Movie Maker usa el tamaño de pantalla del proyecto: se cambia con un override.cfg temporal (se borra al terminar)
printf '[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\nwindow/stretch/mode="canvas_items"\nwindow/stretch/aspect="expand"\n' "$W" "$H" > override.cfg
trap 'rm -f override.cfg' EXIT
ARGS=()
[ -n "$ONLY" ] && ARGS+=("--only=$ONLY")
xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 --write-movie "$OUT/trailer.avi" \
	tools/trailer/trailer.tscn -- "${ARGS[@]}" 2>&1 | tee "$OUT/log.txt" | grep -E "TRAILER_LISTO|SCRIPT ERROR" || true
# el registro de sonidos queda en user://trailer_sonidos.json
SND="$HOME/.local/share/godot/app_userdata/$(grep -oP 'config/name="\K[^"]+' project.godot)/trailer_sonidos.json"
[ -f "$SND" ] && cp "$SND" "$OUT/trailer_sonidos.json"
ffmpeg -y -loglevel error -i "$OUT/trailer.avi" -c:v libx264 -pix_fmt yuv420p -crf 18 -preset medium -c:a aac -b:a 192k -movflags +faststart "$OUT/trailer_vertical.mp4"
python3 tools/trailer/audio_pack.py "$OUT"
echo "Listo: $OUT"
