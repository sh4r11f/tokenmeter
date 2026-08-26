// TokenMeter — GNOME Shell extension (the Linux counterpart of the
// macOS menu bar app in Sources/TokenMeter/).
//
// Renders a top-bar indicator ("5h 42%") from the snapshot that
// ~/.claude/tokenmeter/statusline.sh writes, with a popup showing both
// rate-limit windows, a label-metric preference, and a "Repair hook"
// action. All data is read from the local status file; this extension
// performs no network I/O of any kind.
//
// Freshness strategy (mirrors the mac app): a Gio directory monitor for
// instant updates when status.json is atomically replaced, plus a 10s
// poll as a safety net — the poll also re-evaluates staleness, which
// flips with no file event at all.

import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

import * as Lib from './lib.js';

const POLL_INTERVAL_SECONDS = 10;

/** Path helpers — everything TokenMeter touches lives under ~/.claude. */
function tokenMeterDir() {
    return GLib.build_filenamev([GLib.get_home_dir(), '.claude', 'tokenmeter']);
}

function statusFilePath() {
    return GLib.build_filenamev([tokenMeterDir(), 'status.json']);
}

function repairScriptPath() {
    return GLib.build_filenamev([tokenMeterDir(), 'install-hook.sh']);
}

/**
 * Read status.json, returning its text or null when missing/unreadable —
 * null is the "not installed yet" signal classifyStatus expects.
 */
function readStatusFile() {
    try {
        const [, bytes] = GLib.file_get_contents(statusFilePath());
        return new TextDecoder().decode(bytes);
    } catch (_e) {
        return null;
    }
}

