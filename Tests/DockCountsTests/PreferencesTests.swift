import XCTest
import AppKit
import ApplicationServices
@testable import DockCounts

final class PreferencesTests: XCTestCase {
    func testCustomHexColorRoundTripAndInvalidInput() {
        let color = RGBColor(hex: " #E55A32 ")!
        XCTAssertEqual(color.hex, "#E55A32")
        XCTAssertEqual(RGBColor(hex: "e55a32"), color)
        XCTAssertNil(RGBColor(hex: "#12"))
        XCTAssertNil(RGBColor(hex: "GGGGGG"))
        XCTAssertNil(RGBColor(hex: "１２３４５６"))
        XCTAssertEqual(RGBColor(red: 2, green: -1, blue: 0.5).hex, "#FF0080")
    }
    private func withStore(_ test: (PreferencesStore, UserDefaults) throws -> Void) rethrows {
        let name = "DockCountsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try test(PreferencesStore(defaults: defaults), defaults)
    }
    func testIndependentFeatureCombinationsAndSingleWindowPolicy() {
        for master in [false, true] {
            for badges in [false, true] {
                for selection in [false, true] {
                    var preferences = AppPreferences()
                    preferences.enabled = master; preferences.badgesEnabled = badges; preferences.windowSelectionEnabled = selection
                    XCTAssertEqual(preferences.needsDock, master && (badges || selection))
                    XCTAssertEqual(preferences.selectsWindow(total: 2), master && selection)
                    XCTAssertFalse(preferences.selectsWindow(total: 0))
                    preferences.selectSingleWindow = false
                    XCTAssertFalse(preferences.selectsWindow(total: 1))
                    XCTAssertEqual(preferences.selectsWindow(total: 3), master && selection)
                    preferences.selectSingleWindow = true
                    XCTAssertEqual(preferences.selectsWindow(total: 1), master && selection)
                }
            }
        }
    }
    func testLegacyPauseMigratesWithoutDisablingIndependentDefaults() {
        withStore { store, defaults in
            defaults.set(false, forKey: "enabled")
            let preferences = store.load()
            XCTAssertFalse(preferences.enabled)
            XCTAssertTrue(preferences.badgesEnabled)
            XCTAssertTrue(preferences.windowSelectionEnabled)
            XCTAssertTrue(preferences.selectSingleWindow)
        }
    }
    func testAllSettingsPersistAcrossNewStoreInstance() {
        withStore { store, defaults in
            var preferences = AppPreferences()
            preferences.enabled = false; preferences.badgesEnabled = false
            preferences.windowSelectionEnabled = true; preferences.selectSingleWindow = false
            preferences.appearance.surface = .solid
            preferences.appearance.backgroundOpacity = 0.43
            preferences.appearance.edge = .outline
            preferences.appearance.highlights = false; preferences.appearance.shadow = false; preferences.appearance.vivid = true
            preferences.appearance.tint = .custom; preferences.appearance.tintStrength = 0.82
            preferences.appearance.customColor = RGBColor(red: 0.9, green: 0.1, blue: 0.2)
            preferences.appearance.textColor = .light
            store.save(preferences)
            XCTAssertEqual(PreferencesStore(defaults: defaults).load(), preferences)
            XCTAssertFalse(defaults.bool(forKey: "enabled"))
        }
    }
    func testIncompleteOrDamagedSettingsHaveSafeDefaultsAndClampValues() throws {
        withStore { store, defaults in
            defaults.set(Data("{\"badgesEnabled\":false,\"appearance\":{\"backgroundOpacity\":4,\"tintStrength\":-2}}".utf8), forKey: PreferencesStore.key)
            let loaded = store.load()
            XCTAssertFalse(loaded.badgesEnabled); XCTAssertTrue(loaded.windowSelectionEnabled)
            XCTAssertEqual(loaded.appearance.backgroundOpacity, 1)
            XCTAssertEqual(loaded.appearance.tintStrength, 0)
            defaults.set(Data("broken".utf8), forKey: PreferencesStore.key)
            XCTAssertEqual(store.load(), AppPreferences())
        }
    }
    func testMaterialAvailabilityAndHighlightSwitchSelectCorrectPresentation() {
        var style = BadgeAppearance()
        XCTAssertEqual(style.resolvedSurface(reduceTransparency: true, supportsGlass: true), .clear)
        XCTAssertEqual(style.resolvedSurface(reduceTransparency: false, supportsGlass: true), .glass)
        XCTAssertEqual(style.resolvedSurface(reduceTransparency: true, supportsGlass: false), .frosted)
        style.highlights = false
        XCTAssertEqual(style.resolvedSurface(reduceTransparency: true, supportsGlass: true), .frosted)
        style.surface = .solid
        XCTAssertEqual(style.resolvedSurface(reduceTransparency: true, supportsGlass: true), .solid)
        style.tint = .none
        XCTAssertNil(style.tintColor())
        XCTAssertEqual(style.effectiveTintStrength(reduceTransparency: true), 0)
    }
    func testAutomaticTextContrastForCustomDarkAndLightTintAndExplicitOverrides() {
        var style = BadgeAppearance()
        style.surface = .solid; style.tint = .custom; style.tintStrength = 1
        style.customColor = RGBColor(red: 0.02, green: 0.02, blue: 0.02)
        XCTAssertTrue(style.usesLightText(reduceTransparency: false, supportsGlass: true, darkAppearance: false))
        style.customColor = RGBColor(red: 0.97, green: 0.97, blue: 0.97)
        XCTAssertFalse(style.usesLightText(reduceTransparency: false, supportsGlass: true, darkAppearance: true))
        style.textColor = .light
        XCTAssertTrue(style.usesLightText(reduceTransparency: false, supportsGlass: true, darkAppearance: false))
        style.textColor = .dark
        XCTAssertFalse(style.usesLightText(reduceTransparency: false, supportsGlass: true, darkAppearance: true))
    }
}
