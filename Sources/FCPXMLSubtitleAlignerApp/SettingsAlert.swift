import AppKit
import FCPXMLAlignerCore

enum SettingsAlertFocusTarget: CaseIterable, Equatable, Hashable {
    case actionField
    case ingredientField
    case minimumField
    case autoShrink
    case restoreDefaultsButton
    case cancelButton
    case processButton
}

enum SettingsAlertFocusChain {
    static let processButtonIndex = 0
    static let cancelButtonIndex = 1
    static let restoreDefaultsButtonIndex = 2

    static let order: [SettingsAlertFocusTarget] = [
        .actionField,
        .ingredientField,
        .minimumField,
        .autoShrink,
        .restoreDefaultsButton,
        .cancelButton,
        .processButton,
    ]

    static func next(after target: SettingsAlertFocusTarget) -> SettingsAlertFocusTarget {
        guard let index = order.firstIndex(of: target) else { return .actionField }
        return order[(index + 1) % order.count]
    }

    @MainActor
    static func connect(
        actionField: NSTextField,
        ingredientField: NSTextField,
        minimumField: NSTextField,
        autoShrinkButton: NSButton,
        alertButtons: [NSButton]
    ) {
        guard alertButtons.indices.contains(processButtonIndex),
              alertButtons.indices.contains(cancelButtonIndex),
              alertButtons.indices.contains(restoreDefaultsButtonIndex)
        else { return }
        let views: [SettingsAlertFocusTarget: NSView] = [
            .actionField: actionField,
            .ingredientField: ingredientField,
            .minimumField: minimumField,
            .autoShrink: autoShrinkButton,
            .restoreDefaultsButton: alertButtons[restoreDefaultsButtonIndex],
            .cancelButton: alertButtons[cancelButtonIndex],
            .processButton: alertButtons[processButtonIndex],
        ]
        for target in order {
            views[target]?.nextKeyView = views[next(after: target)]
        }
    }
}

@MainActor
final class SettingsAlert {
    private let inputURL: URL
    private let settingsStore: SettingsStore
    private let coordinator: ProcessingCoordinator
    private let lifecycle: ApplicationLifecycle
    private let onSessionFinished: @MainActor () -> Void
    private let actionField = NSTextField()
    private let ingredientField = NSTextField()
    private let minimumField = NSTextField()
    private let autoShrinkButton = NSButton(checkboxWithTitle: "Auto-shrink", target: nil, action: nil)

    init(
        inputURL: URL,
        settingsStore: SettingsStore,
        coordinator: ProcessingCoordinator,
        lifecycle: ApplicationLifecycle,
        onSessionFinished: @escaping @MainActor () -> Void
    ) {
        self.inputURL = inputURL
        self.settingsStore = settingsStore
        self.coordinator = coordinator
        self.lifecycle = lifecycle
        self.onSessionFinished = onSessionFinished
        apply(SettingsFormFields(settings: settingsStore.load()))
    }

    func show() {
        while true {
            let alert = makeAlert()
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                switch SettingsFormValidator.validate(fields) {
                case .success(let settings):
                    settingsStore.save(settings)
                    guard lifecycle.beginProcessing() else {
                        Self.showAlreadyProcessing()
                        onSessionFinished()
                        return
                    }
                    Task { [self, inputURL, coordinator] in
                        let outcome = await coordinator.process(input: inputURL, settings: settings)
                        let shouldPresentOutcome = !lifecycle.isTerminationPending
                        _ = lifecycle.finishProcessing()
                        if shouldPresentOutcome {
                            switch outcome {
                            case .completed(let summary): Self.showSuccess(summary)
                            case .failed(let failure): Self.showFailure(failure)
                            case .alreadyProcessing: Self.showAlreadyProcessing()
                            }
                        }
                        onSessionFinished()
                    }
                    return
                case .failure(let error):
                    showValidationError(error)
                }
            case .alertThirdButtonReturn:
                apply(SettingsFormFields(settings: settingsStore.restoreDefaults()))
            default:
                onSessionFinished()
                return
            }
        }
    }

    private var fields: SettingsFormFields {
        SettingsFormFields(
            actionBaseSize: actionField.stringValue,
            ingredientBaseSize: ingredientField.stringValue,
            minimumSize: minimumField.stringValue,
            autoShrink: autoShrinkButton.state == .on
        )
    }

    private func apply(_ fields: SettingsFormFields) {
        actionField.stringValue = fields.actionBaseSize
        ingredientField.stringValue = fields.ingredientBaseSize
        minimumField.stringValue = fields.minimumSize
        autoShrinkButton.state = fields.autoShrink ? .on : .off
    }

    private func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Align FCPXML subtitles"
        alert.informativeText = "Choose typography settings for \(inputURL.lastPathComponent)."
        alert.addButton(withTitle: "Process")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Restore Template Defaults")
        alert.accessoryView = formView()
        let window = alert.window
        window.initialFirstResponder = actionField
        SettingsAlertFocusChain.connect(
            actionField: actionField,
            ingredientField: ingredientField,
            minimumField: minimumField,
            autoShrinkButton: autoShrinkButton,
            alertButtons: alert.buttons
        )
        return alert
    }

    private func formView() -> NSView {
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 8
        form.translatesAutoresizingMaskIntoConstraints = false
        form.addArrangedSubview(row(label: "Action caption size", field: actionField))
        form.addArrangedSubview(row(label: "Ingredient card size", field: ingredientField))
        form.addArrangedSubview(row(label: "Minimum size", field: minimumField))
        form.addArrangedSubview(autoShrinkButton)

        actionField.setAccessibilityLabel("Action caption size")
        ingredientField.setAccessibilityLabel("Ingredient card size")
        minimumField.setAccessibilityLabel("Minimum size")
        autoShrinkButton.setAccessibilityLabel("Auto-shrink")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 128))
        container.addSubview(form)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            form.topAnchor.constraint(equalTo: container.topAnchor),
            form.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func row(label: String, field: NSTextField) -> NSView {
        field.controlSize = .regular
        field.widthAnchor.constraint(equalToConstant: 100).isActive = true
        let row = NSStackView(views: [NSTextField(labelWithString: label), field])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    private func showValidationError(_ error: SettingsValidationError) {
        let alert = NSAlert(error: error)
        alert.messageText = "Check the settings"
        alert.runModal()
    }

    private static func showSuccess(_ summary: ProcessingSummary) {
        let alert = NSAlert()
        alert.messageText = "Alignment complete"
        alert.informativeText = "Output: \(summary.outputURL.path)\nReport: \(summary.reportURL.path)"
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([summary.outputURL, summary.reportURL])
        }
    }

    private static func showFailure(_ failure: ProcessingFailure) {
        let alert = NSAlert(error: failure)
        alert.messageText = "Alignment failed"
        alert.informativeText = "\(failure.message)\n\nNo output was created."
        alert.runModal()
    }

    private static func showAlreadyProcessing() {
        let alert = NSAlert()
        alert.messageText = "Already processing"
        alert.informativeText = "Wait for the current file to finish before starting another one."
        alert.runModal()
    }
}
