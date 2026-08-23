#!/usr/bin/env bash
# Fetches the clip music.
#
# Not committed: audio is large and binary, and these four are a first pass
# chosen to have something to test against. The checksums pin exactly which
# recordings they are, and the beat grids beside them (<track>.json) are
# committed, so what the composer cuts on is reviewable in a diff even
# though the audio is not.
#
# All four are CC0 by Loyalty Freak Music, via Wikimedia Commons. CC0 only,
# never CC-BY: an attribution obligation would follow every clip a user
# posts, which is friction they did not sign up for. See MUSIC-LICENSES.md.
#
# Swapping one is a matter of changing its URL and checksum here, then
# re-running `docker compose run --rm beats`.
set -euo pipefail

MEDIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

fetch() {
    local name="$1" url="$2" expected="$3"
    local file="$MEDIA_DIR/$name"

    if [ -f "$file" ] && [ "$(sha256_of "$file")" = "$expected" ]; then
        echo "ok       $name"
        return 0
    fi

    curl -fsSL -A "harbour-nami/1.0" "$url" -o "$file"

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

# Softly
fetch "sentimental.ogg" \
    "https://upload.wikimedia.org/wikipedia/commons/0/0b/Loyalty_Freak_Music_-_06_-_Softly.ogg" \
    "6fea22d33d59b8e27f13d19e2b2a8069275e1784b8e989cedc79cb952937e5d9"

# Old Key, the fastest of the four at 152 bpm
fetch "energetic.ogg" \
    "https://upload.wikimedia.org/wikipedia/commons/a/ad/Loyalty_Freak_Music_-_03_-_Old_Key.ogg" \
    "5182735c55982476007b468a9ffea7173ea724335a1d6de2cb90470a8e80197f"

# Yippee!, 89 bpm
fetch "polaroid.ogg" \
    "https://upload.wikimedia.org/wikipedia/commons/1/17/Loyalty_Freak_Music_-_08_-_Yippee_.ogg" \
    "52594ef5f66dcf85a61f8068d2094a0de70925105eee14eaf213ca8a4ac89052"

# Roller Fever
fetch "bauhaus.ogg" \
    "https://upload.wikimedia.org/wikipedia/commons/7/7c/Loyalty_Freak_Music_-_01_-_Roller_Fever.ogg" \
    "13ec2e23828b9ff3399ed9cd2f580382a3d77debce3c615dadedee04fb49b2a8"

echo "clip music ready in $MEDIA_DIR"
