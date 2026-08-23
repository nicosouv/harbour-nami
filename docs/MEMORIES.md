# Memories 0.9.0

Design note for the memories rework. Decisions taken 2026-08-22.

Today a "memory" is not an object: `MemoriesPage.qml` recomputes everything
in JS on every opening, looping over all people x all their photos, and the
only trigger is "N years ago". It has no title, no cover, no identity, so
nothing can point at it: not a home banner, not a video, not an edit.

0.9.0 turns a memory into a stored entity, restructures the home around it,
and adds an automatic clip that plays in the app. 0.9.1 writes that clip to
disk as an mp4.

## Scope split

- **0.9.0**: data model, recipes, home restructure, in-app clip player,
  four styles, bundled tracks, basic editing. No file is written.
- **0.9.1**: offline renderer, mp4 export, share.

The split exists so the branch stays testable on device from week one. Both
halves consume the same edit decision list (below), so the export reuses the
0.9.0 work instead of duplicating it.

## Data model

Two new tables, migrated in `FaceDatabase::createTables()`.

Two tables, created in `FaceDatabase::initializeSchema()` (done in 0.9.0).

```sql
CREATE TABLE memories (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    kind         TEXT NOT NULL,      -- anniversary|trip|event|person|duo|month
    source_key   TEXT NOT NULL,      -- "2023" | trip_id | "yyyy-MM-dd" | person_id
    title        TEXT NOT NULL,
    subtitle     TEXT,
    cover_photo  TEXT,
    style        TEXT NOT NULL DEFAULT 'sentimental',
    track_id     TEXT,
    sort_date    TEXT,               -- what it is about, not when it was made
    score        REAL DEFAULT 0.0,   -- recipe confidence, ranks the home hero
    dismissed    INTEGER DEFAULT 0,
    edited       INTEGER DEFAULT 0,
    created_at   TEXT DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(kind, source_key)
);

CREATE TABLE memory_photos (
    memory_id  INTEGER NOT NULL REFERENCES memories(id) ON DELETE CASCADE,
    photo_id   INTEGER NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
    position   INTEGER NOT NULL,
    included   INTEGER DEFAULT 1,
    PRIMARY KEY (memory_id, photo_id)
);
```

`UNIQUE(kind, source_key)` is what makes regeneration idempotent: a recipe
re-run updates its own memory instead of piling up duplicates.

Three fields draw the line between what a recipe owns and what the user owns:

- `style`, `track_id`, `cover_photo` and `dismissed` are the user's. A
  regeneration refreshes `title`, `subtitle`, `sort_date`, `score` and the
  photo set around them, and never touches them.
- `edited` is set the moment the user renames, reorders or excludes. From
  then on the recipe skips the memory entirely.
- `dismissed` hides a memory without deleting it, and the row staying in
  place is what stops the recipe from resurrecting it. This is what the UI
  should offer rather than an outright delete.

`included = 0` keeps an excluded photo's row so the exclusion can be undone.
Reads resolve `cover_photo` to the first included photo when nothing is
pinned, so no caller has to know about the fallback.

0.9.1 adds a `video_path` column for the exported clip.

## Recipes

`MemoryGenerator` (done in 0.9.0) runs at most once a day, keyed on
`memories_generated_on` in `settings`. Six recipes:

| kind | source_key | trigger | stored title |
| --- | --- | --- | --- |
| `anniversary` | the year | photos within 10 days of today's date, in earlier years | `2023` |
| `trip` | trip id | a row in `trips` with enough photos | the trip name |
| `event` | `yyyy-MM-dd` | a day with 12+ photos, not in a trip, not hidden | `2025-09-20` |
| `person` | person id | 12+ photos in the last 12 months | the person's name |
| `duo` | `a-b` | two people on 8+ photos together | `Marie & Paul` |
| `month` | `yyyy-MM` | the month that just ended | `2026-05` |

Each asks the database one question (`photosOnMonthDays`, `photosOnDates`,
`busiestDays`, `photosOfPerson`, `peopleSeenTogether`, `photosOfPeoplePair`,
`photosInMonth`). None of them walks the gallery in C++: the pages that group
photos in JavaScript already loop over every person's every photo on each
opening, and this must not become that.

Guards: at least 5 photos or no memory; at most 3 memories per run for the
recipes that scale with the gallery (event, person, duo); days already
grouped into a trip belong to the trip, and days the user hid from the
Events list stay hidden here.

### Titles are stored untranslated

A memory's title lands in the database as raw material, never as a rendered
phrase: `2023`, `2026-05`, or the trip/person name where the title genuinely
is user data. QML translates the computed ones at display time.

Storing "Il y a 3 ans" instead would need translation machinery on the C++
side that this project does not have, and would freeze the title in whatever
language was active the day the recipe ran. The app has an in-app language
override, so that is not hypothetical: switching it would leave every
existing memory speaking the previous language.

