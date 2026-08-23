import Foundation
import FCPXMLAlignerCore

public struct CLIExecutionResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct CLISuccessPayload: Codable, Equatable, Sendable {
    public let outputPath: String
    public let reportPath: String
    public let changedTitles: Int
    public let skippedTitles: Int

    public init(outputPath: String, reportPath: String, changedTitles: Int, skippedTitles: Int) {
        self.outputPath = outputPath
        self.reportPath = reportPath
        self.changedTitles = changedTitles
        self.skippedTitles = skippedTitles
    }
}

public struct CLIApplication {
    public static let version = "1.0.0"

    public init() {}

    public func run(arguments: [String]) -> CLIExecutionResult {
        do {
            let parsed = try CLIArguments.parse(arguments)
            switch parsed.mode {
            case .help:
                return CLIExecutionResult(exitCode: 0, stdout: Self.helpText, stderr: "")
            case .version:
                return CLIExecutionResult(
                    exitCode: 0,
                    stdout: "fcpxml-aligner \(Self.version)\n",
                    stderr: ""
                )
            case .align:
                guard let input = parsed.input else {
                    throw CLIArgumentError.missingInput
                }
                try validateInput(input)
                let output = try OutputWriter().process(input: input, settings: parsed.settings)
                return try successResult(output, json: parsed.json)
            }
        } catch let error as CLIArgumentError {
            return failure(
                exitCode: 64,
                message: error.localizedDescription,
                helpHint: true
            )
        } catch let error as CLIInputError {
            return failure(exitCode: 66, message: error.localizedDescription)
        } catch let error as AlignerError {
            switch error {
            case .unsupportedInput, .missingInfoXML:
                return failure(exitCode: 66, message: error.localizedDescription)
            case .malformedXML, .noBasicTitles, .invalidTypographySettings,
                 .targetFontUnavailable, .invalidTypographyMeasurement, .invariantViolation:
                return failure(exitCode: 65, message: error.localizedDescription)
            }
        } catch {
            return failure(exitCode: 65, message: error.localizedDescription)
        }
    }

    private func validateInput(_ input: URL) throws {
        let fileManager = FileManager.default
        let fileExtension = input.pathExtension.lowercased()
        guard fileExtension == "fcpxml" || fileExtension == "fcpxmld" else {
            throw CLIInputError(
                "Unsupported input '\(fileExtension)'. Choose an .fcpxml file or .fcpxmld bundle."
            )
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            throw CLIInputError("Input does not exist: \(input.path)")
        }

        if fileExtension == "fcpxml" {
            guard !isDirectory.boolValue, fileManager.isReadableFile(atPath: input.path) else {
                throw CLIInputError("Input is not a readable FCPXML file: \(input.path)")
            }
            return
        }

        guard isDirectory.boolValue, fileManager.isReadableFile(atPath: input.path) else {
            throw CLIInputError("Input is not a readable FCPXML bundle: \(input.path)")
        }
        let infoXML = input.appendingPathComponent("Info.fcpxml")
        var infoIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: infoXML.path, isDirectory: &infoIsDirectory),
              !infoIsDirectory.boolValue,
              fileManager.isReadableFile(atPath: infoXML.path)
        else {
            throw CLIInputError("FCPXML bundle has no readable Info.fcpxml: \(input.path)")
        }
    }

    private func successResult(_ output: OutputResult, json: Bool) throws -> CLIExecutionResult {
        let payload = CLISuccessPayload(
            outputPath: output.outputURL.standardizedFileURL.path,
            reportPath: output.reportURL.standardizedFileURL.path,
            changedTitles: output.report.changedTitles,
            skippedTitles: output.report.skippedTitles
        )
        let stdout: String
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let encoded = String(data: try encoder.encode(payload), encoding: .utf8) else {
                throw CLIOutputError.encodingFailed
            }
            stdout = encoded + "\n"
        } else {
            stdout = """
            Output: \(payload.outputPath)
            Report: \(payload.reportPath)
            Changed: \(payload.changedTitles)
            Skipped: \(payload.skippedTitles)

            """
        }
        return CLIExecutionResult(exitCode: 0, stdout: stdout, stderr: "")
    }

    private func failure(exitCode: Int32, message: String, helpHint: Bool = false) -> CLIExecutionResult {
        var stderr = "Error: \(message)\n"
        if helpHint {
            stderr += "Try 'fcpxml-aligner --help' for usage.\n"
        }
        return CLIExecutionResult(exitCode: exitCode, stdout: "", stderr: stderr)
    }

    private static let helpText = """
    Usage: fcpxml-aligner [options] <input.fcpxml|input.fcpxmld>

    Align Basic Title subtitles with their Custom backgrounds. The input is never modified.
    Output is written to new sibling files; the tool does not overwrite existing output.

    Options:
      --action-size <points>      Action title base size (default: 17)
      --ingredient-size <points>  Ingredient title base size (default: 15)
      --minimum-size <points>     Minimum auto-shrink size (default: 13)
      --safe-width <fraction>     Safe-width fraction from 0.1 to 1.0 (default: 0.9)
      --auto-shrink               Enable automatic shrinking (default)
      --no-auto-shrink            Disable automatic shrinking
      --json                      Emit one JSON result object
      --help, -h                  Show this help
      --version                   Show the version

    """
}

private struct CLIInputError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private enum CLIOutputError: Error, LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "The JSON result could not be encoded as UTF-8."
    }
}
