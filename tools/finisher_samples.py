#!/usr/bin/env python3
"""Generate eight short PROTOKSEED finisher cuts, never complete loops.

python tools/finisher_samples.py "/path/to/PROTOKSEED SAMPLE PACK"
Requires NumPy; Python wave reads/writes PCM. Original files are read-only.
Sources are hash-locked below. catalog.json records ranges, processing and PCM
measurements. Only derived mono PCM16/22050 cuts and import settings are shipped.
The supplied pack had no licence/readme: redistribution permission is unverified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import wave

import numpy as np

RATE = 22050
SOURCE_RATE = 44100
SOURCES = {
    "snap": ("KICKS/PTKSD - KICK F 05.wav", "783e7c69e8b7a5477af5c7576258c0ccd3c45a4901ec4c22e6b01ec959b1637d"),
    "metal": ("KICKS/PTKSD - KICK G# 03.wav", "b1dfa37ecd7611670315f8b7b58b9088ad3e3eb77747ab7e57d5c3317d02db2d"),
    "crunch": ("KICKS/PTKSD - KICK D 01.wav", "d0da3a434a8314690be312a736be68529bf80b33e1349e3537749e4c7d261421"),
    "slam": ("KICKS/PTKSD - KICK F 22.wav", "6be08b4dfa50656d1f25cfcd08ffafddc47f01ac5172a28ae64e3d17d9b9e795"),
    "acid": ("SYNTHS, DRUMS, LEADS/PTKSD - 303 01.wav", "7727347f76bd8401c517c1d34a0f28c3d2bff2f37f9d46217e0aa22d7322a9ff"),
    "scrape": ("SYNTHS, DRUMS, LEADS/PTKSD - FX 03.wav", "a4d92be29209ccd71998f375f88807c9920688be6ce0253d0cea2026876b5018"),
    "tail": ("SYNTHS, DRUMS, LEADS/PTKSD - FX 05.wav", "8cc6741b1c8d72125e4a26c6d2080998e84a6acadf0a76eebd5dd5e06e90d97d"),
    "drums": ("SYNTHS, DRUMS, LEADS/PTKSD - DRUM LOOP 04.wav", "c67584125f5221883b7966936a8eb3f5d4569b918ae38e4812ce173ddb649c39"),
    "lead": ("SYNTHS, DRUMS, LEADS/PTKSD - LEAD 01.wav", "d258a50192a8f3d96fab0102f15c06f6d10e5e7fa37aae7b004fbb88db925259"),
}


def layer(source, start, end, at, duration, gain=1.0, reverse=False,
          sweep=0.0, rise=False, decay=0.0, drive=1.0):
    return dict(source=source, source_seconds=[start, end], at_seconds=at,
                duration_seconds=duration, gain=gain, reverse=reverse,
                sweep=sweep, rise=rise, decay=decay, drive=drive)


# Fixed audible windows selected from measured source energy, not silent tails.
# Sweep warps source traversal quadratically: positive accelerates/pitches up,
# negative decelerates/pitches down. 4 ms layer boundaries overlap as crossfades.
# All launch durations end before the shared 460 ms gameplay contact.
RECIPES = [
    ("flip_launch", .36, .46, [
        layer("lead", .48, .80, 0, .30, reverse=True, rise=True, sweep=.25),
        layer("snap", .015, .085, .275, .085, gain=.42, decay=3)]),
    ("flip_impact", .24, .66, [
        layer("snap", 0, .22, 0, .24, decay=5),
        layer("tail", .005, .10, 0, .11, gain=.30, decay=4)]),
    ("corkscrew_launch", .40, .44, [
        layer("acid", .54, .64, 0, .10, sweep=.3),
        layer("acid", .66, .76, .085, .095, gain=.9, reverse=True),
        layer("acid", .80, .90, .165, .085, gain=.8, sweep=.4),
        layer("acid", 1.20, 1.30, .235, .075, gain=.7, reverse=True),
        layer("scrape", .10, .23, .295, .105, gain=.6, sweep=.2)]),
    ("corkscrew_impact", .30, .62, [
        layer("metal", .002, .245, 0, .30, decay=7),
        layer("scrape", .12, .27, 0, .18, gain=.45, decay=9)]),
    ("drop_kick_launch", .32, .45, [
        layer("drums", .72, .83, 0, .12, reverse=True, gain=.7),
        layer("lead", .78, .95, .10, .22, reverse=True, rise=True, drive=2.5)]),
    ("drop_kick_impact", .40, .68, [
        layer("crunch", 0, .19, 0, .24, decay=9, drive=1.8),
        layer("crunch", .025, .26, .095, .305, gain=.85, decay=8, drive=2.3),
        layer("drums", .72, .85, .09, .13, gain=.35, decay=6)]),
    ("axe_kick_launch", .42, .44, [
        layer("scrape", .08, .38, 0, .42, sweep=-.45, decay=1, drive=3),
        layer("lead", .48, .72, .045, .34, gain=.5, sweep=-.4, decay=2)]),
    ("axe_kick_impact", .36, .68, [
        layer("slam", 0, .25, 0, .36, sweep=-.25, decay=7),
        layer("tail", 0, .25, 0, .30, gain=.35, decay=5, drive=1.8)]),
]


def fade(samples, seconds=.004):
    count = min(round(seconds * RATE), len(samples) // 2)
    ramp = np.linspace(0, 1, count)
    samples[:count] *= ramp
    samples[-count:] *= ramp[::-1]
    return samples


def prepare(pack: Path, output: Path):
    output.mkdir(parents=True, exist_ok=True)
    # Current pitch traversals reach 1.65x source speed: 6 kHz leaves room below
    # the output's 11.025 kHz Nyquist, including the filter transition band.
    taps = np.arange(-63, 64, dtype=np.float64)
    kernel = (12000 / SOURCE_RATE) * np.sinc(12000 / SOURCE_RATE * taps) * np.hamming(127)
    kernel /= kernel.sum()
    sources = {}
    for name, (relative, digest) in SOURCES.items():
        source = pack / relative
        if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Source hash changed: {source}")
        with wave.open(str(source), "rb") as reader:
            if (reader.getnchannels(), reader.getsampwidth(), reader.getframerate(), reader.getcomptype()) != (2, 2, SOURCE_RATE, "NONE"):
                raise ValueError(f"Unexpected source format: {source}")
            stereo = np.frombuffer(reader.readframes(reader.getnframes()), dtype="<i2").reshape(-1, 2)
        mono = stereo.astype(np.float64).mean(axis=1) / 32768
        sources[name] = np.convolve(np.pad(mono, (63, 63), mode="reflect"), kernel, mode="valid")
    catalog = dict(sample_rate=RATE, channels=1, pcm_bits=16,
                   permission="Unverified: supplied pack contained no licence/readme",
                   processing="Stereo average; 127-tap 6kHz Hamming/sinc source lowpass; quadratic pitch traversal; per-cut DC removal and RMS balance; 4ms layer crossfades; final DC removal, 5ms fades and peak ceiling",
                   sources={name: dict(filename=rel, sha256=digest) for name, (rel, digest) in SOURCES.items()}, clips=[])
    for index, (name, duration, ceiling, layers) in enumerate(RECIPES):
        mix = np.zeros(round(duration * RATE), dtype=np.float64)
        for spec in layers:
            start, end = (round(t * SOURCE_RATE) for t in spec["source_seconds"])
            cut = sources[spec["source"]][start:end].copy()
            if len(cut) != end - start or len(cut) < 2:
                raise ValueError(f"Invalid source range: {name}: {spec}")
            cut -= cut.mean()
            rms = float(np.sqrt(np.mean(cut ** 2)))
            if rms < .0001:
                raise ValueError(f"Silent source range: {name}: {spec}")
            cut *= .20 / rms
            if spec["reverse"]:
                cut = cut[::-1]
            count = round(spec["duration_seconds"] * RATE)
            progress = np.linspace(0, 1, count)
            traversal = progress + spec["sweep"] * (progress ** 2 - progress)
            sound = np.interp(traversal * (len(cut) - 1), np.arange(len(cut)), cut)
            if spec["drive"] != 1:
                sound = np.tanh(sound * spec["drive"]) / spec["drive"]
            if spec["rise"]:
                sound *= progress ** .75
            sound *= np.exp(-spec["decay"] * progress) * spec["gain"]
            fade(sound)
            offset = round(spec["at_seconds"] * RATE)
            length = min(len(sound), len(mix) - offset)
            mix[offset:offset + length] += sound[:length]
        mix -= mix.mean()
        fade(mix, .005)
        mix *= ceiling / float(np.max(np.abs(mix)))
        pcm = np.rint(mix * 32767).astype("<i2")
        target = output / f"{name}.wav"
        with wave.open(str(target), "wb") as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(RATE)
            writer.writeframes(pcm.tobytes())
        resource = f"res://assets/audio/finishers/{name}.wav"
        imported = f"res://.godot/imported/{name}.wav-{hashlib.md5(resource.encode()).hexdigest()}.sample"
        target.with_suffix(".wav.import").write_text(
            '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n'
            f'path="{imported}"\n\n[deps]\n\nsource_file="{resource}"\n'
            f'dest_files=["{imported}"]\n\n[params]\n\n'
            'force/8_bit=false\nforce/mono=true\nforce/max_rate=false\n'
            'force/max_rate_hz=22050\nedit/trim=false\nedit/normalize=false\n'
            'edit/loop_mode=0\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n', encoding="utf-8")
        rms = float(np.sqrt(np.mean((pcm.astype(np.float64) / 32768) ** 2)))
        peak = float(np.max(np.abs(pcm.astype(np.int32))) / 32768)
        entry = dict(name=name, variation=index // 2, contact=bool(index % 2),
                     frames=len(pcm), seconds=len(pcm) / RATE, peak=peak,
                     rms=rms, peak_dbfs=20 * np.log10(peak), rms_dbfs=20 * np.log10(rms),
                     pcm_bytes=pcm.nbytes, wav_sha256=hashlib.sha256(target.read_bytes()).hexdigest(), layers=layers)
        catalog["clips"].append(entry)
        print(f"{name}: {entry['seconds']:.3f}s, {entry['pcm_bytes']} PCM bytes, peak {entry['peak_dbfs']:.2f} dBFS, RMS {entry['rms_dbfs']:.2f} dBFS")
    (output / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "assets/audio/finishers")
    arguments = parser.parse_args()
    prepare(arguments.pack, arguments.output)
