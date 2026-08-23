import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct ProjectDimensions: Equatable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct TitleTextRun {
    public let element: XMLElement
    public let ref: String
    public let string: String
    public let sourceFontFamily: String?
    public let sourceFontFace: String?
    public let isItalic: Bool

    public init(
        element: XMLElement,
        ref: String,
        string: String,
        sourceFontFamily: String? = nil,
        sourceFontFace: String? = nil,
        isItalic: Bool = false
    ) {
        self.element = element
        self.ref = ref
        self.string = string
        self.sourceFontFamily = sourceFontFamily
        self.sourceFontFace = sourceFontFace
        self.isItalic = isItalic
    }
}

public struct TitleRecord {
    public let element: XMLElement
    public let name: String
    public let ref: String
    public let lane: String
    public let offset: String
    public let start: String
    public let duration: String
    public let visibleText: String
    public let visibleLines: [String]
    public let visibleTextRuns: [TitleTextRun]
    public let projectDimensions: ProjectDimensions?

    public init(
        element: XMLElement,
        name: String,
        ref: String,
        lane: String,
        offset: String,
        start: String,
        duration: String,
        visibleText: String,
        visibleLines: [String],
        visibleTextRuns: [TitleTextRun],
        projectDimensions: ProjectDimensions? = nil
    ) {
        self.element = element
        self.name = name
        self.ref = ref
        self.lane = lane
        self.offset = offset
        self.start = start
        self.duration = duration
        self.visibleText = visibleText
        self.visibleLines = visibleLines
        self.visibleTextRuns = visibleTextRuns
        self.projectDimensions = projectDimensions
    }
}

public final class FCPXMLDocument {
    public let inputDocument: InputDocument
    public let xmlDocument: XMLDocument
    public let rootElement: XMLElement
    public let version: String
    public let projectNames: [String]
    public let basicTitleResourceIDs: Set<String>
    public let customResourceIDs: Set<String>
    public let titles: [TitleRecord]
    public let projectDimensions: ProjectDimensions?

    public var customGeneratorResourceIDs: Set<String> {
        customResourceIDs
    }

    public var rootXML: String {
        rootElement.xmlString
    }

    public convenience init(inputDocument: InputDocument) throws {
        let parsedDocument: XMLDocument
        do {
            parsedDocument = try XMLDocument(contentsOf: inputDocument.xmlURL, options: .nodePreserveAll)
        } catch {
            throw AlignerError.malformedXML(error.localizedDescription)
        }
        try self.init(inputDocument: inputDocument, parsedDocument: parsedDocument)
    }

    public convenience init(xmlString: String) throws {
        let parsedDocument: XMLDocument
        do {
            parsedDocument = try XMLDocument(xmlString: xmlString, options: .nodePreserveAll)
        } catch {
            throw AlignerError.malformedXML(error.localizedDescription)
        }
        let inMemoryURL = URL(fileURLWithPath: "/in-memory.fcpxml")
        try self.init(inputDocument: InputDocument(sourceURL: inMemoryURL), parsedDocument: parsedDocument)
    }

