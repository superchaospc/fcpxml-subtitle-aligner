import XCTest
@testable import FCPXMLAlignerCore

final class TitleClassifierTests: XCTestCase {
    func testSimpleInstructionIsAction() {
        XCTAssertEqual(TitleClassifier.classify("Mix until smooth"), .action)
    }

    func testFiveLineTitleWithTwoQuantitiesIsIngredient() {
        let title = """
        Flour 500g
        Warm water 300ml
        Salt 1 tsp
        Oil
        Scallions
        """
        XCTAssertEqual(TitleClassifier.classify(title), .ingredient)
    }

    func testQuantityInSingleLineInstructionRemainsAction() {
        XCTAssertEqual(TitleClassifier.classify("Let it rest for 2 hours"), .action)
        XCTAssertEqual(TitleClassifier.classify("yeast 5g & sugar 1/2 tsp"), .action)
    }

    func testFollowForMoreIsClosing() {
        XCTAssertEqual(TitleClassifier.classify("Simple kitchen notes\nFollow for more"), .closing)
    }

    func testSingleLineFollowForMoreIsClosing() {
        XCTAssertEqual(TitleClassifier.classify("Follow for more"), .closing)
    }

    func testGenericTwoLineNonIngredientIsClosing() {
        XCTAssertEqual(TitleClassifier.classify("Serve warm\nEnjoy!"), .closing)
    }

    func testThreeLinesWithOnlyOneQuantityIsClosing() {
        XCTAssertEqual(TitleClassifier.classify("Flour 500g\nMix well\nServe warm"), .closing)
    }

    func testTwoStandaloneFractionQuantityLinesAreIngredient() {
        let title = """
        Flour 1/2
        Water 3/4
        Salt
        """
        XCTAssertEqual(TitleClassifier.classify(title), .ingredient)
    }

    func testDecimalAndUppercaseUnitsAreQuantities() {
        let title = """
        Flour 0.5KG
        Water 1.25 L
        Salt
        """
        XCTAssertEqual(TitleClassifier.classify(title), .ingredient)
    }

    func testWordContainingGIsNotAQuantity() {
        XCTAssertEqual(TitleClassifier.classify("Bag\nMix gently\nServe"), .closing)
    }

    func testDifferentWordsContainingGAreNotQuantities() {
        XCTAssertEqual(TitleClassifier.classify("Bag\nGinger\nEgg"), .closing)
    }

    func testUnicodeAndAlphanumericQuantityLikeTokensAreNotQuantities() {
        XCTAssertEqual(TitleClassifier.classify("café500g\n500gâteau\n1ml2"), .closing)
    }

    func testCombiningMarksAroundQuantityLikeTokensAreNotQuantities() {
        let title = "cafe\u{0301}500g\n500g\u{0302}\nSalt"
        XCTAssertEqual(TitleClassifier.classify(title), .closing)
    }

    func testBlankAndWhitespaceOnlyLinesDoNotCount() {
        XCTAssertEqual(TitleClassifier.classify("Flour 500g\n\n  \nWater 300ml"), .closing)
    }

    func testAdditionalUnitsAreRecognized() {
        let cases = [
            "Calcium 10mg\nWater 1/2\nSalt",
            "Flour 1 cup\nWater 1/2\nSalt",
            "Flour 2 cups\nWater 1/2\nSalt",
            "Oil 1 tbsp\nWater 1/2\nSalt",
            "Oil 3oz\nWater 1/2\nSalt",
            "Sugar 5%\nWater 1/2\nSalt"
        ]

        for title in cases {
            XCTAssertEqual(TitleClassifier.classify(title), .ingredient, "Expected ingredient for: \(title)")
        }
    }

    func testCurrentFixtureHasExpectedTitleKinds() throws {
        let kinds = try currentFixtureDocument().titles.map { TitleClassifier.classify($0.visibleText) }
        XCTAssertEqual(kinds, [.action, .ingredient] + Array(repeating: .action, count: 14) + [.closing])
    }
}
