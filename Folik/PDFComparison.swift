import Foundation
import PDFKit

nonisolated enum PDFComparisonChangeKind: String, Sendable {
    case added = "Added"
    case removed = "Removed"
    case modified = "Changed"

    var icon: String {
        switch self {
        case .added: "plus.circle"
        case .removed: "minus.circle"
        case .modified: "arrow.left.arrow.right.circle"
        }
    }
}

nonisolated struct PDFComparisonChange: Identifiable, Equatable, Sendable {
    let id: Int
    let kind: PDFComparisonChangeKind
    let originalPage: Int?
    let revisedPage: Int?
    let originalExcerpt: String?
    let revisedExcerpt: String?

    var title: String {
        switch (kind, originalPage, revisedPage) {
        case (.added, _, let revised?): "Page \(revised) added"
        case (.removed, let original?, _): "Page \(original) removed"
        case (.modified, let original?, let revised?): "Page \(original) → \(revised) changed"
        default: kind.rawValue
        }
    }
}

nonisolated struct PDFComparisonReport: Identifiable, Equatable, Sendable {
    let id = UUID()
    let originalPageCount: Int
    let revisedPageCount: Int
    let unchangedPageCount: Int
    let changes: [PDFComparisonChange]

    var addedCount: Int { changes.filter { $0.kind == .added }.count }
    var removedCount: Int { changes.filter { $0.kind == .removed }.count }
    var modifiedCount: Int { changes.filter { $0.kind == .modified }.count }
    var isIdentical: Bool { changes.isEmpty && originalPageCount == revisedPageCount }
}

nonisolated enum PDFComparisonError: LocalizedError, Equatable {
    case noSearchableText
    case tooMuchText

    var errorDescription: String? {
        switch self {
        case .noSearchableText:
            "Neither PDF has enough selectable text to compare. Make searchable copies with OCR, then try again."
        case .tooMuchText:
            "These PDFs contain too much extracted text for a safe on-device comparison."
        }
    }
}

nonisolated enum PDFComparison {
    private static let maximumTextBytes = 16 * 1024 * 1024

    static func compare(_ originalData: Data, _ revisedData: Data) throws -> PDFComparisonReport {
        let original = try pages(in: originalData)
        let revised = try pages(in: revisedData)
        guard original.contains(where: { !$0.isEmpty }) || revised.contains(where: { !$0.isEmpty }) else {
            throw PDFComparisonError.noSearchableText
        }

        let matches = longestCommonSubsequence(original, revised)
        var changes: [PDFComparisonChange] = []
        var originalStart = 0
        var revisedStart = 0

        func appendSegment(originalEnd: Int, revisedEnd: Int) {
            let originalCount = originalEnd - originalStart
            let revisedCount = revisedEnd - revisedStart
            let paired = min(originalCount, revisedCount)
            for offset in 0..<paired {
                let oldIndex = originalStart + offset
                let newIndex = revisedStart + offset
                changes.append(PDFComparisonChange(
                    id: changes.count,
                    kind: .modified,
                    originalPage: oldIndex + 1,
                    revisedPage: newIndex + 1,
                    originalExcerpt: excerpt(original[oldIndex]),
                    revisedExcerpt: excerpt(revised[newIndex])
                ))
            }
            if originalCount > paired {
                for index in (originalStart + paired)..<originalEnd {
                    changes.append(PDFComparisonChange(
                        id: changes.count, kind: .removed, originalPage: index + 1,
                        revisedPage: nil, originalExcerpt: excerpt(original[index]), revisedExcerpt: nil
                    ))
                }
            }
            if revisedCount > paired {
                for index in (revisedStart + paired)..<revisedEnd {
                    changes.append(PDFComparisonChange(
                        id: changes.count, kind: .added, originalPage: nil,
                        revisedPage: index + 1, originalExcerpt: nil, revisedExcerpt: excerpt(revised[index])
                    ))
                }
            }
        }

        for match in matches {
            appendSegment(originalEnd: match.original, revisedEnd: match.revised)
            originalStart = match.original + 1
            revisedStart = match.revised + 1
        }
        appendSegment(originalEnd: original.count, revisedEnd: revised.count)

        return PDFComparisonReport(
            originalPageCount: original.count,
            revisedPageCount: revised.count,
            unchangedPageCount: matches.count,
            changes: changes
        )
    }

    private static func pages(in data: Data) throws -> [String] {
        let document = try PDFProcessing.document(data)
        var totalBytes = 0
        return try (0..<document.pageCount).map { index in
            try Task.checkCancellation()
            let text = normalize(document.page(at: index)?.string ?? "")
            totalBytes += text.utf8.count
            guard totalBytes <= maximumTextBytes else { throw PDFComparisonError.tooMuchText }
            return text
        }
    }

    private static func normalize(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
    }

    private static func excerpt(_ text: String) -> String {
        guard !text.isEmpty else { return "No selectable text on this page." }
        if text.count <= 220 { return text }
        return String(text.prefix(217)) + "…"
    }

    private static func longestCommonSubsequence(
        _ original: [String],
        _ revised: [String]
    ) -> [(original: Int, revised: Int)] {
        let columns = revised.count + 1
        var lengths = Array(repeating: 0, count: (original.count + 1) * columns)
        guard !original.isEmpty, !revised.isEmpty else { return [] }
        for old in 1...original.count {
            for new in 1...revised.count {
                let index = old * columns + new
                if original[old - 1] == revised[new - 1] {
                    lengths[index] = lengths[(old - 1) * columns + new - 1] + 1
                } else {
                    lengths[index] = max(lengths[(old - 1) * columns + new], lengths[old * columns + new - 1])
                }
            }
        }
        var old = original.count
        var new = revised.count
        var matches: [(Int, Int)] = []
        while old > 0, new > 0 {
            if original[old - 1] == revised[new - 1] {
                matches.append((old - 1, new - 1)); old -= 1; new -= 1
            } else if lengths[(old - 1) * columns + new] >= lengths[old * columns + new - 1] {
                old -= 1
            } else {
                new -= 1
            }
        }
        return matches.reversed()
    }
}
