# Downhill Rush

A top-down BMX downhill survival race for GameNight: everyone rides the same
procedurally generated mountain on one shared screen, seen from above. The
camera follows the leader and never waits. Fall behind, crash once too often or take the scenic route and
you drop off the bottom of the screen: you're out. Last rider standing, or
first through the finish gate, takes the round. First to three rounds wins.

Godot 4.5, GL Compatibility renderer, 1 to 8 riders. Everything is built from
code at runtime: low-poly flat-shaded terrain, trees, rocks and riders, with
no textures or imported models. Each rider has a ring in their colour on the
ground under them, which also shows where they will land mid-jump.

Every rider is a big-headed chibi with eyes, a hat of their own (mohawk,
horns, cat ears, propeller, unicorn horn, crown, antenna or rooster comb) and
sometimes a cape or a backpack flag. Bots have names like Gnarly Gus, Sir Skid
and Wobbles, and riders throw tailwhips on long jumps. The HUD is built from
tilted sticker cards in Bungee Shade, Bungee and Lilita One, with a cheeky line
for every elimination and win.

![The riders](docs/screenshots/riders.jpg)

![Racing down Ember Peak](docs/screenshots/race.jpg)

| | |
|---|---|
| ![Over the gap](docs/screenshots/jump.jpg) | ![Round over](docs/screenshots/round-over.jpg) |

## Play

```sh
godot --path downhill-rush            # join screen
godot --path downhill-rush -- --demo  # six bots, no input needed
```

Pads: left stick steers, **A** hops, **RT / X** pedals, **LT / B** brakes. In
the air, push the stick forward to drop the nose and pull back to lift it.
Keyboard riders use WASD + Space or the arrow keys + Enter. On the join
screen, press A (Space, Enter) to join; the first rider presses A again to
start. B toggles bots, which fill the field up to four riders. Escape pauses.

## How a mountain works

`src/course.gd` lays out a winding centre line with steep and mellow pitches,
then places features along it: gap jumps, tabletops, drops onto a landing,
step-ups, roller sections and rock gardens. Each jump is flown by test riders
using the real bike physics (`src/bike.gd`) to find the range of approach
speeds that land cleanly; jumps nobody can clear are softened until they can.
The sign before each jump shows how fussy it is: green lands almost anything,
orange needs some speed control and red needs exactly the right speed.

Riders live in track space (distance along the line and offset from it). Bike
physics runs on the same analytic height function the terrain mesh is built
from, so take-offs, cased landings and hard flat landings behave the way the
ground looks. A landing is judged by how steeply you hit the slope and how far
the bike's pitch is from it: soft, rough (slowed and wobbling) or a crash.
Trees and rocks are solid; hop small rocks with A.

## GameNight

The [GameNight Godot addon](https://github.com/ontola/gamenight/tree/main/sdk/godot)
is vendored in `addons/gamenight` (from gamenight `ba2cce0`). Under a GameNight
host the game:

- reads each seat's input with `GameNight.frame_for_seat` and plays `ai` seats
  as bots; empty seats get no rider;
- sends `participation` (`instant_join: false`) and `ready` after building
  the first mountain;
- starts the countdown on `start`, freezes on `pause`, reports every finished
  round with `notify_finished`, then keeps running its own next round and match;
- picks up name changes from `party_updated` without resetting the match;
- declares two settings: rounds to win (1 to 9) and mountain length
  (short, medium, long; applies from the next mountain).

`gamenight.json` is a draft catalog entry. It has no download yet.

## Checks

```sh
godot --headless --path downhill-rush --script tests/course_check.gd  # every jump clearable
godot --headless --path downhill-rush --script tests/ride_check.gd    # crashes and times per strategy
python3 downhill-rush/tests/lifecycle.py --godot godot               # managed launch against a fake host
tools/shot.sh out.png --demo --skip=30                               # screenshot via xvfb
```

`--skip=N` fast-forwards the race by N seconds, `--seed=N` fixes the mountain,
`--shot-phase=join|countdown|race|round_over` and `--shot-air` pick the moment.
`--showcase` points a close camera at the start grid to show off the riders.

## Not yet

No sound, no packaged release or catalog download, and the feel has only been
tuned against bots and simulations, not real controllers.

## License

See the repository license. The GameNight addon keeps its own license. The
fonts in `assets/fonts` (Bungee, Bungee Shade and Lilita One) are under the SIL
Open Font License; their license texts sit next to them.
