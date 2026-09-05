import CoreGraphics
import CoreText
import Foundation
import UIKit

nonisolated final class OfficePDFRenderer {
    private let document: OfficeDocument
    private let context: CGContext
    private let output: NSMutableData
    private var cursor: CGFloat = 0
    private var pageCount = 0
    private var pendingBreak = false
    private var warnings: Set<String>
    private var fontCache: [String: CTFont] = [:]
    private var contentWidth: CGFloat { document.pageSize.width - document.margins.left - document.margins.right }
    private var contentHeight: CGFloat { document.pageSize.height - document.margins.top - document.margins.bottom }
    private var top: CGFloat { document.pageSize.height - document.margins.top }

    static func render(_ document: OfficeDocument) throws -> OfficePreview {
        let renderer = try OfficePDFRenderer(document)
        var closed = false
        defer { if !closed { renderer.context.closePDF() } }
        for block in document.blocks {
            try Task.checkCancellation()
            if case .pageBreak = block { renderer.pendingBreak = true; continue }
            if renderer.pageCount == 0 || renderer.pendingBreak {
                try renderer.newPage(); renderer.pendingBreak = false
            }
            switch block {
            case .paragraph(let paragraph): try renderer.paragraph(paragraph)
            case .image(let image): try renderer.image(image)
            case .table(let rows): try renderer.table(rows)
            case .pageBreak: break
            }
            guard renderer.output.length < 50 * 1024 * 1024 else { throw OfficeConversionError.tooLarge }
        }
        guard renderer.pageCount > 0 else { throw OfficeConversionError.emptyDocument }
        renderer.context.endPDFPage()
        renderer.context.closePDF()
        closed = true
        return OfficePreview(data: renderer.output as Data, warnings: renderer.warnings.sorted(), pageCount: renderer.pageCount)
    }

    private init(_ document: OfficeDocument) throws {
        self.document = document
        warnings = document.warnings
        output = NSMutableData()
        var bounds = CGRect(origin: .zero, size: document.pageSize)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width >= 288, bounds.height >= 288,
              document.margins.isValid(for: document.pageSize),
              let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw OfficeConversionError.cannotLayout }
        self.context = context
    }
    private func newPage() throws {
        guard pageCount < 500 else { throw OfficeConversionError.cannotLayout }
        if pageCount > 0 { context.endPDFPage() }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: document.pageSize))
        context.textMatrix = .identity
        cursor = top
        pageCount += 1
    }
    private func attributed(_ paragraph: OfficeParagraph, inTable: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let paragraphStyle = NSMutableParagraphStyle()
        switch paragraph.alignment {
        case "center": paragraphStyle.alignment = .center
        case "right", "end": paragraphStyle.alignment = .right
        case "justify": paragraphStyle.alignment = .justified
        default: paragraphStyle.alignment = .left
        }
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.paragraphSpacing = inTable ? min(paragraph.after, 12) : 0
        for run in paragraph.runs {
            let style = run.style
            let size = style.size * (style.scriptPosition == 0 ? 1 : 0.7)
            let key = "\(style.font)|\(size)|\(style.bold)|\(style.italic)"
            let font: CTFont
            if let cached = fontCache[key] { font = cached }
            else {
                var base = CTFontCreateWithName(style.font as CFString, size, nil)
                let actual = (CTFontCopyFamilyName(base) as String).lowercased().replacingOccurrences(of: " ", with: "")
                let requested = style.font.lowercased().replacingOccurrences(of: " ", with: "")
                if !requested.contains(actual), !actual.contains(requested) {
                    warnings.insert("Unavailable fonts were replaced with fonts installed on this device.")
                }
                var traits: CTFontSymbolicTraits = []
                if style.bold { traits.insert(.boldTrait) }
                if style.italic { traits.insert(.italicTrait) }
                if let copy = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, [.boldTrait, .italicTrait]) { base = copy }
                font = base
                fontCache[key] = font
            }
            let rgb = UInt32(style.color, radix: 16) ?? 0
            let color = CGColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle,
                .underlineStyle: style.underline ? NSUnderlineStyle.single.rawValue : 0,
                .baselineOffset: style.scriptPosition == 0 ? 0 : style.size * (style.scriptPosition > 0 ? 0.35 : -0.2),
                .strikethroughStyle: style.strikethrough ? 1 : 0
            ]
            if let link = OfficeNumbering.safeLink(style.link) { attributes[.link] = link }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        if result.length == 0 { result.append(NSAttributedString(string: " ")) }
        return result
    }
    private func height(_ framesetter: CTFramesetter, from location: Int, width: CGFloat) -> CGFloat {
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: location, length: 0), nil,
                                                               CGSize(width: width, height: 1_000_000), nil)
        return ceil(size.height) + 3
    }
    private func frame(_ setter: CTFramesetter, from location: Int, rect: CGRect) -> CTFrame {
        CTFramesetterCreateFrame(setter, CFRange(location: location, length: 0), CGPath(rect: rect, transform: nil), nil)
    }
    private func drawTextFrame(_ frame: CTFrame) {
        CTFrameDraw(frame, context)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let origin = CTFrameGetPath(frame).boundingBox.origin
        for (index, line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let range = CTRunGetStringRange(run)
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &ascent, &descent, nil))
                let start = CTLineGetOffsetForStringIndex(line, range.location, nil)
                let end = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
                let baseline = origin.y + origins[index].y
                let x = origin.x + origins[index].x + min(start, end)
                if let link = attributes[NSAttributedString.Key.link.rawValue] as? String,
                   let safe = OfficeNumbering.safeLink(link), let url = URL(string: safe) {
                    context.setURL(url as CFURL, for: CGRect(x: x, y: baseline - descent, width: max(width, abs(end - start)), height: ascent + descent))
                }
                if (attributes[NSAttributedString.Key.strikethroughStyle.rawValue] as? NSNumber)?.intValue == 1 {
                    context.saveGState()
                    context.setStrokeColor((attributes[NSAttributedString.Key.foregroundColor.rawValue] as! CGColor?) ?? CGColor(gray: 0, alpha: 1))
                    context.setLineWidth(max(0.5, ascent / 14))
                    context.move(to: CGPoint(x: x, y: baseline + ascent * 0.32))
                    context.addLine(to: CGPoint(x: x + width, y: baseline + ascent * 0.32))
                    context.strokePath()
                    context.restoreGState()
                }
            }
        }
    }

    private func paragraph(_ paragraph: OfficeParagraph) throws {
        if paragraph.breakBefore && cursor < top { try newPage() }
        let text = attributed(paragraph)
        let setter = CTFramesetterCreateWithAttributedString(text)
        let indent = min(paragraph.indent, max(0, contentWidth - 80))
        let width = contentWidth - indent
        if paragraph.keepWithNext && cursor < top && height(setter, from: 0, width: width) + 30 > cursor - document.margins.bottom { try newPage() }
        cursor -= paragraph.before
        var location = 0
        while location < text.length {
            try Task.checkCancellation()
            if cursor - document.margins.bottom < 24 { try newPage() }
            let available = cursor - document.margins.bottom
            let usedHeight = min(available, height(setter, from: location, width: width))
            let textFrame = frame(setter, from: location, rect: CGRect(x: document.margins.left + indent, y: cursor - usedHeight, width: width, height: usedHeight))
            let visible = CTFrameGetVisibleStringRange(textFrame)
            if visible.length == 0 {
                if cursor < top { try newPage(); continue }
                throw OfficeConversionError.cannotLayout
            }
            drawTextFrame(textFrame)
            location += visible.length
            cursor -= usedHeight
            if location < text.length { try newPage() }
        }
        cursor -= paragraph.after
    }
    private func image(_ source: OfficeImage) throws {
        let bitmap = try PDFConverter.image(source.data)
        let natural = CGSize(width: CGFloat(bitmap.width), height: CGFloat(bitmap.height))
        let requestedWidth = source.width.isFinite && source.width > 0 ? source.width : min(natural.width, contentWidth)
        // Preserve aspect ratio even when original crop/transform isn't supported.
        var size = CGSize(width: requestedWidth, height: requestedWidth * natural.height / natural.width)
        let scale = min(1, min(contentWidth / size.width, (contentHeight - 12) / size.height))
        size.width *= scale; size.height *= scale
        if cursor - document.margins.bottom < size.height && cursor < top { try newPage() }
        context.interpolationQuality = .high
        context.draw(bitmap, in: CGRect(x: document.margins.left + (contentWidth - size.width) / 2, y: cursor - size.height, width: size.width, height: size.height))
        cursor -= size.height + 12
    }
    private enum CellSegment {
        case text(NSAttributedString, CTFramesetter)
        case image(OfficeImage, CGSize)
    }
    private struct CellPosition {
        var segment = 0
        var textOffset = 0
    }
    private func cellSegments(_ blocks: [OfficeBlock], width: CGFloat) throws -> [CellSegment] {
        var segments: [CellSegment] = []
        for block in blocks {
            switch block {
            case .paragraph(let paragraph):
                let text = attributed(paragraph, inTable: true)
                segments.append(.text(text, CTFramesetterCreateWithAttributedString(text)))
            case .image(let source):
                let thumb = try PDFConverter.image(source.data, maximumPixelSize: 300)
                let requested = source.width.isFinite && source.width > 0 ? source.width : width
                var size = CGSize(width: min(requested, width), height: min(requested, width) * CGFloat(thumb.height) / CGFloat(thumb.width))
                let scale = min(1, (contentHeight - 24) / size.height)
                size.width *= scale; size.height *= scale
                segments.append(.image(source, size))
            case .table(let rows):
                warnings.insert("Nested tables are arranged in reading order inside their parent cell.")
                for row in rows.rows { for cell in row { segments += try cellSegments(cell.blocks, width: width) } }
            case .pageBreak: warnings.insert("Page breaks inside table cells are ignored.")
            }
        }
        return segments
    }
    private func cellHeight(_ segments: [CellSegment], position: CellPosition, width: CGFloat) -> CGFloat {
        var result: CGFloat = 0
        for index in position.segment..<segments.count {
            switch segments[index] {
            case .text(_, let setter): result += height(setter, from: index == position.segment ? position.textOffset : 0, width: width) + 4
            case .image(_, let size): result += size.height + 8
            }
        }
        return result
    }
    private func drawCell(_ segments: [CellSegment], position: inout CellPosition, bounds: CGRect) throws -> Bool {
        var y = bounds.maxY
        var progressed = false
        while position.segment < segments.count {
            try Task.checkCancellation()
            let available = y - bounds.minY
            if available < 4 { break }
            switch segments[position.segment] {
            case .text(let text, let setter):
                let used = min(available, height(setter, from: position.textOffset, width: bounds.width))
                let textFrame = frame(setter, from: position.textOffset, rect: CGRect(x: bounds.minX, y: y - used, width: bounds.width, height: used))
                let visible = CTFrameGetVisibleStringRange(textFrame)
                guard visible.length > 0 else { return progressed }
                drawTextFrame(textFrame)
                position.textOffset += visible.length
                progressed = true
                y -= used + 4
                if position.textOffset == text.length { position.segment += 1; position.textOffset = 0 }
                else { return progressed }
            case .image(let source, let size):
                guard size.height <= available + 0.1 else { return progressed }
                let bitmap = try PDFConverter.image(source.data)
                context.draw(bitmap, in: CGRect(x: bounds.midX - size.width / 2, y: y - size.height, width: size.width, height: size.height))
                y -= size.height + 8
                position.segment += 1
                progressed = true
            }
        }
        return progressed
    }
    private func table(_ table: OfficeTable) throws {
        let rows = table.rows
        guard !rows.isEmpty else { return }
        warnings.insert("Table borders and row heights may differ from the original.")
        let columnCount = rows.map { $0.reduce(0) { $0 + $1.columnSpan } }.max() ?? 1
        guard (1...20).contains(columnCount) else { throw OfficeConversionError.cannotLayout }
        let sourceWidths = table.columnWidths
        let hasWidths = sourceWidths.count == columnCount && sourceWidths.allSatisfy { $0.isFinite && $0 > 0 }
        let weights = hasWidths ? sourceWidths : Array(repeating: CGFloat(1), count: columnCount)
        let maximum = weights.max() ?? 1
        let normalized = weights.map { $0 / maximum }
        let total = normalized.reduce(0, +)
        var grid = normalized.map { contentWidth * $0 / total }
        if grid.contains(where: { $0 <= 18 }) {
            warnings.insert("Very narrow table columns were widened to keep their content readable.")
            let minimum = min(24, contentWidth / CGFloat(columnCount))
            let remaining = max(0, contentWidth - minimum * CGFloat(columnCount))
            grid = normalized.map { minimum + remaining * $0 / total }
        }
        guard grid.allSatisfy({ $0 > 18 }) else { throw OfficeConversionError.cannotLayout }
        for row in rows {
            var column = 0
            let widths = row.map { cell -> CGFloat in
                defer { column += cell.columnSpan }
                return grid[column..<(column + cell.columnSpan)].reduce(0, +)
            }
            let segments = try row.enumerated().map { try cellSegments($0.element.blocks, width: widths[$0.offset] - 12) }
            var positions = Array(repeating: CellPosition(), count: row.count)
            var remaining = true
            while remaining {
                try Task.checkCancellation()
                if cursor - document.margins.bottom < 36 { try newPage() }
                let desired = max(24, row.indices.map { cellHeight(segments[$0], position: positions[$0], width: widths[$0] - 12) + 12 }.max() ?? 24)
                if desired <= contentHeight && desired > cursor - document.margins.bottom && cursor < top { try newPage() }
                let rowHeight = min(desired, cursor - document.margins.bottom)
                var madeProgress = false
                var x = document.margins.left
                for index in row.indices {
                    let bounds = CGRect(x: x, y: cursor - rowHeight, width: widths[index], height: rowHeight)
                    context.setStrokeColor(CGColor(gray: 0.65, alpha: 1)); context.setLineWidth(0.5); context.stroke(bounds)
                    if try drawCell(segments[index], position: &positions[index], bounds: bounds.insetBy(dx: 6, dy: 6)) { madeProgress = true }
                    x += widths[index]
                }
                cursor -= rowHeight
                remaining = row.indices.contains { positions[$0].segment < segments[$0].count }
                if remaining {
                    // A large image or line may need a full fresh page. If no cell
                    // progresses even there, stop instead of looping or clipping.
                    guard madeProgress || rowHeight < contentHeight else { throw OfficeConversionError.cannotLayout }
                    try newPage()
                }
            }
        }
        cursor -= 8
    }
}
