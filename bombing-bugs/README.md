# Bombing Bugs

A Godot 4.6 couch arena game inspired by Blast Party, with original procedural
3D clay-style insects and a garden-floor setting. Its source and executable are
separate from the LÖVE game; adding this project does not replace a published
Blast Party build or its catalog listing.

Play a ladybug, ant, bee or beetle. Scuttle between mossy pebbles, blow open
seeds and acorns, collect extra bomb capacity and range, and be the last bug
(or team) standing. Bombs explode in cardinal crosses only. No diagonal or
beam/line shape upgrades; no timer decides the winner. Results last six seconds
or until a player presses A, then the next round starts.

## Play

Open `project.godot` in Godot 4.6.2, or run:

```sh
godot --path bombing-bugs
```

- Left stick / D-pad: smooth movement, with gentle corner assistance.
- A: plant a bomb. You can walk off a newly planted bomb but cannot re-enter it.
- Start: pause and change options. B: close the options.
- Back/Select: GameNight lobby when managed by the host.
- Keyboard fallback: WASD or arrows, Space/Enter to plant, Esc/P to pause.

Standalone play uses up to four connected controllers, or one keyboard player
if no pads are connected. Controllers are assigned at round start. AI fills the
remaining slots up to the requested count, without replacing human players.
One human with AI set to zero is a practice arena. Options use D-pad/stick,
A/B, or mouse; settings take effect on **Start a new round** or the next round.

Teams pair seats 1+3 against 2+4. Friendly fire is optional; your own bombs
always hurt. Eliminated bugs remain as little toppled bodies until next round.

## GameNight and assistant integration

The vendored public Godot SDK handles hidden preload, fullscreen activation,
pause/resume, stale controller input, performance reports and host-loss exit.
The game sends real preparation progress and reports each completed round.
Managed input uses the assigned **seat index**, never OS joystick order.
Host names and player colours identify bugs in the HUD and floor rings.
Custom pixel faces are not yet displayed on these insect models.

`declare_settings` exposes these options to the app and assistant using the
standard host setting API; no game-specific LLM endpoint is necessary:

| Key | Values | Applies |
| --- | --- | --- |
| `ai_players` | 0–3, capped at four total players | Next round |
| `teams` | Free-for-all, Teams | Next round |
| `arena` | Clover garden, Seed crossroads, Pebble islands | Next round |
| `friendly_fire` | Boolean | Next round |
| `fuse` | 15–40 tenths of a second | Next round |
| `speed` | 20–50 tenths of a tile/second | Next round |
| `crates` | 20–75 percent seed cover | Next round |
| `pickups` | Boolean | Next round |
| `sound` | Boolean | Live |

Menu changes publish `set_setting` so the host can persist/share them. Remote
values are validated. The game contains soft procedural effects and no music,
so it does not compete with the party's music player.

## Validate and build

From this repository's root:

```sh
godot --headless --path bombing-bugs --editor --import --quit
godot --headless --path bombing-bugs --script tests/simulation.gd
python3 bombing-bugs/tests/lifecycle.py /path/to/godot
mkdir -p dist
godot --headless --path bombing-bugs --export-release Windows "$PWD/dist/BombingBugs.exe"
# On Windows, check the exported executable as well:
python bombing-bugs/tests/lifecycle.py C:/path/to/BombingBugs.exe --packaged
```

Simulation tests cover continuous movement, collision, bomb exit/re-entry,
chain reactions, blast occlusion, team damage/results, no time limit, safe
spawns and connected layouts over 90 seeds, and ten complete AI battles.
The lifecycle test launches the actual game with an isolated WebSocket host,
checks a nonzero seat's input, Start/Back, pause freeze, deferred settings,
dispose and host-loss shutdown. The WebSocket test peer uses only Python's
standard library and does not connect to your actual running party.

For a visual preview: `godot --path bombing-bugs -- --demo` runs AI play.
`--screenshot=/absolute/path.png` captures the rendered viewport and exits.
Screenshots under `docs/` are actual engine renders, not the AI concept image.

The Windows export was smoke-tested and passed the same managed lifecycle test
on Godot 4.6.2, including two separate seats. The simulation suite passed on
Windows 4.6.2 and Linux 4.5.2 (7,848 assertions and ten completed AI battles).
These automated checks do not certify physical controllers, Windows foreground
handoff or a production catalog install. A physical controller playtest is still required.
All meshes and sound effects are generated in code; no external art pack or
runtime asset-generation service is required. License: repository MIT license.
