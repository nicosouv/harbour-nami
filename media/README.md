# Clip music

```
docker compose run --rm beats
```

fetches the four originals, transcodes them to mono 44.1 kHz Vorbis trimmed
to 92 seconds, and writes each one's beat grid beside it. The transcodes and the
grids are committed; the originals, under `.sources/`, are not.

The app runs without any of it: a style whose audio is missing plays silently
against an even grid at its own fallback tempo, which is enough to see the
edit working.

## What goes here

Two files per track, named after the style that opens on it
(`sentimental`, `energetic`, `polaroid`, `bauhaus`):

```
sentimental.ogg      the audio (.opus, .ogg, .mp3 or .m4a)
sentimental.json     its beat grid
```

## The beat grid

Computed off the device, once, because the tracks ship with the app and
their rhythm is therefore known in advance. Read from the untranscoded
original when it is there: soundfile handles Vorbis directly, where Opus
sends librosa down a deprecated path, and the beats are in the same places
either way. Nothing on the phone does any
signal processing and the RPM carries no DSP library.

```json
{
  "track_id": "sentimental",
  "bpm": 92.0,
  "beats": [340, 992, 1644],
  "sections": [{ "t": 340, "energy": 0.2 }, { "t": 21400, "energy": 0.8 }],
  "safe_out_ms": 62000
}
```

- `beats` are milliseconds from the start of the file. Every cut lands on
  one of these, which is the whole point of shipping them.
- `sections` mark where the track's energy changes, as **where the track sits
  between its own quietest and loudest moment**, not as an absolute loudness.
  The energetic style halves its shots above 0.6, and that question only
  means anything relative to the track being asked about. Measured
  absolutely, the answer was never yes on any of the four tracks here: how
  hot a recording was mastered decided it, rather than whether the music
  lifts. A track with no dynamics reads as 0 throughout rather than having
  its noise floor stretched into a false crescendo.
- Sections stop at `safe_out_ms`. Past there is dead weight in a file that
  gets committed.
- `safe_out_ms` is where a clip has to have ended. Past it the track is
  fading out, and a shot still running looks like a mistake.

Beats out of order are sorted rather than trusted, and a grid with fewer than
two beats is treated as absent.

## Why Vorbis and not Opus

Opus always decodes at 48 kHz; it has no other mode. These sources are
44.1 kHz, and on a device whose PulseAudio sink is sitting at 44.1 the
mismatch plays back 8.8% slow, so the track sounds stretched. Intermittently,
because the sink's rate depends on whatever opened audio first. Encoding at
the source's own rate removes the negotiation, and `libgstvorbis` has been on
every Sailfish device there has ever been.

## Licensing

CC0 only. CC-BY would force an attribution into a clip the user posts
publicly, which is friction and a risk they did not sign up for.

Sources, authors, licences and checksums are in `MUSIC-LICENSES.md` at the
repository root, along with what still needs doing to the current four.

## What the tracks produce today

40 photos, composed against the real grids:

| Style | Tempo | Shots | Length | Per shot |
| --- | --- | --- | --- | --- |
| sentimental | 69.8 bpm | 25 | 86s | 3.4s |
| energetic | 152.0 bpm | 40 | 32s | 0.8s |
| polaroid | 89.1 bpm | 40 | 53s | 1.3s |
| bauhaus | 129.2 bpm | 40 | 37s | 0.9s |

One thing that measurement turned up: the energetic clip ends at 32 seconds,
and its track's loud part starts at 36. The composer always opens on the
first beat of the file, so a short clip against a long track plays the intro
and stops before the music arrives. Choosing a start point by energy, the
way the end already respects `safe_out_ms`, is the fix, and it is a decision
about how clips should feel rather than a bug to patch in passing.
