import XCTest
@testable import FCPXMLSubtitleAlignerApp

final class ApplicationLifecycleTests: XCTestCase {
    func testIdleQuitTerminatesImmediately() async {
        let lifecycle = await MainActor.run { ApplicationLifecycle() }

        let decision = await MainActor.run { lifecycle.requestTermination() }

        XCTAssertEqual(decision, .terminateNow)
    }

    func testActiveProcessingDelaysTerminationWithoutEarlyReply() async {
        let lifecycle = await MainActor.run { ApplicationLifecycle() }
        await MainActor.run {
            XCTAssertTrue(lifecycle.beginSession())
            XCTAssertTrue(lifecycle.beginProcessing())
        }

        let decision = await MainActor.run { lifecycle.requestTermination() }
        let earlyReply = await MainActor.run { lifecycle.finishProcessing() }

        XCTAssertEqual(decision, .terminateLater)
        XCTAssertFalse(earlyReply)
    }

    func testCompletionRepliesToPendingTerminationExactlyOnce() async {
        let lifecycle = await MainActor.run { ApplicationLifecycle() }
        await MainActor.run {
            XCTAssertTrue(lifecycle.beginSession())
            XCTAssertTrue(lifecycle.beginProcessing())
            XCTAssertEqual(lifecycle.requestTermination(), .terminateLater)
            XCTAssertFalse(lifecycle.finishProcessing())
        }

        let firstReply = await MainActor.run { lifecycle.finishSession() }
        let secondReply = await MainActor.run { lifecycle.finishSession() }

        XCTAssertTrue(firstReply)
        XCTAssertFalse(secondReply)
    }

    func testSuccessAndFailureUseTheSameCompletionReplyPath() async {
        for _ in 0..<2 {
            let lifecycle = await MainActor.run { ApplicationLifecycle() }
            await MainActor.run {
                XCTAssertTrue(lifecycle.beginSession())
                XCTAssertTrue(lifecycle.beginProcessing())
                XCTAssertEqual(lifecycle.requestTermination(), .terminateLater)
                XCTAssertFalse(lifecycle.finishProcessing())
            }
            let reply = await MainActor.run { lifecycle.finishSession() }
            XCTAssertTrue(reply)
        }
    }
}
