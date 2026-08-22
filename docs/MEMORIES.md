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

A `MemoryGenerator` in C++ runs at most once a day (timestamp in `settings`,
throttled at startup, off the UI thread). It materialises up to ~12 memories:

| kind | trigger | title |
| --- | --- | --- |
| `anniversary` | photos within `memories_window_days` of today, previous years | "Il y a 3 ans" |
| `trip` | a row in `trips` with enough photos | the trip name |
| `event` | a date key with an unusual photo count | the formatted date |
| `person` | a person with enough photos in the last 12 months | the person's name |
| `duo` | two people co-occurring on enough photos | "Marie & Paul" |
| `month` | the month that just ended | "Juillet 2026" |

Photo selection per memory: cap at ~40, prefer photos with verified faces,
spread across the time range, drop near-duplicates by capture time proximity.
The existing `trips` / `trip_dates` / `event_covers` tables feed the trip and
event recipes directly.

## The clip engine: one EDL, two consumers

`MemoryComposer` (C++, pure, unit-testable, no pixels touched) maps

```
(photos, style, track beat grid) -> [ Shot { photo_path, t_start_ms, t_dur_ms,
                                             transition, rect_from, rect_to,
                                             grade } ... ]
```

Two consumers read the same list:

1. **Preview**: a QML `MemoryPlayer` component. `Image` elements driven by
   `NumberAnimation` on a source rect, audio through QtMultimedia. Real time,
   no encoding, and it is most of the perceived value.
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

The composer cuts on beat multiples and lands the last shot on a section
boundary, so a clip never ends mid-phrase. Zero DSP dependency in the RPM.

### Face-aware framing

The `faces` table already stores bounding boxes, and `FaceImageProvider`
already crops from them. The Ken Burns move therefore never crops a head, and
can aim: wide start, resolve onto the face of the memory's person. This is the
differentiator, and the data for it already exists.

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
from the home).

```
HomePage.qml            (new, becomes the initial page)
  hero memory card      full-bleed 16:9, title, one date line; absent if none
  events strip          horizontal, edge-to-edge, no section title, hidden < 2
  people row            top N by recency, "All people" leads to PeoplePage
  pulldown              About, Settings, Memories, Events, Identify, Scan

PeoplePage.qml          (the current MainPage, near verbatim)
  search, sort chips, list/grid layouts, context menus
```

Two known traps:

- A horizontal `ListView` inside a vertical `SilicaListView` fights for the
  flick. Set `flickableDirection: Flickable.HorizontalFlick` and
  `preventStealing` on the strip.
- No `ContextMenu` inside a `GridView`: it cannot reflow and draws over the
  neighbouring cells (see the note in `MainPage.qml`). Use `ActionSheetPage`.

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
