#!/usr/bin/env node
// Unit tests for the QML JavaScript libraries. They are plain .js modules
// behind a `.pragma library` line, so node can load and exercise them
// directly - no Qt, no device, milliseconds to run.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');

function loadQmlJs(relativePath) {
    const source = fs.readFileSync(path.join(ROOT, relativePath), 'utf8')
        .replace('.pragma library', '');
    const context = {};
    vm.createContext(context);
    vm.runInContext(source, context, { filename: relativePath });
    return context;
}

let passed = 0;
const failures = [];

function check(name, fn) {
    try {
        fn();
        passed++;
    } catch (error) {
        failures.push({ name, message: error.message });
    }
}

function assert(condition, message) {
    if (!condition) {
        throw new Error(message || 'assertion failed');
    }
}

function assertClose(actual, expected, tolerance, message) {
    if (Math.abs(actual - expected) > tolerance) {
        throw new Error(`${message || 'value'}: expected ${expected} +/- ${tolerance}, got ${actual}`);
    }
}

/* ---------------- geoutils ---------------- */

const geo = loadQmlJs('qml/js/geoutils.js');

check('haversine: same point is zero', () => {
    assert(geo.haversineKm(48.857, 2.352, 48.857, 2.352) === 0);
});

check('haversine: Paris to Lyon is ~392km', () => {
    assertClose(geo.haversineKm(48.857, 2.352, 45.764, 4.836), 392, 8, 'Paris-Lyon');
});

check('haversine: Paris to New York is ~5837km', () => {
    assertClose(geo.haversineKm(48.857, 2.352, 40.713, -74.006), 5837, 25, 'Paris-NY');
});

check('haversine: one degree of latitude is ~111km anywhere', () => {
    for (const lat of [-60, -10, 0, 35, 60, 75]) {
        assertClose(geo.haversineKm(lat, 12, lat + 1, 12), 111.2, 0.5, `at lat ${lat}`);
    }
});

check('haversine: a degree of longitude shrinks with latitude', () => {
    const atEquator = geo.haversineKm(0, 0, 0, 1);
    const atSixty = geo.haversineKm(60, 0, 60, 1);
    // cos(60) = 0.5, so half as much ground
    assertClose(atSixty / atEquator, 0.5, 0.01, 'longitude scaling');
});

check('haversine: sign of the delta does not matter', () => {
    const forward = geo.haversineKm(10, 20, 30, 40);
    const backward = geo.haversineKm(30, 40, 10, 20);
    assertClose(forward, backward, 1e-9, 'symmetry');
});

/* ---------------- world coastlines ---------------- */
// The dataset is stitched offline into closed rings so TripRouteMap can fill
// land. Nothing at runtime re-checks that, so it is checked here.

const coast = loadQmlJs('qml/js/worldcoastlines.js');

check('coastlines: dataset is present and non-trivial', () => {
    assert(Array.isArray(coast.COASTLINES), 'COASTLINES is not an array');
    assert(coast.COASTLINES.length > 100, `only ${coast.COASTLINES.length} rings`);
});

check('coastlines: every ring is closed', () => {
    coast.COASTLINES.forEach((ring, index) => {
        const n = ring.length;
        assert(n >= 8, `ring ${index} has ${n / 2} points`);
        assert(n % 2 === 0, `ring ${index} has an odd coordinate count`);
        assert(ring[0] === ring[n - 2] && ring[1] === ring[n - 1],
               `ring ${index} does not close: ${ring[0]},${ring[1]} vs ${ring[n - 2]},${ring[n - 1]}`);
    });
});

check('coastlines: coordinates are valid WGS84', () => {
    for (const ring of coast.COASTLINES) {
        for (let i = 0; i < ring.length; i += 2) {
            assert(ring[i] >= -180 && ring[i] <= 180, `longitude out of range: ${ring[i]}`);
            assert(ring[i + 1] >= -90 && ring[i + 1] <= 90, `latitude out of range: ${ring[i + 1]}`);
        }
    }
});

