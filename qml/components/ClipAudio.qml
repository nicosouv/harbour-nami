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

    // What the player uses as its clock while the music is running
    readonly property int positionMs: audio.position - startMs
    readonly property bool ready: audio.status === Audio.Buffered
                                  || audio.status === Audio.Loaded

    function restart() {
        audio.stop()
        if (source.length > 0) {
            audio.seek(startMs)
            audio.play()
        }
    }

    onPlayingChanged: {
        if (playing) {
            if (audio.position < startMs) {
                audio.seek(startMs)
            }
            audio.play()
        } else {
            audio.pause()
        }
    }

    // Changing a memory's style changes its track. Without this the element
    // keeps playing whatever it loaded first: a new source on a running
    // player is not a new track, it is the old one with a different file
    // name attached.
    onSourceChanged: audio.stop()

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
        onStatusChanged: console.log("ClipAudio: status", status, "for", source)
    }
}
