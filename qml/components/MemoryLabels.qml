import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/memories.js" as Memories

// The words on a memory card.
//
// Titles are not stored translated (see qml/js/memories.js): the generator
// writes raw material and the phrasing happens here, so a memory reads in
// whatever language the app is set to today rather than the one it was
// generated in.
//
// It is a component rather than a JS library because qsTr() needs a
// translation context, and a `.pragma library` has none of its own.
QtObject {
    id: labels

    // The app can be set to a language other than the phone's, so month and
    // day names have to follow that setting rather than QLocale::system(),
    // which is what Qt.formatDate() would use.
    property var locale: {
        if (!facePipeline || !facePipeline.initialized) {
            return Qt.locale()
        }
        var override = facePipeline.getSetting("language", "system")
        return (!override || override === "system") ? Qt.locale() : Qt.locale(override)
    }

    function title(memory) {
        if (!memory) return ""

        if (!Memories.hasComputedTitle(memory.kind)) {
            // A trip, a person, a pair: the stored title is already the
            // user's own words
            return memory.title
        }

        if (memory.kind === "anniversary") {
            var years = Memories.yearsAgo(memory, new Date())
            return years === 1 ? qsTr("A year ago") : qsTr("%1 years ago").arg(years)
        }

        if (memory.kind === "month") {
            var month = Memories.monthDate(memory)
            return month ? month.toLocaleDateString(locale, "MMMM yyyy") : memory.title
        }

        var day = Memories.eventDate(memory)
        return day ? day.toLocaleDateString(locale, "d MMMM yyyy") : memory.title
    }

    // One quiet line under the title: when it was, and how much of it there
    // is. Anything else the card could say is something the photo says better.
    function subtitle(memory) {
        if (!memory) return ""

        var parts = []

        // An anniversary's title is already "3 years ago", so the date it
        // actually fell on is what the line adds
        var date = Memories.subjectDate(memory)
        if (date && memory.kind !== "month" && memory.kind !== "event") {
            parts.push(date.toLocaleDateString(locale, "d MMMM yyyy"))
        }

        var count = memory.photo_count || 0
        if (count > 0) {
            parts.push(count + " " + (count === 1 ? qsTr("photo") : qsTr("photos")))
        }

        return parts.join("  ·  ")
    }
}
