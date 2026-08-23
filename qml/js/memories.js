// Reading the raw material a memory carries.
//
// MemoryGenerator stores titles untranslated on purpose: "2023" for an
// anniversary, "2026-05" for a month, "2025-09-20" for a day, and the trip
// or person name where the title genuinely is the user's own words. A title
// rendered into the database would be stuck in whatever language was active
// the day the recipe ran, and the app lets the user override its language.
//
// So the phrasing happens at display time, in components/MemoryLabels.qml.
// What lives here is the part with no words in it: turning a source_key
// back into a date, and counting years. It is pure, which is why it is
// testable in node rather than only on a device.
.pragma library

// Kinds whose title this file has to reconstruct. The others (trip, person,
// duo) carry a title that is already the right words in any language.
var COMPUTED_TITLE_KINDS = ["anniversary", "month", "event"]

function hasComputedTitle(kind) {
    return COMPUTED_TITLE_KINDS.indexOf(kind) >= 0
}

// An anniversary's source_key is the year its photos were taken
function anniversaryYear(memory) {
    if (!memory || memory.kind !== "anniversary") {
        return 0
    }
    var year = parseInt(memory.source_key, 10)
    return isFinite(year) ? year : 0
}

// How many years ago, counted from `now` rather than from a stored value:
// a memory generated in December must not still say "2 years ago" in March
function yearsAgo(memory, now) {
    var year = anniversaryYear(memory)
    if (year <= 0) {
        return 0
    }
    return Math.max(0, now.getFullYear() - year)
}

// "2026-05" -> the first of that month, which is what a month name is
// formatted from. Returns null when the key is not a month.
function monthDate(memory) {
    if (!memory || memory.kind !== "month") {
        return null
    }
    var parts = String(memory.source_key).split("-")
    if (parts.length !== 2) {
        return null
    }
    var year = parseInt(parts[0], 10)
    var month = parseInt(parts[1], 10)
    if (!isFinite(year) || !isFinite(month) || month < 1 || month > 12) {
        return null
    }
    return new Date(year, month - 1, 1)
}

// "2025-09-20" -> that day
function eventDate(memory) {
    if (!memory || memory.kind !== "event") {
        return null
    }
    var parts = String(memory.source_key).split("-")
    if (parts.length !== 3) {
        return null
    }
    var year = parseInt(parts[0], 10)
    var month = parseInt(parts[1], 10)
    var day = parseInt(parts[2], 10)
    if (!isFinite(year) || !isFinite(month) || !isFinite(day)
            || month < 1 || month > 12 || day < 1 || day > 31) {
        return null
    }
    var date = new Date(year, month - 1, day)
    // Rejects "2025-02-30", which Date would roll over to 2 March
    if (date.getMonth() !== month - 1 || date.getDate() !== day) {
        return null
    }
    return date
}

// The date a memory is about, whatever its kind. sort_date comes from the
// generator as epoch seconds and is the fallback for the kinds whose
// source_key holds no date at all (trip, person, duo).
function subjectDate(memory) {
    if (!memory) {
        return null
    }
    var fromKey = memory.kind === "month" ? monthDate(memory)
                : memory.kind === "event" ? eventDate(memory)
                : null
    if (fromKey) {
        return fromKey
    }
    if (memory.timestamp) {
        return new Date(memory.timestamp * 1000)
    }
    return null
}
