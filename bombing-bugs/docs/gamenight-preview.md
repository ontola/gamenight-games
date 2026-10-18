# GameNight store clip and stills

`assets/gamenight/` holds the store media: `preview.mp4` (5 s, 150 frames,
960×540, 30 FPS, silent H.264) with its poster `preview.jpg`, plus
`cover.png` (360×480), `icon.png` (128×128) and `gameplay.png` (640×360).
All of it is the real game: bots play (`--demo`), the real simulation and
renderer draw every frame. Nothing is staged beyond picking the garden, the
round seed and how far the round is fast-forwarded before recording.

## Reproduce

```sh
godot --headless --path bombing-bugs --script tools/scan_preview.gd   # find moments
GODOT=godot bombing-bugs/tools/capture_preview.sh /tmp/takes          # needs xvfb-run
python3 bombing-bugs/tools/encode_preview.py /tmp/takes bombing-bugs/assets/gamenight
```

`--seed=N` makes round 1 use seed N+71 (the scan uses the same), `--size=` picks the garden size (the takes use Medium), `--skip=S`
lets the bots play S seconds unseen first. Godot 4.6.2 with llvmpipe renders
the window at 1440×810; the encoder scales to 960×540. Encoding is bit-exact:
the same takes give the same file.

## Shot list

| cut | take | garden, seed | frames | shows |
|---|---|---|---|---|
| 1 | knockout | Clover garden, 431, skip 5.2 s | 20–53 | four blasts at once, sand mounds blown open, power-ups revealed |
| 2 | pickups | Seed crossroads, 431, skip 3.8 s | 44–74 | the open crossroads, chained blasts along both edges |
| 3 | islands | Pebble islands, 600, skip 4.5 s | 36–65 | a different layout, crossing blasts, a bug knocked out |
| 4 | teamwin | Clover garden teams, 600, skip 7.5 s | 20–74 | a big cross blast, the last enemy out, "Team 1 wins!" while leftover bombs go off |

Poster: islands frame 50. Stills: `gameplay.png` is pickups frame 68,
`cover.png` a crop of that frame with the title in the game's own font
(DynaPuff), `icon.png` the ladybug from teamwin frame 20.

SHA-256 at capture (game commit with tools/capture_preview.sh):

```
ffbb06e8e2121a6ed263884dc18798eb0aab5bf181ac4411aadf1daf91121f44  preview.mp4
07a70d2f1f5332e01b0df7ab8794133fd0f6ed04153d61a93834dd129b97b033  preview.jpg
```
