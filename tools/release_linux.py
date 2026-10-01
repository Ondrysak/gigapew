#!/usr/bin/env python3
"""Export and package the Linux x86_64 release with Godot 4.7.2."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE_VERSION = "4.7.2"
PRESET = "linux/x86_64"
EXECUTABLE = "kakaboomboom.x86_64"


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=str(Path.home() / ".local/opt/godot/4.7.2/godot"))
    args = parser.parse_args()
    godot = shutil.which(args.godot)
    if not godot:
        parser.error(f"Godot executable not found: {args.godot}; pass --godot PATH")
    engine = subprocess.check_output([godot, "--version"], text=True).strip()
    if not engine.startswith(ENGINE_VERSION + ".stable."):
        parser.error(f"Release requires Godot {ENGINE_VERSION} stable, found {engine}")

    # Godot's config has top-level keys and Variant values, not standard INI.
    project = (ROOT / "project.godot").read_text()
    application = re.search(r"^\[application\]\s*\n(.*?)(?=^\[|\Z)", project, re.M | re.S)
    version_setting = re.search(r'^config/version\s*=\s*(".*")\s*$', application[1], re.M) if application else None
    if not version_setting:
        parser.error("Missing application/config/version in project.godot")
    version = json.loads(version_setting[1])
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?", version):
        parser.error("application/config/version must be a semantic version")
    data_home = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share")))
    template = data_home / "godot/export_templates/4.7.2.stable/linux_release.x86_64"
    if not template.is_file():
        parser.error("Missing Godot 4.7.2 Linux x86_64 release template. "
                     "Install the matching templates using Editor > Manage Export Templates.")

    output = ROOT / "export/linux"
    output.mkdir(parents=True, exist_ok=True)
    name = f"kakaboomboom-{version}-linux-x86_64"
    # Export into staging so a failed command cannot masquerade as a new release.
    with tempfile.TemporaryDirectory(prefix=".release-", dir=output) as temporary:
        staging = Path(temporary)
        package = staging / name
        package.mkdir()
        executable = package / EXECUTABLE
        subprocess.run([godot, "--headless", "--path", str(ROOT), "--export-release",
                        PRESET, str(executable)], cwd=ROOT, check=True)
        if not executable.is_file() or executable.stat().st_size == 0:
            raise RuntimeError("Godot returned without generating the executable")
        executable.chmod(0o755)
        for filename in ("README.md", "CREDITS.md", "RELEASE_NOTES.md"):
            shutil.copy2(ROOT / filename, package / filename)
        shutil.copytree(ROOT / "tools/release/licenses", package / "licenses")
        (package / "VERSION").write_text(version + "\n")
        metadata = {
            "game": "Kakaboomboom", "version": version,
            "platform": "linux", "architecture": "x86_64",
            "godot": engine, "preset": PRESET, "configuration": "release",
            "built_at_utc": datetime.now(timezone.utc).isoformat(),
            "executable": EXECUTABLE, "embedded_pck": True,
            "executable_sha256": sha256(executable),
            "export_template_sha256": sha256(template),
        }
        (package / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
        files = sorted(path for path in package.rglob("*") if path.is_file())
        (package / "SHA256SUMS").write_text("".join(
            f"{sha256(path)}  {path.relative_to(package).as_posix()}\n" for path in files))
        archive = staging / (name + ".tar.gz")
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(package, arcname=name)
        archive_checksum = staging / (archive.name + ".sha256")
        archive_checksum.write_text(f"{sha256(archive)}  {archive.name}\n")
        destination = output / name
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(str(package), destination)
        os.replace(archive, output / archive.name)
        os.replace(archive_checksum, output / archive_checksum.name)
        # Keep the preset's plain executable path useful for direct local launches.
        shutil.copy2(destination / EXECUTABLE, output / EXECUTABLE)
        print(f"Release: {output / archive.name}")
        print(f"Run: {destination / EXECUTABLE}")


if __name__ == "__main__":
    main()
