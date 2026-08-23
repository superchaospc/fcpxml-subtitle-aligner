import XCTest
@testable import FCPXMLAlignerCore

final class SettingsPersistenceTests: XCTestCase {
    private var suitesToRemove = [String]()

    override func tearDown() {
        for suite in suitesToRemove {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        suitesToRemove = []
        super.tearDown()
    }

    func testCustomSettingsRoundTrip() {
        let (defaults, key) = makeDefaults()
        let expected = AlignmentSettings(
            actionBaseSize: 21.5,
            ingredientBaseSize: 18.25,
            minimumSize: 14,
            autoShrink: false,
            safeWidthFraction: 0.61
        )
        let store = SettingsStore(defaults: defaults, key: key)

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testMissingSettingsLoadTemplateDefaults() {
        let (defaults, key) = makeDefaults()

        XCTAssertEqual(SettingsStore(defaults: defaults, key: key).load(), .templateDefaults)
    }

    func testCorruptSettingsLoadTemplateDefaults() {
        let (defaults, key) = makeDefaults()
        defaults.set(Data("not settings".utf8), forKey: key)

        XCTAssertEqual(SettingsStore(defaults: defaults, key: key).load(), .templateDefaults)
    }

    func testRestoreDefaultsPersistsTemplateDefaults() {
        let (defaults, key) = makeDefaults()
        let store = SettingsStore(defaults: defaults, key: key)
        store.save(AlignmentSettings(
            actionBaseSize: 20,
            ingredientBaseSize: 19,
            minimumSize: 15,
            autoShrink: false,
            safeWidthFraction: 0.5
        ))

        XCTAssertEqual(store.restoreDefaults(), .templateDefaults)
        XCTAssertEqual(store.load(), .templateDefaults)
    }

    func testUntouchedPreviousTemplateDefaultsMigrateToCurrentTemplate() {
        let (defaults, key) = makeDefaults()
        let store = SettingsStore(defaults: defaults, key: key)
        store.save(AlignmentSettings(
            actionBaseSize: 17,
            ingredientBaseSize: 16,
            minimumSize: 13,
            autoShrink: true,
            safeWidthFraction: 0.72
        ))

        XCTAssertEqual(store.load(), AlignmentSettings.templateDefaults)
        XCTAssertEqual(store.load().ingredientBaseSize, 15)
    }

    func testCustomizedSettingsDoNotMigrateWithPreviousTemplateDefaults() {
        let (defaults, key) = makeDefaults()
        let store = SettingsStore(defaults: defaults, key: key)
        let customized = AlignmentSettings(
            actionBaseSize: 18,
            ingredientBaseSize: 16,
            minimumSize: 13,
            autoShrink: true,
            safeWidthFraction: 0.72
        )
        store.save(customized)

        XCTAssertEqual(store.load(), customized)
    }

    func testStoresWithDifferentSuitesDoNotShareData() {
        let (_, key) = makeDefaults()
        let suiteA = "SettingsPersistenceTests.a.\(UUID().uuidString)"
        let suiteB = "SettingsPersistenceTests.b.\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteA)!
        let defaultsB = UserDefaults(suiteName: suiteB)!
        suitesToRemove.append(contentsOf: [suiteA, suiteB])
        let custom = AlignmentSettings(
            actionBaseSize: 20,
            ingredientBaseSize: 18,
            minimumSize: 12,
            autoShrink: false,
            safeWidthFraction: 0.7
        )

        SettingsStore(defaults: defaultsA, key: key).save(custom)

        XCTAssertEqual(SettingsStore(defaults: defaultsA, key: key).load(), custom)
        XCTAssertEqual(SettingsStore(defaults: defaultsB, key: key).load(), .templateDefaults)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "SettingsPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        suitesToRemove.append(suite)
        return (defaults, "settings.\(UUID().uuidString)")
    }
}