    private init(inputDocument: InputDocument, parsedDocument: XMLDocument) throws {
        self.inputDocument = inputDocument
        self.xmlDocument = parsedDocument

        guard let rootElement = parsedDocument.rootElement() else {
            throw AlignerError.malformedXML("The document has no root element.")
        }
        self.rootElement = rootElement
        version = rootElement.attribute(forName: "version")?.stringValue ?? ""

        let effects = try Self.elements(atXPath: "//resources/effect", in: parsedDocument)
        let discoveredBasicTitleResourceIDs = Set(
            effects.filter(Self.isBasicTitleEffect).compactMap { $0.attribute(forName: "id")?.stringValue }
        )
        let discoveredCustomResourceIDs = Set(
            effects.filter(Self.isCustomSolidEffect).compactMap { $0.attribute(forName: "id")?.stringValue }
        )
        let discoveredProjectNames = try Self.elements(atXPath: "//project", in: parsedDocument).compactMap {
            $0.attribute(forName: "name")?.stringValue
        }
        let dimensionsByFormatID = try Self.formatDimensions(in: parsedDocument)
        let discoveredProjectDimensions = try Self.unambiguousProjectDimensions(
            in: parsedDocument,
            dimensionsByFormatID: dimensionsByFormatID
        )

        let titleElements = try Self.elements(atXPath: "//title", in: parsedDocument).filter {
            guard let reference = $0.attribute(forName: "ref")?.stringValue else { return false }
            return discoveredBasicTitleResourceIDs.contains(reference)
        }
        guard !titleElements.isEmpty else {
            throw AlignerError.noBasicTitles
        }
        let discoveredTitles = try titleElements.map {
            try Self.makeTitleRecord(
                $0,
                projectDimensions: Self.containingProjectDimensions(
                    for: $0,
                    dimensionsByFormatID: dimensionsByFormatID
                )
            )
        }

        basicTitleResourceIDs = discoveredBasicTitleResourceIDs
        customResourceIDs = discoveredCustomResourceIDs
        projectNames = discoveredProjectNames
        titles = discoveredTitles
        projectDimensions = discoveredProjectDimensions
    }

    private static func makeTitleRecord(
        _ element: XMLElement,
        projectDimensions: ProjectDimensions?
    ) throws -> TitleRecord {
        var styleDefinitions: [String: [XMLElement]] = [:]
        for definition in try elements(atXPath: "./text-style-def", in: element) {
            guard let identifier = definition.attribute(forName: "id")?.stringValue else { continue }
            styleDefinitions[identifier, default: []].append(definition)
        }
        let textStyleElements = try elements(atXPath: "./text/text-style", in: element)
        let visibleTextRuns = textStyleElements.map {
            let reference = $0.attribute(forName: "ref")?.stringValue ?? ""
            let definition: XMLElement? = styleDefinitions[reference].flatMap { definitions -> XMLElement? in
                guard definitions.count == 1 else { return nil }
                return (definitions[0].children ?? []).compactMap { $0 as? XMLElement }
                    .first { $0.name == "text-style" }
            }
            let sourceFontFamily = $0.attribute(forName: "font")?.stringValue
                ?? definition?.attribute(forName: "font")?.stringValue
            let sourceFontFace = $0.attribute(forName: "fontFace")?.stringValue
                ?? definition?.attribute(forName: "fontFace")?.stringValue
            let italicValue = $0.attribute(forName: "italic")?.stringValue
                ?? definition?.attribute(forName: "italic")?.stringValue
            let isItalic = ["1", "true", "yes"].contains(italicValue?.lowercased() ?? "")
                || sourceFontFace?.localizedCaseInsensitiveContains("italic") == true
            return TitleTextRun(
                element: $0,
                ref: reference,
                string: visibleString(in: $0),
                sourceFontFamily: sourceFontFamily,
                sourceFontFace: sourceFontFace,
                isItalic: isItalic
            )
        }
        let visibleText = visibleTextRuns.map(\.string).joined()
        let visibleLines = visibleText
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return TitleRecord(
            element: element,
            name: element.attribute(forName: "name")?.stringValue ?? "",
            ref: element.attribute(forName: "ref")?.stringValue ?? "",
            lane: element.attribute(forName: "lane")?.stringValue ?? "",
            offset: element.attribute(forName: "offset")?.stringValue ?? "",
            start: element.attribute(forName: "start")?.stringValue ?? "",
            duration: element.attribute(forName: "duration")?.stringValue ?? "",
            visibleText: visibleText,
            visibleLines: visibleLines,
            visibleTextRuns: visibleTextRuns,
            projectDimensions: projectDimensions
        )
    }

    private static func isBasicTitleEffect(_ effect: XMLElement) -> Bool {
        let name = effect.attribute(forName: "name")?.stringValue ?? ""
        let uid = effect.attribute(forName: "uid")?.stringValue ?? ""
        return name.caseInsensitiveCompare("Basic Title") == .orderedSame
            || uid.localizedCaseInsensitiveContains("Basic Title.moti")
    }

