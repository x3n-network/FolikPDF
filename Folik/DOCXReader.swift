import Foundation
import CoreGraphics

nonisolated final class DOCXReader {
    private struct Relationship {
        let target: String
        let type: String
        let external: Bool
    }
    private let package: OfficePackage
    private var document = OfficeDocument()
    private var mainPart = ""
    private var relationships: [String: Relationship] = [:]
    private var styles: [String: OfficeXMLNode] = [:]
    private var defaults: OfficeXMLNode?
    private var numbering: OfficeXMLNode?
    private var counters: [String: [Int: Int]] = [:]
    private var noteReferences: [(kind: String, id: String)] = []
    private var readingNotes = false

    init(package: OfficePackage) { self.package = package }

    func read() throws -> OfficeDocument {
        let rootRelationships = try readRelationships(for: "")
        guard let main = rootRelationships.values.first(where: { $0.type.hasSuffix("/officeDocument") && !$0.external }) else {
            throw OfficeConversionError.missingPart
        }
        mainPart = try OfficePackage.resolve(main.target, relativeTo: "")
        let root = try OfficeXML.parse(package.read(mainPart))
        guard root.name == "w:document", let body = root.child("w:body") else { throw OfficeConversionError.invalidPackage }
        relationships = try readRelationships(for: mainPart)
        if let part = try relatedPart("/styles") {
            let root = try OfficeXML.parse(package.read(part))
            for style in root.all("w:style") {
                if let id = style.attributes["w:styleId"] { styles[id] = style }
            }
            defaults = root.child("w:docDefaults")
        }
        if let part = try relatedPart("/numbering") { numbering = try OfficeXML.parse(package.read(part)) }
        for relationship in relationships.values {
            if ["/header", "/footer", "/comments"].contains(where: relationship.type.hasSuffix) {
                document.warnings.insert("Headers, footers, and comments are not included.")
            }
        }
        let sections = body.descendants("w:sectPr")
        if sections.count > 1 { document.warnings.insert("Multiple sections use one page size and continuous text flow.") }
        if let size = sections.first?.child("w:pgSz"),
           let width = Double(size.attributes["w:w"] ?? ""), let height = Double(size.attributes["w:h"] ?? ""),
           (288...1440).contains(width / 20), (288...1440).contains(height / 20) {
            document.pageSize = CGSize(width: width / 20, height: height / 20)
        }
        if let properties = sections.first?.child("w:pgMar") {
            var margins = document.margins
            if let value = Double(properties.attributes["w:top"] ?? "") { margins.top = value / 20 }
            if let value = Double(properties.attributes["w:bottom"] ?? "") { margins.bottom = value / 20 }
            if let value = Double(properties.attributes["w:left"] ?? "") { margins.left = value / 20 }
            if let value = Double(properties.attributes["w:right"] ?? "") { margins.right = value / 20 }
            if margins.isValid(for: document.pageSize) { document.margins = margins }
            else { document.warnings.insert("Invalid or oversized page margins were replaced with standard margins.") }
            if (Double(properties.attributes["w:gutter"] ?? "0") ?? 0) > 0 { document.warnings.insert("Binding gutters are not included in page margins.") }
        }
        if sections.contains(where: { (Int($0.child("w:cols")?.attributes["w:num"] ?? "1") ?? 1) > 1 }) {
            document.warnings.insert("Multiple text columns are converted to a single column.")
        }
        document.blocks = try blocks(body)
        try appendNotes()
        guard document.blocks.count <= 20_000 else { throw OfficeConversionError.tooLarge }
        return document
    }

    private func readRelationships(for part: String) throws -> [String: Relationship] {
        let components = part.split(separator: "/").map(String.init)
        let prefix = components.dropLast().joined(separator: "/")
        let path = part.isEmpty ? "_rels/.rels" : (prefix.isEmpty ? "" : prefix + "/") + "_rels/" + (components.last ?? "") + ".rels"
        guard package.names.contains(path) else { return [:] }
        let root = try OfficeXML.parse(package.read(path))
        guard root.name == "rel:Relationships" else { throw OfficeConversionError.invalidPackage }
        var result: [String: Relationship] = [:]
        for node in root.all("rel:Relationship") {
            guard let id = node.attributes["Id"], let target = node.attributes["Target"], let type = node.attributes["Type"], result[id] == nil else {
                throw OfficeConversionError.invalidPackage
            }
            result[id] = Relationship(target: target, type: type, external: node.attributes["TargetMode"] == "External")
        }
        return result
    }
    private func relatedPart(_ type: String) throws -> String? {
        guard let relationship = relationships.values.first(where: { $0.type.hasSuffix(type) && !$0.external }) else { return nil }
        return try OfficePackage.resolve(relationship.target, relativeTo: mainPart)
    }

    private func styleChain(_ id: String?) -> [OfficeXMLNode] {
        var chain: [OfficeXMLNode] = []
        var next = id
        var visited: Set<String> = []
        while let name = next, let style = styles[name], visited.insert(name).inserted, chain.count < 16 {
            chain.insert(style, at: 0)
            next = style.value("w:basedOn")
        }
        return chain
    }
    private func toggle(_ node: OfficeXMLNode?) -> Bool? {
        guard let node else { return nil }
        return !["0", "false", "off", "none"].contains(node.attributes["w:val"] ?? "1")
    }
    private func applyRun(_ properties: OfficeXMLNode?, to style: inout OfficeTextStyle) {
        guard let properties else { return }
        if let value = toggle(properties.child("w:b")) { style.bold = value }
        if let value = toggle(properties.child("w:i")) { style.italic = value }
        if let value = toggle(properties.child("w:u")) { style.underline = value }
        if let value = Double(properties.value("w:sz") ?? ""), value.isFinite { style.size = min(96, max(6, value / 2)) }
        if let font = properties.child("w:rFonts")?.attributes["w:ascii"], font.count < 100 { style.font = font }
        if let color = properties.value("w:color"), color.count == 6, UInt32(color, radix: 16) != nil { style.color = color }
        if let value = toggle(properties.child("w:strike")) { style.strikethrough = value }
        if let value = properties.value("w:vertAlign") {
            style.scriptPosition = value == "superscript" ? 1 : (value == "subscript" ? -1 : 0)
        }
    }
    private func applyParagraph(_ properties: OfficeXMLNode?, to paragraph: inout OfficeParagraph) {
        guard let properties else { return }
        if let align = properties.value("w:jc") { paragraph.alignment = align == "both" ? "justify" : align }
        if let indent = Double(properties.child("w:ind")?.attributes["w:left"] ?? "") { paragraph.indent = min(144, max(0, indent / 20)) }
        if let spacing = properties.child("w:spacing") {
            if let before = Double(spacing.attributes["w:before"] ?? "") { paragraph.before = min(72, max(0, before / 20)) }
            if let after = Double(spacing.attributes["w:after"] ?? "") { paragraph.after = min(72, max(0, after / 20)) }
        }
        if let value = toggle(properties.child("w:pageBreakBefore")) { paragraph.breakBefore = value }
        if let value = toggle(properties.child("w:keepNext")) { paragraph.keepWithNext = value }
    }

    private func blocks(_ container: OfficeXMLNode) throws -> [OfficeBlock] {
        var result: [OfficeBlock] = []
        for node in container.children where node.name != "#text" {
            try Task.checkCancellation()
            switch node.name {
            case "w:p": result += try paragraph(node)
            case "mc:AlternateContent":
                if let alternative = node.alternative { result += try blocks(alternative) }
                else { document.warnings.insert("An alternate document object has no supported representation and was omitted.") }
            case "w:tbl": result.append(try table(node))
            case "w:sdt": if let content = node.child("w:sdtContent") { result += try blocks(content) }
            case "w:ins", "w:moveTo":
                document.warnings.insert("Tracked changes show the current text without revision markup.")
                result += try blocks(node)
            case "w:del", "w:moveFrom": document.warnings.insert("Tracked changes show the current text without revision markup.")
            case "w:tcPr", "w:sectPr", "w:bookmarkStart", "w:bookmarkEnd", "w:proofErr": break
            default:
                document.warnings.insert("Some unsupported document objects are omitted. Compare the preview with the original.")
            }
            guard result.count <= 20_000 else { throw OfficeConversionError.tooLarge }
        }
        return result
    }

    private func paragraph(_ node: OfficeXMLNode) throws -> [OfficeBlock] {
        let properties = node.child("w:pPr")
        let chain = styleChain(properties?.value("w:pStyle") ?? styles.values.first(where: { $0.attributes["w:type"] == "paragraph" && $0.attributes["w:default"] == "1" })?.attributes["w:styleId"])
        var paragraph = OfficeParagraph()
        var base = OfficeTextStyle()
        applyRun(defaults?.child("w:rPrDefault")?.child("w:rPr"), to: &base)
        applyParagraph(defaults?.child("w:pPrDefault")?.child("w:pPr"), to: &paragraph)
        for style in chain { applyRun(style.child("w:rPr"), to: &base); applyParagraph(style.child("w:pPr"), to: &paragraph) }
        applyParagraph(properties, to: &paragraph)
        if let id = properties?.value("w:pStyle"), id.lowercased().hasPrefix("heading") {
            paragraph.keepWithNext = true
            if chain.isEmpty { base.bold = true; base.size = 20 }
        }
        let numProperties = properties?.child("w:numPr") ?? chain.reversed().compactMap { $0.child("w:pPr")?.child("w:numPr") }.first
        if let numProperties, let id = numProperties.value("w:numId"), id != "0" {
            let level = min(8, max(0, Int(numProperties.value("w:ilvl") ?? "0") ?? 0))
            paragraph.indent = max(paragraph.indent, CGFloat(level) * 18)
            paragraph.runs.append(OfficeRun(text: listMarker(id: id, level: level) + " ", style: base))
        }
        var output: [OfficeBlock] = []
        func flush() {
            if !paragraph.runs.isEmpty { output.append(.paragraph(paragraph)); paragraph.runs = []; paragraph.breakBefore = false; paragraph.before = 0 }
        }
        func visit(_ node: OfficeXMLNode, style: OfficeTextStyle) throws {
            switch node.name {
            case "w:pPr", "w:rPr", "w:bookmarkStart", "w:bookmarkEnd", "w:proofErr", "w:lastRenderedPageBreak": return
            case "w:t": paragraph.runs.append(OfficeRun(text: node.text, style: style)); return
            case "w:tab": paragraph.runs.append(OfficeRun(text: "\t", style: style)); return
            case "w:br", "w:cr":
                if node.attributes["w:type"] == "page" { flush(); output.append(.pageBreak) }
                else { paragraph.runs.append(OfficeRun(text: "\u{2028}", style: style)) }
                return
            case "w:noBreakHyphen": paragraph.runs.append(OfficeRun(text: "‑", style: style)); return
            case "w:softHyphen": paragraph.runs.append(OfficeRun(text: "\u{00AD}", style: style)); return
            case "w:del", "w:moveFrom", "w:delText":
                document.warnings.insert("Tracked changes show the current text without revision markup."); return
            case "w:ins", "w:moveTo": document.warnings.insert("Tracked changes show the current text without revision markup.")
            case "mc:AlternateContent":
                if let alternative = node.alternative { for child in alternative.children { try visit(child, style: style) } }
                else { document.warnings.insert("An alternate document object has no supported representation and was omitted.") }
                return
            case "w:drawing", "w:pict":
                flush()
                if let box = node.descendants("w:txbxContent").first {
                    document.warnings.insert("Text boxes are placed in reading order; their shape and positioning may differ.")
                    output += try blocks(box)
                } else if let image = try drawing(node) { output.append(.image(image)) }
                return
            case "w:instrText", "w:fldChar": document.warnings.insert("Fields use their saved text and are not recalculated."); return
            case "w:footnoteReference", "w:endnoteReference":
                guard let id = node.attributes["w:id"] else { return }
                let kind = node.name == "w:footnoteReference" ? "footnote" : "endnote"
                if !readingNotes, !noteReferences.contains(where: { $0.kind == kind && $0.id == id }) { noteReferences.append((kind, id)) }
                var referenceStyle = style; referenceStyle.scriptPosition = 1
                paragraph.runs.append(OfficeRun(text: "[\(kind == "footnote" ? "F" : "E")\(id)]", style: referenceStyle))
                return
            case "w:footnoteRef", "w:endnoteRef": return
            case "w:commentReference": document.warnings.insert("Comments are not included."); return
            case "w:object", "w:sym": document.warnings.insert("Embedded objects and special symbol runs are omitted."); return
            case "w:r":
                var nextStyle = style
                for definition in styleChain(node.child("w:rPr")?.value("w:rStyle")) { applyRun(definition.child("w:rPr"), to: &nextStyle) }
                applyRun(node.child("w:rPr"), to: &nextStyle)
                for child in node.children { try visit(child, style: nextStyle) }
                return
            case "w:hyperlink":
                var linkedStyle = style
                if let id = node.attributes["r:id"], let relationship = relationships[id], relationship.external,
                   let link = OfficeNumbering.safeLink(relationship.target) { linkedStyle.link = link }
                else { document.warnings.insert("Internal or unsupported hyperlinks are retained as text.") }
                for child in node.children { try visit(child, style: linkedStyle) }
                return
            case "w:fldSimple": document.warnings.insert("Fields use their saved text and are not recalculated.")
            case "#text": return
            default:
                if !["w:sdt", "w:sdtContent", "w:smartTag"].contains(node.name) {
                    document.warnings.insert("Some unsupported inline formatting or objects may differ or be omitted.")
                }
            }
            for child in node.children { try visit(child, style: style) }
        }
        for child in node.children { try visit(child, style: base) }
        flush()
        if output.isEmpty { paragraph.runs = [OfficeRun(text: " ", style: base)]; output.append(.paragraph(paragraph)) }
        return output
    }

    private func listMarker(id: String, level: Int) -> String {
        guard let instance = numbering?.all("w:num").first(where: { $0.attributes["w:numId"] == id }),
              let abstractID = instance.value("w:abstractNumId"),
              let abstract = numbering?.all("w:abstractNum").first(where: { $0.attributes["w:abstractNumId"] == abstractID }) else {
            document.warnings.insert("Some list numbering is unavailable and is shown as bullets."); return "•"
        }
        func property(_ name: String, at index: Int) -> String? {
            let override = instance.all("w:lvlOverride").first { $0.attributes["w:ilvl"] == String(index) }
            let definition = abstract.all("w:lvl").first { $0.attributes["w:ilvl"] == String(index) }
            if name == "w:start", let start = override?.value("w:startOverride") { return start }
            return override?.child("w:lvl")?.value(name) ?? definition?.value(name)
        }
        let start = min(1_000_000, max(0, Int(property("w:start", at: level) ?? "1") ?? 1))
        var values = counters[id] ?? [:]
        values[level] = (values[level] ?? (start - 1)) + 1
        for deeper in values.keys.filter({ $0 > level }) {
            let restart = Int(property("w:lvlRestart", at: deeper) ?? String(deeper)) ?? deeper
            if restart > 0 && level < restart { values.removeValue(forKey: deeper) }
        }
        counters[id] = values
        let format = property("w:numFmt", at: level) ?? "decimal"
        if format == "bullet" { return "•" }
        if format == "none" { return "" }
        var label = property("w:lvlText", at: level) ?? "%\(level + 1)."
        for index in 0...8 {
            let numberFormat = property("w:numFmt", at: index) ?? "decimal"
            if label.contains("%\(index + 1)"), !OfficeNumbering.formats.contains(numberFormat) {
                document.warnings.insert("An unsupported list-number format is shown as decimal numbers.")
            }
            let value = values[index] ?? Int(property("w:start", at: index) ?? "1") ?? 1
            label = label.replacingOccurrences(of: "%\(index + 1)", with: OfficeNumbering.label(value, format: numberFormat))
        }
        return String(label.prefix(80))
    }

    private func appendNotes() throws {
        guard !noteReferences.isEmpty else { return }
        let owner = mainPart
        let ownerRelationships = relationships
        defer { mainPart = owner; relationships = ownerRelationships; readingNotes = false }
        var notes: [OfficeBlock] = []
        var parts: [String: (String, OfficeXMLNode)] = [:]
        for kind in ["footnote", "endnote"] {
            if let path = try relatedPart("/" + kind + "s") { parts[kind] = (path, try OfficeXML.parse(package.read(path))) }
        }
        readingNotes = true
        for reference in noteReferences {
            guard let (path, root) = parts[reference.kind],
                  let node = root.all("w:" + reference.kind).first(where: { $0.attributes["w:id"] == reference.id }) else {
                document.warnings.insert("A referenced note could not be found in the document package."); continue
            }
            mainPart = path; relationships = try readRelationships(for: path)
            let label = "[\(reference.kind == "footnote" ? "F" : "E")\(reference.id)]"
            var titleStyle = OfficeTextStyle(); titleStyle.bold = true
            notes.append(.paragraph(OfficeParagraph(runs: [OfficeRun(text: label, style: titleStyle)], keepWithNext: true)))
            notes += try blocks(node)
        }
        if !notes.isEmpty {
            document.warnings.insert("Footnotes and endnotes are collected in a Notes section at the end.")
            var titleStyle = OfficeTextStyle(); titleStyle.bold = true; titleStyle.size = 20
            document.blocks += [.pageBreak, .paragraph(OfficeParagraph(runs: [OfficeRun(text: "Notes", style: titleStyle)], keepWithNext: true))] + notes
        }
    }

    private func drawing(_ node: OfficeXMLNode) throws -> OfficeImage? {
        if !node.descendants("wp:anchor").isEmpty { document.warnings.insert("Floating images are placed in the text flow; wrapping and cropping may differ.") }
        guard let blip = node.descendants("a:blip").first, let id = blip.attributes["r:embed"],
              let relationship = relationships[id], !relationship.external else {
            document.warnings.insert("Linked images, vector drawings, charts, and unsupported artwork are omitted."); return nil
        }
        let path = try OfficePackage.resolve(relationship.target, relativeTo: mainPart)
        let data = try package.read(path)
        do { _ = try PDFConverter.image(data, maximumPixelSize: 16) }
        catch { document.warnings.insert("An image format could not be rendered and was omitted."); return nil }
        let extent = node.descendants("wp:extent").first
        return OfficeImage(data: data, width: CGFloat(Double(extent?.attributes["cx"] ?? "") ?? 0) / 12700,
                           height: CGFloat(Double(extent?.attributes["cy"] ?? "") ?? 0) / 12700)
    }

    private func table(_ node: OfficeXMLNode) throws -> OfficeBlock {
        var rows: [[OfficeCell]] = []
        for row in node.all("w:tr") {
            var cells: [OfficeCell] = []
            for cell in row.all("w:tc") {
                let span = Int(cell.child("w:tcPr")?.value("w:gridSpan") ?? "1") ?? 1
                guard (1...20).contains(span) else { throw OfficeConversionError.tooLarge }
                if cell.child("w:tcPr")?.child("w:vMerge") != nil {
                    document.warnings.insert("Vertically merged table cells are shown with separate row borders.")
                }
                cells.append(OfficeCell(blocks: try blocks(cell), columnSpan: span))
            }
            guard cells.reduce(0, { $0 + $1.columnSpan }) <= 20, rows.count < 2000 else { throw OfficeConversionError.tooLarge }
            if !cells.isEmpty { rows.append(cells) }
        }
        let widths = node.child("w:tblGrid")?.all("w:gridCol").compactMap { item -> CGFloat? in
            guard let value = Double(item.attributes["w:w"] ?? ""), value.isFinite, value > 0 else { return nil }
            return value / 20
        } ?? []
        return .table(OfficeTable(rows: rows, columnWidths: widths))
    }
}
