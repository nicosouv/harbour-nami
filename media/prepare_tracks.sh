#!/usr/bin/env bash
# Turns the supplied music into what the app ships.
#
#   docker compose run --rm beats
#
# Put your tracks in media/.sources/<style>.<ext> and run the above. The
# four styles are sentimental, energetic, polaroid and bauhaus, and the
# extension can be wav, flac, aiff, m4a, mp3, opus or ogg.
#
# Nothing is downloaded. The app declares no Internet permission and fetches
# nothing at runtime: the .ogg files beside this script are committed and go
# into the package, and this only regenerates them.
#
# A style with no source keeps whatever is already committed, so running
# this after replacing one track does not disturb the other three.
set -euo pipefail

MEDIA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$MEDIA_DIR/.sources"

# Slightly past the 90s a clip may use, so the last shot never runs onto the
# end of the file
CLIP_SECONDS=92

STYLES="sentimental energetic polaroid bauhaus"

supplied() {
    local id="$1"
    for ext in wav flac aiff m4a mp3 opus ogg; do
        if [ -f "$SOURCE_DIR/$id.$ext" ]; then
            echo "$SOURCE_DIR/$id.$ext"
            return
        fi
    done
}

for id in $STYLES; do
    source="$(supplied "$id")"
    target="$MEDIA_DIR/$id.ogg"

    if [ -z "$source" ]; then
        if [ -f "$target" ]; then
            echo "$(printf '%-12s' "$id") keeping the committed track"
        else
            echo "$(printf '%-12s' "$id") no source and nothing committed" >&2
        fi
        continue
    fi

    # loudnorm first, fade last. Tracks arrive mastered at whatever level
    # their author chose, and a quiet one does not merely sound quieter: it
    # reads as a clip in slow motion, and switching style mid-preview jumps
    # in volume. EBU R128 puts them all at the same perceived loudness so
    # choosing a style is choosing music, not volume.
    #
    # Mono, because a phone speaker is. Vorbis at the source's own 44.1 kHz
    # rather than Opus, which only ever decodes at 48 and plays back slow
    # against a sink sitting at 44.1. The fade is a safety net for a track
    # with no ending of its own at 92 seconds; the player fades out at the
    # clip's end regardless.
    ffmpeg -y -loglevel error -i "$source" \
        -t "$CLIP_SECONDS" -ac 1 -ar 44100 \
        -af "loudnorm=I=-16:TP=-1.5:LRA=11,afade=t=out:st=$((CLIP_SECONDS - 3)):d=3" \
        -c:a libvorbis -q:a 2 \
        "$target"

    echo "$(printf '%-12s' "$id") $(basename "$source") -> $(du -h "$target" | cut -f1)"
done

echo "clip music ready in $MEDIA_DIR"
