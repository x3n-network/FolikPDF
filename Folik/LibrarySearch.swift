import Foundation
import PDFKit

nonisolated struct LibrarySearchRequest: Hashable {
    let query: String
    let documents: [LibraryDocument]
}
nonisolated struct LibrarySearchHit: Sendable {
    let page: Int
    let excerpt: String
}
nonisolated struct LibrarySearchResult: Sendable {
    var hits: [URL: LibrarySearchHit] = [:]
    var skipped = 0
}
nonisolated enum LibrarySearch {
    static func search(_ query: String, documents: [LibraryDocument]) throws -> LibrarySearchResult {
        var result = LibrarySearchResult()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        for item in documents {
            try Task.checkCancellation()
            guard item.fileSize <= PDFProcessing.maximumBytes,
                  let pdf = PDFDocument(url: item.url), !pdf.isLocked, pdf.pageCount <= 500 else { result.skipped += 1; continue }
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                guard let text = pdf.page(at: index)?.string,
                      let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
                let start = text.index(range.lowerBound, offsetBy: -35, limitedBy: text.startIndex) ?? text.startIndex
                let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
                let excerpt = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
                result.hits[item.url] = LibrarySearchHit(page: index + 1, excerpt: excerpt)
                break
            }
        }
        return result
    }
}
