import Foundation
import PDFKit

nonisolated struct LibrarySearchRequest: Hashable {
    let query: String
    let documents: [LibraryDocument]
}
nonisolated struct LibrarySearchHit: Sendable, Hashable {
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
            var matches = DocumentMatches(query: query)
            for index in 0..<pdf.pageCount {
                try Task.checkCancellation()
                try autoreleasepool {
                    let text = pdf.page(at: index)?.string ?? ""
                    try Task.checkCancellation()
                    matches.consume(text, page: index + 1)
                }
            }
            matches.append(document: item, to: &result)
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

    struct DocumentMatches {
        private static let maximumRetainedHits = 50
        let query: String
        private(set) var hasText = false
        private(set) var matchingPages = 0
        private(set) var hits: [LibrarySearchHit] = []

        mutating func consume(_ text: String, page: Int) {
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasText = true }
            guard !query.isEmpty, let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { return }
            matchingPages += 1
            guard hits.count < Self.maximumRetainedHits else { return }
            let start = text.index(range.lowerBound, offsetBy: -35, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
            let excerpt = text[start..<end].split(whereSeparator: \.isWhitespace).joined(separator: " ")
            hits.append(LibrarySearchHit(page: page, excerpt: excerpt))
        }

        func append(document: LibraryDocument, to result: inout LibrarySearchResult) {
            if !hasText { result.noSearchableText.insert(document.url) }
            if !hits.isEmpty {
                result.hits[document.url] = hits
                result.matchingPageCounts[document.url] = matchingPages
            }
        }
    }

    private static func addMatches(_ query: String, pages: [String], document: LibraryDocument, to result: inout LibrarySearchResult) {
        var matches = DocumentMatches(query: query)
        for (index, text) in pages.enumerated() { matches.consume(text, page: index + 1) }
        matches.append(document: document, to: &result)
    }
}
