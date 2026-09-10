#if DEBUG
import Darwin
import PDFKit
import UIKit
import os

/// Opt-in, generated-document workload for the isolated QA app. Never runs in Release.
@MainActor
enum PerformanceProbe {
    static let log = OSLog(subsystem: "com.x3nllc.Folik.profiling", category: .pointsOfInterest)
    static func run() async throws -> [String: Double] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Annotated.pdf")
        try autoreleasepool {
            let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).pdfData { context in
                for index in 0..<150 {
                    context.beginPage()
                    ("Profile page \(index)" as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
                }
            }
            let pdf = PDFDocument(data: data)!
            for index in 0..<150 {
                for number in 0..<20 {
                    let annotation = PDFAnnotation(bounds: CGRect(x: 30, y: 50 + number * 25, width: 120, height: 20), forType: .square, withProperties: nil)
                    pdf.page(at: index)!.addAnnotation(annotation)
                }
            }
            guard pdf.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        }
        var result: [String: Double] = ["before_open_mb": footprintMB()]
        os_signpost(.begin, log: log, name: "Open annotated PDF")
        let start = CFAbsoluteTimeGetCurrent()
        let item = LibraryDocument(url: url, pageCount: 150, fileSize: 0, modifiedAt: Date())
        var session: DocumentSession? = DocumentSession(item: item)
        result["open_ms"] = (CFAbsoluteTimeGetCurrent() - start) * 1000
        result["annotation_count"] = Double(session?.annotations.count ?? 0)
        result["after_open_mb"] = footprintMB()
        os_signpost(.end, log: log, name: "Open annotated PDF")
        session = nil
        let stagedStart = CFAbsoluteTimeGetCurrent()
        var staged: DocumentSession? = DocumentSession(item: item, deferredPreparation: true)
        result["reader_initial_ms"] = (CFAbsoluteTimeGetCurrent() - stagedStart) * 1000
        await staged?.prepareForReading()
        result["reader_ready_ms"] = (CFAbsoluteTimeGetCurrent() - stagedStart) * 1000
        result["reader_batches"] = Double(staged?.preparationBatchCount ?? 0)
        result["reader_annotation_count"] = Double(staged?.annotations.count ?? 0)
        result["reader_longest_batch_ms"] = staged?.longestPreparationBatchMilliseconds ?? 0
        staged = nil

        let scans = autoreleasepool {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1600), format: format).image { context in
                UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1600))
                ("Profile invoice 4827" as NSString).draw(at: CGPoint(x: 90, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
            }
            return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
                for _ in 0..<12 { context.beginPage(); image.draw(in: CGRect(x: 0, y: 0, width: 600, height: 800)) }
            }
        }
        result["before_ocr_mb"] = footprintMB()
        os_signpost(.begin, log: log, name: "OCR twelve scan pages")
        let ocrStart = CFAbsoluteTimeGetCurrent()
        let output = try await PDFProcessing.searchable(scans) { page, _ in
            await MainActor.run { result["ocr_page_\(page)_mb"] = footprintMB() }
        }
        result["ocr_ms"] = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000
        result["after_ocr_mb"] = footprintMB()
        result["ocr_pages"] = Double(output.pageCount)
        os_signpost(.end, log: log, name: "OCR twelve scan pages")
        let report = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PerformanceReport.json")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        print("FOLIK_PROFILE \(result)")
        return result
    }

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1048576 : -1
    }
}
#endif
