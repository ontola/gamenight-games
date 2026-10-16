"""Minimal stdlib-only WebSocket peer for an isolated GameNight host."""
import base64
import hashlib
import json
import socket
import struct
import time


class Peer:
    def __init__(self, conn):
        self.conn = conn
        self.buffer = b""
        conn.settimeout(10)
        request = b""
        while b"\r\n\r\n" not in request:
            request += conn.recv(1024)
        key = next(line.split(b":", 1)[1].strip() for line in request.split(b"\r\n") if line.lower().startswith(b"sec-websocket-key"))
        accept = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest()).decode()
        conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" + f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())
        conn.settimeout(.2)

    def send(self, **message):
        payload = json.dumps(message).encode()
        header = bytes([0x81, len(payload)]) if len(payload) < 126 else bytes([0x81, 126]) + struct.pack("!H", len(payload))
        self.conn.sendall(header + payload)

    def fill(self, size, deadline):
        while len(self.buffer) < size:
            if time.monotonic() > deadline:
                raise TimeoutError("WebSocket test peer timed out")
            try:
                chunk = self.conn.recv(65536)
            except socket.timeout:
                continue
            if not chunk:
                raise EOFError("Game disconnected")
            self.buffer += chunk

    def receive(self, deadline):
        self.fill(2, deadline)
        opcode, flags = self.buffer[:2]
        length = flags & 127
        offset = 2
        if length == 126:
            self.fill(4, deadline)
            length = struct.unpack("!H", self.buffer[2:4])[0]
            offset = 4
        elif length == 127:
            self.fill(10, deadline)
            length = struct.unpack("!Q", self.buffer[2:10])[0]
            offset = 10
        masked = bool(flags & 128)
        total = offset + (4 if masked else 0) + length
        self.fill(total, deadline)
        mask = self.buffer[offset:offset+4] if masked else bytes(4)
        start = offset + (4 if masked else 0)
        payload = bytes(value ^ mask[i % 4] for i, value in enumerate(self.buffer[start:total]))
        self.buffer = self.buffer[total:]
        if opcode & 15 == 8:
            raise EOFError("Game closed WebSocket")
        if opcode & 15 == 1:
            return json.loads(payload)
        return self.receive(deadline)

    def expect(self, kind, timeout=30):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            message = self.receive(deadline)
            if message.get("type") == kind:
                return message
        raise AssertionError(f"Missing {kind}")
