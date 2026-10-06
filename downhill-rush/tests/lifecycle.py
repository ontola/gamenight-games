"""Managed-launch check against a minimal fake GameNight host.

Starts the game the way the daemon does (GAMENIGHT=1, GAMENIGHT_ADDR, ...),
then walks it through hello, settings, prepare, participation, ready, start,
host controller frames, pause, resume, dispose and host loss.

    python3 tests/lifecycle.py --godot /path/to/godot

Standard library only. Runs headless.
"""
import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class Peer:
    def __init__(self, conn):
        self.conn = conn
        self.conn.settimeout(30)
        self.buffer = b""
        request = b""
        while b"\r\n\r\n" not in request:
            request += conn.recv(1024)
        key = [line.split(b":", 1)[1].strip() for line in request.split(b"\r\n") if line.lower().startswith(b"sec-websocket-key")][0]
        accept = base64.b64encode(hashlib.sha1(key + GUID.encode()).digest()).decode()
        conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())
        self.conn.settimeout(0.2)

    def send(self, **message):
        data = json.dumps(message).encode()
        header = bytes([0x81])
        if len(data) < 126: header += bytes([len(data)])
        elif len(data) < 65536: header += bytes([126]) + struct.pack("!H", len(data))
        else: header += bytes([127]) + struct.pack("!Q", len(data))
        self.conn.sendall(header + data)

    def _fill(self, n, deadline):
        while len(self.buffer) < n:
            if time.time() > deadline: return False
            try:
                chunk = self.conn.recv(65536)
            except socket.timeout:
                continue
            if not chunk: raise EOFError
            self.buffer += chunk
        return True

    def receive(self, deadline):
        if not self._fill(2, deadline): return None
        first, second = self.buffer[0], self.buffer[1]
        length = second & 127
        offset = 2
        if length == 126:
            if not self._fill(4, deadline): return None
            length = struct.unpack("!H", self.buffer[2:4])[0]; offset = 4
        elif length == 127:
            if not self._fill(10, deadline): return None
            length = struct.unpack("!Q", self.buffer[2:10])[0]; offset = 10
        masked = second & 128
        total = offset + (4 if masked else 0) + length
        if not self._fill(total, deadline): return None
        mask = self.buffer[offset:offset + 4] if masked else b"\0\0\0\0"
        start = offset + (4 if masked else 0)
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(self.buffer[start:total]))
        self.buffer = self.buffer[total:]
        if first & 15 == 1: return json.loads(payload)
        if first & 15 == 8: raise EOFError
        return self.receive(deadline)

    def expect(self, kind, timeout=30.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            message = self.receive(deadline)
            if message and message.get("type") == kind: return message
        raise AssertionError(f"timed out waiting for {kind}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args = parser.parse_args()
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    port = server.getsockname()[1]
    env = dict(os.environ, GAMENIGHT="1", GAMENIGHT_ADDR=f"127.0.0.1:{port}",
               GAMENIGHT_GAME_ID="downhill-rush", GAMENIGHT_TOKEN="test-token")
    game = subprocess.Popen([args.godot, "--headless", "--path", str(ROOT)], env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        server.settimeout(60)
        conn, _ = server.accept()
        peer = Peer(conn)
        hello = peer.expect("hello")
        assert hello["game"] == "downhill-rush" and hello["token"] == "test-token", hello
        peer.send(type="welcome", party={"players": [], "seats": []})
        settings = peer.expect("declare_settings")
        assert {s["key"] for s in settings["settings"]} == {"rounds_to_win", "mountain"}, settings
        peer.send(type="setting_changed", key="mountain", value="short")
        session = "11111111-2222-3333-4444-555555555555"
        seats = [{"index": 0, "controller": "ordinal:7", "occupant": {"kind": "local", "player_id": "p-ada"}},
                 {"index": 1, "occupant": {"kind": "ai"}},
                 {"index": 2, "occupant": {"kind": "empty"}}]
        players = [{"id": "p-ada", "name": "Ada", "color": "#ff7547"}]
        peer.send(type="prepare", session=session, game="downhill-rush", seats=seats, players=players)
        participation = peer.expect("participation", timeout=60)
        assert participation["session"] == session and participation["instant_join"] is False
        peer.expect("ready", timeout=60)
        peer.send(type="start", session=session)
        # Hold the right trigger on the seat's controller for a few seconds.
        end = time.time() + 7.0
        while time.time() < end:
            peer.send(type="controller_frame", controllers=[{"controller": "ordinal:7", "axes": [0, 0, 0, 0, 0, 32767], "buttons": 0}])
            peer.receive(time.time() + 0.03)
        peer.send(type="party_updated", session=session, seats=seats,
                  players=[{"id": "p-ada", "name": "Ada L.", "color": "#ff7547"}], presence=[])
        peer.send(type="pause", session=session)
        time.sleep(0.5)
        peer.send(type="resume", session=session)
        time.sleep(0.5)
        peer.send(type="dispose", session=session)
        time.sleep(0.5)
        assert game.poll() is None, "game exited while the host was still connected"
        conn.close()
        game.wait(timeout=20)
    finally:
        if game.poll() is None: game.kill()
        output = game.stdout.read().decode(errors="replace")
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