The same applies to dates, which is why `subtitle` stays empty for now.
`kind`, `source_key`, `timestamp` and `photo_count` are enough for QML to
build every line it shows.

### Choosing which photos make the clip

Capped at 40, and the selection is what makes a two-week trip feel like two
weeks:

1. **Bursts collapse.** Frames within 3 seconds of each other are one moment;
   the one with the most known faces survives. Six near-identical frames make
   a clip stutter in place.
2. **The range is sliced into 40 buckets** and photos are taken one per
   bucket, round after round, until the clip is full.

Round-robin rather than proportional sampling is deliberate. A single day
holding 100 photos out of 140 would otherwise fill three quarters of the
clip: it has more to show than a quiet day, not thirty times more. Within a
bucket, photos with identified faces come first.

### Default styles

Assigned by what the memory is about, and only a default (the user's choice
is never overwritten): people-shaped recipes (anniversary, person, duo) open
on `sentimental`, activity-shaped ones (trip, event) on `energetic`, and the
monthly round-up is a survey rather than a story, so it gets `bauhaus`.

## The clip engine: one EDL, two consumers

Done in 0.9.0. `MemoryComposer` (C++, pure, unit-testable, no pixels touched)
maps

```
(photos, style, track beat grid) -> [ Shot { photo_path, t_start_ms, t_dur_ms,
                                             transition, rect_from, rect_to,
                                             grade } ... ]
```

Two consumers read the same list:

1. **Preview**: the QML `MemoryPlayer` component (done in 0.9.0). Everything
   on screen derives from one number, `positionMs`: which shot is up, how far
   its camera move has travelled, how far a transition has got. None of it is
   state that can drift out of step with the music, and it is the same thing
   the renderer will do frame by frame.

   The crop is done by oversizing the image behind a clip and sliding it,
   not by scaling the item: the composer's rectangles are normalized
   coordinates in the source photo and this maps them straight across. A
   rectangle half the width means an image drawn at twice the viewport width.

   `QtMultimedia` is imported in `components/ClipAudio.qml` and nowhere else,
   and that file is reached through a `Loader`. An import that cannot resolve
   takes down the component declaring it, so keeping it in a leaf means a
   device without the multimedia plugin plays clips silently instead of
   failing to open the page.
2. **Renderer** (0.9.1): the same shots rendered frame by frame with OpenCV,
   which is already linked, then encoded.

What you preview is what you export, because it is literally the same data.

### Beat sync

No audio analysis on the device. Tracks ship with the app, so the beat grid is
precomputed at build time by `scripts/analyze_track.py` (librosa) and committed
next to the audio:

```json
{ "bpm": 92.0, "first_beat_ms": 340, "beats": [340, 992, ...],
  "sections": [{ "t": 340, "energy": 0.2 }, { "t": 21400, "energy": 0.8 }],
  "safe_out_ms": 62000 }
```

The composer cuts on beat multiples and stops before `safe_out_ms`, so a clip
never runs past the fade. Zero DSP dependency in the RPM.

Until the tracks land, `BeatGrid::even()` produces a regular grid at the
style's own fallback tempo (88, 128, 96 and 112 bpm). The whole feature
therefore works before the music does, and the four styles still cut at
visibly different rates. See `media/README.md` for the file layout.

### Face-aware framing

The `faces` table already stores bounding boxes, and `FaceImageProvider`
already crops from them. The Ken Burns move therefore never crops a head, and
can aim: wide start, resolve onto the face of the memory's person. This is the
differentiator, and the data for it already exists.

How much freedom there is depends entirely on the shapes involved, and it is
worth knowing which way round. A 4:3 photo into a 16:9 clip keeps 94% of the
width and 75% of the height, so the framing decision is almost purely
vertical: whether the crop takes the top of someone's head. A portrait photo
into the same clip keeps only 42% of the height, and there the choice of
which 42% is the entire shot.

### What the composer guarantees

The tests are the specification, and these are the parts worth stating:

- Shots run back to back with no gap and no overlap, and every cut, in and
  out, lands on a beat.
- The clip ends before the track does.
- More photos than the track can hold are sampled evenly across the memory,
  never truncated. The generator already spread them over the whole time
  range and truncating here would undo that.
- The first shot cuts in rather than dissolving from nothing.
- Crops carry the output aspect and never leave the photo.
- The same input always composes the same edit. The player and the renderer
  each compose their own copy; if those could differ, the preview would be a
  promise the export does not keep and nothing in either would notice.

## Styles

A style is a parameter table, not code:

| style | beats/shot | transition | zoom | grade | ratio |
| --- | --- | --- | --- | --- | --- |
| sentimental | 4 | dissolve 600ms | 1.00 -> 1.06 | warm, soft vignette | 16:9 |
| energetic | 1 (0.5 on high-energy sections) | hard cut | punch-in 1.12 | contrast + | 16:9 |
| polaroid | 2 | drop + rotate ±2° | 1.00 -> 1.04 | grain, amber | 4:3 on paper |
| bauhaus | 2 | geometric wipe, primary flat | none, strict grid | neutral | 16:9 |

