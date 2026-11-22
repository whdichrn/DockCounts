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
        XCTAssertEqual(preferences.badgeVisibility, .auto)
        XCTAssertTrue(preferences.windowSelectionEnabled)
        XCTAssertEqual(preferences.triggerMode, .multipleWindows)
        XCTAssertTrue(preferences.minimizeActiveSingleWindow)
        XCTAssertTrue(preferences.secondClickRunsNativeAction)
        XCTAssertTrue(preferences.cmdTabRestoreMinimized)
        XCTAssertEqual(preferences.cmdTabMultiMinimizedBehavior, .showPicker)
        XCTAssertTrue(preferences.cmdTabReopenEmptyApp)
        XCTAssertEqual(preferences.appearanceMode, .system)
        XCTAssertEqual(preferences.language, .system)
        XCTAssertEqual(preferences.appearance.preset, .glass)
        XCTAssertEqual(preferences.appearance.size, .compact)
        XCTAssertEqual(preferences.appearance.opacity, 1.0)
        XCTAssertEqual(SettingsTab.allCases, [.general, .enhancement, .appearance, .about])
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
              "badgeVisibility": "smart",
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
            XCTAssertEqual(migrated.badgeVisibility, .auto)
            XCTAssertEqual(migrated.triggerMode, .anyWindow)
            XCTAssertTrue(migrated.secondClickRunsNativeAction)
            XCTAssertEqual(migrated.appearanceMode, .system)
            XCTAssertEqual(migrated.language, .system)
            XCTAssertEqual(migrated.appearance.preset, .solid)
            XCTAssertEqual(migrated.appearance.opacity, 0.4)

            defaults.set(
                Data("{\"badgeVisibility\":\"minimizedOnly\"}".utf8),
                forKey: PreferencesStore.key
            )
            XCTAssertEqual(store.load().badgeVisibility, .hidden)

            defaults.set(
                Data("{\"badgeVisibility\":\"always\"}".utf8),
                forKey: PreferencesStore.key
            )
            XCTAssertEqual(store.load().badgeVisibility, .always)
        }
    }

    func testAllSettingsPersistAcrossNewStoreInstance() {
        withStore { store, defaults in
            var preferences = AppPreferences()
            preferences.enabled = false
            preferences.badgesEnabled = false
            preferences.badgeVisibility = .hidden
            preferences.windowSelectionEnabled = true
            preferences.triggerMode = .anyWindow
            preferences.minimizeActiveSingleWindow = false
            preferences.secondClickRunsNativeAction = false
            preferences.cmdTabRestoreMinimized = false
            preferences.cmdTabMultiMinimizedBehavior = .restoreRecent
            preferences.cmdTabReopenEmptyApp = false
            preferences.appearanceMode = .dark
            preferences.language = .en
            preferences.appearance.preset = .accent
            preferences.appearance.size = .standard
            preferences.appearance.opacity = 0.72
            store.save(preferences)

            XCTAssertEqual(PreferencesStore(defaults: defaults).load(), preferences)
            XCTAssertFalse(defaults.bool(forKey: "enabled"))
        }
    }

    func testAppearanceModeMapsNSAppearanceAndColorScheme() {
        XCTAssertNil(AppAppearanceMode.system.nsAppearance)
        XCTAssertNil(AppAppearanceMode.system.preferredColorScheme)

        XCTAssertEqual(AppAppearanceMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppAppearanceMode.light.preferredColorScheme, .light)

        XCTAssertEqual(AppAppearanceMode.dark.nsAppearance?.name, .darkAqua)
        XCTAssertEqual(AppAppearanceMode.dark.preferredColorScheme, .dark)
    }

    func testAppLanguageResolution() {
        XCTAssertEqual(AppLanguage.system.resolve(preferredLanguages: ["zh-Hans-CN", "en-US"]), .zhHans)
        XCTAssertEqual(AppLanguage.system.resolve(preferredLanguages: ["zh-Hant-TW"]), .zhHans)
        XCTAssertEqual(AppLanguage.system.resolve(preferredLanguages: ["en-US", "zh-Hans-CN"]), .en)
        XCTAssertEqual(AppLanguage.zhHans.resolve(preferredLanguages: ["en-US"]), .zhHans)
        XCTAssertEqual(AppLanguage.en.resolve(preferredLanguages: ["zh-Hans-CN"]), .en)
        XCTAssertEqual(AppLanguage.system.title(in: .zhHans), "跟随系统")
        XCTAssertEqual(AppLanguage.system.title(in: .en), "System")
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