check('coastlines: rings are ordered largest first', () => {
    const area = ring => {
        let sum = 0;
        for (let i = 0, n = ring.length; i < n; i += 2) {
            const j = (i + 2) % n;
            sum += ring[i] * ring[j + 1] - ring[j] * ring[i + 1];
        }
        return Math.abs(sum / 2);
    };
    // Small islands must be drawn after the continent they sit near, or the
    // continent's fill paints over them
    const areas = coast.COASTLINES.map(area);
    for (let i = 1; i < areas.length; i++) {
        assert(areas[i] <= areas[i - 1] + 1e-6,
               `ring ${i} (area ${areas[i].toFixed(2)}) comes after a smaller one`);
    }
});

check('coastlines: the big landmasses are there', () => {
    const bbox = ring => {
        let minLon = 180, maxLon = -180, minLat = 90, maxLat = -90;
        for (let i = 0; i < ring.length; i += 2) {
            minLon = Math.min(minLon, ring[i]); maxLon = Math.max(maxLon, ring[i]);
            minLat = Math.min(minLat, ring[i + 1]); maxLat = Math.max(maxLat, ring[i + 1]);
        }
        return { minLon, maxLon, minLat, maxLat };
    };
    const boxes = coast.COASTLINES.map(bbox);
    const covers = (lon, lat) => boxes.some(b =>
        lon >= b.minLon && lon <= b.maxLon && lat >= b.minLat && lat <= b.maxLat);

    assert(covers(2.35, 48.86), 'no ring covers Paris');
    assert(covers(-74.0, 40.7), 'no ring covers New York');
    assert(covers(24.94, 60.17), 'no ring covers Helsinki');
    assert(covers(133, -25), 'no ring covers Australia');
});

/* ---------------- mosaic layout ---------------- */

const mosaic = loadQmlJs('qml/js/mosaic.js');

check('mosaic: aspect honours a quarter turn', () => {
    assert(mosaic.aspectOf({ width: 400, height: 300 }) === 4 / 3, 'landscape');
    assert(mosaic.aspectOf({ width: 400, height: 300, rotation: 90 }) === 3 / 4,
           'rotated landscape should read as portrait');
    assert(mosaic.aspectOf({ width: 400, height: 300, rotation: 180 }) === 4 / 3,
           'a half turn keeps the aspect');
    assert(mosaic.aspectOf({ width: 0, height: 0 }) === 1,
           'unknown dimensions fall back to square');
});

check('mosaic: every full row ends exactly on the margin', () => {
    const photos = [];
    for (let i = 0; i < 40; i++) {
        // alternate landscape, portrait and square
        const shapes = [{ width: 4000, height: 3000 },
                        { width: 3000, height: 4000 },
                        { width: 2000, height: 2000 }];
        photos.push(shapes[i % 3]);
    }
    const avail = 900, gap = 8;
    const rows = mosaic.layout(photos, avail, 300, gap);
    assert(rows.length > 1, 'expected several rows');

    rows.slice(0, -1).forEach((row, index) => {
        const total = row.reduce((sum, cell) => sum + cell.width, 0)
                      + (row.length - 1) * gap;
        assert(total === avail, `row ${index} spans ${total}, expected ${avail}`);
    });
});

check('mosaic: photos in a row share one height', () => {
    const photos = [{ width: 4000, height: 3000 }, { width: 3000, height: 4000 },
                    { width: 2000, height: 2000 }, { width: 4000, height: 3000 },
                    { width: 3000, height: 4000 }, { width: 2000, height: 2000 }];
    const rows = mosaic.layout(photos, 900, 300, 8);
    for (const row of rows) {
        const heights = new Set(row.map(cell => cell.height));
        assert(heights.size === 1, 'a row mixed several heights');
    }
});

check('mosaic: a lone trailing photo is not blown up to full width', () => {
    // One landscape photo alone on the last row
    const rows = mosaic.layout([{ width: 4000, height: 3000 }], 900, 300, 8);
    assert(rows.length === 1, 'expected a single row');
    const only = rows[0][0];
    assert(only.width < 900, `lone photo stretched to ${only.width}`);
    assert(only.height <= 300 * 1.5 + 1, `lone photo grew to ${only.height}`);
});

