# Downhill Rush

A top-down BMX downhill survival race for GameNight: everyone rides the same
procedurally generated mountain on one shared screen, seen from above. The
mountain's main direction runs to the bottom right, but the valley swings hard
to the side now and then before the camera follows it round. The camera looks ahead of the
leader, so riders sit towards the top left with the slope below them (a lone
rider furthest, a spread-out pack less), and it never waits. Fall behind, crash once too often or take the scenic route and
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
godot --path downhill-rush            # straight onto the mountain
godot --path downhill-rush -- --demo  # six bots, no input needed
```

Pads: point the left stick where you want to go on screen (mostly to the
bottom right) and the bike turns towards it. **A** hops, **RT / X** pedals,
**LT / B** brakes. In the air the bike stays lined up with where it's flying;
the stick can only nudge it a little. Brake in the air to lift the nose. Keyboard riders steer left and right relative to the bike
with WASD + Space or the arrow keys + Enter.

The scoreboard lists riders in race order, with riders who are out struck
through at the bottom. Under GameNight the names and colours come from the
party.

There is no title screen: the game opens on the mountain. Press A on any pad
(or Space / Enter) and you're on a bike. Before the first race that starts
the countdown; during the countdown you join the grid; mid-race you drop in
just behind the leader. Riding alone works too.

Start (or Escape) opens the menu, the only one there is: the game's name, who
is riding, Add rider (puts whoever picks it on a bike), New race, difficulty,
landscape, mountain length, rounds to win, bots (off by default; on, they fill
the field up to four riders) and Quit. Settings apply from the next mountain;
New race builds one straight away.

## How a mountain works

`src/course.gd` builds a steep, rough mountainside and you pick your own line
down it. One way down is always rideable: a winding trail of packed dirt (or
trodden snow) with no trees or big boulders on it, only the odd small rock
that bucks you. It finds a chute through every cliff band, a bridge or the
ramp over every gorge, a lane through every slalom and the path down every
gully, and goes round lakes. It doesn't avoid kickers, and it's narrower on
harder mountains (6.4 m on easy down to 3.2 m on extreme). The run is a
shuffled string of set pieces with open mountain between them:

- **band**: a cliff band across the slope (below);
- **turn**: the valley swings about 60 degrees to one side;
- **flat**: a bench where you have to pedal;
- **kicker**: one to three jumps built into the slope;
- **gully**: a single narrow, steep path between boulder-strewn banks;
- **slalom**: rows of trees or rocks with a few gaps;
- **open**: just the mountain;
- **lake**: a tarn on a bench; ride round it, because the deep end is a crash;
- **chasm**: a gorge right across the slope, crossed on a narrow rock bridge
  or by flying the ramp next to it. Fall in and you crash and come back on
  the far side.

Every mountain has a biome: alpine, forest, autumn, desert or snow. It sets
the ground colours, which set pieces turn up (deserts get more gorges and no
lakes or streams) and the trees: pines and firs, oaks, birches, autumn trees,
dead trees, saguaro cacti, joshua trees and snow-laden firs. The mix of trees
drifts along the run, so you pass through a pine stand, then a birch grove.
On a snow mountain it snows, powder grips a little less than grass, and the
lakes are frozen: you can ride across, but the ice barely grips, so steer or
brake hard on it and you slide out. `--biome=NAME` picks the biome and
`--look=S` parks the camera S metres down the run for screenshots.

Difficulty (easy, normal, hard, extreme; `--difficulty=NAME`) scales the
mountain and the race: cliff bands get taller, gorges wider and their bridges
narrower, the slope steeper, the trees and boulders denser and the lanes
through them tighter. Landings forgive less, the camera starts faster and
tops out higher, and the bots ride better. Easy always has two bridges over
every gorge.

Cliff bands work like this: above each
one the ground eases into a shelf, then drops off a ledge. Small ledges can be
ridden; big ones will put you on your face, unless you find one of the few
chutes where the ledge becomes a steep ramp. Between the bands there are forest
clumps, boulder fields, loose scree with little grip, and streams that bog you
down. Wooded, lumpy hillsides keep the field together. The valley floor drifts from
side to side, each bank wanders in and out on its own, and the fall line itself
snakes, so the way down is rarely straight to the bottom right. Slaloms are
thickets with winding lanes through them, not rows.
Ground colours blend per vertex, and dirt and scree patches are domain-warped
so they come in natural, winding shapes.

Bike physics (`src/bike.gd`) runs on the same analytic height function the
terrain mesh is built from, so every roll, ledge and hollow behaves the way it
looks. Gravity is strong on these pitches, so most of the riding is braking:
tyres have limited grip that depends on the ground (`Bike.GRIP`,
`Course.grip`); ask for more and you slide, and hold a big slide and you wash
out. Side slopes keep pulling you down the fall line.

You only fall for a reason you can see. There are two:

- **Landing at the wrong angle** (`Bike.landing_severity`). Legs soak up the
  impact, so how hard you land doesn't matter until it's huge (~16 m/s into
  the slope). What matters is the bike meeting the ground the way it points:
  nose first more than ~35° off the slope digs the front wheel in, back wheel
  first is fine up to ~57°. In the air the bike stays lined up with where it
  flies (the stick only nudges it), so a crooked landing comes from a crooked
  take-off. Short hops off bumps you didn't see are mostly forgiven.
- **The front wheel catching** (`Bike._collide_obstacles`): riding nearly
  head-on (within 40°) into something taller than the front axle, so the
  wheel stops while you keep going. A trunk stops it at 2.5 m/s, a rounded
  boulder at up to 7 m/s depending on its height. Clip it at an angle and you
  glance off; anything lower than the axle you ride over, and small rocks
  buck you into the air. Riding into a bank steeper than 45° counts too.

Both limits scale with difficulty. Shoves from other riders make you wobble
but never put you down, and sliding a turn just scrubs speed. Riding into deep
water is a crash. A rider who makes no headway for 3 s is walked a few metres
on to clear ground.

The rider's body moves on its own over the bike (`RiderView._ride_body`):
the bike follows every bump and slope, the body keeps its pitch and roll with
its own inertia, the legs are a spring-damper against the bike's jolts (a
landing drops you into a squat), and weight shifts back on steep descents and
forward when the bike slows. Two-bone IK puts the feet on the pedals and the
hands on the grips, so knees and elbows take up the difference.

A crash is simulated, not animated. The rider goes limp as a ragdoll
(`src/ragdoll.gd`): fifteen joints, from pelvis and head to hands and feet,
held together by sticks and integrated with Verlet, so arms and legs flop as
the body flies over the bars, hits the ground, slides with friction and
bounces off trees and rocks. The bike is one tumbling body (`src/tumble.gd`)
that skids and settles on its side. On a slope too steep for friction to hold
you, you keep sliding. Hard impacts leave a little blood on the ground for
the rest of the round. Once they've come to
rest (at least 1.1 s, at most 2.8 s) you get back on where the bike lies.

Building a mountain's meshes takes a few seconds, so the next one is built on
a thread while you ride the current one; the next round starts straight away.

Bots (`src/bot.gd`) read the slope ahead: they score a fan of lines for
ledges, trees and boulders, head for a chute when a big cliff comes up, and
brake for whatever their line throws at them.

## GameNight

The [GameNight Godot addon](https://github.com/ontola/gamenight/tree/main/sdk/godot)
is vendored in `addons/gamenight` and kept identical to gamenight `main`; CI fails
when it falls behind (update with gamenight's `sdk/godot/sync.py`). Under a GameNight
host the game:

- reads each seat's input with `GameNight.frame_for_seat` and plays `ai` seats
  as bots; empty seats get no rider;
- sends `participation` (`instant_join: false`) and `ready` after building
  the first mountain;
- starts the countdown on `start`, freezes on `pause`, reports every finished
  round with `notify_finished`, then keeps running its own next round and match;
- picks up name changes from `party_updated` without resetting the match;
- declares four settings: rounds to win (1 to 9), mountain length (short,
  medium, long), difficulty (easy, normal, hard, extreme) and landscape
  (random or one biome). The last three apply from the next mountain.

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
