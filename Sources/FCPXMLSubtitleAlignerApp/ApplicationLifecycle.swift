import Foundation

enum TerminationDecision: Equatable, Sendable {
    case terminateNow
    case terminateLater
}

/// Owns the AppKit lifecycle decisions independently of modal UI and filesystem work.
@MainActor
final class ApplicationLifecycle {
    private var sessionActive = false
    private var processingActive = false
    private var terminationPending = false
    private var terminationReplySent = false

    var isTerminationPending: Bool { terminationPending }

    func beginSession() -> Bool {
        guard !sessionActive else { return false }
        sessionActive = true
        return true
    }

    func finishSession() -> Bool {
        sessionActive = false
        return consumePendingTerminationReplyIfReady()
    }

    func beginProcessing() -> Bool {
        guard sessionActive, !processingActive else { return false }
        processingActive = true
        return true
    }

    /// Processing completion is deliberately separate from session completion so any
    /// main-actor outcome handling can settle before a delayed termination is replied to.
    func finishProcessing() -> Bool {
        processingActive = false
        return false
    }

    func requestTermination() -> TerminationDecision {
        guard processingActive else { return .terminateNow }
        terminationPending = true
        return .terminateLater
    }

    private func consumePendingTerminationReplyIfReady() -> Bool {
        guard terminationPending, !processingActive, !terminationReplySent else { return false }
        terminationReplySent = true
        return true
    }
}
