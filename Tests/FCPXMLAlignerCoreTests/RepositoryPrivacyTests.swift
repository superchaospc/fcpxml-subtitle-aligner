import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest
@testable import FCPXMLAlignerCore

final class RepositoryPrivacyTests: XCTestCase {
    private let fixtureNames = ["sample-current", "sample-gold", "sample-template"]

    func testEveryTrackedRegularFileHasNoPrivateDataInRawOrBookmarkBytes() throws {
        var violations: [String] = []

        for file in try trackedRegularFiles() {
            let data = try Data(contentsOf: file.url)
            let privateMatches = forbiddenTokens.indices.filter { index in
                containsEncodedBytes(forbiddenTokens[index], in: data)
            }
            violations += privateMatches.map { "\(file.relativePath): private-token-\($0)" }

            guard !intentionalBinaryIconPaths.contains(file.relativePath) else {
                continue
            }

            let bookmarkPayloads = bookmarkPayloads(in: data)
            for (index, payload) in bookmarkPayloads.enumerated() {
                guard let decoded = Data(base64Encoded: payload) else {
                    violations.append("\(file.relativePath): malformed-bookmark-\(index)")
                    continue
                }
                let decodedMatches = forbiddenTokens.indices.filter { tokenIndex in
                    containsEncodedBytes(forbiddenTokens[tokenIndex], in: decoded)
                }
                violations += decodedMatches.map {
                    "\(file.relativePath): bookmark-\(index)-private-token-\($0)"
                }
            }
        }

        XCTAssertEqual(violations.sorted(), [], "Private data found:\n\(violations.sorted().joined(separator: "\n"))")
    }

