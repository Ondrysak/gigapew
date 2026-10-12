#!/usr/bin/env python3
"""Prepare the five music samples: python tools/music_samples.py /path/to/pack.

Requires NumPy. This only converts selected WAVs, never the existing voice files.
Provenance: local folder named PROTOKSEED SAMPLE PACK. Its complete inventory
contained WAV files only, no license/readme/author attribution. Redistribution
permission is unverified; this is NOT a CC0 or royalty-free claim.

All sources: stereo little-endian PCM16, 44100 Hz. SHA256 pins the actual local
source, not a filename-based assumption. Stereo is averaged, a 127-tap Hamming
windowed sinc lowpass (cutoff 0.225 cycles/input frame) removes aliasing before
2:1 decimation, DC is removed, peaks are normalized, boundary fades applied,
then output is rounded to mono PCM16 at 22050 Hz. No compressor/distortion.

DRUM LOOP 01: 124518 input frames / 44100 = 2.823537415 s. Eight beats imply
170.000253 BPM; kick/snare activity at ~0, .353, .529, .882, 1.059, 1.412,
1.941, 2.294, 2.471 s confirms the 170 BPM grid. Keep the whole loop and its
articulation; there is no leading-silence trim or tempo stretch. Output is
62259 frames. Only 1 ms at each boundary is faded, not individual transients.

303 01 is a 22.588254 s modulated acid phrase, not a single stable note. The
one-beat slice starting at beat two retains the actual acid texture. Spectral
peaks move around ~332/498 Hz, so no reliable D root is claimed or fabricated:
this sample is intentionally NOT pitch-corrected. Kicks are source-labelled D.
FX 01 is 2.909093 s; keep its first .48 s as a short accent, not the whole tail.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import wave

import numpy as np

RATE = 22050
# name, relative source, SHA256, source frames, start seconds, end seconds,
# peak target, fade milliseconds (attack/release).
SAMPLES = (
    ("kick", "KICKS/PTKSD - KICK D 01.wav",
     "d0da3a434a8314690be312a736be68529bf80b33e1349e3537749e4c7d261421",
     15565, 0.0, None, .92, (1.0, 3.0)),
    ("kick_heavy", "KICKS/PTKSD - KICK D 02.wav",
     "c86961f00571462c1acb7832e7e63baf3ba265f144bc9558f6954953e1634a35",
     15565, 0.0, None, .94, (1.0, 3.0)),
    ("break", "SYNTHS, DRUMS, LEADS/PTKSD - DRUM LOOP 01.wav",
     "b9331d47a485d5ef0ebaaf8211d59d78206615142ac21a809808f468dc91e6f5",
     124518, 0.0, None, .86, (1.0, 1.0)),
    ("stab", "SYNTHS, DRUMS, LEADS/PTKSD - 303 01.wav",
     "7727347f76bd8401c517c1d34a0f28c3d2bff2f37f9d46217e0aa22d7322a9ff",
     996142, 120.0 / 170.0, 180.0 / 170.0, .80, (2.0, 8.0)),
    ("fx", "SYNTHS, DRUMS, LEADS/PTKSD - FX 01.wav",
     "d3f62722cb19b895568593023767d9f788d65050da15998a097957363f106d8e",
     128291, 0.0, .48, .72, (1.0, 8.0)),
)


def prepare(pack: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    taps = np.arange(-63, 64, dtype=np.float64)
    kernel = .45 * np.sinc(.45 * taps) * np.hamming(127)
    kernel /= kernel.sum()
    for name, relative, expected_hash, frames, start, end, peak, fades in SAMPLES:
        source = pack / relative
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != expected_hash:
            raise ValueError(f"Source checksum mismatch: {source}: {digest}")
        with wave.open(str(source), "rb") as reader:
            if (reader.getnchannels(), reader.getsampwidth(), reader.getframerate(),
                    reader.getnframes(), reader.getcomptype()) != (2, 2, 44100, frames, "NONE"):
                raise ValueError(f"Unexpected source WAV format: {source}")
            stereo = np.frombuffer(reader.readframes(frames), dtype="<i2").reshape(-1, 2)
        mono = stereo.astype(np.float64).mean(axis=1) / 32768.0
        # Filter the original recording before cropping; slices retain surrounding
        # filter context. Full loops keep their exact original frame count/grid.
        mono = np.convolve(np.pad(mono, (63, 63), mode="reflect"), kernel, mode="valid")[::2]
        begin = round(start * RATE)
        finish = len(mono) if end is None else round(end * RATE)
        samples = mono[begin:finish].copy()
        if len(samples) == 0:
            raise ValueError(f"Empty sample slice: {name}")
        samples -= samples.mean()
        maximum = float(np.max(np.abs(samples)))
        if maximum == 0.0:
            raise ValueError(f"Silent source: {source}")
        samples *= peak / maximum
        for is_end, milliseconds in enumerate(fades):
            count = min(len(samples) // 2, round(milliseconds * RATE / 1000.0))
            envelope = np.linspace(0.0, 1.0, count)
            if is_end:
                samples[-count:] *= envelope[::-1]
            else:
                samples[:count] *= envelope
        pcm = np.rint(np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
        target = output / f"{name}.wav"
        with wave.open(str(target), "wb") as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(RATE)
            writer.writeframes(pcm.tobytes())
        resource = f"res://assets/audio/protokseed/{name}.wav"
        imported = f"res://.godot/imported/{name}.wav-{hashlib.md5(resource.encode()).hexdigest()}.sample"
        # Explicit PCM16: load_bank decodes the import's data, including in exports.
        target.with_suffix(".wav.import").write_text(
            '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n'
            f'path="{imported}"\n\n[deps]\n\nsource_file="{resource}"\n'
            f'dest_files=["{imported}"]\n\n[params]\n\n'
            'force/8_bit=false\nforce/mono=true\nforce/max_rate=false\n'
            'force/max_rate_hz=22050\nedit/trim=false\nedit/normalize=false\n'
            'edit/loop_mode=0\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n',
            encoding="utf-8",
        )
        print(f"{name}: {len(pcm)} frames, {len(pcm)/RATE:.6f}s, "
              f"{target.stat().st_size} bytes, SHA256 {hashlib.sha256(target.read_bytes()).hexdigest()}")
    print("Break tempo: 170.000253 BPM, 8 beats; license permission unverified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path, help="Local PROTOKSEED SAMPLE PACK directory")
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[1] / "assets/audio/protokseed")
    arguments = parser.parse_args()
    prepare(arguments.pack, arguments.output)
