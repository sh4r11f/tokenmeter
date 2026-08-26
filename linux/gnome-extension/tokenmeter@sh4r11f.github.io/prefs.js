// TokenMeter — preferences window (the Linux counterpart of the mac
// app's PreferencesView). One choice: which rate-limit window drives the
// compact top-bar label. Launch-at-login has no equivalent here — the
// extension runs whenever GNOME Shell does.

import Adw from 'gi://Adw';
import Gtk from 'gi://Gtk';

import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

// Display order ↔ gsettings nick mapping for the combo row.
const METRIC_NICKS = ['five-hour', 'seven-day', 'most-urgent'];
const METRIC_TITLES = ['5-hour limit', '7-day limit', 'Whichever is more urgent'];

export default class TokenMeterPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        const page = new Adw.PreferencesPage();
        const group = new Adw.PreferencesGroup({
            title: 'Top bar label',
            description: 'Which rate-limit window the compact label shows.',
        });

        const row = new Adw.ComboRow({
            title: 'Metric',
            model: Gtk.StringList.new(METRIC_TITLES),
        });
        // Reflect the stored setting; unknown values fall back to 5-hour.
        row.selected = Math.max(0, METRIC_NICKS.indexOf(settings.get_string('label-metric')));
        row.connect('notify::selected', () => {
            settings.set_string('label-metric', METRIC_NICKS[row.selected]);
        });

        group.add(row);
        page.add(group);
        window.add(page);
    }
}
