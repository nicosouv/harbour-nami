import QtQuick 2.6
import Sailfish.Silica 1.0

// The names of the clip styles, in the app's language.
//
// The ids come from C++ (MemoryStyles::all()) and are stored in the database
// as they are, so they must never be translated: the same reason memory
// titles are not stored translated. What gets translated is only what the
// picker shows.
//
// A component rather than a JS library because qsTr() needs a translation
// context, and a `.pragma library` has none of its own.
QtObject {
    function name(styleId) {
        switch (styleId) {
        // Slow, warm, long cross-fades: looking back at something
        case "sentimental": return qsTr("Sentimental")
        // Fast cuts on the beat, harder contrast
        case "energetic":   return qsTr("Energetic")
        // 4:3 in a white frame, grain, each photo dropped on the pile
        case "polaroid":    return qsTr("Polaroid")
        // Strict grid, geometric wipes, the photograph left alone
        case "bauhaus":     return qsTr("Bauhaus")
        }
        return styleId
    }
}