    private static func isCustomSolidEffect(_ effect: XMLElement) -> Bool {
        let name = effect.attribute(forName: "name")?.stringValue ?? ""
        let uid = effect.attribute(forName: "uid")?.stringValue ?? ""
        return name.caseInsensitiveCompare("Custom") == .orderedSame
            || uid.localizedCaseInsensitiveContains("Generators.localized/Solids.localized/Custom")
    }

    private static func visibleString(in element: XMLElement) -> String {
        let parsedValue = element.stringValue ?? ""
        guard parsedValue.isEmpty else { return parsedValue }

        // FoundationXML preserves whitespace-only element content in serialization,
        // but omits its text node/stringValue. Those runs carry intentional line breaks.
        let serialized = element.xmlString
        guard
            let openingTagStart = serialized.range(of: "<text-style"),
            let openingTagEnd = serialized[openingTagStart.lowerBound...].firstIndex(of: ">"),
            let closingTagStart = serialized.range(of: "</text-style>", options: .backwards)?.lowerBound
        else { return parsedValue }
        let contentStart = serialized.index(after: openingTagEnd)
        guard contentStart <= closingTagStart else { return parsedValue }
        let serializedContent = String(serialized[contentStart..<closingTagStart])
        return serializedContent.allSatisfy(\.isWhitespace) ? serializedContent : parsedValue
    }

    private static func formatDimensions(in document: XMLDocument) throws -> [String: ProjectDimensions] {
        let formats = try elements(atXPath: "//resources/format", in: document)
        var dimensionsByFormatID: [String: ProjectDimensions] = [:]
        var encounteredFormatIDs = Set<String>()
        for format in formats {
            // Missing/empty IDs have historically not been usable for format lookup, so leave
            // them unresolved rather than assigning an arbitrary identity. Nonempty IDs must be
            // unique even if their dimensions are otherwise unusable.
            guard let identifier = format.attribute(forName: "id")?.stringValue, !identifier.isEmpty else {
                continue
            }
            guard encounteredFormatIDs.insert(identifier).inserted else {
                throw AlignerError.malformedXML("Duplicate nonempty format id: \(identifier).")
            }
            guard
                let widthString = format.attribute(forName: "width")?.stringValue,
                let heightString = format.attribute(forName: "height")?.stringValue,
                let width = Int(widthString),
                let height = Int(heightString)
            else {
                continue
            }
            dimensionsByFormatID[identifier] = ProjectDimensions(width: width, height: height)
        }
        return dimensionsByFormatID
    }

    private static func unambiguousProjectDimensions(
        in document: XMLDocument,
        dimensionsByFormatID: [String: ProjectDimensions]
    ) throws -> ProjectDimensions? {
        let sequences = try elements(atXPath: "//project/sequence", in: document)
        guard !sequences.isEmpty else { return nil }
        let dimensions = sequences.compactMap { sequence -> ProjectDimensions? in
            guard let formatID = sequence.attribute(forName: "format")?.stringValue else { return nil }
            return dimensionsByFormatID[formatID]
        }
        guard dimensions.count == sequences.count, let first = dimensions.first else { return nil }
        return dimensions.allSatisfy { $0 == first } ? first : nil
    }

    private static func containingProjectDimensions(
        for title: XMLElement,
        dimensionsByFormatID: [String: ProjectDimensions]
    ) -> ProjectDimensions? {
        var ancestor: XMLNode? = title.parent
        while let element = ancestor as? XMLElement {
            if element.name == "sequence" {
                guard let formatID = element.attribute(forName: "format")?.stringValue else { return nil }
                return dimensionsByFormatID[formatID]
            }
            ancestor = element.parent
        }
        return nil
    }

    private static func elements(atXPath path: String, in node: XMLNode) throws -> [XMLElement] {
        try node.nodes(forXPath: path).compactMap { $0 as? XMLElement }
    }
}
