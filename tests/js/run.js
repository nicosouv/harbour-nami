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

/* ---------------- report ---------------- */

for (const failure of failures) {
    console.log(`FAIL  ${failure.name}\n      ${failure.message}`);
}
console.log(`\n${passed} passed, ${failures.length} failed`);
process.exit(failures.length ? 1 : 0);
