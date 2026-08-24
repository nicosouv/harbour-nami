#!/usr/bin/env bash
# Fetches the clip music and transcodes it into what the app ships.
#
#   docker compose run --rm beats
#
# The originals are 2.8 to 4.3 MB of stereo Vorbis and are not kept. What
# lands in media/ is a mono 44.1 kHz cut of the first 92 seconds, small
# enough to commit.
#
# Committing them matters more than the disk space: a release build that
# fetches its own assets from a third party fails the day that third party
# moves a file, and it fails at tag time.
#
# All four are CC0 by Loyalty Freak Music, via Wikimedia Commons. CC0 only,
# never CC-BY: an attribution obligation would follow every clip a user
# posts. See MUSIC-LICENSES.md.
#
# Swapping one is a URL and a checksum here, then re-running the above.
set -euo pipefail

MEDIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Originals, gitignored: only the transcode is worth keeping
SOURCE_DIR="$MEDIA_DIR/.sources"
mkdir -p "$SOURCE_DIR"

# Slightly past the 90s a clip may use, so the last shot never runs onto the
# end of the file
CLIP_SECONDS=92

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# A track you supplied, whatever its extension, or nothing
supplied() {
    local id="$1"
    for ext in wav flac aiff m4a mp3 opus ogg; do
        if [ -f "$SOURCE_DIR/$id.$ext" ]; then
            echo "$SOURCE_DIR/$id.$ext"
            return
        fi
    done
}

prepare() {
    local id="$1" url="$2" expected="$3"
    local target="$MEDIA_DIR/$id.ogg"

    # Your own file wins over the download. Drop anything into
    # media/.sources/<style>.<ext> and re-run: the checksummed fetch below is
    # only there so the repository has something to play out of the box.
    local source
    source="$(supplied "$id")"

    if [ -n "$source" ]; then
        echo "$(printf '%-12s' "$id") using $(basename "$source")"
    else
        source="$SOURCE_DIR/$id.ogg"
        curl -fsSL -A "harbour-nami/1.0" "$url" -o "$source"

        local actual
        actual="$(sha256_of "$source")"
        if [ "$actual" != "$expected" ]; then
            echo "checksum mismatch for $id" >&2
            echo "  expected: $expected" >&2
            echo "  actual:   $actual" >&2
            rm -f "$source"
            exit 1
        fi
    fi

    # Vorbis at the source's own 44.1 kHz, not Opus.
    #
    # Opus always decodes at 48 kHz, by design, and these sources are 44.1.
    # On a device whose PulseAudio sink is sitting at 44.1, that mismatch
    # plays back 8.8% slow: the track sounds stretched, and only sometimes,
    # because the sink's rate depends on whatever opened audio first.
    # Matching the source rate removes the negotiation entirely, and
    # libgstvorbis is on every Sailfish device there has ever been.
    #
    # Mono, because a phone speaker is. The fade is a safety net for a track
    # with no ending of its own at 92 seconds; the player fades out at the
    # clip's end regardless.
    ffmpeg -y -loglevel error -i "$source" \
        -t "$CLIP_SECONDS" -ac 1 -ar 44100 \
        -af "afade=t=out:st=$((CLIP_SECONDS - 3)):d=3" \
        -c:a libvorbis -q:a 2 \
        "$target"

    echo "$(printf '%-12s' "$id") $(du -h "$target" | cut -f1)"
}

# Softly, 69.8 bpm
prepare "sentimental" \
    "https://upload.wikimedia.org/wikipedia/commons/0/0b/Loyalty_Freak_Music_-_06_-_Softly.ogg" \
    "6fea22d33d59b8e27f13d19e2b2a8069275e1784b8e989cedc79cb952937e5d9"

# Old Key, the fastest of the four at 152 bpm
prepare "energetic" \
    "https://upload.wikimedia.org/wikipedia/commons/a/ad/Loyalty_Freak_Music_-_03_-_Old_Key.ogg" \
    "5182735c55982476007b468a9ffea7173ea724335a1d6de2cb90470a8e80197f"

# Yippee!, 89 bpm
prepare "polaroid" \
    "https://upload.wikimedia.org/wikipedia/commons/1/17/Loyalty_Freak_Music_-_08_-_Yippee_.ogg" \
    "52594ef5f66dcf85a61f8068d2094a0de70925105eee14eaf213ca8a4ac89052"

# Roller Fever, 129 bpm
prepare "bauhaus" \
    "https://upload.wikimedia.org/wikipedia/commons/7/7c/Loyalty_Freak_Music_-_01_-_Roller_Fever.ogg" \
    "13ec2e23828b9ff3399ed9cd2f580382a3d77debce3c615dadedee04fb49b2a8"

echo "clip music ready in $MEDIA_DIR"
