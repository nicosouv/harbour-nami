#!/usr/bin/env python3
"""Works out where a track's beats fall, once, off the device.

The tracks ship with the app, so their rhythm is known before anyone
installs it. Doing this here means the phone never runs any signal
processing and the RPM carries no DSP library: it reads a JSON file instead.

    docker compose run --rm beats

writes one <track>.json next to each <track>.ogg in media/. The result is
committed; the audio is not.

Beats are what MemoryComposer cuts on, and a slideshow whose changes land off
the music reads as broken even to someone who could not say why.
"""

import json
import sys
from pathlib import Path

try:
    import librosa
    import numpy as np
except ImportError:
    sys.exit("needs librosa: run this through `docker compose run --rm beats`")

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "media"
AUDIO_SUFFIXES = (".opus", ".ogg", ".mp3", ".m4a", ".wav", ".flac")

# How much of a track a clip may use. Past this most tracks are winding down,
# and a shot still running over a fade looks like a mistake.
MAX_CLIP_MS = 90_000
# Pulled in from the very end, so the last shot is never sitting on silence
TAIL_MARGIN_MS = 1_500


# Below this the track has no dynamics worth reacting to, and stretching
# what little it has would make a flat track look like it lifts
FLAT_TRACK_RANGE = 0.08


def energy_sections(y, sample_rate, safe_out_ms):
    """Where the track gets louder or quieter, as points with a 0..1 energy.

    The value is where the track sits between its own quietest and loudest
    moment, not an absolute loudness. The composer asks one question of it,
    whether the moment is above 0.6, and that question only means anything
    relative to the track it is being asked about: an absolute scale made
    the answer depend on how hot the recording was mastered, and on the four
    tracks measured here it was never yes.

    Only the part a clip can use is described. Sections past safe_out_ms are
    dead weight in a file that gets committed.
    """
    rms = librosa.feature.rms(y=y)[0]
    times = librosa.times_like(rms, sr=sample_rate)
    if rms.size == 0:
        return []

    # One value every four seconds. The composer reads this to decide how
    # fast to cut, and a section per bar would answer differently every bar.
    window = max(1, int(4.0 * len(times) / max(times[-1], 1.0)))

    coarse = []
    for start in range(0, len(rms), window):
        chunk = rms[start:start + window]
        moment = int(times[start] * 1000)
        if chunk.size == 0 or moment > safe_out_ms:
            continue
        coarse.append((moment, float(np.mean(chunk))))

    if not coarse:
        return []

    values = [value for _, value in coarse]
    lo, hi = min(values), max(values)
    span = hi - lo
    loudest = hi or 1.0

    sections = []
    for moment, value in coarse:
        # A track that does not move reads as quiet throughout rather than
        # having its noise floor stretched into a false crescendo
        energy = 0.0 if span / loudest < FLAT_TRACK_RANGE else (value - lo) / span
        energy = round(energy, 3)
        if not sections or abs(sections[-1]["energy"] - energy) > 0.15:
            sections.append({"t": moment, "energy": energy})

    return sections


# Below either of these a track has a tempo but not much music, and a clip
# cut to it feels slow whatever the beat grid says. Both were read off the
# four tracks first shipped: the good ones sat near 0.16 loudness and 4
# onsets a second, and the two that felt like slow motion were at 0.045 and
# 0.109, and 2.5 and 3.0.
QUIET = 0.12
SPARSE = 3.2


def character(path):
    """How loud and how busy, which is what tempo alone does not say."""
    y, sample_rate = librosa.load(str(path), mono=True, duration=92)
    onsets = librosa.onset.onset_detect(y=y, sr=sample_rate, units="time")
    loudness = float(np.mean(librosa.feature.rms(y=y)[0]))
    duration = max(1.0, librosa.get_duration(y=y, sr=sample_rate))
    return len(onsets) / duration, loudness


def analyse(path):
    y, sample_rate = librosa.load(str(path), mono=True)
    duration_ms = int(librosa.get_duration(y=y, sr=sample_rate) * 1000)

    tempo, frames = librosa.beat.beat_track(y=y, sr=sample_rate, units="frames")
    # librosa 0.10 hands tempo back as an array even for a single estimate
    tempo = float(np.atleast_1d(tempo)[0])
    beat_times = librosa.frames_to_time(frames, sr=sample_rate)
    beats = [int(round(t * 1000)) for t in beat_times]

    if len(beats) < 2:
        raise SystemExit(f"{path.name}: no usable beat track")

    safe_out = min(duration_ms - TAIL_MARGIN_MS, MAX_CLIP_MS)
    # Keep one beat past the cut-off so a shot can end exactly on it
    beats = [b for b in beats if b <= safe_out + 2000]

    return {
        "track_id": path.stem,
        "bpm": round(tempo, 2),
        "beats": beats,
        "sections": energy_sections(y, sample_rate, safe_out),
        "safe_out_ms": int(safe_out),
    }


def main():
    # The untranscoded originals when they are there: soundfile reads them
    # directly, where Opus sends librosa down a deprecated audioread path,
    # and the beats are in the same places either way
    sources = MEDIA / ".sources"
    directory = sources if sources.is_dir() and any(sources.iterdir()) else MEDIA

    tracks = sorted(p for p in directory.iterdir() if p.suffix in AUDIO_SUFFIXES)
    if not tracks:
        print(f"no audio in {directory}; nothing to analyse")
        return 0

    print(f"{'track':16s} {'bpm':>7s} {'onset/s':>8s} {'loud':>7s}  {'beats':>6s}")
    weak = []

    for path in tracks:
        grid = analyse(path)
        # Always beside the audio the app ships, whichever file was read
        target = MEDIA / (path.stem + ".json")
        target.write_text(json.dumps(grid, indent=2) + "\n", encoding="utf-8")

        onsets, loudness = character(path)
        print(f"{path.stem:16s} {grid['bpm']:7.1f} {onsets:8.2f} {loudness:7.4f} "
              f" {len(grid['beats']):6d}")

        if loudness < QUIET or onsets < SPARSE:
            weak.append((path.stem, onsets, loudness))

    # The lesson from the first four, made into something the tool says out
    # loud. Two of them were picked on tempo, which said nothing about
    # whether there was any music there: one was four times quieter than the
    # rest and played like a clip in slow motion.
    for name, onsets, loudness in weak:
        reasons = []
        if loudness < QUIET:
            reasons.append(f"quiet ({loudness:.3f}, others sit near 0.16)")
        if onsets < SPARSE:
            reasons.append(f"sparse ({onsets:.2f} onsets/s)")
        print(f"\n  {name}: {' and '.join(reasons)}."
              f"\n  A clip cut to this will feel slower than its tempo says.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
