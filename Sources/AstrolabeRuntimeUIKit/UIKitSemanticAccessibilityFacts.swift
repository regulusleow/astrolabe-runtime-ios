import AstrolabeProtocol

/// Projects sanitized AX values; never reads live objects or infers state from text.
enum UIKitSemanticAccessibilityFacts {
    /// Semantic wire types permit at most 512 characters, including compiler-generated generic names.
    static func runtimeTypeName(_ name: String) -> String { String(name.prefix(512)) }

    static func role(traits: [String], nativeRole: String?) -> String {
        if nativeRole == "input" || traits.contains("searchField") { return "input" }
        if traits.contains("toggleButton") || traits.contains("adjustable") { return "control" }
        if traits.contains("button") || traits.contains("keyboardKey") { return "button" }
        if traits.contains("image") { return "image" }
        if traits.contains("staticText") { return "text" }
        return nativeRole ?? "container"
    }

    static func section(for info: RuntimeAccessibility?) throws -> RuntimeAttributeSection? {
        guard let info else { return nil }
        func attribute(_ suffix: String, _ value: RuntimeAttributeValue) throws -> RuntimeAttribute {
            RuntimeAttribute(identifier: try .init(rawValue: "ios.accessibility." + suffix), value: value)
        }
        var attributes = [try attribute("element", .boolean(info.element))]
        for (name, value) in [("identifier", info.identifier), ("label", info.label),
                              ("value", info.value), ("hint", info.hint)] {
            if let value { attributes.append(try attribute(name, .string(value))) }
        }
        if !info.traits.isEmpty { attributes.append(try attribute("traits", .stringList(info.traits))) }
        return RuntimeAttributeSection(category: try .init(rawValue: "ios.accessibility"), attributes: attributes)
    }
}
