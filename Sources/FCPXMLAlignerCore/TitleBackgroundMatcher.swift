import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct RationalTime: Equatable, Comparable, Sendable {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private let seconds: Decimal

    public init?(numerator: Int64, denominator: Int64) {
        guard let seconds = Self.divide(Decimal(numerator), by: Decimal(denominator)) else {
            return nil
        }
        self.seconds = seconds
    }

    public init?(parsing value: String) {
        guard value.hasSuffix("s") else { return nil }
        let body = String(value.dropLast())
        guard !body.isEmpty else { return nil }

        let parts = body.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            guard let seconds = Self.decimal(from: String(parts[0])) else { return nil }
            self.seconds = seconds
        case 2:
            guard
                let numerator = Self.decimal(from: String(parts[0])),
                let denominator = Self.decimal(from: String(parts[1])),
                let seconds = Self.divide(numerator, by: denominator)
            else {
                return nil
            }
            self.seconds = seconds
        default:
            return nil
        }
    }

    public static func < (lhs: RationalTime, rhs: RationalTime) -> Bool {
        var left = lhs.seconds
        var right = rhs.seconds
        return NSDecimalCompare(&left, &right) == .orderedAscending
    }

    public func adding(_ other: RationalTime) -> RationalTime? {
        guard let seconds = Self.add(seconds, other.seconds) else { return nil }
        return RationalTime(seconds: seconds)
    }

    private init(seconds: Decimal) {
        self.seconds = seconds
    }

    private static func decimal(from value: String) -> Decimal? {
        guard isSignedInteger(value), significantDigitCount(of: value) <= 38 else { return nil }
        return Decimal(string: value, locale: posixLocale)
    }

    private static func isSignedInteger(_ value: String) -> Bool {
        let digits = value.first == "-" || value.first == "+" ? value.dropFirst() : value[...]
        return !digits.isEmpty && digits.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func significantDigitCount(of value: String) -> Int {
        let digits = value.first == "-" || value.first == "+" ? value.dropFirst() : value[...]
        let significantDigits = digits.drop(while: { $0 == "0" })
        return max(significantDigits.count, 1)
    }

    private static func add(_ lhs: Decimal, _ rhs: Decimal) -> Decimal? {
        var left = lhs
        var right = rhs
        var result = Decimal()
        guard isFinite(NSDecimalAdd(&result, &left, &right, .plain)) else { return nil }
        return result
    }

    private static func divide(_ numerator: Decimal, by denominator: Decimal) -> Decimal? {
        var numerator = numerator
        var denominator = denominator
        var result = Decimal()
        guard denominator != .zero,
              isFinite(NSDecimalDivide(&result, &numerator, &denominator, .plain))
        else {
            return nil
        }
        return result
    }

    private static func isFinite(_ error: NSDecimalNumber.CalculationError) -> Bool {
        error == .noError || error == .lossOfPrecision
    }
}

public struct MatchResult {
    public let title: TitleRecord
    public let background: XMLElement?
    public let skipReason: String?

    public init(title: TitleRecord, background: XMLElement?, skipReason: String?) {
        self.title = title
        self.background = background
        self.skipReason = skipReason
    }
}

public enum TitleBackgroundMatcher {
    public static func matches(in document: FCPXMLDocument) -> [MatchResult] {
        document.titles.map { match(title: $0, customResourceIDs: document.customGeneratorResourceIDs) }
    }

    private static func match(title: TitleRecord, customResourceIDs: Set<String>) -> MatchResult {
        guard
            let titleOffset = RationalTime(parsing: title.offset),
            let titleDuration = RationalTime(parsing: title.duration),
            titleDuration > RationalTime.zero,
            let parent = title.element.parent as? XMLElement
        else {
            return MatchResult(title: title, background: nil, skipReason: "missing background")
        }

        guard let titleEnd = titleOffset.adding(titleDuration) else {
            return MatchResult(title: title, background: nil, skipReason: "missing background")
        }
        let candidates = (parent.children ?? []).compactMap { $0 as? XMLElement }.compactMap { element -> (element: XMLElement, offset: RationalTime, duration: RationalTime)? in
            guard
                element.name == "video" || element.name == "generator",
                let reference = element.attribute(forName: "ref")?.stringValue,
                customResourceIDs.contains(reference),
                let offsetString = element.attribute(forName: "offset")?.stringValue,
                let durationString = element.attribute(forName: "duration")?.stringValue,
                let offset = RationalTime(parsing: offsetString),
                let duration = RationalTime(parsing: durationString),
                duration > RationalTime.zero
            else {
                return nil
            }
            return (element, offset, duration)
        }.filter { candidate in
            guard let candidateEnd = candidate.offset.adding(candidate.duration) else { return false }
            return candidate.offset < titleEnd && titleOffset < candidateEnd
        }

        let exactCandidates = candidates.filter { $0.offset == titleOffset && $0.duration == titleDuration }
        if exactCandidates.count == 1 {
            return MatchResult(title: title, background: exactCandidates[0].element, skipReason: nil)
        }
        if exactCandidates.count > 1 || candidates.count > 1 {
            return MatchResult(title: title, background: nil, skipReason: "ambiguous backgrounds")
        }
        if let candidate = candidates.only {
            return MatchResult(title: title, background: candidate.element, skipReason: nil)
        }
        return MatchResult(title: title, background: nil, skipReason: "missing background")
    }
}

private extension RationalTime {
    static let zero = RationalTime(seconds: .zero)
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
