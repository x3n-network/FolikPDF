import CoreGraphics
import Foundation
import PDFKit

nonisolated enum RedactionSuggestionKind: String, CaseIterable, Hashable, Sendable {
    case search
    case email
    case phone
    case socialSecurityNumber

    var title: String {
        switch self {
        case .search: "Text match"
        case .email: "Email address"
        case .phone: "Phone number"
        case .socialSecurityNumber: "Social Security number"
        }
    }

    static let sensitiveInformation: Set<Self> = [.email, .phone, .socialSecurityNumber]
}

nonisolated struct RedactionSuggestion: Identifiable, Sendable {
    let id = UUID()
    let kind: RedactionSuggestionKind
    let matchedText: String
    let area: RedactionArea
}

nonisolated enum SmartRedactionError: LocalizedError, Equatable {
    case noSearchableText
    case noMatches
    case tooManyMatches

    var errorDescription: String? {
        switch self {
        case .noSearchableText:
            "No searchable text was found. Use Make PDF Searchable first, then try again."
        case .noMatches:
            "No matching text was found. Try another search or review the page manually."
        case .tooManyMatches:
            "More than 500 matches were found. Use a more specific search or redact fewer pattern types at once."
        }
    }
}

nonisolated enum SmartRedaction {
    private static let maximumSuggestions = 500

    static func findText(in data: Data, query: String) throws -> [RedactionSuggestion] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw SmartRedactionError.noMatches }
        return try scan(data) { text in
            let source = text as NSString
            var ranges: [(NSRange, RedactionSuggestionKind)] = []
            var remaining = NSRange(location: 0, length: source.length)
            while remaining.length > 0 {
                try Task.checkCancellation()
                let match = source.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: remaining)
                guard match.location != NSNotFound else { break }
                ranges.append((match, .search))
                let next = NSMaxRange(match)
                remaining = NSRange(location: next, length: source.length - next)
            }
            return ranges
        }
    }

    static func findSensitiveInformation(in data: Data, kinds: Set<RedactionSuggestionKind> = RedactionSuggestionKind.sensitiveInformation) throws -> [RedactionSuggestion] {
        let patterns: [(RedactionSuggestionKind, String)] = [
            (.email, #"(?i)(?<![A-Z0-9._%+\-])[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,63}(?![A-Z0-9.\-])"#),
            (.phone, #"(?<!\w)(?:\+?1[\s.\-]?)?(?:\(\d{3}\)|\d{3})[\s.\-]\d{3}[\s.\-]\d{4}(?!\w)"#),
            (.socialSecurityNumber, #"(?<!\d)\d{3}[\- ]\d{2}[\- ]\d{4}(?!\d)"#)
        ].filter { kinds.contains($0.0) }
        return try scan(data) { text in
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            return try patterns.flatMap { kind, pattern in
                try NSRegularExpression(pattern: pattern).matches(in: text, range: fullRange).map { ($0.range, kind) }
            }.sorted { $0.0.location < $1.0.location }
        }
    }

    private static func scan(_ data: Data, matches: (String) throws -> [(NSRange, RedactionSuggestionKind)]) throws -> [RedactionSuggestion] {
        let pdf = try PDFProcessing.document(data)
        var suggestions: [RedactionSuggestion] = []
        var foundSearchableText = false
        for pageIndex in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: pageIndex), let pageText = page.string,
                  !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            foundSearchableText = true
            for (range, kind) in try matches(pageText) {
                try Task.checkCancellation()
                guard let selection = page.selection(for: range) else { continue }
                let lineSelections = selection.selectionsByLine()
                for line in lineSelections.isEmpty ? [selection] : lineSelections {
                    guard let area = normalizedArea(for: line.bounds(for: page), on: page, pageIndex: pageIndex) else { continue }
                    let matchedText = (pageText as NSString).substring(with: range)
                    suggestions.append(RedactionSuggestion(kind: kind, matchedText: matchedText, area: area))
                    guard suggestions.count <= maximumSuggestions else { throw SmartRedactionError.tooManyMatches }
                }
            }
        }
        guard foundSearchableText else { throw SmartRedactionError.noSearchableText }
        guard !suggestions.isEmpty else { throw SmartRedactionError.noMatches }
        return suggestions
    }

    private static func normalizedArea(for selectionBounds: CGRect, on page: PDFPage, pageIndex: Int) -> RedactionArea? {
        guard let ref = page.pageRef, !selectionBounds.isNull, !selectionBounds.isEmpty,
              let displayBounds = try? PDFProcessing.bounds(ref) else { return nil }
        let transform = ref.getDrawingTransform(.cropBox, rect: displayBounds, rotate: 0, preserveAspectRatio: true)
        var transformed = selectionBounds.applying(transform).standardized.insetBy(dx: -2, dy: -2)
        transformed = transformed.intersection(displayBounds)
        guard !transformed.isNull, transformed.width > 0, transformed.height > 0 else { return nil }
        let normalized = CGRect(
            x: transformed.minX / displayBounds.width,
            y: 1 - transformed.maxY / displayBounds.height,
            width: transformed.width / displayBounds.width,
            height: transformed.height / displayBounds.height
        )
        return RedactionArea(page: pageIndex, rect: normalized)
    }
}
