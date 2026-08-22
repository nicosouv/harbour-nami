#!/usr/bin/env bash
# Downloads the reference portraits the pipeline test recognises against.
#
# They are not committed: a face recognition project should not carry photos
# of people in its history, and the pinned checksums give the same
# reproducibility without them. Same pattern as the ML models in
# scripts/download_models_for_build.sh.
#
# All three are public domain works of NASA, taken in the same studio, which
# is what makes them a fair test: same lighting, same framing, so a match or
# a rejection is about the face and not about the photograph.
#
#   meir-2016.jpg / meir-2013.jpg  one person, three years apart, different
#                                  hair, clothing and pose
#   koch-2023.jpg                  a different person of similar build and
#                                  colouring, so rejecting her is not free
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/faces"
mkdir -p "$FIXTURE_DIR"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

fetch() {
    local name="$1" url="$2" expected="$3"
    local file="$FIXTURE_DIR/$name"

    if [ -f "$file" ] && [ "$(sha256_of "$file")" = "$expected" ]; then
        echo "ok       $name"
        return 0
    fi

    curl -fsSL -A "harbour-nami-tests/1.0" "$url" -o "$file"

    local actual
    actual="$(sha256_of "$file")"
    if [ "$actual" != "$expected" ]; then
        echo "checksum mismatch for $name" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        rm -f "$file"
        exit 1
    fi
    echo "fetched  $name"
}

# https://commons.wikimedia.org/wiki/File:Jessica_Meir_full_length_portrait_(1)_(cropped).jpg
fetch "meir-2016.jpg" \
    "https://upload.wikimedia.org/wikipedia/commons/3/34/Jessica_Meir_full_length_portrait_%281%29_%28cropped%29.jpg" \
    "a05177c09ee70711b86fbd46199e4860e3bb810b890cb51c6fad01b8ce9d97e6"

# https://commons.wikimedia.org/wiki/File:Jessica_U._Meir_portrait_for_media_event.jpg
fetch "meir-2013.jpg" \
    "https://upload.wikimedia.org/wikipedia/commons/4/45/Jessica_U._Meir_portrait_for_media_event.jpg" \
    "9bca8a99d464af7b2a799f8fdce70eaff12c7a270bcdadf8c2c15125f549c4fd"

# https://commons.wikimedia.org/wiki/File:Christina_Koch_Artemis_2_Crew_Portrait.jpg
fetch "koch-2023.jpg" \
    "https://upload.wikimedia.org/wikipedia/commons/c/cc/Christina_Koch_Artemis_2_Crew_Portrait.jpg" \
    "83df50feb1efe4867db27be3238ee0de0f8bdc2635f47c289d501e086ec1f1d1"

echo "reference portraits ready in $FIXTURE_DIR"
