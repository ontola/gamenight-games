# Hexstead

A building and trading game for 2 to 6 players. The TV shows a new hex
island every round; each player's cards and choices are on their own phone,
through GameNight's phone screens. It is the test game for asymmetric play:
the TV and the phones show different things. MIT licensed, LÖVE 11.5.

## How it plays

- Each field produces one resource: Timber, Clay, Wool, Grain or Ore. The
  lake produces nothing and is where the storm starts.
- Everyone places a hamlet and a road, then again in reverse order. The
  second hamlet pays out one card per field it touches.
- On your turn you roll two dice. Every field with that number pays each
  hamlet next to it one card, and each town two.
- Build with what you hold:

  | Build | Cost | Points |
  | --- | --- | --- |
  | Road | Timber, Clay | |
  | Hamlet | Timber, Clay, Wool, Grain | 1 |
  | Town (upgrades a hamlet) | 2 Grain, 3 Ore | 2 |
  | Festival (twice per game) | Wool, Grain, Ore | 1 |

- Hamlets need a free corner with no neighbouring hamlet, reached by your road.
- The bank trades 4 of a kind for 1. Each round the market favours one
  resource, which then trades 2 for 1.
- A 7 brings the storm: anyone holding more than 9 cards loses half, and the
  roller moves the storm to a field. That field stops producing, and the
  roller takes a random card from a player next to it.
- First to 8 points wins. A new island rises 12 seconds later.

What makes it Hexstead: the island grows into a different shape every round,
the market rate changes every round, festivals replace development cards, and
there is no trading between players yet.

## Phones

The game declares `phone/` as its phone screen (`declare_companion`). The
GameNight app opens it on the Game tab when Hexstead starts; any browser
signed in to the GameNight works too. The phone shows your hand, a tappable
board that highlights where you may build, dice, the bank and the scoreboard.
The game checks every move; the page only draws the view it is sent.

AI seats are played by bots. A player without a phone gets 15 seconds on
their turn, then a bot plays that turn so the table never stalls. With fewer
than three players, bots fill up to three.

## Run

```sh
love hexstead                       # four bots, to watch
HEXSTEAD_TEST=1 love hexstead       # rule tests: 60 boards, 25 bot games
```

Under GameNight (`GAMENIGHT=1`) it reads `GAMENIGHT_ADDR`, `GAMENIGHT_GAME_ID`
and `GAMENIGHT_TOKEN`, prepares hidden, shows on Start and reports `finished`
when someone wins. `HEXSTEAD_SEED` fixes the island; `HEXSTEAD_BOT_STEP` sets
seconds per bot move (default 0.9).

`net/transport.lua` and `net/window.lua` come from the party pack, which
derives them from Polle Pas's MIT-licensed Pinpals integration
(`vendor/PINPALS-LICENSE`). `vendor/json.lua` is rxi's MIT JSON library.
