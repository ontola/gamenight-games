"""Managed-launch check against the GameNight SDK's fake host.

Starts the game the way the daemon does (GAMENIGHT=1, GAMENIGHT_ADDR, ...),
then walks it through hello, settings, prepare, participation, ready, start,
host controller frames, pause, resume, dispose and host loss.

    python3 tests/lifecycle.py --godot /path/to/godot

Standard library only (addons/gamenight/fake_host.py). Runs headless.
"""
import argparse
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "addons" / "gamenight"))
from fake_host import FakeHost  # noqa: E402


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args = parser.parse_args()
    with FakeHost(args.godot, "downhill-rush", path=ROOT, timeout=60) as host:
        # FakeHost already checked the hello's game id and launch token.
        host.send({"type": "welcome", "party": {"players": [], "seats": []}})
        settings = host.expect("declare_settings")
        assert {s["key"] for s in settings["settings"]} == {"rounds_to_win", "lives", "mountain", "difficulty", "landscape"}, settings
        host.setting("mountain", "short")
        session = "11111111-2222-3333-4444-555555555555"
        seats = [host.local_seat(0, "p-ada", controller="ordinal:7"),
                 host.ai_seat(1),
                 {"index": 2, "occupant": {"kind": "empty"}}]
        players = [{"id": "p-ada", "name": "Ada", "color": "#ff7547"}]
        host.prepare(seats, players, session=session, wait_ready=False)
        participation = host.expect("participation", timeout=60)
        assert participation["session"] == session and participation["instant_join"] is False
        host.expect("ready", timeout=60)
        host.start()
        # Hold the right trigger on the seat's controller for a few seconds.
        end = time.time() + 7.0
        while time.time() < end:
            host.frames({"controller": "ordinal:7", "axes": [0, 0, 0, 0, 0, 32767], "buttons": 0})
            time.sleep(0.03)
        host.send({"type": "party_updated", "session": session, "seats": seats,
                   "players": [{"id": "p-ada", "name": "Ada L.", "color": "#ff7547"}], "presence": []})
        host.pause()
        time.sleep(0.5)
        host.resume()
        time.sleep(0.5)
        host.dispose()
        time.sleep(0.5)
        assert host.process.poll() is None, "game exited while the host was still connected"
        host.disconnect()
        host.exit_code(20)
        output = host.output()
    errors = [line for line in output.splitlines() if "SCRIPT ERROR" in line or line.startswith("ERROR")]
    errors = [e for e in errors if "audio" not in e.lower()]
    riders = [line for line in output.splitlines() if "session disposed" in line]
    assert riders and "Ada L. " in riders[0], output
    ada = float(riders[0].split("Ada L. ")[1].split("m")[0])
    assert ada > 30.0, f"seat input did not move Ada: {riders[0]}"
    if errors:
        print(output)
        raise SystemExit("game logged errors")
    print("lifecycle OK: hello, settings, prepare, participation, ready, start, frames, pause, resume, dispose, host loss")


if __name__ == "__main__":
    main()
