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
    var hits: [URL: [LibrarySearchHit]] = [:]
    var matchingPageCounts: [URL: Int] = [:]
    var skipped = 0
    var noSearchableText: Set<URL> = []
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
            var pages: [String] = []
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                pages.append(pdf.page(at: index)?.string ?? "")
            }
            addMatches(query, pages: pages, document: item, to: &result)
        }
        return result
    }

    static func search(
        _ query: String,
        indexedPages: [(document: LibraryDocument, pages: [String])],
        skipped: Int
    ) throws -> LibrarySearchResult {
        var result = LibrarySearchResult(skipped: skipped)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        for indexed in indexedPages {
            try Task.checkCancellation()
            addMatches(query, pages: indexed.pages, document: indexed.document, to: &result)
        }
        return result
    }

    private static func addMatches(
        _ query: String,
        pages: [String],
        document: LibraryDocument,
        to result: inout LibrarySearchResult
    ) {
        let hasSelectableText = pages.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard hasSelectableText else {
            result.noSearchableText.insert(document.url)
            return
        }

        var hits: [LibrarySearchHit] = []
        var matchingPages = 0
        for (index, text) in pages.enumerated() {
            guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            matchingPages += 1
            guard hits.count < 3 else { continue }
            let start = text.index(range.lowerBound, offsetBy: -35, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
            let excerpt = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            hits.append(LibrarySearchHit(page: index + 1, excerpt: excerpt))
        }
        if !hits.isEmpty {
            result.hits[document.url] = hits
            result.matchingPageCounts[document.url] = matchingPages
        }
    }
}
