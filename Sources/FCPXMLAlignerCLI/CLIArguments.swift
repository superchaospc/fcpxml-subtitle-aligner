import Foundation
import FCPXMLAlignerCore

public struct CLIArguments: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case align
        case help
        case version
    }

    public let mode: Mode
    public let input: URL?
    public let settings: AlignmentSettings
    public let json: Bool

    public static func parse(_ arguments: [String]) throws -> CLIArguments {
        var mode = Mode.align
        var inputPath: String?
        var settings = AlignmentSettings.templateDefaults
        var json = false
        var sawAlignmentArgument = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            guard mode == .align else {
                throw CLIArgumentError.unexpectedArgument(argument)
            }

            switch argument {
            case "--help", "-h":
                guard inputPath == nil, !sawAlignmentArgument else {
                    throw CLIArgumentError.unexpectedArgument(argument)
                }
                mode = .help

            case "--version":
                guard inputPath == nil, !sawAlignmentArgument else {
                    throw CLIArgumentError.unexpectedArgument(argument)
                }
                mode = .version

            case "--action-size":
                settings.actionBaseSize = try number(after: argument, in: arguments, index: &index)
                sawAlignmentArgument = true

            case "--ingredient-size":
                settings.ingredientBaseSize = try number(after: argument, in: arguments, index: &index)
                sawAlignmentArgument = true

            case "--minimum-size":
                settings.minimumSize = try number(after: argument, in: arguments, index: &index)
                sawAlignmentArgument = true

            case "--safe-width":
                settings.safeWidthFraction = try number(after: argument, in: arguments, index: &index)
                sawAlignmentArgument = true

            case "--auto-shrink":
                settings.autoShrink = true
                sawAlignmentArgument = true

            case "--no-auto-shrink":
                settings.autoShrink = false
                sawAlignmentArgument = true

            case "--json":
                json = true
                sawAlignmentArgument = true

            default:
                guard !argument.hasPrefix("-") else {
                    throw CLIArgumentError.unexpectedArgument(argument)
                }
                guard inputPath == nil else {
                    throw CLIArgumentError.unexpectedArgument(argument)
                }
                inputPath = argument
            }

            index += 1
        }

        if mode == .align {
            guard let inputPath else { throw CLIArgumentError.missingInput }
            try validate(settings)

            let currentDirectory = URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
            let input = URL(fileURLWithPath: inputPath, relativeTo: currentDirectory)
                .absoluteURL
                .standardizedFileURL
            return CLIArguments(mode: mode, input: input, settings: settings, json: json)
        }

        return CLIArguments(mode: mode, input: nil, settings: settings, json: json)
    }

    private static func number(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> Double {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIArgumentError.missingValue(option)
        }

        let value = arguments[valueIndex]
        guard !optionNames.contains(value) else {
            throw CLIArgumentError.missingValue(option)
        }
        guard let number = Double(value), number.isFinite else {
            throw CLIArgumentError.invalidNumber(option: option, value: value)
        }

        index = valueIndex
        return number
    }

    private static func validate(_ settings: AlignmentSettings) throws {
        guard settings.actionBaseSize > 0 else {
            throw CLIArgumentError.invalidSettings("Action size must be greater than zero.")
        }
        guard settings.ingredientBaseSize > 0 else {
            throw CLIArgumentError.invalidSettings("Ingredient size must be greater than zero.")
        }
        guard settings.minimumSize > 0 else {
            throw CLIArgumentError.invalidSettings("Minimum size must be greater than zero.")
        }
        guard settings.minimumSize <= settings.actionBaseSize,
              settings.minimumSize <= settings.ingredientBaseSize
        else {
            throw CLIArgumentError.invalidSettings(
                "Minimum size must not exceed either action size or ingredient size."
            )
        }
        guard (0.1...1.0).contains(settings.safeWidthFraction) else {
            throw CLIArgumentError.invalidSettings("Safe width must be between 0.1 and 1.0.")
        }
    }

    private static let optionNames: Set<String> = [
        "--action-size",
        "--ingredient-size",
        "--minimum-size",
        "--safe-width",
        "--auto-shrink",
        "--no-auto-shrink",
        "--json",
        "--help",
        "-h",
        "--version",
    ]
}

public enum CLIArgumentError: Error, LocalizedError, Equatable {
    case missingInput
    case unexpectedArgument(String)
    case missingValue(String)
    case invalidNumber(option: String, value: String)
    case invalidSettings(String)

    public var errorDescription: String? {
        switch self {
        case .missingInput:
            "An input FCPXML file is required."
        case .unexpectedArgument(let argument):
            "Unexpected argument: \(argument)"
        case .missingValue(let option):
            "Missing value for \(option)."
        case .invalidNumber(let option, let value):
            "Invalid number for \(option): \(value)"
        case .invalidSettings(let message):
            message
        }
    }
}
