import Foundation
import zlib

nonisolated enum OfficeConversionError: LocalizedError {
    case invalidPackage, unsupportedPackage, tooLarge, invalidXML, missingPart, emptyDocument, cannotLayout, pagesNeedsExport
    var errorDescription: String? {
        switch self {
        case .pagesNeedsExport: "This Pages file has no usable saved PDF preview. In Pages, choose Export → PDF, then import that PDF into Folik."
        case .invalidPackage: "This document is damaged or isn’t a supported Office document."
        case .unsupportedPackage: "This document uses encryption or a package format Folik doesn’t support. Export an unprotected DOCX, ODT, or PDF from its original app."
        case .tooLarge: "This document exceeds Folik’s conversion limits. Choose a file up to 25 MB with less than 100 MB of unpacked content."
        case .invalidXML: "The document contains invalid or unsupported XML. Try saving a new copy in its original app."
        case .missingPart: "A required part of this document is missing. Try saving a new copy in its original app."
        case .emptyDocument: "No supported document content was found. Export this document to PDF from its original app."
        case .cannotLayout: "Some content can’t fit within Folik’s page or complexity limits. Export this document to PDF from its original app."
        }
    }
}

/// A bounded, in-memory reader for the stored/deflate ZIP packages used by Office.
/// Never extracts paths onto the filesystem. ZIP64, split archives and encryption
/// are deliberately rejected. Central-directory sizes also bound decompression.
nonisolated struct OfficePackage {
    static let maximumFileBytes = 25 * 1024 * 1024
    private struct Entry {
        let method: Int
        let flags: Int
        let crc: UInt32
        let compressed: Int
        let expanded: Int
        let offset: Int
    }
    private let data: Data
    private let entries: [String: Entry]
    var names: [String] { Array(entries.keys) }

    init(data: Data) throws {
        guard data.count <= Self.maximumFileBytes else { throw OfficeConversionError.tooLarge }
        if data.starts(with: [0xd0, 0xcf, 0x11, 0xe0]) { throw OfficeConversionError.unsupportedPackage }
        guard data.count >= 22 else { throw OfficeConversionError.invalidPackage }
        var end: Int?
        for index in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try data.zip32(index) == 0x06054b50,
               index + 22 + Int(try data.zip16(index + 20)) == data.count { end = index; break }
        }
        guard let end else { throw OfficeConversionError.invalidPackage }
        guard try data.zip16(end + 4) == 0, try data.zip16(end + 6) == 0,
              try data.zip16(end + 8) == data.zip16(end + 10) else { throw OfficeConversionError.unsupportedPackage }
        let count = Int(try data.zip16(end + 10))
        let size = Int(try data.zip32(end + 12))
        let start = Int(try data.zip32(end + 16))
        guard count > 0, count <= 4096, start + size == end else { throw OfficeConversionError.unsupportedPackage }
        var cursor = start
        var total = 0
        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            try Task.checkCancellation()
            guard try data.zip32(cursor) == 0x02014b50 else { throw OfficeConversionError.invalidPackage }
            let flags = Int(try data.zip16(cursor + 8))
            let method = Int(try data.zip16(cursor + 10))
            let compressed = Int(try data.zip32(cursor + 20))
            let expanded = Int(try data.zip32(cursor + 24))
            let nameLength = Int(try data.zip16(cursor + 28))
            let extraLength = Int(try data.zip16(cursor + 30))
            let commentLength = Int(try data.zip16(cursor + 32))
            let offset = Int(try data.zip32(cursor + 42))
            guard flags & 0x2041 == 0, [0, 8].contains(method),
                  try data.zip16(cursor + 34) == 0 else { throw OfficeConversionError.unsupportedPackage }
            total += expanded
            guard expanded <= 20 * 1024 * 1024, total <= 100 * 1024 * 1024 else { throw OfficeConversionError.tooLarge }
            let rawName = try data.zipSlice(cursor + 46, nameLength)
            guard let name = String(data: rawName, encoding: .utf8),
                  Self.validPath(name), entries[name] == nil else { throw OfficeConversionError.invalidPackage }
            guard offset < start, try data.zip32(offset) == 0x04034b50,
                  Int(try data.zip16(offset + 6)) == flags,
                  Int(try data.zip16(offset + 8)) == method else { throw OfficeConversionError.invalidPackage }
            let localNameLength = Int(try data.zip16(offset + 26))
            let localExtraLength = Int(try data.zip16(offset + 28))
            guard try data.zipSlice(offset + 30, localNameLength) == rawName else { throw OfficeConversionError.invalidPackage }
            let payload = offset + 30 + localNameLength + localExtraLength
            guard payload + compressed <= start else { throw OfficeConversionError.invalidPackage }
            entries[name] = Entry(method: method, flags: flags, crc: try data.zip32(cursor + 16),
                                  compressed: compressed, expanded: expanded, offset: payload)
            cursor += 46 + nameLength + extraLength + commentLength
            guard cursor <= end else { throw OfficeConversionError.invalidPackage }
        }
        guard cursor == end else { throw OfficeConversionError.invalidPackage }
        self.data = data
        self.entries = entries
    }

    func read(_ name: String) throws -> Data {
        guard let entry = entries[name] else { throw OfficeConversionError.missingPart }
        try Task.checkCancellation()
        let compressed = try data.zipSlice(entry.offset, entry.compressed)
        let result: Data
        if entry.method == 0 {
            guard entry.compressed == entry.expanded else { throw OfficeConversionError.invalidPackage }
            result = compressed
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw OfficeConversionError.invalidPackage
            }
            defer { inflateEnd(&stream) }
            // One spare byte detects output larger than the declared expanded size.
            var output = Data(count: entry.expanded + 1)
            let status = compressed.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { buffer in
                    stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(compressed.count)
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(entry.expanded + 1)
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END, stream.total_out == entry.expanded,
                  stream.total_in == entry.compressed else { throw OfficeConversionError.invalidPackage }
            output.removeLast()
            result = output
        }
        let checksum = result.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(result.count)) }
        guard UInt32(checksum) == entry.crc else { throw OfficeConversionError.invalidPackage }
        return result
    }

    static func resolve(_ target: String, relativeTo part: String) throws -> String {
        guard let decoded = target.removingPercentEncoding,
              !decoded.contains(":"), !decoded.contains("\\"), !decoded.contains("?"), !decoded.contains("#") else {
            throw OfficeConversionError.invalidPackage
        }
        var components = decoded.hasPrefix("/") ? [] : part.split(separator: "/").dropLast().map(String.init)
        for component in decoded.split(separator: "/").map(String.init) {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { throw OfficeConversionError.invalidPackage }
                components.removeLast()
            } else { components.append(component) }
        }
        let path = components.joined(separator: "/")
        guard validPath(path) else { throw OfficeConversionError.invalidPackage }
        return path
    }

    private static func validPath(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.contains("\\") && !name.contains(":") &&
        name.rangeOfCharacter(from: .controlCharacters) == nil &&
        !name.split(separator: "/").contains(where: { $0 == ".." || $0 == "." })
    }
}

nonisolated private extension Data {
    func zip16(_ index: Int) throws -> UInt16 {
        guard index >= 0, index + 2 <= count else { throw OfficeConversionError.invalidPackage }
        return UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }
    func zip32(_ index: Int) throws -> UInt32 {
        UInt32(try zip16(index)) | UInt32(try zip16(index + 2)) << 16
    }
    func zipSlice(_ index: Int, _ length: Int) throws -> Data {
        guard index >= 0, length >= 0, index + length <= count else { throw OfficeConversionError.invalidPackage }
        return subdata(in: index..<(index + length))
    }
}
