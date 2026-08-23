# Clip music

Empty on purpose: the tracks are supplied separately from the code, and the
app runs without them. A style whose audio has not landed plays silently
against an even grid at its own fallback tempo, which is enough to see the
edit working.

## What goes here

Two files per track, named after the style that opens on it
(`sentimental`, `energetic`, `polaroid`, `bauhaus`):

```
sentimental.opus     the audio (.opus, .ogg, .mp3 or .m4a)
sentimental.json     its beat grid
```

## The beat grid

Computed off the device, at build time, because the tracks ship with the app
and their rhythm is therefore known in advance. Nothing on the phone does any
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
- `sections` mark where the track's energy changes, 0 quiet to 1 loudest.
  The energetic style halves its shots above 0.6.
- `safe_out_ms` is where a clip has to have ended. Past it the track is
  fading out, and a shot still running looks like a mistake.

Beats out of order are sorted rather than trusted, and a grid with fewer than
two beats is treated as absent.

## Licensing

CC0 only. CC-BY would force an attribution into a clip the user posts
publicly, which is friction and a risk they did not sign up for.

Each track needs an entry in `MUSIC-LICENSES.md` at the repository root with
its source, author, licence and sha256.
