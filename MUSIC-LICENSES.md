# Clip music

Four tracks, one per clip style, chosen by ear and supplied by the project
owner. All four come from **Pixabay**, under the
[Pixabay Content License](https://pixabay.com/service/license-summary/).

| Style | Track |
| --- | --- |
| sentimental | [Warm Nostalgic Sentimental](https://pixabay.com/music/acoustic-group-warm-nostalgic-sentimental-music-471262/) |
| energetic | [Energetic](https://pixabay.com/music/upbeat-energetic-energetic-music-507828/) |
| polaroid | [Polaroid Lo-Fi](https://pixabay.com/music/beats-polaroid-lo-fi-515821/) |
| bauhaus | [Hi-Tech Loop](https://pixabay.com/music/corporate-hi-tech-loop-151203/) |

The links are also in the app's About page. Pixabay asks for no attribution;
they are there because somebody wrote this music and a clip made with it says
so nowhere else.

## What ships

The originals are not committed. `media/prepare_tracks.sh` transcodes
whatever is in `media/.sources/<style>.<ext>` into the `.ogg` files beside
it, which are committed and go into the package:

- **Mono, 44.1 kHz Vorbis**, trimmed to the 92 seconds a clip can reach.
  Not Opus: Opus only ever decodes at 48 kHz, and against a device sink
  sitting at 44.1 that plays back 8.8% slow, which sounds like a clip in
  slow motion.
- **Normalised to -16 LUFS** (EBU R128). Tracks arrive mastered at whatever
  level their author chose, and a quiet one does not merely sound quieter:
  switching style mid-preview jumped in volume, and the quietest of the
  first four was mistaken for a playback fault.
- About 2.9 MB across the four.

Nothing is fetched at runtime. The app declares no Internet permission and
never could.

## Replacing a track

Drop the new file at `media/.sources/<style>.<ext>` (wav, flac, aiff, m4a,
mp3, opus or ogg) and run `docker compose run --rm beats`. A style with no
source keeps whatever is committed, so replacing one does not disturb the
other three.

## What the analysis is for

Tempo decides how fast the clip cuts. It says nothing about whether there is
any music there, and picking on tempo alone is how a 152 bpm track that was
four times quieter than the others ended up on the energetic style and played
like slow motion.

`docker compose run --rm beats` therefore prints onset density and loudness
beside the tempo, and warns when a track is too sparse. It no longer warns
about loudness: the transcode normalises it, and what is left of the
difference is dynamic range, which is not a fault.

Ears still decide. The numbers only catch a pick that cannot work.

## On the licence

Not legal advice, and worth reading yourself. The two clauses that bear on
an app like this one:

- **Attribution is optional**, so nothing is imposed on someone who posts a
  clip made with Nami. That was the deciding requirement, and it is why
  CC-BY was ruled out early.
- **Content may not be sold or distributed "on a Standalone basis"**, which
  the terms define as "where no creative effort has been applied to the
  Content and it remains in substantially the same form as it exists on the
  Service".

A clip is the music cut to somebody's photographs, so that is plainly not
standalone. The files inside the package and inside this repository are
closer to the line: they are the tracks, trimmed and re-encoded, which is a
format change rather than creative effort. Bundling a soundtrack in an
application is the use Pixabay exists for, and the clause is aimed at
re-uploading content to stock sites or selling packs of it. The public
repository is the weaker of the two, since anyone can take the file from it.