check('mosaic: squareAll ignores the photo dimensions', () => {
    const photos = [{ width: 4000, height: 3000 }, { width: 3000, height: 4000 },
                    { width: 4000, height: 3000 }];
    const rows = mosaic.layout(photos, 900, 300, 8, 1.5, true);
    for (const row of rows) {
        for (const cell of row) {
            assert(Math.abs(cell.width - cell.height) <= 1,
                   `square crop laid out as ${cell.width}x${cell.height}`);
        }
    }
});

check('mosaic: empty and degenerate inputs give no rows', () => {
    assert(mosaic.layout([], 900, 300, 8).length === 0, 'empty list');
    assert(mosaic.layout(null, 900, 300, 8).length === 0, 'null list');
    assert(mosaic.layout([{ width: 100, height: 100 }], 0, 300, 8).length === 0,
           'zero width');
});

/* ---------------- memories ---------------- */

const memories = loadQmlJs('qml/js/memories.js');

check('memories: only the computed kinds need rewriting', () => {
    // trip, person and duo carry a title that is already the user's own
    // words, and translating those would be wrong in any language
    assert(memories.hasComputedTitle('anniversary'));
    assert(memories.hasComputedTitle('month'));
    assert(memories.hasComputedTitle('event'));
    assert(!memories.hasComputedTitle('trip'));
    assert(!memories.hasComputedTitle('person'));
    assert(!memories.hasComputedTitle('duo'));
});

check('memories: years ago counts from now, not from a stored value', () => {
    const memory = { kind: 'anniversary', source_key: '2023' };
    // The same row has to read differently once the year turns, which is
    // exactly what a title rendered into the database could not do
    assert(memories.yearsAgo(memory, new Date(2026, 5, 15)) === 3, '2026');
    assert(memories.yearsAgo(memory, new Date(2027, 0, 2)) === 4, '2027');
});

check('memories: a month key becomes the first of that month', () => {
    const date = memories.monthDate({ kind: 'month', source_key: '2026-05' });
    assert(date.getFullYear() === 2026 && date.getMonth() === 4
           && date.getDate() === 1, `got ${date}`);
});

check('memories: an event key becomes that day', () => {
    const date = memories.eventDate({ kind: 'event', source_key: '2025-09-20' });
    assert(date.getFullYear() === 2025 && date.getMonth() === 8
           && date.getDate() === 20, `got ${date}`);
});

check('memories: a nonsense key yields no date rather than a wrong one', () => {
    assert(memories.monthDate({ kind: 'month', source_key: '2026-13' }) === null, 'month 13');
    assert(memories.monthDate({ kind: 'month', source_key: 'later' }) === null, 'not a date');
    // Date would silently roll this over to 2 March
    assert(memories.eventDate({ kind: 'event', source_key: '2025-02-30' }) === null, 'Feb 30');
    assert(memories.eventDate({ kind: 'event', source_key: '2025-09' }) === null, 'no day');
    assert(memories.monthDate({ kind: 'trip', source_key: '7' }) === null, 'wrong kind');
});

check('memories: the subject date falls back to sort_date', () => {
    // A trip's source_key is an id, so the only date it has is the one the
    // generator stored
    const stamp = Math.floor(new Date(2025, 3, 10).getTime() / 1000);
    const date = memories.subjectDate({ kind: 'trip', source_key: '7', timestamp: stamp });
    assert(date.getFullYear() === 2025 && date.getMonth() === 3, `got ${date}`);

    assert(memories.subjectDate({ kind: 'trip', source_key: '7' }) === null, 'no date at all');
    assert(memories.subjectDate(null) === null, 'no memory');
});

/* ---------------- the home page hero ---------------- */

const band = (...scores) => scores.map((score, index) => ({ memory_id: index, score }));

