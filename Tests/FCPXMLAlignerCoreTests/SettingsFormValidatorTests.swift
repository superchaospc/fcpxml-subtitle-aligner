import XCTest
@testable import FCPXMLAlignerCore

final class SettingsFormValidatorTests: XCTestCase {
    func testValidFieldsProduceSettingsAndKeepSafeWidthTemplateValue() throws {
        let fields = SettingsFormFields(
            actionBaseSize: "17.5",
            ingredientBaseSize: "16",
            minimumSize: "13",
            autoShrink: false
        )

        let settings = try SettingsFormValidator.validate(fields).get()

        XCTAssertEqual(settings.actionBaseSize, 17.5)
        XCTAssertEqual(settings.ingredientBaseSize, 16)
        XCTAssertEqual(settings.minimumSize, 13)
        XCTAssertFalse(settings.autoShrink)
        XCTAssertEqual(settings.safeWidthFraction, 0.9)
    }

    func testCommaDecimalIsRejectedIndependentlyOfCurrentLocale() {
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "17,5", ingredientBaseSize: "16", minimumSize: "13", autoShrink: true
            )),
            .failure(.invalidNumber(field: .actionBaseSize))
        )
    }

    func testHexadecimalAndScientificNotationAreRejected() {
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "0x1p0", ingredientBaseSize: "16", minimumSize: "13", autoShrink: true
            )),
            .failure(.invalidNumber(field: .actionBaseSize))
        )
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "1e2", ingredientBaseSize: "16", minimumSize: "13", autoShrink: true
            )),
            .failure(.invalidNumber(field: .actionBaseSize))
        )
    }

    func testNaNAndInfinityAreRejected() {
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "nan", ingredientBaseSize: "16", minimumSize: "13", autoShrink: true
            )),
            .failure(.invalidNumber(field: .actionBaseSize))
        )
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "17", ingredientBaseSize: "infinity", minimumSize: "13", autoShrink: true
            )),
            .failure(.invalidNumber(field: .ingredientBaseSize))
        )
    }

    func testZeroAndNegativeValuesAreRejected() {
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "0", ingredientBaseSize: "16", minimumSize: "13", autoShrink: true
            )),
            .failure(.mustBePositive(field: .actionBaseSize))
        )
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "17", ingredientBaseSize: "-16", minimumSize: "13", autoShrink: true
            )),
            .failure(.mustBePositive(field: .ingredientBaseSize))
        )
    }

    func testMinimumAboveEitherBaseIsRejected() {
        XCTAssertEqual(
            SettingsFormValidator.validate(SettingsFormFields(
                actionBaseSize: "17", ingredientBaseSize: "16", minimumSize: "16.1", autoShrink: true
            )),
            .failure(.minimumExceedsBase)
        )
    }
}
