# Tests

Three layers, from cheapest to heaviest.

## `scripts/check_qml.py` — static QML checks

Runs anywhere, no Qt. Every rule comes from a bug that shipped:

- **`ListModel.get()` inside a property binding** — the binding keeps a guard
  on the transient wrapper `get()` returns; the model frees it on its own
  schedule, and the binding's destructor then calls a virtual on freed memory.
  Aborts the process with "pure virtual method called". Crashed every face
  identification in 0.8.3.
- **Unguarded `setLineDash`** — Qt Quick's Canvas has no such method; the call
  throws and takes the whole paint handler with it, so the canvas renders
  blank. Left the trip map an empty sheet of paper in 0.8.3.
- **`clear()` on a model handed to another component** — destroys every
  delegate at once, including those of a dialog still bound to it.

## `scripts/check_translations.py` — catalogues against the sources

`lupdate` is not run locally (the `.ts` files are hand-edited), so nothing
otherwise notices when the two drift, and the drift is silent: a string with
no entry, or an entry under a context no file uses any more, builds and ships
perfectly and simply comes out in English.

Renaming a page is the sharp edge. Qt keys translations by context, and for
QML the context is the file's base name, so `MainPage.qml` becoming
`PeoplePage.qml` orphaned all 31 of its messages in seven locales at once.

It compares both directions, and skips `harbour-nami-en.ts`, which carries
only the handful of strings that read differently in the UI than in the code.

## `tests/js/run.js` — JavaScript unit tests

`node tests/js/run.js`. The QML JS libraries are plain modules behind a
`.pragma library` line, so node loads them directly. Covers the geo maths and
the integrity of the bundled coastline dataset (closed rings, ordered by area,
valid coordinates) that `TripRouteMap` relies on to fill land.

## C++ unit tests

Qt5 and OpenSSL are the only dependencies - no OpenCV, no ML models, no
cross-compiler, no device:

```
cmake -S tests -B build-tests
cmake --build build-tests
QT_QPA_PLATFORM=offscreen ctest --test-dir build-tests --output-on-failure
```

Or, without installing Qt on the host, in the same Ubuntu the CI lane uses:

```
docker compose run --rm tests
```

`tst_facedatabase` covers the schema, the backup format (including that
contact links stay out of it), the import being additive and skipping photos
that no longer exist, and the helpers behind identification suggestions.

`tst_backupcrypto` covers the passphrase encryption both ways: a good
passphrase round-trips a multi-megabyte payload, and a wrong passphrase,
flipped ciphertext bit, tampered tag or truncated payload all fail instead of
returning something that looks like data.

`tst_memorycomposer` covers the edit decision list: cuts landing on beats,
the clip ending before the track, photos sampled across the whole memory
rather than truncated, crops carrying the output aspect and staying inside
the photo, the camera resolving onto the faces, and the same input always
composing the same edit.

Two of its assertions started out too weak to be worth having. Checking that
a crop contains a face's *centre* passes even when the framing ignores faces
completely, because a 4:3 photo cropped to 16:9 keeps 94% of its width and
contains almost any centre. They now check the whole face box, and the
two-face case uses a portrait photo, where a 16:9 crop keeps 42% of the
height and the framing actually has a choice to get wrong.

`tst_memorygenerator` covers the six recipes against small explicit
galleries, with the date injected rather than read from the clock: an
anniversary recipe tested against "today" would pass in August and fail in
December. It also pins the two judgement calls, that titles are stored
untranslated and that a long memory is spread across its whole range instead
of collapsing onto its busiest day.

`tst_memories` covers the memories storage: regeneration being idempotent,
the fields a recipe may refresh versus the ones that belong to the user, the
cover falling back to the first photo, exclusions being undoable, reordering,
and a pruned photo dropping out of its memories.

Keeping these layers free of OpenCV is deliberate - `FaceEmbedding` lives in
its own `src/faceembedding.h` precisely so the storage layer can be tested
without the vision stack.

## `tests/syntax-check.sh` — compile gate for the rest of `src/`

The consequence of that split is that nothing above ever compiles
`facepipeline.cpp` or the vision classes. This does, against Ubuntu's OpenCV
instead of the cross-compiled minimal build, so a signature error surfaces
without the Sailfish SDK:

```
docker compose run --rm syntax
```

It stops at `-fsyntax-only`: no linking, no RPM. `src/harbour-nami.cpp` is
skipped, since `sailfishapp.h` exists only inside the SDK.

## `tst_pipeline` — the recognition engine end to end

```
docker compose run --rm pipeline
```

Real JPEGs in, detection, alignment, embedding, storage, matching. The only
test here that would have caught the accuracy bugs the P0 audit found, since
none of them threw: channels in the wrong order, no landmark alignment, an
aspect ratio distorted by a non-uniform resize. All three just made
recognition quietly worse.

It is also the only guard on the thresholds. `AUTO_MATCH_THRESHOLD` and
`GROUPING_THRESHOLD` are numbers somebody picked; here they meet two faces
that really are the same person, three years apart, and two that really are
not. Measured: 0.85 for the same person, 0.61-0.63 for different ones.

Off by default (`-DWITH_PIPELINE_TESTS=ON`), because it needs what the rest
of the suite deliberately avoids:

- **OpenCV >= 4.8.** The YuNet 2023mar model uses layers the 4.6 DNN importer
  rejects outright, and 4.6 is what Ubuntu 24.04 ships, hence the separate
  Debian image in `tests/Dockerfile.pipeline`.
- **The ML models**, via `scripts/download_models_for_build.sh`.
- **Three reference portraits**, via `tests/fixtures/download_faces.sh`.
  Public domain NASA studio portraits, checksum pinned and gitignored: a
  face recognition project should not carry photos of people in its history.
  Two are the same astronaut in 2013 and 2016 (different hair, clothing,
  pose); the third is a different astronaut of similar build and colouring,
  so rejecting her is not free.

The compose service runs both downloads first; they no-op once the checksums
match.

## Not covered

**The interface.** `Sailfish.Silica` is closed Jolla code and cannot be
installed on a build machine, so no test can instantiate a `Page`, a
`PageHeader` or read `Theme`. A Silica stub was considered and rejected: the
bugs `check_qml.py` exists for (a `ContextMenu` inside a `GridView`,
`autoTransform` under a QtQuick 2.0 import, `ListModel.get()` in a binding)
are all behaviours of the real Silica and the real QML engine, and a stub
would have caught none of them while suggesting otherwise.

**A channel-order regression applied consistently.** Swapping BGR and RGB on
both sides of a comparison moves the same-person score from 0.85 to 0.81 and
leaves the separation from different people almost unchanged, so no threshold
assertion sees it. Catching it would take a golden embedding vector pinned to
a tolerance, which is not stable enough across OpenCV versions and
architectures to be worth the flakiness.

**The thumbnail cache budget.** `trimCache` only runs against a 128 MB
constant, and filling that in a test costs more than the coverage is worth.
