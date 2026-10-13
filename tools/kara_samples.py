#!/usr/bin/env python3
"""Download every jirikara.cz indexed chip without transcoding source MP3s.

Run: python tools/kara_samples.py
Requires ffprobe on PATH. Serial requests are spaced out; existing audio is never
overwritten. This is an offline asset-preparation tool, not game runtime code.
The user authorized reuse; an independently verified redistribution licence has
not been established. Public availability is not a licence grant.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
import urllib.request

INDEX_URL = "https://www.jirikara.cz/"
SCRIPT_URL = INDEX_URL + "script.js"
AUDIO_RULE = "audio/${slug}.mp3"
EVENT_SLUGS = {
    "warning": "delej",
    "fire": "ohen",
    "rush": "delej",
    "reversed": "co_se_deje",
    "calm": "cas_klidu",
}
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "assets/audio/kara"


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class ChipIndex(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.clips = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if "chip" not in attributes.get("class", "").split():
            return
        slug = attributes.get("data-slug", "")
        text = attributes.get("data-clipboard-text")
        if not re.fullmatch(r"[A-Za-z0-9_-]+", slug) or text is None:
            raise ValueError("Indexed chip lacks a safe exact slug or clipboard text")
        if any(clip["slug"] == slug for clip in self.clips):
            raise ValueError(f"Duplicate indexed slug: {slug}")
        self.clips.append({"slug": slug, "text": text})


def fetch(url):
    request = urllib.request.Request(url, headers={
        "User-Agent": "Kakaboomboom-offline-audio-catalog/1.0",
        "Accept-Encoding": "identity",
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read()
        return data, {
            "url": url,
            "resolved_url": response.geturl(),
            "retrieved_utc": utc_now(),
            "sha256": sha256(data),
            "bytes": len(data),
            "content_type": response.headers.get("Content-Type"),
            "etag": response.headers.get("ETag"),
            "last_modified": response.headers.get("Last-Modified"),
        }


def decoded_metadata(path):
    result = subprocess.run([
        "ffprobe", "-v", "error", "-select_streams", "a:0",
        "-show_frames", "-show_streams", "-show_format",
        "-show_entries",
        "frame=nb_samples:stream=codec_name,sample_rate,channels:format=duration",
        "-of", "json", str(path),
    ], check=True, capture_output=True, text=True, timeout=60)
    if result.stderr.strip():
        raise ValueError(f"ffprobe decode error: {result.stderr.strip()}")
    metadata = json.loads(result.stdout)
    stream = metadata["streams"][0]
    rate = int(stream["sample_rate"])
    samples = sum(int(frame.get("nb_samples", 0)) for frame in metadata.get("frames", []))
    if stream["codec_name"] != "mp3" or rate <= 0 or samples <= 0:
        raise ValueError("Source did not decode as nonempty MP3 audio")
    return {
        "codec": stream["codec_name"],
        "sample_rate": rate,
        "channels": int(stream["channels"]),
        "decoded_samples": samples,
        "decoded_duration_seconds": samples / rate,
        "container_duration_seconds": float(metadata["format"]["duration"]),
        "duration_method": "ffprobe decoded frame nb_samples sum / sample_rate",
    }


def download(output, delay):
    output.mkdir(parents=True, exist_ok=True)
    index_bytes, index_source = fetch(INDEX_URL)
    time.sleep(delay)
    script_bytes, script_source = fetch(SCRIPT_URL)
    script_text = script_bytes.decode("utf-8")
    if not re.search(r"const\s+src\s*=\s*`audio/\$\{slug\}\.mp3`", script_text):
        raise ValueError("Website playback URL rule changed; refusing guessed audio URLs")
    parser = ChipIndex()
    parser.feed(index_bytes.decode("utf-8"))
    if not parser.clips:
        raise ValueError("Website index contains no chips")
    indexed_slugs = {clip["slug"] for clip in parser.clips}
    if not set(EVENT_SLUGS.values()).issubset(indexed_slugs):
        raise ValueError("A selected event slug is no longer indexed")
    catalog = {
        "schema_version": 1,
        "source_index": index_source,
        "source_script": script_source,
        "verified_audio_url_rule": AUDIO_RULE,
        "processing": "None: original HTTP response MP3 bytes; no trimming, normalization or transcoding",
        "authorization": {
            "user_authorized_download_and_reuse": True,
            "user_statement": "User explicitly requested/authorized reuse and described the clips as free.",
            "independently_verified_license": None,
            "license_evidence": "No redistribution licence grant identified in the inspected source index or playback script. Public availability and user authorization do not establish rights-holder permission.",
            "inspected_urls": [INDEX_URL, SCRIPT_URL],
        },
        "selected_event_slugs": EVENT_SLUGS,
        "indexed_count": len(parser.clips),
        "clips": [],
        "failures": [],
    }
    for chip in parser.clips:
        time.sleep(delay)
        slug = chip["slug"]
        filename = slug + ".mp3"
        url = INDEX_URL + "audio/" + filename
        entry = {**chip, "filename": filename, "source_url": url}
        temporary = None
        try:
            data, source = fetch(url)
            entry.update(source)
            destination = output / filename
            if destination.exists() and destination.read_bytes() != data:
                raise ValueError("Existing file differs from downloaded source; refusing overwrite")
            with tempfile.NamedTemporaryFile(dir=output, suffix=".mp3", delete=False) as handle:
                temporary = Path(handle.name)
                handle.write(data)
            entry.update(decoded_metadata(temporary))
            if not destination.exists():
                # Link creates the destination exclusively, never replacing user audio.
                os.link(temporary, destination)
            entry["status"] = "downloaded"
            print(f"{filename}: {len(data)} bytes, {entry['decoded_duration_seconds']:.3f}s", flush=True)
        except Exception as error:
            entry["status"] = "failed"
            entry["error"] = str(error)
            catalog["failures"].append({"slug": slug, "source_url": url, "error": str(error)})
            print(f"FAILED {url}: {error}", flush=True)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        catalog["clips"].append(entry)
    successful = [entry for entry in catalog["clips"] if entry["status"] == "downloaded"]
    catalog["downloaded_count"] = len(successful)
    catalog["total_mp3_bytes"] = sum(entry["bytes"] for entry in successful)
    catalog["completed_utc"] = utc_now()
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output,
                                     suffix=".json", delete=False) as handle:
        temporary_catalog = Path(handle.name)
        json.dump(catalog, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    temporary_catalog.replace(output / "catalog.json")
    print(f"Downloaded {len(successful)}/{len(parser.clips)} clips; {catalog['total_mp3_bytes']} MP3 bytes", flush=True)
    return 1 if catalog["failures"] else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--delay", type=float, default=0.5, help="Seconds between serial requests (minimum 0.25)")
    args = parser.parse_args()
    if args.delay < 0.25:
        parser.error("--delay must be at least 0.25 seconds")
    return download(args.output, args.delay)


if __name__ == "__main__":
    raise SystemExit(main())