`bauhaus` is the signature style: off-white or black ground, photo placed on a
strict grid, cuts on the beat, a red/blue/yellow flat sweeping the transition,
grotesque type on the title card. `polaroid` is the deliberate departure, and
it reuses the scatter aesthetic `MemoryDetailPage` already has.

## Music

CC0 only. CC-BY would force an attribution into a clip the user posts publicly,
which is friction and a risk. Four tracks, 60-90s, Opus, roughly 1 MB each,
listed in `MUSIC-LICENSES.md` with source, author, licence and sha256. Muting
the clip must be possible.

Tracks are supplied by the project owner; the build pipeline (beat grid,
manifest, install rules) is independent of which files land there.

## Home restructure

The home becomes a "Today" feed and the people list moves to its own page,
reached with `pageStack.pushAttached()` (the native Sailfish idiom: swipe left
from the home). Done in 0.9.0, except the two strips.

```
HomePage.qml            (new, the initial page)
  hero memory card      full-bleed 16:9, title, one date line; absent if none
  events strip          horizontal, edge-to-edge, no section title, hidden < 2
  people row            top N by recency, most recently photographed first
  pulldown              About, Settings, Memories, Events, Identify, Scan

PeoplePage.qml          (the old MainPage, renamed)
  search, sort chips, list/grid layouts, context menus
  pulldown              Identify, Scan only
```

The pulldown split is the rule for the whole app: the home carries the app's
own navigation, and a page carries only what acts on what it shows. Repeating
About and Settings on every page is how a menu grows to eight items nobody
reads.

The empty-library blurb moved to the home with it. It explains what the app
is, and the home is where a first launch lands.

Three known traps:

- A horizontal `ListView` inside a vertical `SilicaFlickable` fights for the
  flick. Set `flickableDirection: Flickable.HorizontalFlick`.
- `ListView.leftMargin` does not exist on every Qt version this ships
  against; use `header`/`footer` spacer items for the page margins.
- No `ContextMenu` inside a `GridView`: it cannot reflow and draws over the
  neighbouring cells (see the note in `PeoplePage.qml`). Use `ActionSheetPage`.

### One feed, not two

The home shows the best memory full width and the rest in a strip below.
There is no separate "recent events" feed: trips and busy days are already
memories, and a second path answering the same question would drift from the
first. What the strip holds is simply everything the recipes found that is
not the hero.

The hero decodes its cover from the original file at display size rather
than through `image://faces/thumb`, whose master is capped at 512px. It is
the one image on the page big enough for that cap to show.

### Renaming a page rewrites its translations

Qt keys translations by context, and for QML the context is the file's base
name. `MainPage.qml` becoming `PeoplePage.qml` orphaned all 31 of its
messages in seven locales at once, silently: the app would have fallen back
to English on that page with nothing failing to build.

So the `MainPage` context was split in two, by hand, across all eight `.ts`
files: the strings `HomePage.qml` uses moved to a `HomePage` context, the
rest to `PeoplePage`, and only `People` was genuinely new.

`scripts/check_translations.py` now catches this, and runs in the static CI
lane. It compares every `qsTr()` in the QML against the catalogues in both
directions: strings with no entry, and entries no file asks for any more.
Writing it turned up two drifts that predated this branch.

## Memory page and editing

`MemoryDetailPage` gains the player at the top, the photo strip below
(reorder, exclude), then style and track chips. Pull-down: rename, choose
cover, regenerate, delete, and in 0.9.1 "Save video".

Editing stays deliberately basic: include/exclude, order, style, track,
length, title. No timeline.

## Export (0.9.1)

The only real technical risk, so it is isolated behind an `Encoder` interface.

- ffmpeg minimal (LGPL) bundled in `%{_libdir}/harbour-nami`, the precedent
  set by the minimal OpenCV build already shipping there, plus openh264 (BSD)
  for real H.264/AAC in mp4. Roughly 5 MB added to the RPM.
- Target 1280x720 at 30 fps, around 8 Mbps. A 40s clip is 1200 frames; expect
  2 to 4x real time on device, so the render runs in the background with
  progress and never blocks the UI.
- Output to `~/Videos/Nami/`, which requires adding `Videos` to the
  `X-Sailjail` permissions in `harbour-nami.desktop` (currently
  `Pictures;Documents;RemovableMedia;Contacts;Privileged`).

## Build and packaging changes

- `Qt5Multimedia` in `PkgConfigBR`, `qt5-qtdeclarative-import-multimedia` in
  `Requires` (audio playback for the preview).
- Tracks, beat grids and style definitions installed under
  `share/harbour-nami/media`.
- `Videos` sailjail permission (0.9.1).
- New translatable strings: style names, memory titles, player controls.
  Titles built from templates so plurals stay correct in all seven locales.
