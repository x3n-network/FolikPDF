import Foundation
import PDFKit
import Vision

nonisolated struct FormFieldSuggestion: Identifiable, Sendable {
    let id: UUID
    let pageIndex: Int
    let kind: FormFieldPlacementKind
    let label: String
    let bounds: CGRect
    let reason: String

    init(
        id: UUID = UUID(),
        pageIndex: Int,
        kind: FormFieldPlacementKind,
        label: String,
        bounds: CGRect,
        reason: String
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.kind = kind
        self.label = label
        self.bounds = bounds
        self.reason = reason
    }
}

nonisolated enum FormFieldSuggestionEngine {
    static let maximumSuggestions = 200

    static func suggestions(in data: Data) async throws -> [FormFieldSuggestion] {
        try await Task.detached(priority: .userInitiated) {
            let document = try PDFProcessing.document(data)
            var suggestions: [FormFieldSuggestion] = []

            for pageIndex in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: pageIndex), let pageRef = page.pageRef else {
                    throw PDFProcessingError.invalid
                }
                let image = try PDFProcessing.bitmap(pageRef, dpi: 120)
                async let recognizedLines = ScannedPDFWriter.recognizeText(in: image)
                let normalizedRectangles = try detectedRectangles(in: image)
                let lines = try await recognizedLines
                try Task.checkCancellation()

                let pageBounds = page.bounds(for: .cropBox)
                let rectangles = normalizedRectangles.map { pageRect($0, in: pageBounds) }
                let existingWidgets = page.annotations
                    .filter { $0.type?.lowercased() == "widget" }
                    .map(\.bounds)
                suggestions.append(contentsOf: inferSuggestions(
                    pageIndex: pageIndex,
                    pageBounds: pageBounds,
                    lines: lines,
                    rectangleBounds: rectangles,
                    existingWidgetBounds: existingWidgets
                ))
                if suggestions.count >= maximumSuggestions {
                    return Array(suggestions.prefix(maximumSuggestions))
                }
            }
            return suggestions
        }.value
    }

    static func inferSuggestions(
        pageIndex: Int,
        pageBounds: CGRect,
        lines: [ScannedPDFWriter.RecognizedLine],
        rectangleBounds: [CGRect],
        existingWidgetBounds: [CGRect] = []
    ) -> [FormFieldSuggestion] {
        let pageLines = lines.compactMap { line -> (text: String, bounds: CGRect)? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedLabel(text).isEmpty else { return nil }
            return (text, pageRect(line.normalizedBounds, in: pageBounds))
        }
        var candidates: [FormFieldSuggestion] = []

        for rectangle in rectangleBounds {
            let bounds = rectangle.standardized.intersection(pageBounds)
            guard isUsable(bounds),
                  !substantiallyOverlaps(bounds, any: existingWidgetBounds),
                  !substantiallyOverlaps(bounds, any: pageLines.map(\.bounds)) else { continue }
            let aspect = bounds.width / max(1, bounds.height)
            let kind: FormFieldPlacementKind
            if (0.72...1.38).contains(aspect), (10...42).contains(bounds.width), (10...42).contains(bounds.height) {
                kind = .checkbox
            } else if aspect >= 2, (18...78).contains(bounds.height), bounds.width >= 64 {
                kind = bounds.height >= 58 ? .multilineText : .text
            } else {
                continue
            }
            let nearby = nearestLabel(to: bounds, kind: kind, lines: pageLines)
            let label = nearby.map { cleanedLabel($0.text) } ?? (kind == .checkbox ? "Checkbox" : "Field")
            let inferredKind = kind == .checkbox ? kind : inferredKind(for: label, fallback: kind)
            appendIfDistinct(FormFieldSuggestion(
                pageIndex: pageIndex,
                kind: inferredKind,
                label: label,
                bounds: bounds,
                reason: kind == .checkbox ? "Detected checkbox" : "Detected box"
            ), to: &candidates, existingWidgetBounds: existingWidgetBounds)
        }

        for line in pageLines where isLikelyFieldLabel(line.text) {
            let kind = inferredKind(for: line.text, fallback: .text)
            guard let bounds = proposedBounds(for: kind, after: line.bounds, in: pageBounds) else { continue }
            let label = cleanedLabel(line.text)
            guard !candidates.contains(where: {
                $0.label.localizedCaseInsensitiveCompare(label) == .orderedSame &&
                $0.bounds.insetBy(dx: -36, dy: -36).intersects(bounds)
            }) else { continue }
            appendIfDistinct(FormFieldSuggestion(
                pageIndex: pageIndex,
                kind: kind,
                label: label,
                bounds: bounds,
                reason: "Recognized label"
            ), to: &candidates, existingWidgetBounds: existingWidgetBounds)
        }

        return candidates
            .sorted {
                if abs($0.bounds.midY - $1.bounds.midY) > 4 { return $0.bounds.midY > $1.bounds.midY }
                return $0.bounds.minX < $1.bounds.minX
            }
            .prefix(maximumSuggestions)
            .map { $0 }
    }

    private static func detectedRectangles(in image: CGImage) throws -> [CGRect] {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 100
        request.minimumAspectRatio = 0.05
        request.maximumAspectRatio = 1
        request.minimumSize = 0.005
        request.minimumConfidence = 0.3
        request.quadratureTolerance = 30
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        return (request.results ?? []).map(\.boundingBox)
    }

    private static func pageRect(_ normalized: CGRect, in pageBounds: CGRect) -> CGRect {
        CGRect(
            x: pageBounds.minX + normalized.minX * pageBounds.width,
            y: pageBounds.minY + normalized.minY * pageBounds.height,
            width: normalized.width * pageBounds.width,
            height: normalized.height * pageBounds.height
        ).standardized
    }

    private static func nearestLabel(
        to fieldBounds: CGRect,
        kind: FormFieldPlacementKind,
        lines: [(text: String, bounds: CGRect)]
    ) -> (text: String, bounds: CGRect)? {
        lines.compactMap { line -> (line: (text: String, bounds: CGRect), score: CGFloat)? in
            let verticalDistance = abs(line.bounds.midY - fieldBounds.midY)
            if kind == .checkbox {
                let gap = line.bounds.minX - fieldBounds.maxX
                guard gap >= -4, gap <= 220, verticalDistance <= max(18, fieldBounds.height) else { return nil }
                return (line, gap + verticalDistance * 2)
            }
            let leftGap = fieldBounds.minX - line.bounds.maxX
            if leftGap >= -4, leftGap <= 180, verticalDistance <= max(20, fieldBounds.height) {
                return (line, leftGap + verticalDistance * 2)
            }
            let aboveGap = line.bounds.minY - fieldBounds.maxY
            let horizontalDistance = abs(line.bounds.minX - fieldBounds.minX)
            guard aboveGap >= -4, aboveGap <= 54, horizontalDistance <= 80 else { return nil }
            return (line, aboveGap + horizontalDistance)
        }
        .min(by: { $0.score < $1.score })?
        .line
    }

    private static func proposedBounds(
        for kind: FormFieldPlacementKind,
        after labelBounds: CGRect,
        in pageBounds: CGRect
    ) -> CGRect? {
        let margin: CGFloat = 24
        let desired = kind.defaultSize
        let rightStart = labelBounds.maxX + 10
        let rightWidth = min(desired.width, pageBounds.maxX - margin - rightStart)
        let proposed: CGRect
        if rightWidth >= min(90, desired.width) {
            proposed = CGRect(
                x: rightStart,
                y: labelBounds.midY - desired.height / 2,
                width: rightWidth,
                height: desired.height
            )
        } else {
            let belowY = labelBounds.minY - desired.height - 8
            let width = min(desired.width, pageBounds.maxX - margin - labelBounds.minX)
            guard belowY >= pageBounds.minY + margin, width >= min(90, desired.width) else { return nil }
            proposed = CGRect(x: labelBounds.minX, y: belowY, width: width, height: desired.height)
        }
        return proposed.intersection(pageBounds.insetBy(dx: margin, dy: margin)).standardized
    }

    private static func inferredKind(
        for label: String,
        fallback: FormFieldPlacementKind
    ) -> FormFieldPlacementKind {
        let normalized = label.localizedLowercase
        if normalized.contains("signature") || normalized.contains("sign here") { return .signature }
        if normalized.range(of: #"\bdate\b"#, options: .regularExpression) != nil { return .date }
        if normalized.contains("comments") || normalized.contains("description") || normalized.contains("explain") || normalized.contains("notes") {
            return .multilineText
        }
        return fallback
    }

    private static func isLikelyFieldLabel(_ label: String) -> Bool {
        let normalized = label.localizedLowercase
        guard label.count <= 80, label.split(whereSeparator: \.isWhitespace).count <= 9 else { return false }
        if label.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":") { return true }
        let keywords = [
            "name", "address", "email", "phone", "telephone", "date", "signature",
            "initials", "city", "state", "zip", "postal", "company", "title",
            "comments", "description", "notes", "account", "number"
        ]
        return keywords.contains { keyword in
            normalized.range(of: "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b", options: .regularExpression) != nil
        }
    }

    private static func cleanedLabel(_ source: String) -> String {
        let withoutBlank = source.replacingOccurrences(
            of: #"[_\.]{2,}"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = withoutBlank
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }

    private static func appendIfDistinct(
        _ candidate: FormFieldSuggestion,
        to candidates: inout [FormFieldSuggestion],
        existingWidgetBounds: [CGRect]
    ) {
        guard isUsable(candidate.bounds),
              !substantiallyOverlaps(candidate.bounds, any: existingWidgetBounds),
              !substantiallyOverlaps(candidate.bounds, any: candidates.map(\.bounds)) else { return }
        candidates.append(candidate)
    }

    private static func substantiallyOverlaps(_ bounds: CGRect, any others: [CGRect]) -> Bool {
        others.contains { other in
            let intersection = bounds.intersection(other)
            guard !intersection.isNull else { return false }
            let smallerArea = min(bounds.width * bounds.height, other.width * other.height)
            return smallerArea > 0 && intersection.width * intersection.height / smallerArea > 0.45
        }
    }

    private static func isUsable(_ bounds: CGRect) -> Bool {
        bounds.width.isFinite && bounds.height.isFinite && bounds.width >= 10 && bounds.height >= 10
    }
}
