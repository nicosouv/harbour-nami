# Roadmap

Based on the July 2026 code audit. Ordered by priority: P0 fixes the core
recognition quality problem, then performance, security, UI/UX.

## P0 — Recognition accuracy and learning (why it "doesn't work well")

Status: items 1–8 implemented (2026-07-04). Stored embeddings are versioned
(`EMBEDDING_VERSION`); on first scan after the upgrade all face data is
cleared and recomputed. Remaining: item 9 (person merge) and threshold
calibration on real photos.

### Accuracy killers in the current pipeline

1. ~~**No face alignment**~~ Done: `alignFace()` warps the face to the
   standard ArcFace 112x112 template with a closed-form least-squares
   similarity transform from the 5 YuNet landmarks (bbox-crop fallback).
2. ~~**Channel order bug**~~ Done: both `qImageToCvMat` helpers now produce
   BGR (OpenCV convention) and the recognizer converts BGR→RGB once.
3. ~~**Aspect-ratio distortion**~~ Done: detection uses a uniform downscale
   with `setInputSize` per image; recognition uses the aligned warp.
4. ~~**Duplicate faces on re-scan**~~ Done: scans are incremental
   (processed photos skipped); `scanGallery(path, recursive, forceRescan)`
   deletes a photo's faces before re-detecting when forced.

### Why it "doesn't learn"

5. ~~**Centroid matching poisons itself**~~ Done: `getAverageEmbedding`
   builds the person prototype from user-verified faces only (falls back to
   all faces when none verified). Top-k nearest-neighbour matching over
   individual embeddings is still worth exploring later.
6. ~~**User corrections are not persistent**~~ Done: `negative_matches`
   table; `removeFaceFromPerson` records the rejection and auto-matching
   skips rejected (face, person) pairs.
7. ~~**"Skip" is not persistent**~~ Done: `ignored` flag on faces +
   `ignoreFace()`; IdentifyFacesPage skip now marks the face ignored and it
   no longer reappears in the identify flow, clustering or stats.
8. ~~**Thresholds**~~ Partially done: auto-assign raised to 0.75 (rescaled
   similarity) and centralized as constants (`AUTO_MATCH_THRESHOLD`,
   `GROUPING_THRESHOLD`); detector default confidence raised from 0.3 to 0.8
   (YuNet real faces score > 0.9). Still to do: calibrate on a real gallery
   after the alignment change.
9. ~~**Person merge missing**~~ Done: `mergePersons(from, into)` reassigns
   faces, carries rejections over and deletes the duplicate; exposed in the
   people list context menu ("Merge into...").

## P1 — Performance

Status: all done (2026-07-04) except the face thumbnail cache.

- ~~**Move the pipeline off the UI thread**~~ Done: decode + detection +
  embedding run on a QtConcurrent worker (one photo in flight); only the SQL
  commit runs on the main thread (QSqlDatabase thread affinity).
- ~~**Cache person prototypes**~~ Done: in-memory cache invalidated on
  identify/remove/merge/delete; no longer O(persons x faces) DB reads per
  detected face.
- ~~**SQLite tuning**~~ Done: one transaction per photo commit;
  `journal_mode=WAL`, `synchronous=NORMAL`, `foreign_keys=ON` at open.
- ~~**Logging**~~ Done: verbose logs moved to the `nami.pipeline` logging
  category, disabled by default (enable with
  `QT_LOGGING_RULES="nami.pipeline.debug=true"`).
- ~~**Single QImage→Mat conversion**~~ Done (once per photo).
- ~~**Incremental scan**~~ Done (P0.4).
- **Face thumbnail cache** on disk for lists (avoid decoding full-size photos
  to render a 100 px avatar).

## P2 — Security and privacy

- **Biometric data at rest**: embeddings + names live in an unencrypted
  SQLite in `~/.local/share`. Done: `chmod 600` on the DB and WAL/SHM files.
  Still open: evaluate SQLCipher. Embeddings are GDPR Art. 9 biometric data.
