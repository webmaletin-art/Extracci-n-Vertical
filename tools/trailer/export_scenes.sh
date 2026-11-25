#!/usr/bin/env bash
# Exporta las ESCENAS del trailer como GLB con animación (blanco, como el juego, con mapa incluido) + disparos y sonidos:
#   tools/trailer/export_scenes.sh [escena ...]      (sin argumentos: todas las escenas)
#   MAPA_APARTE=1: las escenas salen sin mapa y se exporta aparte mapa_torre_alfa.glb
#   Escenas: intro pistolas caja escalera escopeta fusil awm extraccion final completa
# Salida ($OUT, por defecto /tmp/escenas):
#   mapa_torre_alfa.glb                   el mapa (una sola vez; todas las escenas usan las mismas coordenadas del mundo)
#   <escena>/escena_<escena>.glb          personajes, armas, miembros arrancados y cámara, con su animación «escena»
#   <escena>/escena_<escena>_disparos.json, sonidos.csv, audio/, mezcla_audio.wav
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT="${OUT:-/tmp/escenas}"
JOBS="${JOBS:-3}"
SCENES=("$@")
[ ${#SCENES[@]} -eq 0 ] && SCENES=(intro pistolas caja escalera escopeta fusil awm extraccion final completa)
mkdir -p "$OUT"
# pantalla chica: sólo hace falta que existan las mallas (más rápido)
printf '[display]\nwindow/size/viewport_width=480\nwindow/size/viewport_height=270\n' > override.cfg
trap 'rm -f override.cfg' EXIT
run_one() {
	local S="$1" D G
	if [ "$S" = "mapa" ]; then
		G="$OUT/mapa_torre_alfa.glb"
		timeout 1500 xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 tools/trailer/trailer.tscn -- --only=mapa "--glb=$G" > "$OUT/log_mapa.txt" 2>&1
		grep -E "EXPORT" "$OUT/log_mapa.txt" | head -3
		return
	fi
	D="$OUT/$S"
	mkdir -p "$D"
	G="$D/escena_$S.glb"
	local ARGS=("--glb=$G")
	[ -n "${MAPA_APARTE:-}" ] && ARGS+=("--nomap")
	[ "$S" != "completa" ] && ARGS+=("--only=$S")
	timeout 3000 xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 30 tools/trailer/trailer.tscn -- "${ARGS[@]}" > "$D/log.txt" 2>&1
	grep -E "TRAILER_LISTO|EXPORT glb|SCRIPT ERROR" "$D/log.txt" | head -4
	if [ -f "$D/escena_${S}_sonidos.json" ]; then
		cp "$D/escena_${S}_sonidos.json" "$D/trailer_sonidos.json"
		python3 tools/trailer/audio_pack.py "$D" || true
	fi
}
export -f run_one
export OUT MAPA_APARTE
LIST=("${SCENES[@]}")
[ -n "${MAPA_APARTE:-}" ] && LIST=(mapa "${SCENES[@]}")
printf '%s\n' "${LIST[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one {}'
echo "Listo: $OUT"
