#!/usr/bin/env python3
"""Cut the captured takes into the five-second store clip and its poster.

    python3 tools/encode_preview.py TAKES assets/gamenight

The edit list below is the whole edit: (take, first frame, frames), 150 frames
at 30 FPS in all. Start cuts at frame 20 or later, the first frames of a take
can show the engine warming up. Shot list: docs/gamenight-preview.md. Encoding is bit-exact
(single thread, no metadata), so the same frames give the same file.
"""
import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CUTS = [("knockout", 20, 34), ("pickups", 44, 31), ("islands", 36, 30), ("teamwin", 20, 55)]
POSTER = ("islands", 50)


def frame(takes: Path, take: str, n: int) -> Path:
    return takes / take / f"f{n:08d}.png"


def main() -> int:
    takes, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        i = 0
        assert sum(length for _, _, length in CUTS) == 150
        for take, start, length in CUTS:
            for n in range(start, start + length):
                shutil.copy(frame(takes, take, n), Path(tmp) / f"{i:04d}.png")
                i += 1
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", f"{tmp}/%04d.png",
                        "-vf", "scale=960:540:flags=lanczos,format=yuv420p", "-c:v", "libx264", "-crf", "24",
                        "-preset", "slow", "-threads", "1", "-movflags", "+faststart", "-an",
                        "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact",
                        str(out / "preview.mp4")], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(frame(takes, *POSTER)), "-q:v", "3",
                    "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact",
                    str(out / "preview.jpg")], check=True)
    for name in ("preview.mp4", "preview.jpg"):
        print(hashlib.sha256((out / name).read_bytes()).hexdigest(), name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
