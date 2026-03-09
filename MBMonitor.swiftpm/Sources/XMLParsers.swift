import Foundation

// MARK: - Simple single-element parser

enum XMLSimpleParser {
    /// Extract the text content of the first occurrence of an element.
    static func firstElementText(named element: String, in data: Data) -> String? {
        let delegate = SingleElementDelegate(targetElement: element)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }
}

private class SingleElementDelegate: NSObject, XMLParserDelegate {
    let targetElement: String
    var result: String?
    private var isCapturing = false
    private var buffer = ""

    init(targetElement: String) { self.targetElement = targetElement }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == targetElement && result == nil {
            isCapturing = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCapturing { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if element == targetElement && isCapturing {
            result = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            isCapturing = false
        }
    }
}

// MARK: - Connector list parser

enum ConnectorParser {
    static func parse(data: Data) -> [Connector] {
        let delegate = ConnectorListDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.connectors
    }
}

/// Parses `<devices><cloud>...</cloud><cloud>...</cloud></devices>` XML.
/// Each `<cloud>` has child elements: guid, name, type, agent-type, created, accessible, etc.
private class ConnectorListDelegate: NSObject, XMLParserDelegate {
    var connectors: [Connector] = []
    private var buffer = ""
    private var attrs: [String: String] = [:]
    private var inCloud = false
    private var depth = 0  // track nesting inside <cloud>

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if element == "cloud" {
            inCloud = true
            depth = 0
            attrs = [:]
        } else if inCloud {
            depth += 1
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        if element == "cloud" {
            // Build connector from collected attrs
            if let guid = attrs["guid"], let name = attrs["name"] {
                var typeStr = attrs["type"] ?? "unknown"
                // DSL connectors: real type is in agent-type
                if typeStr == "dsl", let agentType = attrs["agent-type"] {
                    typeStr = agentType
                }
                // Skip system devices
                if typeStr != "system" {
                    let connector = Connector(
                        id: guid.lowercased(),
                        name: String(name.prefix(200)),
                        type: ConnectorType(rawValue: typeStr) ?? .unknown,
                        created: ISO8601DateFormatter().date(from: attrs["created"] ?? "") ?? .now,
                        health: .unknown
                    )
                    connectors.append(connector)
                }
            }
            inCloud = false
        } else if inCloud {
            // Only capture direct children of <cloud> (depth == 1)
            if depth == 1 {
                let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { attrs[element] = value }
            }
            depth -= 1
        }
    }
}

// MARK: - Health parser

enum HealthParser {
    static func parse(data: Data) -> (HealthStatus, String?) {
        let health = XMLSimpleParser.firstElementText(named: "health", in: data) ?? "unknown"
        let reason = XMLSimpleParser.firstElementText(named: "reason", in: data)
        return (HealthStatus(rawValue: health) ?? .unknown, reason)
    }
}
