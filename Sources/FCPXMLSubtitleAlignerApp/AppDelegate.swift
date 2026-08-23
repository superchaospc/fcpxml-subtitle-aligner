import AppKit
import Foundation
import FCPXMLAlignerCore

enum FileOpenDecision: Equatable, Sendable {
    case process(URL)
    case rejectMultipleFiles
    case rejectUnsupportedFile
}

enum FileOpenRouter {
    static func decision(for urls: [URL]) -> FileOpenDecision {
        guard urls.count == 1 else { return .rejectMultipleFiles }
        guard let url = urls.first, ["fcpxml", "fcpxmld"].contains(url.pathExtension.lowercased()) else {
            return .rejectUnsupportedFile
        }
        return .process(url)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let coordinator = ProcessingCoordinator()
    private let lifecycle = ApplicationLifecycle()
    private var activeSettingsAlert: SettingsAlert?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard lifecycle.beginSession() else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }
        let urls = filenames.map(URL.init(fileURLWithPath:))
        switch FileOpenRouter.decision(for: urls) {
        case .process(let url):
            sender.reply(toOpenOrPrint: .success)
            sender.activate(ignoringOtherApps: true)
            let alert = SettingsAlert(
                inputURL: url,
                settingsStore: settingsStore,
                coordinator: coordinator,
                lifecycle: lifecycle,
                onSessionFinished: { [weak self] in self?.finishActiveSession() }
            )
            activeSettingsAlert = alert
            alert.show()
        case .rejectMultipleFiles:
            sender.reply(toOpenOrPrint: .failure)
            _ = lifecycle.finishSession()
            showOpenError("Select exactly one .fcpxml or .fcpxmld file at a time.")
        case .rejectUnsupportedFile:
            sender.reply(toOpenOrPrint: .failure)
            _ = lifecycle.finishSession()
            showOpenError("Only .fcpxml and .fcpxmld files are supported.")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch lifecycle.requestTermination() {
        case .terminateNow: .terminateNow
        case .terminateLater: .terminateLater
        }
    }

    private func finishActiveSession() {
        activeSettingsAlert = nil
        if lifecycle.finishSession() {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func showOpenError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cannot open file"
        alert.informativeText = message
        alert.runModal()
    }
}
