import Foundation

nonisolated final class OfficeXMLNode {
    let name: String
    let attributes: [String: String]
    var children: [OfficeXMLNode] = []
    var content = ""
    var supportedChoice = false
    var alternative: OfficeXMLNode? {
        children.first { $0.name == "mc:Choice" && $0.supportedChoice } ?? child("mc:Fallback")
    }
    init(_ name: String, attributes: [String: String] = [:]) { self.name = name; self.attributes = attributes }
    func child(_ name: String) -> OfficeXMLNode? { children.first { $0.name == name } }
    func all(_ name: String) -> [OfficeXMLNode] { children.filter { $0.name == name } }
    func descendants(_ name: String) -> [OfficeXMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }
    var text: String { name == "#text" ? content : children.map(\.text).joined() }
    func value(_ childName: String) -> String? { child(childName)?.attributes["w:val"] }
}

/// Namespace-aware bounded XML. DTDs and entity declarations are not part of
/// accepted Office content; external resources are never resolved.
nonisolated final class OfficeXML: NSObject, XMLParserDelegate {
    private var stack: [OfficeXMLNode] = []
    private var prefixes: [String: [String]] = [:]
    private var root: OfficeXMLNode?
    private var nodes = 0
    private var rejected = false

    static func parse(_ data: Data) throws -> OfficeXMLNode {
        guard data.count <= 8 * 1024 * 1024 else { throw OfficeConversionError.tooLarge }
        // Normalizing NULs also catches UTF-16/32 declarations before the parser.
        let probe = String(decoding: data.filter { $0 != 0 }, as: UTF8.self).uppercased()
        guard !probe.contains("<!DOCTYPE"), !probe.contains("<!ENTITY") else { throw OfficeConversionError.invalidXML }
        let delegate = OfficeXML()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.rejected, let root = delegate.root else { throw OfficeConversionError.invalidXML }
        return root
    }

    private func prefix(for uri: String) -> String {
        switch uri {
        case "http://schemas.openxmlformats.org/wordprocessingml/2006/main", "http://purl.oclc.org/ooxml/wordprocessingml/main": "w"
        case "http://schemas.openxmlformats.org/officeDocument/2006/relationships", "http://purl.oclc.org/ooxml/officeDocument/relationships": "r"
        case "http://schemas.openxmlformats.org/package/2006/relationships": "rel"
        case "http://schemas.openxmlformats.org/drawingml/2006/main", "http://purl.oclc.org/ooxml/drawingml/main": "a"
        case "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing", "http://purl.oclc.org/ooxml/drawingml/wordprocessingDrawing": "wp"
        case "urn:oasis:names:tc:opendocument:xmlns:office:1.0": "office"
        case "urn:oasis:names:tc:opendocument:xmlns:text:1.0": "text"
        case "urn:oasis:names:tc:opendocument:xmlns:style:1.0": "style"
        case "urn:oasis:names:tc:opendocument:xmlns:table:1.0": "table"
        case "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0": "draw"
        case "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0": "fo"
        case "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0": "svg"
        case "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0": "manifest"
        case "http://www.w3.org/1999/xlink": "xlink"
        case "http://www.w3.org/XML/1998/namespace": "xml"
        case "http://schemas.openxmlformats.org/markup-compatibility/2006": "mc"
        case "urn:schemas-microsoft-com:vml": "v"
        case "http://schemas.microsoft.com/office/word/2010/wordprocessingShape": "wps"
        case "http://schemas.openxmlformats.org/drawingml/2006/picture": "pic"
        default: "{\(uri)}"
        }
    }
    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        prefixes[prefix, default: []].append(namespaceURI)
    }
    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = prefixes[prefix]?.popLast() }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        nodes += 1
        guard nodes <= 100_000, stack.count < 80, !Task.isCancelled else { rejected = true; parser.abortParsing(); return }
        let name = (namespaceURI.map { prefix(for: $0) + ":" } ?? "") + elementName
        var attributes: [String: String] = [:]
        for (key, value) in attributeDict {
            let pieces = key.split(separator: ":", maxSplits: 1).map(String.init)
            if pieces.count == 2, let uri = prefixes[pieces[0]]?.last {
                attributes[prefix(for: uri) + ":" + pieces[1]] = value
            } else { attributes[key] = value }
        }
        let node = OfficeXMLNode(name, attributes: attributes)
        if name == "mc:Choice" {
            let required = (attributes["Requires"] ?? "").split(separator: " ").map(String.init)
            node.supportedChoice = !required.isEmpty && required.allSatisfy {
                guard let uri = prefixes[$0]?.last else { return false }
                return ["w", "wps", "a", "wp", "pic", "v"].contains(prefix(for: uri))
            }
        }
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { _ = stack.popLast() }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let parent = stack.last else { return }
        if let last = parent.children.last, last.name == "#text" { last.content += string }
        else {
            nodes += 1
            guard nodes <= 100_000 else { rejected = true; parser.abortParsing(); return }
            let node = OfficeXMLNode("#text"); node.content = string; parent.children.append(node)
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        self.parser(parser, foundCharacters: String(decoding: CDATABlock, as: UTF8.self))
    }
}
