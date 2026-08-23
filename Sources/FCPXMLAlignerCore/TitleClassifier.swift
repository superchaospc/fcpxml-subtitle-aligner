import Foundation

public enum TitleKind: String, Equatable, Sendable {
    case action
    case ingredient
    case closing
}

public enum TitleClassifier {
    private static let quantityPattern = #"(?<![\p{L}\p{M}\p{N}\p{Pc}])(?:\d+(?:[.,]\d+)?|\d+\s*/\s*\d+)\s*(?:kg|mg|ml|tbsp|tsp|cups?|oz|g|l|%)(?![\p{L}\p{M}\p{N}\p{Pc}])|(?<![\p{L}\p{M}\p{N}\p{Pc}/])\d+\s*/\s*\d+(?![\p{L}\p{M}\p{N}\p{Pc}/])"#

    public static func classify(_ text: String) -> TitleKind {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let quantityLineCount = lines.reduce(into: 0) { count, line in
            if line.range(of: quantityPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                count += 1
            }
        }

        if lines.count >= 3 && quantityLineCount >= 2 {
            return .ingredient
        }

        if text.range(of: "follow for more", options: [.caseInsensitive, .diacriticInsensitive]) != nil
            || lines.count >= 2 {
            return .closing
        }

        return .action
    }
}
