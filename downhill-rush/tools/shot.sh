#!/bin/sh
# Usage: tools/shot.sh out.png [extra game args...]
# Renders one frame with a software GL context. Needs xvfb-run and Godot 4.5.
GODOT=${GODOT:-godot}
out=$1; shift
cd "$(dirname "$0")/.." && xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 1600x900 -- --shot="$out" "$@" 2>&1 | grep -E "SCRIPT|ERROR: [^C]|Saved"
