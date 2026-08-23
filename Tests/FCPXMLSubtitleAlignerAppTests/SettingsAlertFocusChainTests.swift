import XCTest
import AppKit
@testable import FCPXMLSubtitleAlignerApp

final class SettingsAlertFocusChainTests: XCTestCase {
    func testFocusChainVisitsEveryFieldAndAlertButtonBeforeCycling() {
        XCTAssertEqual(
            SettingsAlertFocusChain.order,
            [
                .actionField,
                .ingredientField,
                .minimumField,
                .autoShrink,
                .restoreDefaultsButton,
                .cancelButton,
                .processButton,
            ]
        )

        var visited = [SettingsAlertFocusTarget]()
        var current = SettingsAlertFocusTarget.actionField
        for _ in SettingsAlertFocusChain.order.indices {
            visited.append(current)
            current = SettingsAlertFocusChain.next(after: current)
        }

        XCTAssertEqual(visited, SettingsAlertFocusChain.order)
        XCTAssertEqual(current, .actionField)
    }

    func testNSAlertReturnsButtonsInAdditionOrderUsedByFocusConnector() async {
        let titles = await MainActor.run {
            let alert = NSAlert()
            alert.addButton(withTitle: "Process")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Restore Template Defaults")
            return alert.buttons.map(\.title)
        }

        XCTAssertEqual(titles, ["Process", "Cancel", "Restore Template Defaults"])
    }

    func testConnectedAppKitViewsReachAlertButtonsAndReturnToActionField() async {
        let links = await MainActor.run {
            let action = NSTextField()
            let ingredient = NSTextField()
            let minimum = NSTextField()
            let autoShrink = NSButton(checkboxWithTitle: "Auto-shrink", target: nil, action: nil)
            let process = NSButton(title: "Process", target: nil, action: nil)
            let cancel = NSButton(title: "Cancel", target: nil, action: nil)
            let restore = NSButton(title: "Restore Template Defaults", target: nil, action: nil)
            let buttons = [process, cancel, restore]

            SettingsAlertFocusChain.connect(
                actionField: action,
                ingredientField: ingredient,
                minimumField: minimum,
                autoShrinkButton: autoShrink,
                alertButtons: buttons
            )

            return [
                action.nextKeyView === ingredient,
                ingredient.nextKeyView === minimum,
                minimum.nextKeyView === autoShrink,
                autoShrink.nextKeyView === buttons[2],
                buttons[2].nextKeyView === buttons[1],
                buttons[1].nextKeyView === buttons[0],
                buttons[0].nextKeyView === action,
            ]
        }

        XCTAssertEqual(links, Array(repeating: true, count: 7))
    }
}
