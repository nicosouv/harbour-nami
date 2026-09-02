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

// === Which memory leads the home page ===

// How far below the best score a memory may sit and still take its turn as
// the hero. The recipes score in wide steps (an anniversary 0.70, a trip
// 0.65, a busy day 0.50), so a band this size holds the memories of
// genuinely the same standing and leaves out the ones that would only get
// there for lack of competition.
var HERO_BAND = 0.15
var HERO_POOL_MAX = 5

// How many of them are in the running, given a list sorted by score
function heroPoolSize(memories) {
    if (!memories || memories.length === 0) {
        return 0
    }
    var best = memories[0].score || 0
    var pool = 1
    while (pool < memories.length && pool < HERO_POOL_MAX
           && (memories[pool].score || 0) >= best - HERO_BAND) {
        pool++
    }
    return pool
}

// Rotated by the day rather than shuffled. The home refreshes on every
// return to it, and a random pick would move the hero under someone coming
// back from a photo; keyed on the date, it is the same card all day and a
// different one tomorrow. Returns -1 when there is nothing to show.
function heroIndex(memories, now) {
    var pool = heroPoolSize(memories)
    if (pool === 0) {
        return -1
    }
    return Math.floor(now.getTime() / 86400000) % pool
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