    func testPublicFixturesContainOnlySyntheticMetadataAndTitleCorpus() throws {
        for fixtureName in fixtureNames {
            let fixture = sourceFixtureURL(fixtureName)
            let data = try Data(contentsOf: fixture)
            let xml = try XCTUnwrap(String(data: data, encoding: .utf8))
            let document = try FCPXMLDocument(xmlString: xml)

            XCTAssertFalse(containsBookmarkElement(in: data), "\(fixtureName) contains bookmark metadata")
            XCTAssertTrue(bookmarkPayloads(in: data).isEmpty, "\(fixtureName) contains bookmark payloads")
            XCTAssertEqual(document.projectNames, ["Synthetic Subtitle Alignment Project"])
            XCTAssertEqual(titleCorpus(document.titles.map(\.visibleText)), syntheticTitleCorpus)
            XCTAssertEqual(document.titles.count, 17)

            let metadata = try XMLFixtureMetadata(xml: xml)
            XCTAssertEqual(metadata.libraryLocations, ["file:///fixtures/SyntheticSubtitleAlignment.fcpbundle"])
            XCTAssertEqual(metadata.eventNames, ["Synthetic Fixture Event"])
            XCTAssertEqual(metadata.projectUIDs, ["fixture-project-001"])
            XCTAssertEqual(metadata.eventUIDs, ["fixture-event-001"])
            XCTAssertEqual(metadata.projectModificationDates, ["2000-01-01 00:00:00 +0000"])
            XCTAssertTrue(metadata.assetNames.allSatisfy { $0.hasPrefix("Synthetic Asset ") })
            XCTAssertFalse(metadata.assetURLs.isEmpty)
            XCTAssertTrue(metadata.assetURLs.allSatisfy { $0.hasPrefix("file:///fixtures/media/") })
            XCTAssertTrue(metadata.assetUIDs.allSatisfy { $0.range(of: #"^fixture-asset-[0-9]{3}$"#, options: .regularExpression) != nil })
            XCTAssertTrue(metadata.effectUIDs.allSatisfy { $0.hasPrefix("com.example.fixture.") })
            XCTAssertEqual(metadata.assetURLs.count, metadata.mediaRepresentationSignatures.count)
            XCTAssertTrue(metadata.mediaRepresentationSignatures.allSatisfy { $0.hasPrefix("fixture-media-signature-") })
            XCTAssertTrue(metadata.timelineClipNames.allSatisfy { $0.hasPrefix("Synthetic ") })
            XCTAssertFalse(metadata.hasUUIDLikeIdentifier)
        }
    }

    func testBookmarkElementDetectionRejectsSelfClosingAndUTF16XML() throws {
        let opening = ["<book", "mark"].joined()
        let utf8 = try XCTUnwrap("\(opening)/>".data(using: .utf8))
        let utf16 = try XCTUnwrap("\(opening)>payload</bookmark>".data(using: .utf16LittleEndian))

        XCTAssertTrue(containsBookmarkElement(in: utf8))
        XCTAssertTrue(containsBookmarkElement(in: utf16))
        XCTAssertFalse(containsBookmarkElement(in: Data("<metadata/>".utf8)))
    }

    private var forbiddenTokens: [String] {
        [
            ["/Us", "ers/"].joined(),
            ["/Vol", "umes/"].joined(),
            ["file:///", "Vol", "umes/"].joined(),
            ["wei", "chaoshen"].joined(),
            ["fc", "no2"].joined(),
            ["recipe", "20250101"].joined(),
            ["recipe", "20260615", ".fcp", "bundle"].joined(),
            ["6-", "15-", "26"].joined(),
            ["chinese", "pancake"].joined(),
            ["chinese", " pancake"].joined(),
            ["pancake", "20260812"].joined(),
            ["2026", "0820"].joined(),
            ["2026", "0821"].joined(),
            ["Untitled-", "101019.wav"].joined(),
            ["Oven Door Open-Close", " Sound Effect- Version 1 - HQ Sounds.mp3"].joined(),
            ["oh no sound effects", " - - 2022-04-04 22-30-22.mp4"].joined(),
            ["Apple Pay Success", " Sound Effect.mp3"].joined(),
        ]
    }

    private var intentionalBinaryIconPaths: Set<String> {
        ["skills/fcpxml-subtitle-aligner/assets/icon-400.png"]
    }

    private var syntheticTitleCorpus: Set<String> {
        [
            "carefully spread the batter across the warm skillet surface",
            "warm the skillet",
            "fold the edges",
            "turn once",
            "brush with oil",
            "cook until crisp",
            "let it rest",
            "slice into wedges",
            "add a bright topping",
            "serve while warm",
            "save a portion",
            "share with friends",
            "clean the pan",
            "plate with care",
            "dish up",
            "flour 500g\nsalt 1 tsp\nthree eggs\nyeast 5g\nwarm water 300ml",
            "follow for more\nsimple kitchen notes",
        ]
    }

    private func titleCorpus(_ titles: [String]) -> Set<String> {
        Set(titles.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
    }

    private func sourceFixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures")
            .appending(path: "\(name).fcpxmld")
            .appending(path: "Info.fcpxml")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func trackedRegularFiles() throws -> [(url: URL, relativePath: String)] {
        let root = repositoryRoot()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = root
        process.arguments = ["ls-files", "-z"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        return output.fileHandleForReading.readDataToEndOfFile()
            .split(separator: 0)
            .compactMap { entry in
                let relativePath = String(decoding: entry, as: UTF8.self)
                let url = root.appending(path: relativePath)
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }
                return (url, relativePath)
            }
    }

    private func containsEncodedBytes(_ token: String, in data: Data) -> Bool {
        let encodings: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian]
        return encodings.contains { encoding in
            guard let encoded = token.data(using: encoding), !encoded.isEmpty else { return false }
            return data.range(of: encoded) != nil
        }
    }

    private func containsBookmarkElement(in data: Data) -> Bool {
        containsEncodedBytes(["<book", "mark"].joined(), in: data)
    }

    private func bookmarkPayloads(in data: Data) -> [Data] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let expression = try? NSRegularExpression(
            pattern: #"<bookmark(?:\s[^>]*)?>([A-Za-z0-9+/=\s]*)</bookmark>"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression?.matches(in: text, range: range).compactMap { match in
            guard let payloadRange = Range(match.range(at: 1), in: text) else { return nil }
            let payload = text[payloadRange].filter { !$0.isWhitespace }
            return Data(payload.utf8)
        } ?? []
    }
}

private struct XMLFixtureMetadata {
    let libraryLocations: [String]
    let eventNames: [String]
    let eventUIDs: [String]
    let projectUIDs: [String]
    let projectModificationDates: [String]
    let assetNames: [String]
    let assetURLs: [String]
    let assetUIDs: [String]
    let effectUIDs: [String]
    let mediaRepresentationSignatures: [String]
    let timelineClipNames: [String]
    let hasUUIDLikeIdentifier: Bool

    init(xml: String) throws {
        let document = try XMLDocument(xmlString: xml, options: .nodePreserveAll)
        func values(_ path: String, attribute: String) throws -> [String] {
            try document.nodes(forXPath: path).compactMap { node in
                (node as? XMLElement)?.attribute(forName: attribute)?.stringValue
            }
        }

        libraryLocations = try values("//library", attribute: "location")
        eventNames = try values("//event", attribute: "name")
        eventUIDs = try values("//event", attribute: "uid")
        projectUIDs = try values("//project", attribute: "uid")
        projectModificationDates = try values("//project", attribute: "modDate")
        assetNames = try values("//asset", attribute: "name")
        assetURLs = try values("//media-rep", attribute: "src")
        assetUIDs = try values("//asset", attribute: "uid")
        effectUIDs = try values("//effect", attribute: "uid")
        mediaRepresentationSignatures = try values("//media-rep", attribute: "sig")
        timelineClipNames = try values("//asset-clip | //clip | //gap | //video", attribute: "name")
        let identifierNodes = try document.nodes(forXPath: "//*[@id or @uid]").compactMap { $0 as? XMLElement }
        let identifiers = identifierNodes.flatMap { node in
            [node.attribute(forName: "id")?.stringValue, node.attribute(forName: "uid")?.stringValue].compactMap { $0 }
        }
        hasUUIDLikeIdentifier = identifiers.contains {
            $0.range(of: #"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}
