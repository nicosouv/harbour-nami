import QtQuick 2.6
import QtMultimedia 5.6

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

    Audio {
        id: audio
        source: root.source
        autoLoad: root.source.length > 0
    }
}
