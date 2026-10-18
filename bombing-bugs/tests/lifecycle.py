"""Exercise the real Godot process over the SDK WebSocket protocol, not mocks of game methods."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import tempfile

ROOT = Path(__file__).resolve().parents[1]
from wire import Peer


def main():
    godot = sys.argv[1] if len(sys.argv) > 1 else "godot"
    project_args = [] if "--packaged" in sys.argv else ["--path", ROOT.as_posix()]
    with socket.socket() as server:
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        server.settimeout(30)
        env = dict(os.environ, GAMENIGHT="1", GAMENIGHT_ADDR=f"127.0.0.1:{server.getsockname()[1]}", GAMENIGHT_GAME_ID="bombing-bugs", GAMENIGHT_TOKEN="isolated-test")
        # Godot on Windows flushes stdout synchronously: an unread PIPE can
        # stall startup before the WebSocket connects. A file cannot deadlock.
        capture = tempfile.TemporaryFile()
        game = subprocess.Popen([godot, "--headless"] + project_args + ["--quit-after", "36000", "--", "--test-state"], cwd=ROOT, env=env, stdout=capture, stderr=subprocess.STDOUT)
        try:
            time.sleep(.5)
            if game.poll() is not None:
                raise AssertionError(f"Game exited at startup: {game.returncode}; root={ROOT}")
            conn, _ = server.accept()
            peer = Peer(conn)
            hello = peer.expect("hello")
            assert hello["game"] == "bombing-bugs" and hello["token"] == "isolated-test"
            peer.send(type="welcome", party={})
            settings = peer.expect("declare_settings")["settings"]
            assert {s["key"] for s in settings} == {"ai_players", "teams", "arena", "size", "friendly_fire", "fuse", "speed", "crates", "pickups", "sound"}
            peer.send(type="setting_changed", key="ai_players", value=0)
            session = "bugs-test-session"
            seats = [{"index":2,"controller":"pad-seven","occupant":{"kind":"local","player_id":"ada"}},
                     {"index":5,"controller":"pad-three","occupant":{"kind":"local","player_id":"bea"}}]
            peer.send(type="prepare", session=session, game="bombing-bugs", seats=seats, players=[{"id":"ada","name":"Ada","color":"#68bbdd"},{"id":"bea","name":"Bea"}])
            peer.expect("ready")
            time.sleep(.2)
            peer.send(type="start", session=session)
            def frames(seconds, buttons=0, x=0):
                end = time.monotonic()+seconds
                while time.monotonic() < end:
                    peer.send(type="controller_frame", controllers=[{"controller":"pad-seven","axes":[x,0,0,0,0,0],"buttons":buttons}])
                    time.sleep(.025)
            frames(3.0, x=32767)
            # Host settings must wait for a round boundary.
            peer.send(type="setting_changed", key="speed", value=45)
            peer.send(type="pause", session=session)
            frames(.5,x=32767)
            peer.send(type="resume", session=session)
            frames(.1)
            frames(.1,buttons=1<<7)  # Start is menu, never lobby.
            frames(.1)
            frames(.1,buttons=1<<7)  # Resume.
            frames(.1)
            frames(.1,buttons=1<<6)  # Back requests lobby.
            peer.expect("request_overlay")
            peer.send(type="dispose", session=session)
            time.sleep(.2)
            assert game.poll() is None
            conn.close()
            game.wait(timeout=10)
        finally:
            if game.poll() is None:
                game.kill()
            game.wait(timeout=10)
            capture.seek(0)
            output = capture.read().decode(errors="replace")
            capture.close()
            if "TEST_STATE" not in output:
                print(output)
    assert "SCRIPT ERROR" not in output and "ERROR:" not in output, output
    states = [json.loads(line.removeprefix("TEST_STATE ")) for line in output.splitlines() if line.startswith("TEST_STATE ")]
    by_event = {s["event"]:s for s in states}
    assert len(by_event["ready"]["positions"]) == 2, states
    assert by_event["pause"]["positions"][0][0] > 1.5, states
    assert by_event["pause"]["positions"][1] == by_event["ready"]["positions"][1], states
    assert by_event["pause"]["age"] == by_event["resume"]["age"], states
    assert by_event["pause"]["options"]["speed"] == 32, states
    assert by_event["pause"]["pending"]["speed"] == 45, states
    assert by_event["menu"]["menu"] is True and "dispose" in by_event, states
    print("PASS managed lifecycle, nonzero seat input, pause freeze, Start menu, Back overlay, next-round settings, host-loss exit")


if __name__ == "__main__":
    main()
