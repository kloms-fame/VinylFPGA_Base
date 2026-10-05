#!/usr/bin/env python3
"""Send one line of Chinese text to the VinylFPGA subtitle overlay."""

from __future__ import annotations

import argparse
import json
import select
import socket
import time
import uuid

from generate_cn_subtitle import (
    DEFAULT_FALLBACK_FONT,
    DEFAULT_FONT,
    load_font,
    rasterize_glyph,
)


SCHEMA = "ek.telemetry/v1"
MAX_TEXT_LENGTH = 32


class BridgeError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--text", help="send this line once instead of prompting")
    parser.add_argument("--allow-write", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--font", default=DEFAULT_FONT)
    parser.add_argument("--fallback-font", default=DEFAULT_FALLBACK_FONT)
    parser.add_argument("--glyph-size", type=int, default=16)
    parser.add_argument("--baseline-y", type=int, default=14)
    parser.add_argument("--threshold", type=int, default=96)
    return parser.parse_args()


def glyph_hex(char: str, font, args: argparse.Namespace) -> str:
    rows = rasterize_glyph(
        char,
        font,
        glyph_size=args.glyph_size,
        baseline_y=args.baseline_y,
        threshold=args.threshold,
    )
    return "".join(f"{row:04X}" for row in rows)


def recv_line(sock: socket.socket, pending: bytes, timeout: float):
    deadline = time.monotonic() + timeout
    while b"\n" not in pending:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise BridgeError("bridge response timeout")
        if not select.select([sock], [], [], min(0.25, remaining))[0]:
            continue
        chunk = sock.recv(65536)
        if not chunk:
            raise BridgeError("bridge closed")
        pending += chunk
    return pending.split(b"\n", 1)


def connect_bridge(host: str, port: int):
    sock = socket.create_connection((host, port), timeout=5.0)
    sock.settimeout(5.0)
    raw, pending = recv_line(sock, b"", 5.0)
    hello = json.loads(raw.decode("utf-8"))
    if hello.get("schema") != SCHEMA or hello.get("type") != "hello":
        sock.close()
        raise BridgeError(f"unexpected bridge hello: {hello!r}")
    return sock, pending


def send_serial(sock: socket.socket, pending: bytes, text: str) -> bytes:
    request_id = str(uuid.uuid4())
    message = {
        "type": "serial.write",
        "id": request_id,
        "text": text,
        "lineEnding": "lf",
    }
    sock.sendall(
        json.dumps(message, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        + b"\n"
    )
    deadline = time.monotonic() + 5.0
    while time.monotonic() < deadline:
        while b"\n" in pending:
            raw, pending = pending.split(b"\n", 1)
            if not raw.strip():
                continue
            response = json.loads(raw.decode("utf-8"))
            if response.get("type") == "ack" and response.get("id") == request_id:
                if not response.get("ok"):
                    raise BridgeError(str(response.get("error") or "write rejected"))
                return pending
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        if not select.select([sock], [], [], min(0.25, remaining))[0]:
            continue
        chunk = sock.recv(65536)
        if not chunk:
            raise BridgeError("bridge closed before ACK")
        pending += chunk
    raise BridgeError(f"ACK timeout for {request_id}")


class Sender:
    def __init__(self, args: argparse.Namespace, font) -> None:
        self.args = args
        self.font = font
        self.sock = None
        self.pending = b""
        self.cache: dict[str, str] = {}

    def open(self) -> None:
        if self.args.dry_run:
            return
        if not self.args.allow_write:
            raise BridgeError(
                "serial write is disabled; enable it in MICU and pass --allow-write"
            )
        self.sock, self.pending = connect_bridge(self.args.host, self.args.port)

    def close(self) -> None:
        if self.sock is not None:
            self.sock.close()
            self.sock = None

    def send(self, command: str) -> None:
        if self.args.dry_run:
            print(command)
            return
        assert self.sock is not None
        self.pending = send_serial(self.sock, self.pending, command)

    def bitmap(self, char: str) -> str:
        if char not in self.cache:
            self.cache[char] = glyph_hex(char, self.font, self.args)
        return self.cache[char]

    def send_text(self, text: str) -> None:
        if len(text) > MAX_TEXT_LENGTH:
            raise ValueError(f"输入 {len(text)} 个字，超过最多 32 个字")
        slots: dict[str, int] = {}
        for char in text:
            if char not in slots:
                slots[char] = len(slots)

        self.send("@C")
        for char, slot in slots.items():
            self.send(f"@G,{slot:02X},{self.bitmap(char)}")
        for char in text:
            self.send(f"@A,{slots[char]:02X}")
        self.send("@T")


def main() -> int:
    args = parse_args()
    font = load_font(args.font, args.fallback_font, args.glyph_size)
    sender = Sender(args, font)
    try:
        sender.open()
        if args.text is not None:
            sender.send_text(args.text)
            return 0
        print("输入不超过 32 个字并按回车发送；空行退出。")
        while True:
            try:
                text = input("字幕> ")
            except EOFError:
                break
            if not text:
                break
            sender.send_text(text)
            print("已发送，等待下一行输入。")
    finally:
        sender.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
