import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct InvariantSnapshot: Equatable {
    public struct ElementAttributes: Equatable {
        public let path: String
        public let elementName: String
        public let attributes: [String: String]
    }

    public struct TextRun: Equatable {
        public let text: String
        public let ref: String
        public let colors: [String: String]
    }

    public struct VisibleTitle: Equatable {
        public let path: String
        public let text: String
        public let runs: [TextRun]
    }

    public let timing: [ElementAttributes]
    public let mediaReferences: [ElementAttributes]
    public let visibleTextAndColors: [VisibleTitle]
    public let nonStyleStructure: [ElementAttributes]

    public init(document: FCPXMLDocument) {
        var timing: [ElementAttributes] = []
        var mediaReferences: [ElementAttributes] = []
        var visibleTextAndColors: [VisibleTitle] = []
        var nonStyleStructure: [ElementAttributes] = []
        let basicTitleElementIDs = Set(document.titles.map { ObjectIdentifier($0.element) })
        let heroTitleElementIDs = Set(document.titles.lazy.filter {
            LayoutVariantSelector.select(visibleText: $0.visibleText) == .heroAction
        }.map { ObjectIdentifier($0.element) })
        let matchedBackgroundElementIDs = Set(
            TitleBackgroundMatcher.matches(in: document).compactMap { $0.background }.map(ObjectIdentifier.init)
        )

        func walk(
            _ element: XMLElement,
            path: String,
            isResourceDescendant: Bool,
            isInsideBasicTitle: Bool,
            isInsideHeroTitle: Bool
        ) {
            let name = element.name ?? ""
            let attributes = Self.attributes(of: element)
            let resourceDescendant = isResourceDescendant || name == "resources"
            let isBasicTitle = name == "title" && basicTitleElementIDs.contains(ObjectIdentifier(element))
            let insideBasicTitle = isInsideBasicTitle || isBasicTitle
            let isHeroTitle = name == "title" && heroTitleElementIDs.contains(ObjectIdentifier(element))
            let insideHeroTitle = isInsideHeroTitle || isHeroTitle
            let parent = element.parent as? XMLElement

            let timingAttributes = attributes.filter { ["offset", "start", "duration"].contains($0.key) }
            if !timingAttributes.isEmpty || ["spine", "clip", "title", "video", "generator"].contains(name) {
                timing.append(ElementAttributes(path: path, elementName: name, attributes: timingAttributes))
            }

            if name != "text-style", resourceDescendant || attributes["ref"] != nil || attributes["src"] != nil {
                mediaReferences.append(ElementAttributes(path: path, elementName: name, attributes: attributes))
            }

            if isBasicTitle {
                visibleTextAndColors.append(Self.visibleTitle(from: element, path: path))
            }

            let isAllowedTransform = name == "adjust-transform"
                && (
                    insideBasicTitle
                        || parent.map { matchedBackgroundElementIDs.contains(ObjectIdentifier($0)) } == true
                )
            if !isAllowedTransform {
                nonStyleStructure.append(ElementAttributes(
                    path: path,
                    elementName: name,
                    attributes: Self.nonStyleAttributes(
                        for: element,
                        parent: parent,
                        isInsideBasicTitle: insideBasicTitle,
                        isInsideHeroTitle: insideHeroTitle,
                        isMatchedCustomBackground: parent.map { matchedBackgroundElementIDs.contains(ObjectIdentifier($0)) } ?? false,
                    allAttributes: attributes
                )
                ))
            }

            let children = (element.children ?? []).compactMap { $0 as? XMLElement }
            for (index, child) in children.enumerated() {
                let childName = child.name ?? ""
                walk(
                    child,
                    path: "\(path)/\(childName)[\(index)]",
                    isResourceDescendant: resourceDescendant,
                    isInsideBasicTitle: insideBasicTitle,
                    isInsideHeroTitle: insideHeroTitle
                )
            }
        }

        let root = document.rootElement
        walk(
            root,
            path: "/\(root.name ?? "fcpxml")[0]",
            isResourceDescendant: false,
            isInsideBasicTitle: false,
            isInsideHeroTitle: false
        )
        self.timing = timing
        self.mediaReferences = mediaReferences
        self.visibleTextAndColors = visibleTextAndColors
        self.nonStyleStructure = nonStyleStructure
    }

    private static func attributes(of element: XMLElement) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (element.attributes ?? []).compactMap { attribute in
            guard let name = attribute.name else { return nil }
            return (name, attribute.stringValue ?? "")
        })
    }

    private static func visibleTitle(from title: XMLElement, path: String) -> VisibleTitle {
        let children = (title.children ?? []).compactMap { $0 as? XMLElement }
        var definitions: [String: [XMLElement]] = [:]
        for definition in children where definition.name == "text-style-def" {
            guard let identifier = definition.attribute(forName: "id")?.stringValue else { continue }
            definitions[identifier, default: []].append(definition)
        }
        let textElement = children.first { $0.name == "text" }
        let runElements = (textElement?.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.name == "text-style" }
        let runs = runElements.map { run in
            let reference = run.attribute(forName: "ref")?.stringValue ?? ""
            let definitionStyle: XMLElement? = definitions[reference].flatMap { candidates -> XMLElement? in
                guard candidates.count == 1 else { return nil }
                return (candidates[0].children ?? []).compactMap { $0 as? XMLElement }
                    .first { $0.name == "text-style" }
            }
            var colors = colorAttributes(of: run)
            if let definitionStyle {
                colors.merge(colorAttributes(of: definitionStyle), uniquingKeysWith: { _, newer in newer })
            }
            return TextRun(text: run.stringValue ?? "", ref: reference, colors: colors)
        }
        return VisibleTitle(path: path, text: runs.map(\.text).joined(), runs: runs)
    }

    private static func colorAttributes(of element: XMLElement) -> [String: String] {
        attributes(of: element).filter { $0.key.localizedCaseInsensitiveContains("color") }
    }

    private static func nonStyleAttributes(
        for element: XMLElement,
        parent: XMLElement?,
        isInsideBasicTitle: Bool,
        isInsideHeroTitle: Bool,
        isMatchedCustomBackground: Bool,
        allAttributes: [String: String]
    ) -> [String: String] {
        var attributes = allAttributes
        if element.name == "project" {
            attributes.removeValue(forKey: "name")
            attributes.removeValue(forKey: "uid")
        }
        if element.name == "text-style", isInsideBasicTitle {
            ["font", "fontSize", "fontFace", "alignment", "lineSpacing"].forEach {
                attributes.removeValue(forKey: $0)
            }
            if isInsideHeroTitle {
                attributes.removeValue(forKey: "bold")
            }
        }
        if element.name == "param",
           isInsideBasicTitle,
           parent?.name == "title",
           let name = attributes["name"],
           ["Alignment", "Line Spacing"].contains(name) {
            attributes.removeValue(forKey: "value")
        }
        if element.name == "adjust-transform", isInsideBasicTitle || isMatchedCustomBackground {
            attributes.removeAll()
        }
        return attributes
    }
}
