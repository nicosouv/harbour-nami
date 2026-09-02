import QtQuick 2.6
import Sailfish.Silica 1.0

// Plays an edit decision list.
//
// Everything on screen is derived from one number, `positionMs`. Which shot
// is up, how far its camera move has travelled, how far a transition has
// got: all of it is a function of the clock, and none of it is state that
// can drift out of step with the music.
//
// That is also what makes this the same thing the offline renderer will do.
// It walks the same list and asks for the same frame at the same time; the
// only difference is that it writes the frames to a file instead of showing
// them. What you preview is what you export because there is one edit and
// one way of reading it.
Item {
    id: player

    // The map FacePipeline.composeMemoryClip() returns.
    //
    // Not called "clip": Item already has a clip property, and a declared
    // one only shadows it at the component's own root. Inside any nested
    // Item, a bare `clip` resolves to that Item's own inherited boolean,
    // which is false. The Loader below read it as its condition and was
    // never activated once, so every clip played silently.
    property var edit: null
    property bool playing: false
    property int positionMs: 0
    property bool loop: false

    readonly property int durationMs: edit ? edit.duration_ms : 0
    readonly property int shotCount: edit && edit.shots ? edit.shots.length : 0
    readonly property bool hasClip: shotCount > 0

    // Which shot covers the clock, and how far through it we are
    property int currentIndex: 0
    readonly property var currentShot: shotAt(currentIndex)
    readonly property var previousShot: (currentIndex > 0) ? shotAt(currentIndex - 1) : null

    function shotAt(index) {
        return (hasClip && index >= 0 && index < shotCount) ? edit.shots[index] : null
    }

    signal finished()

    function play() {
        if (!hasClip) return
        if (positionMs >= durationMs) {
            positionMs = 0
        }
        clockReset()
        playing = true
    }

    function pause() {
        playing = false
    }

    function restart() {
        positionMs = 0
        currentIndex = 0
        clockReset()
        playing = true
        if (audioLoader.item) {
            audioLoader.item.restart()
        }
    }

    function seek(ms) {
        positionMs = Math.max(0, Math.min(durationMs, ms))
        clockReset()
        updateIndex()
    }

    // Walked rather than searched: the clock moves forward a frame at a
    // time, so the answer is almost always the shot we are already on
    function updateIndex() {
        if (!hasClip) return

        var index = currentIndex
        if (index >= shotCount || edit.shots[index].start_ms > positionMs) {
            index = 0
        }
        while (index + 1 < shotCount && edit.shots[index + 1].start_ms <= positionMs) {
            index++
        }
        currentIndex = index
    }

    // 0 at the start of the current shot, 1 at its end. Drives the camera.
    function shotProgress(shot) {
        if (!shot || shot.duration_ms <= 0) return 0
        return Math.max(0, Math.min(1, (positionMs - shot.start_ms) / shot.duration_ms))
    }

    // 0 to 1 across the transition into the current shot, 1 once it is over
    readonly property real transitionProgress: {
        if (!currentShot || currentShot.transition_ms <= 0) return 1
        var elapsed = positionMs - currentShot.start_ms
        return Math.max(0, Math.min(1, elapsed / currentShot.transition_ms))
    }

    readonly property string transition: currentShot ? currentShot.transition : "cut"
    readonly property bool inTransition: previousShot !== null && transitionProgress < 1

    // The clip ends where the edit ends, which is almost never where the
    // track ends. Winding the music down over the last moment is the
    // difference between an ending and a power cut.
    property int fadeOutMs: 1200
    readonly property real audioLevel: {
        if (durationMs <= 0 || fadeOutMs <= 0) return 1.0
        var remaining = durationMs - positionMs
        return remaining >= fadeOutMs ? 1.0 : Math.max(0.0, remaining / fadeOutMs)
    }

    onEditChanged: {
        positionMs = 0
        currentIndex = 0
        playing = false
        clockReset()
    }

    onPositionMsChanged: updateIndex()

    // === The clock ===
    //
    // It runs on its own, on real elapsed time, and only listens to the
    // music when the music has something new to say.
    //
    // Reading the audio position every frame and believing it was the first
    // version, and it stuttered: Audio.position is not a clock, it is the
    // last value the backend pushed, and the backend pushes one about once
    // a second. Between two of those, the same number is read thirty times,
    // so the camera move stopped dead and then jumped.
    //
    // So: advance on the wall clock, and correct only when a genuinely new
    // sample arrives and disagrees by more than the sampling can explain. A
    // stale sample re-read is not evidence of drift.
    property double lastTickMs: 0
    property int lastReportedMs: -1

    // The longest gap a tick may account for. A screen that blanked or a
    // page that was pushed on top must not make the clip leap forward.
    readonly property int maxStepMs: 250
    readonly property int resyncMs: 200

    function clockReset() {
        lastTickMs = 0
        lastReportedMs = -1
    }

    onPlayingChanged: {
        if (!playing) clockReset()
    }

    Timer {
        interval: 32
        repeat: true
        running: player.playing && player.hasClip

        onTriggered: {
            var now = Date.now()
            var elapsed = player.lastTickMs > 0
                ? Math.min(player.maxStepMs, now - player.lastTickMs)
                : interval
            player.lastTickMs = now

            var next = player.positionMs + elapsed

            var audio = audioLoader.item
            if (audio && audio.ready && audio.positionMs !== player.lastReportedMs) {
                // A fresh sample, taken now rather than up to a second ago
                player.lastReportedMs = audio.positionMs
                if (Math.abs(audio.positionMs - next) > player.resyncMs) {
                    next = audio.positionMs
                }
            }

            if (next >= player.durationMs) {
                if (player.loop) {
                    player.restart()
                    return
                }
                player.positionMs = player.durationMs
                player.playing = false
                player.finished()
                return
            }
            player.positionMs = next
        }
    }

    Loader {
        id: audioLoader
        // Only when there is actually a file: with no track the player runs
        // on its own clock and the clip is silent
        active: edit && edit.track_path && edit.track_path.length > 0
        // Resolved against this file rather than left relative: a Loader
        // resolves against its own component, and being explicit costs
        // nothing next to a silent failure
        source: Qt.resolvedUrl("ClipAudio.qml")

        // Bindings, not assignments. Choosing another style recomposes the
        // edit onto a different track, but `active` stays true throughout,
        // so the Loader never reloads and onLoaded never runs again: a
        // one-time assignment here left the first track playing forever.
        onLoaded: {
            item.source = Qt.binding(function () {
                return (player.edit && player.edit.track_path)
                    ? "file://" + player.edit.track_path : ""
            })
            item.startMs = Qt.binding(function () {
                return player.edit ? player.edit.track_start_ms : 0
            })
            item.playing = Qt.binding(function () { return player.playing })
            item.level = Qt.binding(function () { return player.audioLevel })
        }

        // The two ways a clip ends up silent, told apart in the log rather
        // than by guesswork: either no track was found for it, or the
        // multimedia plugin is not on this device
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("MemoryPlayer: no audio, ClipAudio.qml failed to load."
                             + " QtMultimedia is probably missing on this device.")
            }
        }

        onActiveChanged: {
            if (!active && player.edit) {
                console.log("MemoryPlayer: no audio, track_path is empty for track",
                            player.edit.track_id)
            }
        }
    }

    // === What you see ===

    Rectangle {
        anchors.fill: parent
        // The ground the shots sit on, and what shows through a wipe
        color: player.transition === "drop" ? "#f2efe9" : "black"
    }

    // === The two frames ===
    //
    // They do not swap sources at a cut, they take turns: one holds the
    // even-numbered shots, the other the odd ones. Whichever is not leading
    // shows the shot being dissolved out of, and once that dissolve is over
    // it goes and fetches the next one, which is the whole trick.
    //
    // The first version assigned "the current shot" to one frame and "the
    // previous shot" to the other. Every cut therefore changed both sources
    // at once, so the photo that had just been decoded for the incoming
    // frame was decoded a second time for the outgoing one, and the photo
    // coming up was decoded at the exact moment it had to appear. Two
    // decodes at every cut, none of them anticipated, on a clip that cuts
    // every half second in the energetic style.
    //
    // Taking turns, a photo is decoded once, one shot ahead of its cue.
    function frameIndexFor(parity) {
        var index = currentIndex
        if (index % 2 === parity) {
            return index
        }
        // Holding the shot being dissolved out of, or already reading ahead
        return inTransition ? index - 1 : index + 1
    }

    readonly property int frameAIndex: frameIndexFor(0)
    readonly property int frameBIndex: frameIndexFor(1)

    // What the shot arriving on screen looks like while it arrives. Written
    // once here rather than twice below: the two frames are the same frame,
    // and only one of them is leading at a time.
    readonly property real incomingOpacity:
        (transition === "dissolve" || transition === "drop") ? transitionProgress : 1.0
    // The polaroid lands on the pile rather than fading in
    readonly property real incomingScale:
        transition === "drop" ? 1.0 + 0.35 * (1.0 - transitionProgress) : 1.0
    readonly property real incomingRotation:
        transition === "drop" ? 4.0 * (1.0 - transitionProgress) : 0.0
    // A wipe reveals it from the left instead
    readonly property real incomingRevealed:
        transition === "wipe" ? transitionProgress : 1.0

    ClipFrame {
        anchors.fill: parent
        readonly property bool leading: player.frameAIndex === player.currentIndex
        shot: player.shotAt(player.frameAIndex)
        // Frozen where its own move ended rather than continuing to drift
        progress: leading ? player.shotProgress(shot) : 1.0
        opacity: leading ? player.incomingOpacity : 1.0
        scale: leading ? player.incomingScale : 1.0
        rotation: leading ? player.incomingRotation : 0.0
        revealed: leading ? player.incomingRevealed : 1.0
        z: leading ? 1 : 0
        visible: leading || (player.inTransition && player.transition !== "cut")
    }

    ClipFrame {
        anchors.fill: parent
        readonly property bool leading: player.frameBIndex === player.currentIndex
        shot: player.shotAt(player.frameBIndex)
        progress: leading ? player.shotProgress(shot) : 1.0
        opacity: leading ? player.incomingOpacity : 1.0
        scale: leading ? player.incomingScale : 1.0
        rotation: leading ? player.incomingRotation : 0.0
        revealed: leading ? player.incomingRevealed : 1.0
        z: leading ? 1 : 0
        visible: leading || (player.inTransition && player.transition !== "cut")
    }

    // The flat colour that sweeps a bauhaus wipe. Its leading edge is the
    // reveal, so the sweep and what it uncovers cannot come apart.
    Rectangle {
        visible: player.transition === "wipe" && player.inTransition
        color: Theme.highlightColor
        width: parent.width * 0.06
        height: parent.height
        x: parent.width * player.transitionProgress
    }

    // The colour treatment, as far as plain QML can take it. The renderer
    // will do this properly; here it is enough to tell the four styles apart.
    Rectangle {
        anchors.fill: parent
        visible: edit !== null && edit.grade !== undefined
        color: edit && edit.grade.warmth > 0 ? "#ffb066" : "#66a0ff"
        opacity: edit ? Math.abs(edit.grade.warmth) * 0.18 : 0
    }

    Rectangle {
        anchors.fill: parent
        visible: edit !== null && edit.grade !== undefined && edit.grade.vignette > 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.rgba("black", edit ? edit.grade.vignette * 0.5 : 0) }
            GradientStop { position: 0.35; color: "transparent" }
            GradientStop { position: 0.65; color: "transparent" }
            GradientStop { position: 1.0; color: Theme.rgba("black", edit ? edit.grade.vignette * 0.6 : 0) }
        }
    }
}
