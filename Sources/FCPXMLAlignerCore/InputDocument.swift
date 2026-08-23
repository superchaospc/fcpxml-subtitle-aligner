import Foundation

public enum InputKind: Equatable, Sendable {
    case file
    case bundle
}

public enum AlignerError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedInput(String)
    case missingInfoXML
    case malformedXML(String)
    case noBasicTitles
    case invalidTypographySettings(String)
    case targetFontUnavailable(family: String, face: String)
    case invalidTypographyMeasurement(String)
    case invariantViolation(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedInput(let fileExtension):
            return "Unsupported input '\(fileExtension)'. Choose an .fcpxml file or .fcpxmld bundle."
        case .missingInfoXML:
            return "The FCPXML bundle does not contain Info.fcpxml."
        case .malformedXML(let reason):
            return "The FCPXML document is malformed: \(reason)"
        case .noBasicTitles:
            return "No Basic Title elements were found in this FCPXML document."
        case .invalidTypographySettings(let reason):
            return "Invalid typography settings: \(reason)"
        case .targetFontUnavailable(let family, let face):
            return "The required target font '\(family) \(face)' is unavailable."
        case .invalidTypographyMeasurement(let reason):
            return "Typography measurement failed: \(reason)"
        case .invariantViolation(let reason):
            return "FCPXML invariant validation failed: \(reason)"
        }
    }
}

public struct InputDocument {
    public let sourceURL: URL
    public let xmlURL: URL
    public let kind: InputKind

    public init(sourceURL: URL) throws {
        self.sourceURL = sourceURL

        switch sourceURL.pathExtension.lowercased() {
        case "fcpxml":
            xmlURL = sourceURL
            kind = .file
        case "fcpxmld":
            let infoURL = sourceURL.appendingPathComponent("Info.fcpxml")
            guard FileManager.default.fileExists(atPath: infoURL.path) else {
                throw AlignerError.missingInfoXML
            }
            xmlURL = infoURL
            kind = .bundle
        default:
            throw AlignerError.unsupportedInput(sourceURL.pathExtension.lowercased())
        }
    }
}
