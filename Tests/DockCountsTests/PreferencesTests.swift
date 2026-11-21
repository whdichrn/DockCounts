import XCTest
import AppKit
@testable import DockCounts

final class PreferencesTests: XCTestCase {
    private func withStore(_ test: (PreferencesStore, UserDefaults) throws -> Void) rethrows {
        let name = "DockCountsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try test(PreferencesStore(defaults: defaults), defaults)
    }

    func testDefaultsPrioritizeSmartNoiseReductionAndMultiWindowTrigger() {
        let preferences = AppPreferences()
        XCTAssertTrue(preferences.enabled)
        XCTAssertTrue(preferences.badgesEnabled)
        XCTAssertEqual(preferences.badgeVisibility, .smart)
        XCTAssertTrue(preferences.windowSelectionEnabled)
        XCTAssertEqual(preferences.triggerMode, .multipleWindows)
        XCTAssertTrue(preferences.minimizeActiveSingleWindow)
        XCTAssertEqual(preferences.appearance.preset, .glass)
        XCTAssertEqual(preferences.appearance.size, .compact)
        XCTAssertEqual(preferences.appearance.opacity, 1.0)
    }

    func testClickActionHandlesActiveSingleWindowAndEdgeGuards() {
        let el = AXUIElementCreateApplication(1)
        let normal = WindowRecord(element: el, title: "Doc", minimized: false, isMain: true)
        let minimized = WindowRecord(element: el, title: "Doc", minimized: true, isMain: false)
        let fullScreen = WindowRecord(element: el, title: "Doc", minimized: false, isMain: true, isFullScreen: true)
        let fixedDialog = WindowRecord(element: el, title: "Alert", minimized: false, isMain: true, canMinimize: false)
        let second = WindowRecord(element: el, title: "Doc 2", minimized: false, isMain: false)

        var prefs = AppPreferences()
        XCTAssertEqual(prefs.clickAction(windows: [normal], isAppActive: true), .minimizeSingleWindow)
        XCTAssertEqual(prefs.clickAction(windows: [normal], isAppActive: false), .passThrough)
        XCTAssertEqual(prefs.clickAction(windows: [minimized], isAppActive: true), .passThrough)
        XCTAssertEqual(prefs.clickAction(windows: [fullScreen], isAppActive: true), .passThrough)
        XCTAssertEqual(prefs.clickAction(windows: [fixedDialog], isAppActive: true), .passThrough)
        XCTAssertEqual(prefs.clickAction(windows: [normal, second], isAppActive: true), .openPicker)

        prefs.triggerMode = .anyWindow
        XCTAssertEqual(prefs.clickAction(windows: [normal], isAppActive: true), .minimizeSingleWindow)
        XCTAssertEqual(prefs.clickAction(windows: [minimized], isAppActive: true), .openPicker)
        XCTAssertEqual(prefs.clickAction(windows: [normal], isAppActive: false), .openPicker)

        prefs.minimizeActiveSingleWindow = false
        XCTAssertEqual(prefs.clickAction(windows: [normal], isAppActive: true), .openPicker)
        prefs.triggerMode = .multipleWindows
        XCTAssertEqual(prefs.clickAction(windows: [normal], isAppActive: true), .passThrough)

        prefs.windowSelectionEnabled = false
        XCTAssertEqual(prefs.clickAction(windows: [normal, second], isAppActive: true), .passThrough)
    }

    func testIndependentFeatureCombinationsAndTriggerModes() {
        for master in [false, true] {
            for badges in [false, true] {
                for selection in [false, true] {
                    var preferences = AppPreferences()
                    preferences.enabled = master
                    preferences.badgesEnabled = badges
                    preferences.windowSelectionEnabled = selection
                    XCTAssertEqual(preferences.needsDock, master && (badges || selection))
                    XCTAssertEqual(preferences.selectsWindow(total: 2), master && selection)
                    XCTAssertFalse(preferences.selectsWindow(total: 0))

                    preferences.triggerMode = .multipleWindows
                    XCTAssertFalse(preferences.selectsWindow(total: 1))
                    XCTAssertEqual(preferences.selectsWindow(total: 3), master && selection)

                    preferences.triggerMode = .anyWindow
                    XCTAssertEqual(preferences.selectsWindow(total: 1), master && selection)
                }
            }
        }
    }

    func testLegacyPreferencesMigrateSafely() {
        withStore { store, defaults in
            defaults.set(false, forKey: "enabled")
            let legacyOnlyEnabled = store.load()
            XCTAssertFalse(legacyOnlyEnabled.enabled)
            XCTAssertEqual(legacyOnlyEnabled.triggerMode, .multipleWindows)

            let legacyJSON = """
            {
              "enabled": true,
              "badgesEnabled": true,
              "windowSelectionEnabled": true,
              "selectSingleWindow": true,
              "appearance": {
                "surface": "solid",
                "tint": "neutral",
                "backgroundOpacity": 0.2
              }
            }
            """
            defaults.set(Data(legacyJSON.utf8), forKey: PreferencesStore.key)
            let migrated = store.load()
            XCTAssertEqual(migrated.triggerMode, .anyWindow)
            XCTAssertEqual(migrated.appearance.preset, .solid)
            XCTAssertEqual(migrated.appearance.opacity, 0.4)
        }
    }

    func testAllSettingsPersistAcrossNewStoreInstance() {
        withStore { store, defaults in
            var preferences = AppPreferences()
            preferences.enabled = false
            preferences.badgesEnabled = false
            preferences.badgeVisibility = .minimizedOnly
            preferences.windowSelectionEnabled = true
            preferences.triggerMode = .anyWindow
            preferences.minimizeActiveSingleWindow = false
            preferences.appearance.preset = .accent
            preferences.appearance.size = .standard
            preferences.appearance.opacity = 0.72
            store.save(preferences)

            XCTAssertEqual(PreferencesStore(defaults: defaults).load(), preferences)
            XCTAssertFalse(defaults.bool(forKey: "enabled"))
        }
    }

    func testIncompleteOrDamagedSettingsHaveSafeDefaultsAndClampValues() {
        withStore { store, defaults in
            defaults.set(
                Data("{\"badgesEnabled\":false,\"appearance\":{\"opacity\":4}}".utf8),
                forKey: PreferencesStore.key
            )
            let loaded = store.load()
            XCTAssertFalse(loaded.badgesEnabled)
            XCTAssertTrue(loaded.windowSelectionEnabled)
            XCTAssertEqual(loaded.appearance.opacity, 1.0)

            defaults.set(Data("{\"appearance\":{\"opacity\":0.1}}".utf8), forKey: PreferencesStore.key)
            XCTAssertEqual(store.load().appearance.opacity, 0.4)

            defaults.set(Data("broken".utf8), forKey: PreferencesStore.key)
            XCTAssertEqual(store.load(), AppPreferences())
        }
    }
}
