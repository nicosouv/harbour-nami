import QtQuick 2.6
// 5.0, not a later one: every property used here (source, autoLoad, volume,
// position, status, play, pause, seek) has been on Audio since then, and an
// import version the device does not have fails the whole component
import QtMultimedia 5.0

// The clip's music, kept in a file of its own so that the QtMultimedia
// import lives here and nowhere else.
//
// MemoryPlayer loads this through a Loader. If the multimedia QML plugin is
// missing on a device, the Loader fails and the clip plays silently, which
// is a far better outcome than the whole page refusing to load: an import
// that cannot resolve takes down the component that declares it.
Item {
    id: root

    property string source: ""
    property bool playing: false
    // Where in the track the clip begins, so the first cut lands on a beat
    // rather than on the silence before it
    property int startMs: 0
    // 0 to 1. The player winds this down over the last moment of the clip:
    // a clip stops where the edit ends, which is almost never where the
    // track ends, and cutting the music dead there sounds like a failure.
    property real level: 1.0

    // Whether the clip's starting point has actually been reached. A seek
    // issued before the media is loaded is dropped on the floor, so this is
    // what stops the player trusting a position that never moved there.
    property bool positioned: false

    // What the player uses as its clock while the music is running. Never
    // negative: before the seek lands, audio.position is still 0 and a
    // startMs of 1.3 seconds would hand the player a clock running from
    // minus 1.3, which parks the clip on its first frame until it catches up.
    readonly property int positionMs: Math.max(0, audio.position - startMs)
    readonly property bool ready: positioned
                                  && (audio.status === Audio.Buffered
                                      || audio.status === Audio.Loaded)

    function seekToStart() {
        if (audio.status !== Audio.Loaded && audio.status !== Audio.Buffered) {
            return  // too early; onStatusChanged will call back
        }
        if (audio.position < startMs) {
            audio.seek(startMs)
        }
        positioned = true
    }

    function restart() {
        audio.stop()
        positioned = false
        if (source.length > 0) {
            seekToStart()
            audio.play()
        }
    }

    onPlayingChanged: {
        if (playing) {
            seekToStart()
            audio.play()
        } else {
            audio.pause()
        }
    }

    // Changing a memory's style changes its track. Without this the element
    // keeps playing whatever it loaded first: a new source on a running
    // player is not a new track, it is the old one with a different file
    // name attached.
    onSourceChanged: {
        audio.stop()
        positioned = false
    }

    Audio {
        id: audio
        source: root.source
        autoLoad: root.source.length > 0
        volume: Math.max(0.0, Math.min(1.0, root.level))

        // Silence has too many possible causes to guess at from a phone:
        // a missing codec, an unreadable path and a blocked audio device all
        // look identical from the outside
        onErrorChanged: {
            if (error !== Audio.NoError) {
                console.warn("ClipAudio: error", error, errorString, "for", source)
            }
        }
        onStatusChanged: {
            console.log("ClipAudio: status", status, "for", source)
            // The media has only just become seekable; if the clip is meant
            // to start further in, this is the first moment that can happen
            if (!root.positioned
                    && (status === Audio.Loaded || status === Audio.Buffered)) {
                root.seekToStart()
            }
        }
    }
}
