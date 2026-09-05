import Foundation

/// MS-DOC 97–2003 main-story text recovery, deliberately separate from the
/// styled DOCX reader. The preview always discloses the loss of rich layout.
nonisolated enum LegacyDOCReader {
    static func read(_ data: Data) throws -> OfficeDocument {
        let container = try CompoundDocument(data)
        let word = try container.read("WordDocument")
        guard try word.office16(0) == 0xa5ec,
              [0x00c1,0x00d9,0x0101,0x010c,0x0112].contains(Int(try word.office16(2))) else { throw OfficeConversionError.unsupportedPackage }
        let flags = try word.office16(10)
        guard flags & 0x8100 == 0 else { throw OfficeConversionError.unsupportedPackage }
        let table = try container.read(flags & 0x0200 == 0 ? "0Table" : "1Table")
        let csw = Int(try word.office16(32))
        let longCountOffset = 34 + csw * 2
        let longCount = Int(try word.office16(longCountOffset))
        guard longCount >= 11 else { throw OfficeConversionError.invalidPackage }
        let characterCount = Int(try word.office32(longCountOffset + 2 + 3 * 4))
        guard characterCount <= 2_000_000 else { throw OfficeConversionError.tooLarge }
        let pairsOffset = longCountOffset + 2 + longCount * 4
        guard try word.office16(pairsOffset) > 33 else { throw OfficeConversionError.invalidPackage }
        let clxOffset = Int(try word.office32(pairsOffset + 2 + 33 * 8))
        let clxLength = Int(try word.office32(pairsOffset + 2 + 33 * 8 + 4))
        let clx = try table.officeSlice(clxOffset, clxLength)
        var offset = 0
        while offset < clx.count && clx[offset] == 1 {
            offset += 3 + Int(try clx.office16(offset + 1))
        }
        guard offset < clx.count, clx[offset] == 2 else { throw OfficeConversionError.invalidPackage }
        let size = Int(try clx.office32(offset + 1))
        guard size >= 4, (size - 4) % 12 == 0 else { throw OfficeConversionError.invalidPackage }
        let plc = try clx.officeSlice(offset + 5, size)
        let count = (size - 4) / 12
        guard count <= 100_000, try plc.office32(0) == 0,
              Int(try plc.office32(count * 4)) >= characterCount else { throw OfficeConversionError.invalidPackage }
        var units: [UInt16] = []
        for index in 0..<count {
            try Task.checkCancellation()
            let start = Int(try plc.office32(index * 4))
            let end = Int(try plc.office32((index + 1) * 4))
            guard end >= start else { throw OfficeConversionError.invalidPackage }
            if start >= characterCount { continue }
            let length = min(end, characterCount) - start
            let fc = try plc.office32((count + 1) * 4 + index * 8 + 2)
            guard fc & 0x80000000 == 0 else { throw OfficeConversionError.invalidPackage }
            let compressed = fc & 0x40000000 != 0
            let location = Int(fc & 0x3fffffff) / (compressed ? 2 : 1)
            let bytes = try word.officeSlice(location, length * (compressed ? 1 : 2))
            if compressed {
                // MS-DOC FcCompressed uses this mapping, not the document locale.
                let special: [UInt8: UInt16] = [0x80:0x20ac,0x82:0x201a,0x83:0x0192,0x84:0x201e,0x85:0x2026,0x86:0x2020,0x87:0x2021,0x88:0x02c6,0x89:0x2030,0x8a:0x0160,0x8b:0x2039,0x8c:0x0152,0x8e:0x017d,0x91:0x2018,0x92:0x2019,0x93:0x201c,0x94:0x201d,0x95:0x2022,0x96:0x2013,0x97:0x2014,0x98:0x02dc,0x99:0x2122,0x9a:0x0161,0x9b:0x203a,0x9c:0x0153,0x9e:0x017e,0x9f:0x0178]
                units += bytes.map { special[$0] ?? UInt16($0) }
            } else {
                for position in stride(from: 0, to: bytes.count, by: 2) { units.append(try bytes.office16(position)) }
            }
        }
        guard units.count == characterCount else { throw OfficeConversionError.invalidPackage }
        // Keep saved field results, never field instructions; preserve cell and
        // paragraph boundaries as text. Revisions cannot be resolved in this mode.
        var fields: [Bool] = []
        var text: [UInt16] = []
        for unit in units {
            switch unit {
            case 0x13: fields.append(false)
            case 0x14: if !fields.isEmpty { fields[fields.count - 1] = true }
            case 0x15: if !fields.isEmpty { fields.removeLast() }
            default:
                guard !fields.contains(false) else { continue }
                if unit == 7 || unit == 13 { text.append(10) }
                else if unit == 11 { text.append(0x2028) }
                else if unit == 9 || unit == 12 || unit >= 32 { text.append(unit) }
            }
            guard fields.count <= 80 else { throw OfficeConversionError.tooLarge }
        }
        guard fields.isEmpty else { throw OfficeConversionError.invalidPackage }
        var model = OfficeDocument()
        model.warnings.insert("Legacy Word text recovery: formatting, images, table layout, headers, footers, notes, comments and text boxes are not included. Tracked deletions may appear. Export DOCX or PDF from Word for greater fidelity.")
        let decoded = String(decoding: text, as: UTF16.self)
        guard !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OfficeConversionError.emptyDocument }
        for (index, page) in decoded.components(separatedBy: "\u{000c}").enumerated() {
            if index > 0 { model.blocks.append(.pageBreak) }
            for line in page.components(separatedBy: "\n") {
                model.blocks.append(.paragraph(OfficeParagraph(runs: [OfficeRun(text: line.isEmpty ? " " : line)])))
            }
        }
        guard model.blocks.count <= 20_000 else { throw OfficeConversionError.tooLarge }
        return model
    }
}
