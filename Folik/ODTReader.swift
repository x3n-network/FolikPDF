import Foundation
import CoreGraphics

nonisolated final class ODTReader {
    private let package: OfficePackage
    private var document = OfficeDocument()
    private var styles: [String: OfficeXMLNode] = [:]
    private var defaults: [String: OfficeXMLNode] = [:]
    private var listStyles: [String: OfficeXMLNode] = [:]
    private var fontFaces: [String: String] = [:]
    private var recentCounters: [String: Int] = [:]
    private var namedCounters: [String: Int] = [:]
    private var notes: [OfficeBlock] = []
    private var readingNote = false
    init(package: OfficePackage) { self.package = package }

    func read() throws -> OfficeDocument {
        guard String(data: try package.read("mimetype"), encoding: .utf8) == "application/vnd.oasis.opendocument.text" else {
            throw OfficeConversionError.invalidPackage
        }
        if package.names.contains("META-INF/manifest.xml") {
            let manifest = try OfficeXML.parse(package.read("META-INF/manifest.xml"))
            guard manifest.descendants("manifest:encryption-data").isEmpty else { throw OfficeConversionError.unsupportedPackage }
        }
        let content = try OfficeXML.parse(package.read("content.xml"))
        guard content.name == "office:document-content", let body = content.child("office:body")?.child("office:text") else {
            throw OfficeConversionError.invalidPackage
        }
        var styleRoots: [OfficeXMLNode] = []
        if package.names.contains("styles.xml") { styleRoots.append(try OfficeXML.parse(package.read("styles.xml"))) }
        styleRoots.append(content)
        for root in styleRoots {
            for style in root.descendants("style:style") {
                if let name = style.attributes["style:name"], let family = style.attributes["style:family"] { styles[family + ":" + name] = style }
            }
            for style in root.descendants("style:default-style") {
                if let family = style.attributes["style:family"] { defaults[family] = style }
            }
            for style in root.descendants("text:list-style") {
                if let name = style.attributes["style:name"] { listStyles[name] = style }
            }
            if !root.descendants("style:header").isEmpty || !root.descendants("style:footer").isEmpty {
                document.warnings.insert("Headers and footers are not included.")
            }
            for face in root.descendants("style:font-face") {
                if let name = face.attributes["style:name"], let font = face.attributes["svg:font-family"] { fontFaces[name] = font }
            }
        }
        let masters = styleRoots.flatMap { $0.descendants("style:master-page") }
        let initialParagraph = body.descendants("text:p").first ?? body.descendants("text:h").first
        let masterName = chain(initialParagraph?.attributes["text:style-name"], family: "paragraph").compactMap { $0.attributes["style:master-page-name"] }.last
        let master = masters.first { $0.attributes["style:name"] == masterName } ?? masters.first
        let layouts = styleRoots.flatMap { $0.descendants("style:page-layout") }
        let layout = (layouts.first { $0.attributes["style:name"] == master?.attributes["style:page-layout-name"] } ?? layouts.first)?.child("style:page-layout-properties")
        if let layout {
            let a = layout.attributes
            if let width = Self.length(a["fo:page-width"]), let height = Self.length(a["fo:page-height"]),
               (288...1440).contains(width), (288...1440).contains(height) { document.pageSize = CGSize(width: width, height: height) }
            let common = Self.length(a["fo:margin"]) ?? 48
            let margins = OfficeMargins(top: Self.length(a["fo:margin-top"]) ?? common,
                                        bottom: Self.length(a["fo:margin-bottom"]) ?? common,
                                        left: Self.length(a["fo:margin-left"]) ?? common,
                                        right: Self.length(a["fo:margin-right"]) ?? common)
            if margins.isValid(for: document.pageSize) { document.margins = margins }
            else { document.warnings.insert("Invalid page margins were replaced with default margins.") }
        }
        if masters.count > 1 { document.warnings.insert("Multiple page styles use the initial page layout throughout.") }
        document.blocks = try blocks(body)
        if !notes.isEmpty {
            document.blocks += [.pageBreak] + notes
            document.warnings.insert("Footnotes and endnotes are collected at the end of the PDF.")
        }
        return document
    }

    static func length(_ string: String?) -> CGFloat? {
        guard let string else { return nil }
        for (suffix, scale) in [("cm", 72.0 / 2.54), ("mm", 72.0 / 25.4), ("in", 72.0), ("pt", 1.0), ("pc", 12.0)] {
            if string.hasSuffix(suffix), let value = Double(string.dropLast(suffix.count)), value.isFinite {
                return CGFloat(value * scale)
            }
        }
        return nil
    }
    private func chain(_ name: String?, family: String) -> [OfficeXMLNode] {
        var result: [OfficeXMLNode] = []
        var next = name
        var seen: Set<String> = []
        while let name = next, let style = styles[family + ":" + name], seen.insert(name).inserted, result.count < 16 {
            result.insert(style, at: 0)
            next = style.attributes["style:parent-style-name"]
        }
        if let base = defaults[family] { result.insert(base, at: 0) }
        return result
    }
    private func apply(_ node: OfficeXMLNode, style: inout OfficeTextStyle, paragraph: inout OfficeParagraph) {
        if let properties = node.child("style:text-properties") {
            let a = properties.attributes
            if let size = Self.length(a["fo:font-size"]) { style.size = min(96, max(6, size)) }
            if let weight = a["fo:font-weight"] { style.bold = weight == "bold" || (Int(weight) ?? 0) >= 600 }
            if let slant = a["fo:font-style"] { style.italic = slant == "italic" || slant == "oblique" }
            if let underline = a["style:text-underline-style"] { style.underline = underline != "none" }
            if let strike = a["style:text-line-through-style"] { style.strikethrough = strike != "none" }
            if let position = a["style:text-position"]?.split(separator: " ").first {
                style.scriptPosition = position == "super" ? 1 : position == "sub" ? -1 : ((Double(position.replacingOccurrences(of: "%", with: "")) ?? 0) > 0 ? 1 : (Double(position.replacingOccurrences(of: "%", with: "")) ?? 0) < 0 ? -1 : 0)
            }
            if let color = a["fo:color"], color.hasPrefix("#"), color.count == 7 { style.color = String(color.dropFirst()) }
            if let font = a["fo:font-family"] ?? a["style:font-name"], font.count < 100 { style.font = (fontFaces[font] ?? font).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
        }
        if let properties = node.child("style:paragraph-properties") {
            let a = properties.attributes
            if let align = a["fo:text-align"] { paragraph.alignment = align == "end" ? "right" : align }
            if let value = Self.length(a["fo:margin-left"]) { paragraph.indent = min(144, max(0, value)) }
            if let value = Self.length(a["fo:margin-top"]) { paragraph.before = min(72, max(0, value)) }
            if let value = Self.length(a["fo:margin-bottom"]) { paragraph.after = min(72, max(0, value)) }
            if a["fo:break-before"] == "page" { paragraph.breakBefore = true }
            if a["fo:keep-with-next"] == "always" { paragraph.keepWithNext = true }
        }
    }

    private func blocks(_ container: OfficeXMLNode, listLevel: Int = 0, inheritedListStyle: String? = nil) throws -> [OfficeBlock] {
        var output: [OfficeBlock] = []
        for node in container.children where node.name != "#text" {
            try Task.checkCancellation()
            switch node.name {
            case "text:p", "text:h": output += try paragraph(node)
            case "text:list": output += try list(node, level: listLevel, inheritedStyle: inheritedListStyle)
            case "table:table": output.append(try table(node))
            case "text:section":
                document.warnings.insert("Sections and columns are converted into a single text flow.")
                output += try blocks(node, listLevel: listLevel, inheritedListStyle: inheritedListStyle)
            case "text:tracked-changes": document.warnings.insert("Tracked-change history is not included.")
            case "text:sequence-decls", "text:variable-decls", "text:user-field-decls", "text:forms": break
            case "draw:frame": output += try frameBlocks(node)
            case "text:table-of-content", "text:illustration-index":
                document.warnings.insert("Indexes and tables of contents use their saved text and are not recalculated.")
                if let body = node.child("text:index-body") { output += try blocks(body) }
            default: document.warnings.insert("Some unsupported document objects are omitted. Compare the preview with the original.")
            }
            guard output.count <= 20_000 else { throw OfficeConversionError.tooLarge }
        }
        return output
    }
    private func paragraph(_ node: OfficeXMLNode) throws -> [OfficeBlock] {
        var paragraph = OfficeParagraph()
        var base = OfficeTextStyle()
        if node.name == "text:h" { base.bold = true; base.size = 20; paragraph.keepWithNext = true }
        for style in chain(node.attributes["text:style-name"], family: "paragraph") { apply(style, style: &base, paragraph: &paragraph) }
        var output: [OfficeBlock] = []
        func flush() {
            if !paragraph.runs.isEmpty { output.append(.paragraph(paragraph)); paragraph.runs = []; paragraph.before = 0; paragraph.breakBefore = false }
        }
        func visit(_ node: OfficeXMLNode, style: OfficeTextStyle) throws {
            switch node.name {
            case "#text": paragraph.runs.append(OfficeRun(text: node.content, style: style)); return
            case "text:s":
                let count = Int(node.attributes["text:c"] ?? "1") ?? 1
                guard (1...10000).contains(count) else { throw OfficeConversionError.tooLarge }
                paragraph.runs.append(OfficeRun(text: String(repeating: " ", count: count), style: style)); return
            case "text:tab": paragraph.runs.append(OfficeRun(text: "\t", style: style)); return
            case "text:line-break": paragraph.runs.append(OfficeRun(text: "\u{2028}", style: style)); return
            case "text:soft-page-break", "text:bookmark", "text:bookmark-start", "text:bookmark-end": return
            case "draw:frame": flush(); output += try frameBlocks(node); return
            case "text:note":
                let label = node.child("text:note-citation")?.text ?? String(notes.count + 1)
                var referenceStyle = style; referenceStyle.scriptPosition = 1
                paragraph.runs.append(OfficeRun(text: "[" + label + "]", style: referenceStyle))
                if !readingNote, let body = node.child("text:note-body") {
                    readingNote = true
                    defer { readingNote = false }
                    var title = OfficeParagraph(); title.runs = [OfficeRun(text: "[" + label + "]", style: style)]
                    notes += [.paragraph(title)] + (try blocks(body))
                }
                return
            case "office:annotation": document.warnings.insert("Comments are not included."); return
            case "text:change", "text:change-start", "text:change-end": document.warnings.insert("Tracked-change history is not included."); return
            case "text:span":
                var next = style
                var ignoredParagraph = OfficeParagraph()
                for definition in chain(node.attributes["text:style-name"], family: "text") { apply(definition, style: &next, paragraph: &ignoredParagraph) }
                for child in node.children { try visit(child, style: next) }
                return
            case "text:a":
                var linked = style; linked.link = OfficeNumbering.safeLink(node.attributes["xlink:href"])
                if linked.link == nil { document.warnings.insert("Internal or unsupported links are preserved as text.") }
                for child in node.children { try visit(child, style: linked) }
                return
            default: document.warnings.insert("Some inline objects or fields use saved text and may differ from the original.")
            }
            for child in node.children { try visit(child, style: style) }
        }
        for child in node.children { try visit(child, style: base) }
        flush()
        if output.isEmpty { paragraph.runs = [OfficeRun(text: " ", style: base)]; output.append(.paragraph(paragraph)) }
        return output
    }

    private func list(_ node: OfficeXMLNode, level: Int, inheritedStyle: String?) throws -> [OfficeBlock] {
        guard level < 9 else { throw OfficeConversionError.tooLarge }
        let styleName = node.attributes["text:style-name"] ?? inheritedStyle ?? ""
        let definition = listStyles[styleName]?.children.first { $0.attributes["text:level"] == String(level + 1) }
        let numbered = definition?.name == "text:list-level-style-number"
        let key = styleName + ":" + String(level)
        var number = min(1_000_000, max(1, Int(definition?.attributes["text:start-value"] ?? "1") ?? 1))
        if let id = node.attributes["text:continue-list"], let next = namedCounters[id] { number = next }
        else if node.attributes["text:continue-numbering"] == "true", let next = recentCounters[key] { number = next }
        if (Int(definition?.attributes["text:display-levels"] ?? "1") ?? 1) > 1 {
            document.warnings.insert("Multi-level ODT list labels show the current level only.")
        }
        var result: [OfficeBlock] = []
        for item in node.children where ["text:list-item", "text:list-header"].contains(item.name) {
            if let start = Int(item.attributes["text:start-value"] ?? "") { number = min(1_000_000, max(1, start)) }
            var marked = false
            for child in item.children where child.name != "#text" {
                if ["text:p", "text:h"].contains(child.name) {
                    var content = try paragraph(child)
                    if !marked, item.name == "text:list-item",
                       let index = content.firstIndex(where: { if case .paragraph = $0 { return true }; return false }),
                       case .paragraph(var paragraph) = content[index] {
                        let prefix = numbered ? (definition?.attributes["style:num-prefix"] ?? "") + OfficeNumbering.label(number, format: OfficeNumbering.odtFormat(definition?.attributes["style:num-format"])) + (definition?.attributes["style:num-suffix"] ?? ".") : (definition?.attributes["text:bullet-char"] ?? "•")
                        paragraph.runs.insert(OfficeRun(text: prefix + " ", style: paragraph.runs.first?.style ?? OfficeTextStyle()), at: 0)
                        paragraph.indent += CGFloat(level) * 18
                        content[index] = .paragraph(paragraph); marked = true
                    }
                    result += content
                } else if child.name == "text:list" {
                    result += try list(child, level: level + 1, inheritedStyle: styleName)
                } else if child.name == "table:table" { result.append(try table(child)) }
            }
            if item.name == "text:list-item" { number += 1 }
            guard result.count <= 20_000 else { throw OfficeConversionError.tooLarge }
        }
        recentCounters[key] = number
        if let id = node.attributes["xml:id"] { namedCounters[id] = number }
        return result
    }

    private func frameBlocks(_ node: OfficeXMLNode) throws -> [OfficeBlock] {
        if let box = node.child("draw:text-box") {
            document.warnings.insert("Text boxes are placed in the text flow; positioning may differ.")
            return try blocks(box)
        }
        return try image(node).map { [.image($0)] } ?? []
    }

    private func image(_ node: OfficeXMLNode) throws -> OfficeImage? {
        guard let image = node.child("draw:image"), let href = image.attributes["xlink:href"],
              !href.contains(":"), !href.hasPrefix("/") else {
            document.warnings.insert("Linked images, text boxes, charts, and unsupported artwork are omitted."); return nil
        }
        let path = try OfficePackage.resolve(href, relativeTo: "content.xml")
        let data = try package.read(path)
        do { _ = try PDFConverter.image(data, maximumPixelSize: 16) }
        catch { document.warnings.insert("An image format could not be rendered and was omitted."); return nil }
        if node.attributes["text:anchor-type"] != "as-char" {
            document.warnings.insert("Floating images are placed in the text flow; wrapping and cropping may differ.")
        }
        return OfficeImage(data: data, width: Self.length(node.attributes["svg:width"]) ?? 0, height: Self.length(node.attributes["svg:height"]) ?? 0)
    }
    private func table(_ node: OfficeXMLNode) throws -> OfficeBlock {
        var rows: [[OfficeCell]] = []
        func rowNodes(_ node: OfficeXMLNode) -> [OfficeXMLNode] {
            node.children.flatMap { child -> [OfficeXMLNode] in
                if child.name == "table:table-row" { return [child] }
                if ["table:table-header-rows", "table:table-rows", "table:table-row-group"].contains(child.name) { return rowNodes(child) }
                return []
            }
        }
        for row in rowNodes(node) {
            let repeats = Int(row.attributes["table:number-rows-repeated"] ?? "1") ?? 1
            guard (1...2000).contains(repeats), rows.count + repeats <= 2000 else { throw OfficeConversionError.tooLarge }
            var cells: [OfficeCell] = []
            for cell in row.children where cell.name == "table:table-cell" {
                let repeatCells = Int(cell.attributes["table:number-columns-repeated"] ?? "1") ?? 1
                let span = Int(cell.attributes["table:number-columns-spanned"] ?? "1") ?? 1
                guard (1...20).contains(span), (1...20).contains(repeatCells),
                      cells.reduce(0, { $0 + $1.columnSpan }) + repeatCells * span <= 20 else { throw OfficeConversionError.tooLarge }
                if cell.attributes["table:number-rows-spanned"] != nil {
                    document.warnings.insert("Vertically merged table cells are shown with separate row borders.")
                }
                cells += Array(repeating: OfficeCell(blocks: try blocks(cell), columnSpan: span), count: repeatCells)
            }
            if !cells.isEmpty { rows += Array(repeating: cells, count: repeats) }
        }
        var widths: [CGFloat] = []
        for column in node.children where column.name == "table:table-column" {
            let count = Int(column.attributes["table:number-columns-repeated"] ?? "1") ?? 1
            guard (1...20).contains(count), widths.count + count <= 20 else { throw OfficeConversionError.tooLarge }
            var width: CGFloat = 0
            for style in chain(column.attributes["table:style-name"], family: "table-column") {
                if let p = style.child("style:table-column-properties") {
                    if let absolute = Self.length(p.attributes["style:column-width"]) { width = absolute }
                    else if let relative = p.attributes["style:rel-column-width"], let value = Double(relative.replacingOccurrences(of: "*", with: "")) { width = CGFloat(value) }
                }
            }
            widths += Array(repeating: width, count: count)
        }
        return .table(OfficeTable(rows: rows, columnWidths: widths))
    }
}
