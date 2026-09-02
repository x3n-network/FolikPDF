import CoreGraphics
import CoreText
import ImageIO
import SwiftUI
import UIKit
import Vision
import VisionKit

enum ScannedPDFError: LocalizedError {
    case noPages
    case invalidPageImage
    case couldNotCreatePDF

    var errorDescription: String? {
        switch self {
        case .noPages:
            "No scanned pages were available. Try scanning the document again."
        case .invalidPageImage:
            "One of the scanned pages couldn’t be processed. Try scanning that page again."
        case .couldNotCreatePDF:
            "The scanned pages couldn’t be written as a PDF. Check available storage and try again."
        }
    }
}

enum ScannedPDFWriter {
    private struct RecognizedLine: Sendable {
        let text: String
        let normalizedBounds: CGRect
    }

    nonisolated static func write(pageImageData: [Data], to outputURL: URL) async throws {
        guard !pageImageData.isEmpty else { throw ScannedPDFError.noPages }
        let firstImage = try decodeImage(pageImageData[0])
        var initialBounds = pageBounds(for: firstImage)
        guard let context = CGContext(outputURL as CFURL, mediaBox: &initialBounds, nil) else {
            throw ScannedPDFError.couldNotCreatePDF
        }
        for data in pageImageData {
            // Decode, recognize, and draw one page at a time so a long camera scan
            // does not retain several full-resolution bitmap buffers concurrently.
            let image = try decodeImage(data)
            let recognizedLines = await recognizeText(in: image)
            var bounds = pageBounds(for: image)
            let mediaBox = Data(bytes: &bounds, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: mediaBox] as CFDictionary)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.interpolationQuality = .high
            let imageRect = aspectFitRect(
                for: CGSize(width: image.width, height: image.height),
                inside: bounds
            )
            context.draw(image, in: imageRect)
            drawSearchableText(recognizedLines, imageRect: imageRect, in: context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    nonisolated private static func decodeImage(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0,
              image.height > 0 else {
            throw ScannedPDFError.invalidPageImage
        }
        return image
    }

    nonisolated private static func recognizeText(in image: CGImage) async -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true

        do {
            return try await request.perform(on: image).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let points = [
                    observation.topLeft.cgPoint,
                    observation.topRight.cgPoint,
                    observation.bottomRight.cgPoint,
                    observation.bottomLeft.cgPoint
                ]
                let minX = points.map(\.x).min() ?? 0
                let maxX = points.map(\.x).max() ?? 0
                let minY = points.map(\.y).min() ?? 0
                let maxY = points.map(\.y).max() ?? 0
                let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                guard !candidate.string.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }
                return RecognizedLine(text: candidate.string, normalizedBounds: bounds)
            }
        } catch {
            return []
        }
    }

    nonisolated private static func drawSearchableText(
        _ lines: [RecognizedLine],
        imageRect: CGRect,
        in context: CGContext
    ) {
        for line in lines {
            let normalized = line.normalizedBounds
            let bounds = CGRect(
                x: imageRect.minX + normalized.minX * imageRect.width,
                y: imageRect.minY + normalized.minY * imageRect.height,
                width: normalized.width * imageRect.width,
                height: normalized.height * imageRect.height
            )
            guard bounds.width > 1, bounds.height > 1 else { continue }

            let fontSize = max(4, bounds.height * 0.82)
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let attributed = CFAttributedStringCreate(
                nil,
                line.text as CFString,
                [kCTFontAttributeName: font] as CFDictionary
            )
            guard let attributed else { continue }
            let textLine = CTLineCreateWithAttributedString(attributed)
            let textWidth = max(
                CGFloat(1),
                CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
            )

            context.saveGState()
            context.setTextDrawingMode(.invisible)
            context.translateBy(x: bounds.minX, y: bounds.minY)
            context.scaleBy(x: bounds.width / textWidth, y: 1)
            context.textPosition = CGPoint(x: 0, y: max(0, (bounds.height - fontSize) / 2))
            CTLineDraw(textLine, context)
            context.restoreGState()
        }
    }

    nonisolated private static func pageBounds(for image: CGImage) -> CGRect {
        image.width > image.height
            ? CGRect(x: 0, y: 0, width: 792, height: 612)
            : CGRect(x: 0, y: 0, width: 612, height: 792)
    }

    nonisolated private static func aspectFitRect(for imageSize: CGSize, inside bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
struct DocumentScannerView: UIViewControllerRepresentable {
    let complete: ([Data]) -> Void
    let cancel: () -> Void
    let fail: (Error) -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator {
        Coordinator(complete: complete, cancel: cancel, fail: fail)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let complete: ([Data]) -> Void
        private let cancel: () -> Void
        private let fail: (Error) -> Void

        init(
            complete: @escaping ([Data]) -> Void,
            cancel: @escaping () -> Void,
            fail: @escaping (Error) -> Void
        ) {
            self.complete = complete
            self.cancel = cancel
            self.fail = fail
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            do {
                let pages = try (0..<scan.pageCount).map { index in
                    guard let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.92) else {
                        throw ScannedPDFError.invalidPageImage
                    }
                    return data
                }
                complete(pages)
            } catch {
                fail(error)
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            cancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            fail(error)
        }
    }
}
