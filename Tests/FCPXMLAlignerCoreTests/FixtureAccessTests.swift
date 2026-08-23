import Foundation
import XCTest

final class FixtureAccessTests: XCTestCase {
    func testBundledFixturesContainInfoFCPXML() throws {
        for fixture in ["sample-current", "sample-gold", "sample-template"] {
            let infoURL = try fixtureURL(fixture).appendingPathComponent("Info.fcpxml")
            XCTAssertTrue(FileManager.default.fileExists(atPath: infoURL.path), "Fixture missing Info.fcpxml: \(fixture)")
        }
    }

    func testFixtureSourcesAndBundledCopiesHavePinnedInventoryAndSHA256() throws {
        let expectedInventory = ["Info.fcpxml"]
        let expectedSHA256ByFixture = [
            "sample-current": "158579222b8bc57cb3db4c1f731726ae165844326f259beafba2cb3dace5ab9e",
            "sample-gold": "e029488c6fdbaaf87e5dcafb551a2a22d1eaac91bca196df43190c55faa35de8",
            "sample-template": "a5dc9ff7487007b6f94e6aa3bcc0e33b20cbf835010e863f22faaff5541c8d88",
        ]

        for (fixture, expectedSHA256) in expectedSHA256ByFixture {
            let source = sourceFixtureURL(fixture)
            let bundled = try fixtureURL(fixture)

            XCTAssertEqual(try inventory(of: source), expectedInventory)
            XCTAssertEqual(try inventory(of: bundled), expectedInventory)
            XCTAssertEqual(try sha256(of: source.appending(path: "Info.fcpxml")), expectedSHA256)
            XCTAssertEqual(try sha256(of: bundled.appending(path: "Info.fcpxml")), expectedSHA256)
        }
    }

    private func sourceFixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures")
            .appending(path: "\(name).fcpxmld")
    }

    private func inventory(of directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    private func sha256(of url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", url.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try XCTUnwrap(
            String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: " ", maxSplits: 1)
                .first
                .map(String.init)
        )
    }
}
