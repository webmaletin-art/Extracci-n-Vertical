#!/usr/bin/env bash
# Reconstruye assets/anims/player_anims.res desde mixamo-respaldo según anims.json.
# Requiere Godot 4.7.2 como "godot" y el repositorio mixamo-respaldo (MIXAMO_DIR, por defecto ../mixamo-respaldo).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/../.."
MIX="${MIXAMO_DIR:-$ROOT/../mixamo-respaldo}"
WORK="$HERE/_work"
rm -rf "$WORK"; mkdir -p "$WORK/src"
cp "$HERE/build.gd" "$HERE/anims.json" "$WORK/"
printf 'config_version=5\n[application]\nconfig/name="anim_builder"\n' > "$WORK/project.godot"
cp "$MIX/personajes/ybot_tpose.fbx" "$WORK/src/ybot.fbx"
cp "$ROOT/tools/ref/operator.fbx" "$WORK/src/operator.fbx"
python3 - "$HERE/anims.json" "$MIX" "$WORK/src" <<'PY'
import json, shutil, sys
cfg, base, dst = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
for aid, d in cfg["player"].items():
    shutil.copy(f"{base}/{d['src']}", f"{dst}/player__{aid}.fbx")
PY
godot --headless --import --path "$WORK" >/dev/null 2>&1 || true
mkdir -p "$ROOT/assets/anims"
godot --headless --path "$WORK" -s build.gd -- "$ROOT/assets/anims" 2>&1 | grep -E "saved|ERROR|SCRIPT" | grep -vE "RID|resources still|Leaked" || true
rm -rf "$WORK"
