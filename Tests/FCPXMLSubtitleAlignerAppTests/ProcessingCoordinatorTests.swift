import XCTest
@testable import FCPXMLSubtitleAlignerApp

final class ProcessingCoordinatorTests: XCTestCase {
    func testSubmissionGateRejectsSecondSubmissionUntilFirstFinishes() async {
        let gate = SubmissionGate()

        let firstSubmission = await gate.begin()
        let secondSubmission = await gate.begin()
        XCTAssertTrue(firstSubmission)
        XCTAssertFalse(secondSubmission)
        await gate.finish()
        let submissionAfterFinishing = await gate.begin()
        XCTAssertTrue(submissionAfterFinishing)
    }

    func testProcessingSummaryIsSendableValue() {
        let summary = ProcessingSummary(
            outputURL: URL(fileURLWithPath: "/tmp/output.fcpxml"),
            reportURL: URL(fileURLWithPath: "/tmp/output-report.txt"),
            changedTitles: 4,
            skippedTitles: 1
        )

        acceptSendable(summary)
        XCTAssertEqual(summary.changedTitles, 4)
    }

    func testInjectedWorkerReturnsSuccessSummary() async {
        let summary = makeSummary()
        let coordinator = await MainActor.run {
            ProcessingCoordinator(worker: { _, _ in .success(summary) })
        }

        let outcome = await coordinator.process(input: URL(fileURLWithPath: "/tmp/input.fcpxml"), settings: .templateDefaults)

        XCTAssertEqual(outcome, .completed(summary))
    }

    func testInjectedWorkerReturnsLocalizedFailure() async {
        let coordinator = await MainActor.run {
            ProcessingCoordinator(worker: { _, _ in .failure(ProcessingFailure(message: "Disk unavailable")) })
        }

        let outcome = await coordinator.process(input: URL(fileURLWithPath: "/tmp/input.fcpxml"), settings: .templateDefaults)

        XCTAssertEqual(outcome, .failed(ProcessingFailure(message: "Disk unavailable")))
    }

    func testSecondSubmissionIsRejectedWhileInjectedWorkerRuns() async {
        let suspension = WorkerSuspension()
        let summary = makeSummary()
        let coordinator = await MainActor.run {
            ProcessingCoordinator(worker: { _, _ in
                await suspension.run()
                return .success(summary)
            })
        }
        let first = Task { await coordinator.process(input: URL(fileURLWithPath: "/tmp/input.fcpxml"), settings: .templateDefaults) }
        await suspension.waitUntilStarted()

        let second = await coordinator.process(input: URL(fileURLWithPath: "/tmp/input.fcpxml"), settings: .templateDefaults)
        await suspension.release()

        XCTAssertEqual(second, .alreadyProcessing)
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .completed(summary))
    }

    func testCancellingCallerDoesNotReleaseSubmissionBeforeWorkerFinishes() async {
        let suspension = WorkerSuspension()
        let summary = makeSummary()
        let coordinator = await MainActor.run {
            ProcessingCoordinator(worker: { _, _ in
                await suspension.run()
                return .success(summary)
            })
        }
        let first = Task { await coordinator.process(input: URL(fileURLWithPath: "/tmp/input.fcpxml"), settings: .templateDefaults) }
        await suspension.waitUntilStarted()
        first.cancel()

        let second = await coordinator.process(input: URL(fileURLWithPath: "/tmp/input.fcpxml"), settings: .templateDefaults)
        await suspension.release()

        XCTAssertEqual(second, .alreadyProcessing)
        let firstOutcome = await first.value
        XCTAssertEqual(firstOutcome, .completed(summary))
    }

    private func makeSummary() -> ProcessingSummary {
        ProcessingSummary(
            outputURL: URL(fileURLWithPath: "/tmp/output.fcpxml"),
            reportURL: URL(fileURLWithPath: "/tmp/output-report.txt"),
            changedTitles: 4,
            skippedTitles: 1
        )
    }

    private func acceptSendable<T: Sendable>(_ value: T) {}
}

private actor WorkerSuspension {
    private var started = false
    private var released = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func run() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
