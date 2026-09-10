import PDFKit
import SwiftUI

nonisolated struct PDFThumbnailRequest: Hashable, Sendable {
    let url: URL
    let page: Int
    let width: Int
    let height: Int
    let revision: String
}

// CGImage is immutable; the worker owns its PDFDocument and never shares live PDFKit objects.
nonisolated final class RenderedPDFThumbnail: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

actor PDFThumbnailCache {
    static let shared = PDFThumbnailCache()
    private let images = NSCache<NSString, RenderedPDFThumbnail>()
    private var documentKey: String?
    private var document: PDFDocument?
    private(set) var renderCount = 0

    init() {
        images.totalCostLimit = 32 * 1024 * 1024
        images.countLimit = 128
    }

    func image(for request: PDFThumbnailRequest) throws -> RenderedPDFThumbnail? {
        try Task.checkCancellation()
        // URL resource values can remain cached after the file at that URL is replaced.
        let attributes = try FileManager.default.attributesOfItem(atPath: request.url.path)
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let sourceKey = "\(request.url.standardizedFileURL.path)|\(modified)|\(bytes)|\(request.revision)"
        let key = "\(sourceKey)|\(request.page)|\(request.width)x\(request.height)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        return try autoreleasepool {
            if documentKey != sourceKey {
                document = PDFDocument(url: request.url)
                documentKey = sourceKey
            }
            guard let document, !document.isLocked, let page = document.page(at: request.page) else { return nil }
            try Task.checkCancellation()
            let size = CGSize(width: max(1, min(1024, request.width)), height: max(1, min(1024, request.height)))
            guard let cgImage = page.thumbnail(of: size, for: .cropBox).cgImage else { return nil }
            try Task.checkCancellation()
            renderCount += 1
            let result = RenderedPDFThumbnail(cgImage)
            images.setObject(result, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
            return result
        }
    }

    func removeAll() {
        images.removeAllObjects()
        document = nil
        documentKey = nil
    }
}

struct FilePDFThumbnail: View {
    let url: URL
    var page = 0
    var size = CGSize(width: 104, height: 136)
    let revision: String
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    private var request: PDFThumbnailRequest {
        PDFThumbnailRequest(url: url, page: page, width: Int(size.width * displayScale), height: Int(size.height * displayScale), revision: revision)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(FolikTheme.recessedSurface)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "doc.fill").font(.title2).foregroundStyle(FolikTheme.cobalt)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(FolikTheme.separator, lineWidth: 0.5) }
        .task(id: request) {
            image = nil
            do {
                let thumbnail = try await PDFThumbnailCache.shared.image(for: request)
                try Task.checkCancellation()
                image = thumbnail.map { UIImage(cgImage: $0.image) }
            } catch { }
        }
        .onDisappear { image = nil }
        .accessibilityHidden(true)
    }
}
