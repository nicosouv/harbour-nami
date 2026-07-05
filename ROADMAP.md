# Roadmap

Based on the July 2026 code audit. Ordered by priority: P0 fixes the core
recognition quality problem, then performance, security, UI/UX.

## Field-reported issues (v0.5.1 on device, 2026-07-04) — fixed in v0.6.0

1. ~~**"Identify faces" shows "could not load page"**~~ Done: the invalid
   `anchors[...]` bindings are gone; the page now shows the cropped face
   via the image provider instead of the photo + overlay.
2. ~~**Events and Memories always empty**~~ Done: `getPersonPhotos()` now
   exposes `timestamp` (epoch seconds) that both pages expect. Real capture
   dates still depend on the EXIF item below (file mtime resets on
   copy/sync).
3. ~~**Person avatars**~~ Done: new `FaceImageProvider`
   (`image://faces/crop?...`) crops the face bbox with 45% margin from the
   EXIF-oriented photo, disk-cached under `~/.cache/harbour-nami/faces/`
   (owner-only files, wiped by "Clear all data"), optional circular mask.
   Used on MainPage, ScanResultsPage, SelectPersonDialog and
   IdentifyFaceDialog (best face = verified first, then highest similarity,
   via `getPersonBestFace()`).
4. ~~**Face framing and highlighting in the identify flow**~~ Done: all
   face squares now show the provider's crop (correct framing with margin),
   and both identify flows have a "View in photo" action opening the new
   `FaceInPhotoPage` — full image with the target face framed and the rest
   dimmed, bbox scaled correctly this time (normalized bbox × painted size).

## P0 — Recognition accuracy and learning (why it "doesn't work well")

Status: all items implemented (2026-07-04). Stored embeddings are versioned
(`EMBEDDING_VERSION`); on first scan after the upgrade all face data is
cleared and recomputed. Remaining: threshold calibration on real photos.

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

5. ~~**Centroid matching poisons itself**~~ Done, twice: prototypes were
   first restricted to user-verified faces, then (0.7.0) replaced by
   **exemplar matching** — each person is represented by up to 5 verified
   embeddings and scored by the best similarity over them, which handles a
   person's different looks (glasses, age, lighting) better than a single
   averaged centroid.
6. ~~**User corrections are not persistent**~~ Done: `negative_matches`
   table; `removeFaceFromPerson` records the rejection and auto-matching
   skips rejected (face, person) pairs.
7. ~~**"Skip" is not persistent**~~ Done: `ignored` flag on faces +
   `ignoreFace()`; IdentifyFacesPage skip now marks the face ignored and it
   no longer reappears in the identify flow, clustering or stats.
8. ~~**Thresholds**~~ Partially done: auto-assign raised to 0.75 (rescaled
   similarity) and centralized as constants (`AUTO_MATCH_THRESHOLD`,
   `GROUPING_THRESHOLD`); detector default confidence raised from 0.3 to 0.8
   (YuNet real faces score > 0.9). The auto-match threshold is now
   user-tunable ("Recognition strictness" in Settings, persisted, 0.65-0.80,
   default 0.72), so calibration can happen on the real gallery.
9. ~~**Person merge missing**~~ Done: `mergePersons(from, into)` reassigns
   faces, carries rejections over and deletes the duplicate; exposed in the
   people list context menu ("Merge into...").

## P1 — Performance

Status: all done.

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
- ~~**Face thumbnail cache**~~ Done in v0.6.0 via `FaceImageProvider`
  (disk-cached crops).

## P2 — Security and privacy

- **Biometric data at rest**: embeddings + names live in an unencrypted
  SQLite in `~/.local/share`. Done: `chmod 600` on the DB and WAL/SHM files.
  SQLCipher evaluated and **not adopted** for now: it would require bundling
  a custom Qt SQL driver plugin, the key would have to live next to the data
  (no SFOS keystore API for apps), and the on-device threat is already
  mitigated by file permissions and device encryption. Revisit if Sailfish
  gains an app keystore.
- ~~**Log hygiene**~~ Done: all per-file/per-face messages (paths, ids,
  scores) are behind the `nami.pipeline` category, disabled by default;
  remaining default-on warnings carry no personal data.
- ~~**Model supply chain**~~ Done: switched recognition to the official
  OpenCV Zoo SFace model via `cv::FaceRecognizerSF` (alignment and
  preprocessing exactly as trained, official cosine threshold 0.363); both
  model downloads are now SHA256-pinned. Bonus discovered during the audit:
  the old "MobileFaceNet" from the personal HuggingFace repo was actually a
  136 MB ResNet — the RPM shrinks from ~138 MB to ~45 MB and ONNX Runtime is
  dropped entirely (OpenCV DNN runs the model).
- ~~**GDPR claims vs reality**~~ Done: `exportData()` writes a JSON export
  (people, faces, photo paths — no raw embeddings) to Documents with 600
  permissions, wired to the Settings button; `VACUUM` after `deleteAllData`.
- ~~**CI**: pin GitHub Actions by commit SHA~~ Done (SHAs with version
  comments). `chmod -R 777` is kept deliberately: the SDK container user
  must write into the runner-owned workdir.

## P3 — UI / UX / usability

- ~~**i18n is currently dead**~~ Done: `qt5_add_translation` compiles the
  `.ts` files and `main.cpp` loads the locale's `QTranslator`; all six `.ts`
  files regenerated from the QML sources with complete fr/de/it/es/fi
  translations (192 strings, plural forms included).
- **ScanningPage**:
  - ~~No way to cancel a running scan~~ Done: the button cancels while
    scanning, and the page handles `scanFailed` (it used to stay stuck after
    a cancel).
  - ~~Hardcoded hex colors~~ Done: `Theme.*` colors and a standard Silica
    button.
- ~~**SettingsPage is mostly placebo**~~ Done: the placebo quality/auto-scan
  controls are removed, "Storage used" shows the real DB size, and "Export
  data" performs the actual JSON export (the old button pushed a
  non-existent QML file → runtime error).
- ~~**Real face thumbnails**~~ Done in v0.6.0 (`FaceImageProvider` +
  `getPersonBestFace`).
- ~~**photo_count is wrong**~~ Done: `COUNT(DISTINCT f.photo_id)`.
- ~~**CoverPage**~~ Done: real stats, refreshed on activation and scan
  completion; shows scan progress while processing.
- ~~**Scan source selection**~~ Done: "Scan folder" in Settings
  (FolderPickerDialog), persisted in the settings table and used by the
  scan.
- ~~**Person merge UI**~~ Done (P0.9). ~~Batch identify~~ Done: "Confirm
  all matches" in the person page menu marks the auto-matched faces as
  verified (they then contribute to the person prototype).
- ~~**Dead code / drift cleanup**~~ Done: removed the stale
  `FaceRecognitionManager.qml` stub, the legacy `python/` implementation
  (only `python/models` remains, used by the build), the phantom CMake
  `QML_FILES` list, and versions are aligned across yaml/spec/CMake.
- ~~**EXIF date**~~ Done: minimal EXIF reader (`src/exifreader.cpp`) reads
  DateTimeOriginal (fallback DateTime, then mtime) so Memories/Events group
  by real capture dates. Already-scanned photos keep their old dates until
  a forced re-scan.