const Indicator = GObject.registerClass(
class TokenMeterIndicator extends PanelMenu.Button {
    _init(extension) {
        // 0.5 = menu alignment; the string names the accessible label.
        super._init(0.5, 'TokenMeter');
        this._extension = extension;
        this._settings = extension.getSettings();

        // --- Top bar: gauge icon + compact percentage label. ---
        const box = new St.BoxLayout({style_class: 'panel-status-menu-box'});
        this._icon = new St.Icon({
            gicon: Gio.FileIcon.new(Gio.File.new_for_path(
                GLib.build_filenamev([extension.path, 'icons', 'tokenmeter-symbolic.svg']))),
            style_class: 'system-status-icon',
        });
        this._label = new St.Label({
            text: '–',
            y_align: Clutter.ActorAlign.CENTER,
            style_class: 'tokenmeter-label',
        });
        box.add_child(this._icon);
        box.add_child(this._label);
        this.add_child(box);

        // --- Popup menu. The status section is rebuilt on every refresh;
        // the static items below it are created once. ---
        this._statusSection = new PopupMenu.PopupMenuSection();
        this.menu.addMenuItem(this._statusSection);
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._buildMetricSubmenu();
        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        const repairItem = new PopupMenu.PopupMenuItem('Repair hook');
        repairItem.connect('activate', () => this._repairHook());
        this.menu.addMenuItem(repairItem);

        const prefsItem = new PopupMenu.PopupMenuItem('Preferences…');
        prefsItem.connect('activate', () => this._extension.openPreferences());
        this.menu.addMenuItem(prefsItem);

        // React to metric changes from either the submenu or the prefs window.
        this._settingsChangedId = this._settings.connect(
            'changed::label-metric', () => this._refresh());

        // Refresh right as the menu opens so countdown/"ago" text is current.
        this._menuOpenId = this.menu.connect('open-state-changed', (_menu, open) => {
            if (open)
                this._refresh();
        });

        this._startWatching();
        this._refresh();
    }

    /** "Top bar shows" submenu with one radio item per metric. */
    _buildMetricSubmenu() {
        this._metricSubmenu = new PopupMenu.PopupSubMenuMenuItem('Top bar shows');
        this._metricItems = new Map();
        for (const [nick, title] of [
            ['five-hour', '5-hour limit'],
            ['seven-day', '7-day limit'],
            ['most-urgent', 'Whichever is more urgent'],
        ]) {
            const item = new PopupMenu.PopupMenuItem(title);
            item.connect('activate', () => this._settings.set_string('label-metric', nick));
            this._metricSubmenu.menu.addMenuItem(item);
            this._metricItems.set(nick, item);
        }
        this.menu.addMenuItem(this._metricSubmenu);
    }

    /**
     * Watch the tokenmeter directory (not the file) because statusline.sh
     * replaces status.json via mv — a directory monitor sees that rename
     * reliably. The directory may not exist before the first install, so
     * _refresh() retries establishing the monitor on every poll tick.
     */
    _startWatching() {
        this._ensureMonitor();
        this._pollId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, POLL_INTERVAL_SECONDS, () => {
            this._ensureMonitor();
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _ensureMonitor() {
        if (this._monitor)
            return;
        const dir = Gio.File.new_for_path(tokenMeterDir());
        if (!dir.query_exists(null))
            return;
        try {
            this._monitor = dir.monitor_directory(Gio.FileMonitorFlags.NONE, null);
            this._monitorChangedId = this._monitor.connect('changed', (_m, file) => {
                // Only react to the snapshot itself, not backups or temp files.
                if (file.get_basename() === 'status.json')
                    this._refresh();
            });
        } catch (e) {
            // Fall back to polling only; never let a monitor failure take
            // down the whole indicator.
            console.warn(`TokenMeter: directory monitor failed, using poll only: ${e.message}`);
            this._monitor = null;
        }
    }

    /** Re-read status.json and redraw the label and the popup status section. */
    _refresh() {
        const now = Date.now() / 1000;
        const status = Lib.classifyStatus(readStatusFile(), now);
        const metric = this._settings.get_string('label-metric');
        const label = Lib.compactLabel(status, metric);

        this._label.text = label.text;
        // Reset styling classes, then apply the ones this state earns.
        for (const cls of ['tokenmeter-warning', 'tokenmeter-critical', 'tokenmeter-dim', 'tokenmeter-stale']) {
            this._label.remove_style_class_name(cls);
            this._icon.remove_style_class_name(cls);
        }
        if (label.level === 'warning')
            this._label.add_style_class_name('tokenmeter-warning');
        else if (label.level === 'critical')
            this._label.add_style_class_name('tokenmeter-critical');
        else if (label.level === 'unknown')
            this._label.add_style_class_name('tokenmeter-dim');
        if (label.isStale) {
            this._label.add_style_class_name('tokenmeter-stale');
            this._icon.add_style_class_name('tokenmeter-stale');
        }

        // Radio ornaments for the metric submenu.
        for (const [nick, item] of this._metricItems) {
            item.setOrnament(nick === metric
                ? PopupMenu.Ornament.DOT
                : PopupMenu.Ornament.NONE);
        }

        this._rebuildStatusSection(status, now);
    }

    /** The dynamic top part of the popup: one block per rate-limit window. */
    _rebuildStatusSection(status, now) {
        this._statusSection.removeAll();

        const addLine = (text, dim = false) => {
            const item = new PopupMenu.PopupMenuItem(text, {reactive: false});
            if (dim)
                item.label.add_style_class_name('tokenmeter-menu-dim');
            this._statusSection.addMenuItem(item);
        };

        switch (status.state) {
        case 'not-installed':
            addLine('Not installed yet');
            addLine('Use "Repair hook" to set up the Claude Code', true);
            addLine('status line integration, then send a message', true);
            addLine('in any Claude Code session.', true);
            break;
        case 'decode-error':
            addLine('Couldn\'t read usage data');
            addLine('status.json exists but isn\'t valid — try "Repair hook".', true);
            break;
        case 'no-data':
            addLine('No subscription rate limit data');
            addLine('Rate limits appear for Claude.ai subscription', true);
            addLine('plans (Pro/Max), not API-key usage.', true);
            addLine(`Updated ${Lib.formatAgo(status.capturedAt, now)}${status.isStale ? ' — stale' : ''}`, true);
            break;
        case 'ok': {
            const addWindow = (title, win) => {
                if (!win)
                    return;
                const used = Math.round(win.usedPercentage);
                const left = Math.round(100 - win.usedPercentage);
                addLine(`${title} — ${used}% used · ${left}% left`);
                addLine(`    ${Lib.formatResetDelta(win.resetsAt, now)}`, true);
            };
            addWindow('5-hour session', status.fiveHour);
            addWindow('7-day weekly', status.sevenDay);
            addLine(`Updated ${Lib.formatAgo(status.capturedAt, now)}${status.isStale ? ' — stale' : ''}`, true);
            break;
        }
        }
    }

    /**
     * Re-run the hook installer that linux/install.sh copied to
     * ~/.claude/tokenmeter/install-hook.sh. Fixed argv (no shell string
     * interpolation), result surfaced as a desktop notification — loud
     * either way, never silent.
     */
    _repairHook() {
        const script = repairScriptPath();
        if (!GLib.file_test(script, GLib.FileTest.EXISTS)) {
            Main.notify('TokenMeter', 'Installer not found — run linux/install.sh from the tokenmeter repo first.');
            return;
        }
        try {
            const proc = Gio.Subprocess.new(
                ['bash', script],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE);
            proc.communicate_utf8_async(null, null, (p, res) => {
                let message;
                try {
                    const [, stdout] = p.communicate_utf8_finish(res);
                    message = p.get_successful()
                        ? (stdout.trim().split('\n').pop() || 'Hook repaired.')
                        : `Repair failed: ${stdout.trim().split('\n').pop() || 'unknown error'}`;
                } catch (e) {
                    message = `Repair failed: ${e.message}`;
                }
                Main.notify('TokenMeter', message);
                // The actor may have been destroyed while the subprocess ran.
                if (this._label)
                    this._refresh();
            });
        } catch (e) {
            Main.notify('TokenMeter', `Repair failed: ${e.message}`);
        }
    }

    destroy() {
        if (this._pollId) {
            GLib.source_remove(this._pollId);
            this._pollId = null;
        }
        if (this._monitor) {
            this._monitor.disconnect(this._monitorChangedId);
            this._monitor.cancel();
            this._monitor = null;
        }
        if (this._settingsChangedId) {
            this._settings.disconnect(this._settingsChangedId);
            this._settingsChangedId = null;
        }
        this._settings = null;
        this._label = null;
        this._icon = null;
        super.destroy();
    }
});

export default class TokenMeterExtension extends Extension {
    enable() {
        this._indicator = new Indicator(this);
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