check('hero: only the memories of the same standing take a turn', () => {
    // 0.50 is a busy day against a 0.78 anniversary: it does not get to
    // lead the home page just because nothing else was generated that week
    assert(memories.heroPoolSize(band(0.78, 0.75, 0.50, 0.50)) === 2, 'wide gap');
    assert(memories.heroPoolSize(band(0.65, 0.65, 0.65)) === 3, 'all equal');
    assert(memories.heroPoolSize(band(0.9)) === 1, 'one memory');
    assert(memories.heroPoolSize([]) === 0, 'nothing at all');
});

check('hero: the pool is capped whatever the scores say', () => {
    const many = band(...new Array(30).fill(0.7));
    assert(memories.heroPoolSize(many) === 5, `got ${memories.heroPoolSize(many)}`);
});

check('hero: the same day always gives the same card', () => {
    const all = band(0.7, 0.7, 0.7);
    const morning = memories.heroIndex(all, new Date(2026, 8, 2, 8, 30));
    const evening = memories.heroIndex(all, new Date(2026, 8, 2, 23, 15));
    assert(morning === evening, `${morning} in the morning, ${evening} at night`);
});

check('hero: consecutive days move through the pool', () => {
    const all = band(0.7, 0.7, 0.7);
    const seen = new Set();
    for (let day = 0; day < 3; day++) {
        seen.add(memories.heroIndex(all, new Date(2026, 8, 2 + day, 12, 0)));
    }
    assert(seen.size === 3, `three days showed ${seen.size} different memories`);
});

check('hero: an empty library has no hero rather than memory zero', () => {
    assert(memories.heroIndex([], new Date()) === -1);
});

/* ---------------- scatter ---------------- */

const scatter = loadQmlJs('qml/js/scatter.js');

check('scatter: every photo gets a place', () => {
    for (const count of [1, 2, 5, 17, 40]) {
        const heap = scatter.layout(count);
        assert(heap.items.length === count,
               `${count} photos laid out as ${heap.items.length}`);
        assert(heap.height > 0, `${count} photos gave no height`);
    }
});

check('scatter: rows hold two to four, not a fixed number', () => {
    // A pile does not have columns. Rows of a single repeated width were
    // exactly what the first version looked like.
    const widths = new Set();
    for (const item of scatter.layout(40).items) {
        widths.add(item.w.toFixed(4));
    }
    assert(widths.size >= 2, `every row came out the same width: ${[...widths]}`);
});

check('scatter: nothing wanders off the table', () => {
    for (const count of [3, 12, 40]) {
        for (const item of scatter.layout(count).items) {
            assert(item.x > -0.05 && item.x + item.w < 1.05,
                   `x ${item.x} width ${item.w} leaves the table`);
            assert(item.y >= -0.05, `y ${item.y} is above the table`);
        }
    }
});

check('scatter: the table is tall enough to hold the pile', () => {
    for (const count of [1, 7, 40]) {
        const heap = scatter.layout(count);
        for (const item of heap.items) {
            assert(item.y + item.h <= heap.height + 1e-9,
                   `a photo reaches ${item.y + item.h}, the table stops at ${heap.height}`);
        }
    }
});

check('scatter: rotations are small enough to still read as prints', () => {
    for (const item of scatter.layout(40).items) {
        assert(Math.abs(item.rotation) <= 10,
               `rotated ${item.rotation} degrees`);
    }
});

check('scatter: the same photos always land the same way', () => {
    // Turning the phone rescales the heap; it must not deal a new one
    const a = JSON.stringify(scatter.layout(23));
    const b = JSON.stringify(scatter.layout(23));
    assert(a === b, 'two layouts of the same count differed');
});

check('scatter: different memories do not open on the same arrangement', () => {
    const a = scatter.layout(9).items[0];
    const b = scatter.layout(10).items[0];
    assert(a.w !== b.w || a.x !== b.x, 'both memories started identically');
});

check('scatter: nothing to lay out is not an error', () => {
    assert(scatter.layout(0).items.length === 0, 'zero');
    assert(scatter.layout(0).height === 0, 'zero height');
    assert(scatter.layout(-3).items.length === 0, 'negative');
});

/* ---------------- report ---------------- */

for (const failure of failures) {
    console.log(`FAIL  ${failure.name}\n      ${failure.message}`);
}
console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
