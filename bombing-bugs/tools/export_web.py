"""Build standalone and hosted Bombing Bugs with Godot 4.6.2 and its web templates.

Run python tools/export_web.py --godot /path/to/godot, then serve dist/web via HTTP.
"""
import argparse
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot", help="Godot editor executable")
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    output = project / "dist" / "web"
    output.mkdir(parents=True, exist_ok=True)
    (output.parent / ".gdignore").touch()
    godot = [args.godot, "--headless", "--path", str(project)]
    subprocess.run([*godot, "--import"], check=True)
    subprocess.run([*godot, "--export-release", "Web", str(output / "index.html")], check=True)
    shutil.copyfile(project / "addons/gamenight/browser_transport.js", output / "bridge.js")
    licenses = output / "licenses"
    licenses.mkdir(exist_ok=True)
    shutil.copyfile(project.parent / "LICENSE", licenses / "GameNight-Games-LICENSE.txt")
    shutil.copyfile(project / "assets/fonts/DynaPuff-OFL.txt", licenses / "DynaPuff-OFL.txt")
    for notice in sorted((project / "third_party").glob("*.txt")):
        shutil.copyfile(notice, licenses / notice.name)
    print(output)


if __name__ == "__main__":
    main()
