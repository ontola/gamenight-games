# GameNight games

The shared LÖVE games live here. Their Git history was extracted from [GameNight](https://github.com/ontola/gamenight).

- `love-party/`: Blast Party, Neon Trails, Neon Siege, Ricochet Club, Volley Trouble, Stack Together and Bubble Buddies, plus their shared runner.
- `downhill-rush/`: Downhill Rush, a standalone Godot 4 mountain-bike party game.
- `bombing-bugs/`: Bombing Bugs, a Godot 4 clay-style insect bomb arena with smooth movement, AI and teams. A separate successor experiment to Blast Party; it does not replace the published LÖVE build.
- Hexstead moved to its own repository, [joepio/hexstead](https://github.com/joepio/hexstead), as a Godot 3D game. The earlier LÖVE prototype is in this repository's history.

GameNight keeps the host, both lobbies, SDKs, catalog, packager and contract tests. Individual game licenses and attribution remain in their source folders.

## Develop and test

Clone this repository next to `gamenight`. In the GameNight checkout, set `GAMENIGHT_GAMES_DIR` to this checkout when testing new game changes:

```sh
export GAMENIGHT_GAMES_DIR=../gamenight-games
python3 scripts/test-love-simulation.py --love love
python3 scripts/package-love-party.py --output dist/party
```

GameNight's `game-sources.json` pins the game revision used by builds and documentation. Update that pin after committing game changes here. The game CI runs simulation and packaging checks against the public host tools; the host CI runs the complete integration suite against its pinned game revision.
