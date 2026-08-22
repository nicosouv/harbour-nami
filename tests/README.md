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

## Not covered

There is no end-to-end test: nothing exercises detection, recognition and the
UI together, and nothing drives the real interface. See the notes in the pull
request discussion for what that would take.
