# Bombing Bugs

A Godot 4.6 couch arena game inspired by Blast Party, with original procedural
3D clay-style insects and a garden-floor setting. Its source and executable are
separate from the LÖVE game; adding this project does not replace a published
Blast Party build or its catalog listing.

Play a ladybug, ant, bee or beetle. Scuttle between mossy rocks, blow open
sandy mounds, collect extra bomb capacity and range, and be the last bug
(or team) standing. Bombs explode in cardinal crosses only. No diagonal or
beam/line shape upgrades; no timer decides the winner. Results last six seconds
or until a player presses A, then the next round starts. Surviving bugs can keep
moving during results; the winner is locked and leftover blasts cannot kill them.
Mint double-bomb tokens add bomb capacity; amber four-arrow flame tokens add
blast range. Matching icons and current totals appear on each player name card.

## Play

Open `project.godot` in Godot 4.6.2, or run:

```sh
godot --path bombing-bugs
```

- Left stick / D-pad: smooth movement, with gentle corner assistance.
- A: plant a bomb. You can walk off a newly planted bomb but cannot re-enter it.
- B: set off your remote bombs (with the Remote power-up).
- Start: pause and change options. B: close the options.
- Back/Select: GameNight lobby when managed by the host.
- Keyboard fallback: WASD or arrows, Space/Enter to plant, Esc/P to pause.

Standalone play uses up to four connected controllers, or one keyboard player
if no pads are connected. Controllers are assigned at round start. AI fills the
remaining slots up to the requested count, without replacing human players.
One human with AI set to zero is a practice arena. Options use D-pad/stick,
A/B, or mouse; settings take effect on **New round · apply options** or the next
round. The menu shows only the basics (AI players, teams, garden, size); fuse,
speed, friendly fire, sand, pickups and sound live under **More options**.

Gardens vary every round. Auto size picks from sizes that suit the player
count (two players: 11×9 or 13×9; three: 13×11 or 15×9; four: 13×11, 15×11 or
15×13) and the camera frames each size the same way. Scattered stones and
Boulder field are generated per round, mirrored so every corner spawn sees the
same garden, and always fully connected once the sand is gone. The countdown
names the garden; the game's name only shows on the start menu.

Each round's seed also picks the garden's look: a colour mood (fresh spring,
lush, dry late summer, autumn), soil patches showing through the moss, the
side props, and where the snail crawls. Grass grows in clumps of curved,
tapered blades that sway in the wind, and flowers, clovers, mushrooms and the
snail move with the same breeze.

Explosions use Growing Guns' layered blast: lumpy fire clouds along every
burning cell, flame tongues, embers, dusty smoke, a flash and a fireball light,
a short camera jolt and a scorch mark. The sound is Growing Guns' synthesised
bang and rumble (`src/boom_sound.gd`); bombs that go off in the same tick play
as one blast, louder and deeper the more cells burn. A bug caught in a blast
flips onto its back, chars black with a small fire on its belly, then falls
apart.

Power-ups drop from sand:

| Power-up | Effect |
| --- | --- |
| Extra bomb | One more bomb at a time (max 4) |
| Range | Longer blasts (max 5) |
| Speed | Walk faster (stacks to 3) |
| Kick | Walk into a bomb to send it sliding until it hits something |
| Ghost | Walk through sand and bombs; rock still stops you |
| Mega | Blasts reach as far as the garden allows |
| Remote | Your bombs wait until you press B (keyboard E or Shift), then all go off |
| Pierce | Blasts bore through every sand mound in range; only rock and bombs stop them |
| Square | Blasts also fill the 3×3 around the bomb |
| Line | Plant again while standing on your bomb to lay the rest of your bombs in a row ahead |
| Skull | A curse for ten seconds (slow, reversed controls or leaky bombs) that passes on by touch |

Every pickup has its own little jingle. The game's name shows big over the
garden during the first countdown, also when GameNight starts the game without
the menu.

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
| `arena` | Surprise me (default, a different garden each round), Clover garden, Seed crossroads, Pebble islands, Scattered stones, Boulder field | Next round |
| `size` | Auto (default), Small 11×9, Medium 13×11, Large 15×13 | Next round |
| `friendly_fire` | Boolean | Next round |
| `fuse` | 15–40 tenths of a second | Next round |
| `speed` | 20–50 tenths of a tile/second | Next round |
| `crates` | 20–75 percent sand cover | Next round |
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
godot --headless --path bombing-bugs --script tests/results-ui.gd
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
Windows 4.6.2 and Linux 4.5.2 (7,857 assertions and ten completed AI battles).
These automated checks do not certify physical controllers, Windows foreground
handoff or a production catalog install. A physical controller playtest is still required.
All meshes and sound effects are generated in code; no external art pack or
runtime asset-generation service is required. License: repository MIT license.

UI lettering uses DynaPuff by Toshi Omagari and Jennifer Daniel, bundled under
the SIL Open Font License in `assets/fonts/DynaPuff-OFL.txt`. The title has a
subtle wave and win messages gently wobble; names and counters remain still.
