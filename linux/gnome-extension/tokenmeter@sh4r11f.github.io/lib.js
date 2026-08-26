// TokenMeter — pure logic shared by the GNOME Shell extension.
//
// This module is the JavaScript port of TokenMeterCore's StatusFileStore
// classification and LabelFormatter (see Sources/TokenMeterCore/), kept
// free of GNOME imports so `gjs -m linux/tests/test-lib.js` can unit-test
// every branch without a running shell. extension.js does the I/O and
// rendering; everything decidable from plain data lives here.

/** Snapshot older than this (seconds) is shown dimmed as "stale". */
export const STALE_AFTER_SECONDS = 120;

/** used_percentage thresholds for label coloring, matching the mac app. */
export const WARNING_AT = 50; // >= this: yellow
export const CRITICAL_AT = 80; // > this: red

/**
 * Classify the raw text of status.json the way StatusFileStore does.
 *
 * @param {string|null} text  file contents, or null if the file is missing
 * @param {number} nowEpochSeconds  current time, injected for testability
 * @returns {{state: 'not-installed'|'decode-error'|'no-data'|'ok',
 *            capturedAt?: number, isStale?: boolean,
 *            fiveHour?: {usedPercentage: number, resetsAt: number}|null,
 *            sevenDay?: {usedPercentage: number, resetsAt: number}|null}}
 */
export function classifyStatus(text, nowEpochSeconds) {
    // Missing file means the hook never ran — "not installed yet", not an error.
    if (text === null || text === undefined)
        return {state: 'not-installed'};

    let parsed;
    try {
        parsed = JSON.parse(text);
    } catch (_e) {
        return {state: 'decode-error'};
    }

    // captured_at is required by the snapshot schema statusline.sh writes;
    // anything else is a snapshot we can't trust.
    if (typeof parsed !== 'object' || parsed === null || typeof parsed.captured_at !== 'number')
        return {state: 'decode-error'};

    const capturedAt = parsed.captured_at;
    const isStale = (nowEpochSeconds - capturedAt) > STALE_AFTER_SECONDS;

    // rate_limits: null means the hook ran but the account has no
    // subscription windows (API-key usage) — a distinct, honest state.
    const rl = parsed.rate_limits;
    if (rl === null || rl === undefined)
        return {state: 'no-data', capturedAt, isStale};

    const readWindow = w => {
        if (typeof w !== 'object' || w === null || typeof w.used_percentage !== 'number')
            return null;
        return {
            usedPercentage: w.used_percentage,
            // resets_at is unix epoch seconds; tolerate it missing (0 = unknown).
            resetsAt: typeof w.resets_at === 'number' ? w.resets_at : 0,
        };
    };

    const fiveHour = readWindow(rl.five_hour);
    const sevenDay = readWindow(rl.seven_day);
    if (fiveHour === null && sevenDay === null)
        return {state: 'no-data', capturedAt, isStale};

    return {state: 'ok', capturedAt, isStale, fiveHour, sevenDay};
}

/**
 * Pick the window that drives the compact top-bar label — the port of
 * LabelFormatter.selectedWindow. `metric` uses the gsettings nicks.
 *
 * @param {ReturnType<typeof classifyStatus>} status  an 'ok' classification
 * @param {'five-hour'|'seven-day'|'most-urgent'} metric
 * @returns {{prefix: string, usedPercentage: number}|null}
 */
export function selectedWindow(status, metric) {
    const five = status.fiveHour ? {prefix: '5h', usedPercentage: status.fiveHour.usedPercentage} : null;
    const seven = status.sevenDay ? {prefix: '7d', usedPercentage: status.sevenDay.usedPercentage} : null;
    switch (metric) {
    case 'seven-day':
        return seven;
    case 'most-urgent':
        // Ties go to the 5-hour window, matching the Swift implementation.
        if (five && seven)
            return five.usedPercentage >= seven.usedPercentage ? five : seven;
        return five ?? seven;
    case 'five-hour':
    default:
        return five;
    }
}

/**
 * The complete top-bar label: text, urgency level, staleness — the port
 * of LabelFormatter.compactLabel.
 *
 * @returns {{text: string, level: 'normal'|'warning'|'critical'|'unknown', isStale: boolean}}
 */
export function compactLabel(status, metric) {
    switch (status.state) {
    case 'not-installed':
        return {text: '–', level: 'unknown', isStale: false};
    case 'decode-error':
        return {text: '!', level: 'unknown', isStale: false};
    case 'no-data':
        return {text: 'n/a', level: 'unknown', isStale: status.isStale};
    case 'ok': {
        const win = selectedWindow(status, metric);
        if (!win)
            return {text: 'n/a', level: 'unknown', isStale: status.isStale};
        const pct = Math.round(win.usedPercentage);
        const level = win.usedPercentage > CRITICAL_AT
            ? 'critical'
            : (win.usedPercentage >= WARNING_AT ? 'warning' : 'normal');
        return {text: `${win.prefix} ${pct}%`, level, isStale: status.isStale};
    }
    default:
        return {text: '?', level: 'unknown', isStale: false};
    }
}

/**
 * "Resets in 2h 13m" / "in 3d 4h" style countdown. Two units maximum so
 * the popup stays scannable; already-passed reset times say "any moment"
 * because the server clock decides, not us.
 */
export function formatResetDelta(resetsAtEpoch, nowEpochSeconds) {
    const delta = resetsAtEpoch - nowEpochSeconds;
    if (resetsAtEpoch <= 0)
        return 'reset time unknown';
    if (delta <= 0)
        return 'resets any moment';
    const days = Math.floor(delta / 86400);
    const hours = Math.floor((delta % 86400) / 3600);
    const minutes = Math.floor((delta % 3600) / 60);
    if (days > 0)
        return `resets in ${days}d ${hours}h`;
    if (hours > 0)
        return `resets in ${hours}h ${minutes}m`;
    return `resets in ${Math.max(minutes, 1)}m`;
}

/** "Updated just now" / "42s ago" / "5m ago" / "3h ago" / "2d ago". */
export function formatAgo(capturedAtEpoch, nowEpochSeconds) {
    const delta = Math.max(0, nowEpochSeconds - capturedAtEpoch);
    if (delta < 10)
        return 'just now';
    if (delta < 60)
        return `${Math.floor(delta)}s ago`;
    if (delta < 3600)
        return `${Math.floor(delta / 60)}m ago`;
    if (delta < 86400)
        return `${Math.floor(delta / 3600)}h ago`;
    return `${Math.floor(delta / 86400)}d ago`;
}
