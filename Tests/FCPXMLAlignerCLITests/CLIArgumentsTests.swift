import Foundation
import XCTest
import FCPXMLAlignerCLI
import FCPXMLAlignerCore

final class CLIArgumentsTests: XCTestCase {
    func testDefaultsUseTemplateSettings() throws {
        let arguments = try CLIArguments.parse(["input.fcpxml"])

        XCTAssertEqual(arguments.mode, .align)
        XCTAssertEqual(arguments.settings, .templateDefaults)
        XCTAssertFalse(arguments.json)
    }

    func testInputIsAnAbsoluteStandardizedFileURLRelativeToCurrentDirectory() throws {
        let arguments = try CLIArguments.parse(["folder/../input.fcpxml"])
        let expected = URL(
            fileURLWithPath: "folder/../input.fcpxml",
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ).standardizedFileURL

        XCTAssertEqual(arguments.input, expected)
        XCTAssertEqual(arguments.input?.isFileURL, true)
        XCTAssertEqual(arguments.input?.path.hasPrefix("/"), true)
    }

    func testAllAlignmentOptionsOverrideDefaults() throws {
        let arguments = try CLIArguments.parse([
            "--action-size", "19.5",
            "--ingredient-size", "18",
            "--minimum-size", "14",
            "--safe-width", "0.75",
            "--no-auto-shrink",
            "--json",
            "input.fcpxml",
        ])

        XCTAssertEqual(arguments.settings.actionBaseSize, 19.5)
        XCTAssertEqual(arguments.settings.ingredientBaseSize, 18)
        XCTAssertEqual(arguments.settings.minimumSize, 14)
        XCTAssertEqual(arguments.settings.safeWidthFraction, 0.75)
        XCTAssertFalse(arguments.settings.autoShrink)
        XCTAssertTrue(arguments.json)
    }

    func testLastAutoShrinkFlagWins() throws {
        let enabled = try CLIArguments.parse([
            "--no-auto-shrink", "--auto-shrink", "input.fcpxml",
        ])
        let disabled = try CLIArguments.parse([
            "--auto-shrink", "--no-auto-shrink", "input.fcpxml",
        ])

        XCTAssertTrue(enabled.settings.autoShrink)
        XCTAssertFalse(disabled.settings.autoShrink)
    }

    func testHelpModesDoNotRequireInput() throws {
        XCTAssertEqual(try CLIArguments.parse(["--help"]).mode, .help)
        XCTAssertEqual(try CLIArguments.parse(["-h"]).mode, .help)
        XCTAssertNil(try CLIArguments.parse(["--help"]).input)
    }

    func testVersionModeDoesNotRequireInput() throws {
        let arguments = try CLIArguments.parse(["--version"])

        XCTAssertEqual(arguments.mode, .version)
        XCTAssertNil(arguments.input)
    }

    func testHelpRejectsPositionalInput() {
        XCTAssertThrowsError(try CLIArguments.parse(["--help", "input.fcpxml"])) { error in
            XCTAssertEqual(error as? CLIArgumentError, .unexpectedArgument("input.fcpxml"))
        }
    }

    func testVersionRejectsUnknownOption() {
        XCTAssertThrowsError(try CLIArguments.parse(["--version", "--verbose"])) { error in
            XCTAssertEqual(error as? CLIArgumentError, .unexpectedArgument("--verbose"))
        }
    }

    func testMissingInputIsRejected() {
        XCTAssertThrowsError(try CLIArguments.parse([])) { error in
            XCTAssertEqual(error as? CLIArgumentError, .missingInput)
        }
    }

    func testDuplicateInputIsRejected() {
        XCTAssertThrowsError(try CLIArguments.parse(["one.fcpxml", "two.fcpxml"])) { error in
            XCTAssertEqual(error as? CLIArgumentError, .unexpectedArgument("two.fcpxml"))
        }
    }

    func testUnknownOptionIsRejected() {
        XCTAssertThrowsError(try CLIArguments.parse(["--verbose", "input.fcpxml"])) { error in
            XCTAssertEqual(error as? CLIArgumentError, .unexpectedArgument("--verbose"))
        }
    }

    func testMissingNumericOptionValuesAreRejected() {
        for option in ["--action-size", "--ingredient-size", "--minimum-size", "--safe-width"] {
            XCTAssertThrowsError(try CLIArguments.parse(["input.fcpxml", option])) { error in
                XCTAssertEqual(error as? CLIArgumentError, .missingValue(option))
            }
        }
    }

    func testInvalidNumberIsRejected() {
        XCTAssertThrowsError(try CLIArguments.parse([
            "--action-size", "large", "input.fcpxml",
        ])) { error in
            XCTAssertEqual(
                error as? CLIArgumentError,
                .invalidNumber(option: "--action-size", value: "large")
            )
        }
    }

    func testNonfiniteNumbersAreRejected() {
        for value in ["nan", "infinity", "-infinity"] {
            XCTAssertThrowsError(try CLIArguments.parse([
                "--ingredient-size", value, "input.fcpxml",
            ])) { error in
                XCTAssertEqual(
                    error as? CLIArgumentError,
                    .invalidNumber(option: "--ingredient-size", value: value)
                )
            }
        }
    }

    func testSizesMustBePositive() {
        let invalidValues = [
            ("--action-size", "0"),
            ("--ingredient-size", "-1"),
            ("--minimum-size", "0"),
        ]

        for (option, value) in invalidValues {
            assertInvalidSettings([option, value, "input.fcpxml"])
        }
    }

    func testMinimumCannotExceedEitherBaseSize() {
        assertInvalidSettings([
            "--action-size", "12", "--minimum-size", "13", "input.fcpxml",
        ])
        assertInvalidSettings([
            "--ingredient-size", "12", "--minimum-size", "13", "input.fcpxml",
        ])
    }

    func testSafeWidthMustBeWithinInclusiveRange() throws {
        XCTAssertEqual(
            try CLIArguments.parse(["--safe-width", "0.1", "input.fcpxml"])
                .settings.safeWidthFraction,
            0.1
        )
        XCTAssertEqual(
            try CLIArguments.parse(["--safe-width", "1.0", "input.fcpxml"])
                .settings.safeWidthFraction,
            1.0
        )
        assertInvalidSettings(["--safe-width", "0.09", "input.fcpxml"])
        assertInvalidSettings(["--safe-width", "1.01", "input.fcpxml"])
    }

    private func assertInvalidSettings(
        _ arguments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try CLIArguments.parse(arguments), file: file, line: line) { error in
            guard case .invalidSettings = error as? CLIArgumentError else {
                return XCTFail("Expected invalidSettings, got \(error)", file: file, line: line)
            }
        }
    }
}
