# Downhill Rush

A top-down BMX downhill survival race for GameNight: everyone rides the same
procedurally generated mountain on one shared screen, seen from above. The
mountain's main direction runs to the bottom right, but the valley swings hard
to the side now and then before the camera follows it round. The camera keeps the leader a
little past the middle, so they still see the slope ahead, and never waits. Fall behind, crash once too often or take the scenic route and
you drop off the bottom of the screen: you're out. Last rider standing, or
first through the finish gate, takes the round. First to three rounds wins.

Godot 4.5, GL Compatibility renderer, 1 to 8 riders. Everything is built from
code at runtime: low-poly terrain, trees, rocks and riders, with no imported
models. Bikes have spoked wheels: tyre, silver rim, hub and laced spokes.

Riders are ordinary 90s BMX kids in flannel, striped or plain shirts, jeans
and sneakers, with a lid or a backwards cap. Clothes, dirt and rock carry small
greyscale textures painted in code (`src/textures.gd`) and sampled without
filtering, so they read as chunky texels on the low-poly shapes.

![The riders](docs/screenshots/riders.jpg)

![Racing down Ember Peak](docs/screenshots/race.jpg)

| | |
|---|---|
| ![Through the chute](docs/screenshots/jump.jpg) | ![Round over](docs/screenshots/round-over.jpg) |

## Play

```sh
godot --path downhill-rush            # join screen
godot --path downhill-rush -- --demo  # six bots, no input needed
```

Pads: point the left stick where you want to go on screen (mostly to the
bottom right) and the bike turns towards it. **A** hops, **RT / X** pedals,
**LT / B** brakes. In the air the stick twists the bike, so point it the way
you are flying to land straight; let go and it slowly squares up. Brake in the
air to lift the nose. Keyboard riders steer left and right relative to the bike
with WASD + Space or the arrow keys + Enter.

The scoreboard lists riders in race order, with riders who are out struck
through at the bottom. Under GameNight the names and colours come from the
party. On the join
screen, press A (Space, Enter) to join; the first rider presses A again to
start. B toggles bots, which fill the field up to four riders. Escape pauses.

## How a mountain works

There is no trail. `src/course.gd` builds a steep, rough mountainside and you
pick your own line down it. The run is a shuffled string of set pieces with
open mountain between them:

- **band**: a cliff band across the slope (below);
- **turn**: the valley swings about 60 degrees to one side;
- **flat**: a bench where you have to pedal;
- **kicker**: one to three jumps built into the slope;
- **gully**: a single narrow, steep path between boulder-strewn banks;
- **slalom**: rows of trees or rocks with a few gaps;
- **open**: just the mountain.

Cliff bands work like this: above each
one the ground eases into a shelf, then drops off a ledge. Small ledges can be
ridden; big ones will put you on your face, unless you find one of the few
chutes where the ledge becomes a steep ramp. Between the bands there are forest
clumps, boulder fields, loose scree with little grip, and streams that bog you
down. Valley walls on either side keep the field together.

Bike physics (`src/bike.gd`) runs on the same analytic height function the
terrain mesh is built from, so every roll, ledge and hollow behaves the way it
looks. Gravity is strong on these pitches, so most of the riding is braking:
tyres have limited grip that depends on the ground (`Bike.GRIP`,
`Course.grip`); ask for more and you slide, and hold a big slide and you wash
out. Side slopes keep pulling you down the fall line.

Whether you fall is one function per kind of hit. A landing
(`Bike.landing_severity`) adds up how hard you hit the ground, how far the
bike's pitch is from the slope (nose first is much worse than back wheel
first) and how crooked the bike is to where you are flying, the last one
counting for more the faster you go. Over 1 is a crash, over 0.6 a hard
landing that costs speed. Obstacles go by closing speed: trees stop you at
4 m/s, boulders at a speed that drops as they get bigger, small rocks buck you
into the air. Below that you glance off. Riding straight into a steep face
also puts you down. Riders are
solid and shove each other around; a hard hit can take someone down.

Bots (`src/bot.gd`) read the slope ahead: they score a fan of lines for
ledges, trees and boulders, head for a chute when a big cliff comes up, and
brake for whatever their line throws at them.

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
godot --headless --path downhill-rush --script tests/course_check.gd  # cliff bands all have a way down
godot --headless --path downhill-rush --script tests/ride_check.gd    # crashes and times per strategy
python3 downhill-rush/tests/lifecycle.py --godot godot               # managed launch against a fake host
tools/shot.sh out.png --demo --skip=30                               # screenshot via xvfb
```

`--skip=N` fast-forwards the race by N seconds, `--seed=N` fixes the mountain,
`--shot-phase=join|countdown|race|round_over` and `--shot-air` pick the moment.
`--showcase` points a close camera at the start grid to show off the riders,
and `--no-hud` hides the HUD.

## Not yet

No sound, no packaged release or catalog download, and the feel has only been
tuned against bots and simulations, not real controllers.

## License

See the repository license. The GameNight addon keeps its own license. The
fonts in `assets/fonts` (Bungee, Bungee Shade and Lilita One) are under the SIL
Open Font License; their license texts sit next to them.
