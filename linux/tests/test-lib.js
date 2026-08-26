// Unit tests for the extension's pure logic (lib.js) — the JS mirror of
// LabelFormatterTests/StatusFileStoreTests/RateLimitStatusTests. Runs
// under plain `gjs -m linux/tests/test-lib.js`; no GNOME Shell needed.

import System from 'system';
import * as Lib from '../gnome-extension/tokenmeter@sh4r11f.github.io/lib.js';

let failures = 0;

function assertEq(actual, expected, label) {
    // JSON round-trip gives cheap structural equality for plain objects.
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) {
        print(`ok: ${label}`);
    } else {
        print(`FAIL: ${label} — expected ${e}, got ${a}`);
        failures += 1;
    }
}

// A fixed "now" makes every staleness/countdown case deterministic.
const NOW = 1_755_400_000;

// Builds status.json text captured `age` seconds before NOW.
function snapshotText(rateLimits, age = 0) {
    return JSON.stringify({captured_at: NOW - age, rate_limits: rateLimits});
}

const FULL = {
    five_hour: {used_percentage: 42.3, resets_at: NOW + 2 * 3600 + 13 * 60},
    seven_day: {used_percentage: 18.1, resets_at: NOW + 3 * 86400 + 4 * 3600},
};

// --- classifyStatus: file-state classification -------------------------

assertEq(Lib.classifyStatus(null, NOW).state, 'not-installed', 'missing file → not-installed');
assertEq(Lib.classifyStatus('not json{', NOW).state, 'decode-error', 'garbage → decode-error');
assertEq(Lib.classifyStatus('{"rate_limits": null}', NOW).state, 'decode-error', 'missing captured_at → decode-error');
assertEq(Lib.classifyStatus(snapshotText(null), NOW).state, 'no-data', 'rate_limits null → no-data');
assertEq(Lib.classifyStatus(snapshotText({}), NOW).state, 'no-data', 'both windows absent → no-data');

const okFresh = Lib.classifyStatus(snapshotText(FULL), NOW);
assertEq(okFresh.state, 'ok', 'full payload → ok');
assertEq(okFresh.isStale, false, 'fresh snapshot not stale');
assertEq(okFresh.fiveHour.usedPercentage, 42.3, 'five-hour percentage parsed');
assertEq(okFresh.sevenDay.usedPercentage, 18.1, 'seven-day percentage parsed');

// Staleness boundary matches Swift's `age > staleAfter` (strictly greater).
assertEq(Lib.classifyStatus(snapshotText(FULL, 120), NOW).isStale, false, 'exactly 120s old → not stale');
assertEq(Lib.classifyStatus(snapshotText(FULL, 121), NOW).isStale, true, '121s old → stale');

// --- compactLabel: text, thresholds, staleness -------------------------

function labelFor(rateLimits, metric, age = 0) {
    return Lib.compactLabel(Lib.classifyStatus(snapshotText(rateLimits, age), NOW), metric);
}

assertEq(Lib.compactLabel({state: 'not-installed'}, 'five-hour'),
    {text: '–', level: 'unknown', isStale: false}, 'not-installed label');
assertEq(Lib.compactLabel({state: 'decode-error'}, 'five-hour'),
    {text: '!', level: 'unknown', isStale: false}, 'decode-error label');
assertEq(labelFor(null, 'five-hour'),
    {text: 'n/a', level: 'unknown', isStale: false}, 'no-data label');
assertEq(labelFor(FULL, 'five-hour'),
    {text: '5h 42%', level: 'normal', isStale: false}, 'five-hour label, 42.3 rounds to 42');
assertEq(labelFor(FULL, 'seven-day'),
    {text: '7d 18%', level: 'normal', isStale: false}, 'seven-day label');
assertEq(labelFor(FULL, 'five-hour', 300).isStale, true, 'stale flag carries into label');

// Thresholds mirror the mac app: warning at >=50, critical strictly >80.
const pct = p => ({five_hour: {used_percentage: p, resets_at: NOW + 60}});
assertEq(labelFor(pct(49.9), 'five-hour').level, 'normal', '49.9% → normal');
assertEq(labelFor(pct(50), 'five-hour').level, 'warning', '50% → warning');
assertEq(labelFor(pct(80), 'five-hour').level, 'warning', '80% → still warning');
assertEq(labelFor(pct(80.1), 'five-hour').level, 'critical', '80.1% → critical');
assertEq(labelFor(pct(42.5), 'five-hour').text, '5h 43%', '42.5 rounds up like Swift .rounded()');

// Metric selection, including the five-hour tie-break for most-urgent.
const fiveOnly = {five_hour: {used_percentage: 7, resets_at: NOW + 60}};
assertEq(labelFor(fiveOnly, 'seven-day').text, 'n/a', 'seven-day metric with five-only data → n/a');
assertEq(labelFor(fiveOnly, 'most-urgent').text, '5h 7%', 'most-urgent falls back to the only window');
assertEq(labelFor(FULL, 'most-urgent').text, '5h 42%', 'most-urgent picks the higher window');
const tied = {
    five_hour: {used_percentage: 33, resets_at: NOW + 60},
    seven_day: {used_percentage: 33, resets_at: NOW + 60},
};
assertEq(labelFor(tied, 'most-urgent').text, '5h 33%', 'most-urgent tie goes to five-hour');
const sevenHigher = {
    five_hour: {used_percentage: 10, resets_at: NOW + 60},
    seven_day: {used_percentage: 90, resets_at: NOW + 60},
};
assertEq(labelFor(sevenHigher, 'most-urgent'),
    {text: '7d 90%', level: 'critical', isStale: false}, 'most-urgent picks seven-day when higher');

// --- time formatting ---------------------------------------------------

assertEq(Lib.formatResetDelta(NOW + 2 * 3600 + 13 * 60, NOW), 'resets in 2h 13m', 'h/m countdown');
assertEq(Lib.formatResetDelta(NOW + 3 * 86400 + 4 * 3600, NOW), 'resets in 3d 4h', 'd/h countdown');
assertEq(Lib.formatResetDelta(NOW + 45, NOW), 'resets in 1m', 'sub-minute rounds up to 1m');
assertEq(Lib.formatResetDelta(NOW - 10, NOW), 'resets any moment', 'past reset time');
assertEq(Lib.formatResetDelta(0, NOW), 'reset time unknown', 'missing reset time');

assertEq(Lib.formatAgo(NOW - 3, NOW), 'just now', 'under 10s → just now');
assertEq(Lib.formatAgo(NOW - 42, NOW), '42s ago', 'seconds bucket');
assertEq(Lib.formatAgo(NOW - 5 * 60, NOW), '5m ago', 'minutes bucket');
assertEq(Lib.formatAgo(NOW - 3 * 3600, NOW), '3h ago', 'hours bucket');
assertEq(Lib.formatAgo(NOW - 2 * 86400, NOW), '2d ago', 'days bucket');

if (failures > 0) {
    print(`${failures} test(s) failed`);
    System.exit(1);
}
print('all lib.js tests passed');