- **Log hygiene**: file paths, person ids and match scores are logged to the
  systemd journal. Strip or gate behind the logging category (same work as P1).
- ~~**Model supply chain**~~ Done: switched recognition to the official
  OpenCV Zoo SFace model via `cv::FaceRecognizerSF` (alignment and
  preprocessing exactly as trained, official cosine threshold 0.363); both
  model downloads are now SHA256-pinned. Bonus discovered during the audit:
  the old "MobileFaceNet" from the personal HuggingFace repo was actually a
  136 MB ResNet — the RPM shrinks from ~138 MB to ~45 MB and ONNX Runtime is
  dropped entirely (OpenCV DNN runs the model).
- **GDPR claims vs reality**: the RPM description advertises "GDPR compliant
  (data export)" but export is a "coming soon" toast. Implement
  `exportPersonData`/full export to JSON. Done already: `VACUUM` after
  `deleteAllData` so deleted embeddings don't linger in free pages.
- **CI**: pin GitHub Actions by commit SHA, drop `chmod -R 777`.

## P3 — UI / UX / usability

- **i18n is currently dead**: CMake installs `*.qm` but nothing runs
  `lrelease`, and `main.cpp` never loads a `QTranslator` (hand-rolled
  `QQuickView` instead of `libsailfishapp`). The app is English-only despite
  the 6 `.ts` files. Fix: `qt5_add_translation` in CMake + load translators
  (or migrate to `SailfishApp::main`), resync `.ts` files (es/fi/it are stale:
  59 lines vs 398 for fr, with strings that no longer exist).
- **ScanningPage**:
  - ~~No way to cancel a running scan~~ Done: the button cancels while
    scanning, and the page handles `scanFailed` (it used to stay stuck after
    a cancel).
  - Hardcoded hex colors (`#0a192f`, `#64ffda`…) break light ambiences and
    Silica conventions — use `Theme.*` colors.
- **SettingsPage is mostly placebo**:
  - "Recognition quality" combo and "Auto-scan" switch do nothing and are not
    persisted. Wire them (ConfigurationValue/dconf → detector threshold,
    match threshold) or remove them.
  - ~~"Storage used" always 0 B~~ Done: `getStatistics()` now reports the
    database file size.
  - "Export data" pushes `../components/NotificationBanner.qml` which does not
    exist → runtime error. Point to a real export flow.
- **Real face thumbnails**: people lists show a generic contact icon; crop and
  cache the best verified face per person for MainPage/PersonDetail/selection
  dialogs.
- **photo_count is wrong**: `getAllPeople`/`getPerson` count faces, not
  photos (`COUNT(f.id)` — a photo with the same person 3 times counts 3).
  Use `COUNT(DISTINCT f.photo_id)`.
- **CoverPage** shows static "0 people / 0 photos"; bind real stats and scan
  progress (cover action to cancel scan would be nice).
- **Scan source selection**: gallery path is hardcoded to `Pictures`; let the
  user pick folders and exclude e.g. `Screenshots`.
- **Person merge UI** (pairs with P0.9) and batch identify ("confirm all
  suggested matches for this person").
- **Dead code / drift cleanup**:
  - `qml/components/FaceRecognitionManager.qml`: stub with misleading
    "not implemented in C++" warnings for features that exist — remove.
  - Legacy `python/` implementation (only `python/models` is used by CMake).
  - CMake `QML_FILES` lists files that don't exist (PhotoGridPage,
    PhotoThumbnail, FaceThumbnail).
  - Version mismatch: `rpm/harbour-nami.yaml` says 0.2.4, CMake/spec say
    0.3.0 — the yaml is supposed to be the single source of truth.
- **EXIF date**: `date_taken` uses file mtime; read EXIF DateTimeOriginal so
  Memories/Events group correctly.
