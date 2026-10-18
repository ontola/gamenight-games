#!/usr/bin/env bash
# Record the takes for the five-second GameNight store clip: the real game with
# bots playing (--demo), rendered frame by frame (--fixed-fps 30 --write-movie),
# so the same flags give the same frames. Each take fast-forwards its round
# unseen (--skip) to a moment tools/scan_preview.gd found. Writes PNG frames per
# take to OUT/<take>/; tools/encode_preview.py cuts them into one clip.
#   GODOT=... tools/capture_preview.sh OUT
set -euo pipefail
out=$(realpath -m "$1")
cd "$(dirname "$0")/.."
take() {
	local name=$1; shift
	mkdir -p "$out/$name"
	xvfb-run -a -s "-screen 0 960x540x24" timeout 900 "${GODOT:-godot}" --resolution 960x540 \
		--audio-driver Dummy --fixed-fps 30 --write-movie "$out/$name/f.png" --quit-after 75 \
		--path . -- --demo "$@" > "$out/$name/log.txt" 2>&1
}
take pickups --arena="Seed crossroads" --seed=431 --skip=3.8
take knockout --arena="Clover garden" --seed=431 --skip=5.2
take islands --arena="Pebble islands" --seed=600 --skip=4.5
take powered --arena="Seed crossroads" --seed=700 --skip=15.5
take teamwin --arena="Clover garden" --teams --seed=600 --skip=7.5
