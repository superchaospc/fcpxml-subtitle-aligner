import Foundation
import FCPXMLAlignerCore

public struct ProcessingSummary: Equatable, Sendable {
    public let outputURL: URL
    public let reportURL: URL
    public let changedTitles: Int
    public let skippedTitles: Int

    public init(outputURL: URL, reportURL: URL, changedTitles: Int, skippedTitles: Int) {
        self.outputURL = outputURL
        self.reportURL = reportURL
        self.changedTitles = changedTitles
        self.skippedTitles = skippedTitles
    }
}

public struct ProcessingFailure: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum ProcessingOutcome: Equatable, Sendable {
    case completed(ProcessingSummary)
    case failed(ProcessingFailure)
    case alreadyProcessing
}

public typealias ProcessingWorker = @Sendable (URL, AlignmentSettings) async -> Result<ProcessingSummary, ProcessingFailure>

public actor SubmissionGate {
    private var submitting = false

    public init() {}

    public func begin() -> Bool {
        guard !submitting else { return false }
        submitting = true
        return true
    }

    public func finish() {
        submitting = false
    }
}

@MainActor
public final class ProcessingCoordinator {
    private let submissionGate: SubmissionGate
    private let worker: ProcessingWorker

    public init(
        submissionGate: SubmissionGate = SubmissionGate(),
        worker: ProcessingWorker? = nil
    ) {
        self.submissionGate = submissionGate
        self.worker = worker ?? ProcessingCoordinator.outputWriterWorker
    }

    public func process(input: URL, settings: AlignmentSettings) async -> ProcessingOutcome {
        guard await submissionGate.begin() else { return .alreadyProcessing }
        let submittedWorker = worker
        let result = await Task.detached(priority: .userInitiated) { await submittedWorker(input, settings) }.value
        await submissionGate.finish()

        switch result {
        case .success(let summary): return .completed(summary)
        case .failure(let failure): return .failed(failure)
        }
    }

    private static func outputWriterWorker(
        input: URL,
        settings: AlignmentSettings
    ) async -> Result<ProcessingSummary, ProcessingFailure> {
        do {
            let output = try OutputWriter().process(input: input, settings: settings)
            return .success(ProcessingSummary(
                outputURL: output.outputURL,
                reportURL: output.reportURL,
                changedTitles: output.report.changedTitles,
                skippedTitles: output.report.skippedTitles
            ))
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failure(ProcessingFailure(message: message))
        }
    }
}
