#!/usr/bin/env bash
# Compiles every C++ file in src/ far enough to catch syntax and signature
# errors, without the Sailfish SDK or the cross-compiled OpenCV minimal.
#
# The unit tests build only the OpenCV-free storage layer, on purpose, so
# nothing there ever compiles facepipeline.cpp or the vision classes. This
# does, against Ubuntu's OpenCV. It is a gate, not a build: no linking, and
# the resulting objects are thrown away.
set -u

CFLAGS=$(pkg-config --cflags \
    Qt5Core Qt5Gui Qt5Qml Qt5Quick Qt5Sql Qt5Concurrent opencv4)

status=0
checked=0

for file in src/*.cpp; do
    # Needs sailfishapp.h, which exists only inside the Sailfish SDK
    if [ "$file" = "src/harbour-nami.cpp" ]; then
        continue
    fi

    if g++ -fsyntax-only -std=c++14 -fPIC $CFLAGS -Isrc "$file"; then
        checked=$((checked + 1))
    else
        echo "FAILED: $file"
        status=1
    fi
done

if [ $status -eq 0 ]; then
    echo "syntax check passed on $checked files"
fi

exit $status
