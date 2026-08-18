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

## `tests/tst_facedatabase.cpp` — C++ unit tests

Needs Qt and OpenCV headers, so it runs in the Sailfish SDK container:

```
cmake -B build-tests -DBUILD_TESTS=ON
cmake --build build-tests --target tst_facedatabase
QT_QPA_PLATFORM=offscreen ctest --test-dir build-tests --output-on-failure
```

Covers the schema, the backup format (including that contact links stay out
of it), the import being additive and skipping missing photos, and the
helpers behind identification suggestions.
