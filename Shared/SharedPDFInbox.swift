import CoreGraphics
import Foundation

nonisolated struct SharedPDFInboxResult: Equatable, Sendable {
    let importedURLs: [URL]
    let failedFilenames: [String]
}

nonisolated enum SharedPDFInboxError: LocalizedError, Equatable {
    case unavailable
    case noPDFs
    case tooManyFiles
    case fileTooLarge(String)
    case totalTooLarge
    case invalidPDF(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Folik’s private sharing space is unavailable. Open Folik once, then try sharing again."
        case .noPDFs:
            "No PDF files were available to add to Folik."
        case .tooManyFiles:
            "Choose no more than 20 PDFs at a time."
        case .fileTooLarge(let name):
            "\(name) is larger than Folik’s 100 MB per-file limit."
        case .totalTooLarge:
            "Those PDFs exceed Folik’s 100 MB total sharing limit."
        case .invalidPDF(let name):
            "\(name) is not a readable PDF."
        }
    }
}

nonisolated enum SharedPDFInbox {
    static let appGroupIdentifier = "group.com.x3nllc.Folik"
    static let maximumFileCount = 20
    static let maximumBytes = 100 * 1024 * 1024

    static func defaultInboxDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("Shared PDF Inbox", isDirectory: true)
    }

    static func temporaryDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { throw SharedPDFInboxError.unavailable }
        let directory = container.appendingPathComponent(".share-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func validate(_ sourceURLs: [URL], fileManager: FileManager = .default) throws {
        guard !sourceURLs.isEmpty else { throw SharedPDFInboxError.noPDFs }
        guard sourceURLs.count <= maximumFileCount else { throw SharedPDFInboxError.tooManyFiles }
        var totalBytes = 0
        for source in sourceURLs {
            try Task.checkCancellation()
            let name = displayFilename(for: source.lastPathComponent)
            guard source.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame,
                  let provider = CGDataProvider(url: source as CFURL),
                  let document = CGPDFDocument(provider), document.numberOfPages > 0 else {
                throw SharedPDFInboxError.invalidPDF(name)
            }
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maximumBytes else { throw SharedPDFInboxError.fileTooLarge(name) }
            let (nextTotal, overflow) = totalBytes.addingReportingOverflow(size)
            guard !overflow, nextTotal <= maximumBytes else { throw SharedPDFInboxError.totalTooLarge }
            totalBytes = nextTotal
        }
    }

    @discardableResult
    static func enqueue(
        _ sourceURLs: [URL],
        into inboxDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try validate(sourceURLs, fileManager: fileManager)
        try fileManager.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)
        let staging = inboxDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        var reserved = Set(try pendingFiles(in: inboxDirectory, fileManager: fileManager).map(\.lastPathComponent))
        var staged: [(temporary: URL, destination: URL)] = []
        for source in sourceURLs {
            try Task.checkCancellation()
            let filename = uniqueFilename(displayFilename(for: source.lastPathComponent), reserved: reserved)
            reserved.insert(filename)
            let temporary = staging.appendingPathComponent(filename)
            try fileManager.copyItem(at: source, to: temporary)
            staged.append((temporary, inboxDirectory.appendingPathComponent(filename)))
        }

        var queued: [URL] = []
        do {
            for item in staged {
                try Task.checkCancellation()
                try fileManager.moveItem(at: item.temporary, to: item.destination)
                queued.append(item.destination)
            }
            return queued
        } catch {
            for url in queued { try? fileManager.removeItem(at: url) }
            throw error
        }
    }

    static func consume(
        from inboxDirectory: URL,
        into libraryDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> SharedPDFInboxResult {
        guard fileManager.fileExists(atPath: inboxDirectory.path) else {
            return SharedPDFInboxResult(importedURLs: [], failedFilenames: [])
        }
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        let pending = try pendingFiles(in: inboxDirectory, fileManager: fileManager)
        var imported: [URL] = []
        var failures: [String] = []
        var reserved = Set<String>()
        var completedMoves: [(source: URL, destination: URL)] = []

        do {
            for source in pending {
                try Task.checkCancellation()
                do {
                    try validate([source], fileManager: fileManager)
                    let filename = uniqueFilename(
                        source.lastPathComponent,
                        in: libraryDirectory,
                        reserved: reserved,
                        fileManager: fileManager
                    )
                    reserved.insert(filename)
                    let destination = libraryDirectory.appendingPathComponent(filename)
                    try fileManager.moveItem(at: source, to: destination)
                    completedMoves.append((source, destination))
                    imported.append(destination)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures.append(source.lastPathComponent)
                }
            }
        } catch {
            for move in completedMoves.reversed() {
                try? fileManager.moveItem(at: move.destination, to: move.source)
            }
            throw error
        }
        return SharedPDFInboxResult(importedURLs: imported, failedFilenames: failures)
    }

    static func pendingFiles(
        in inboxDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: inboxDirectory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: inboxDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.pathExtension.localizedCaseInsensitiveCompare("pdf") == .orderedSame &&
            ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func displayFilename(for proposed: String) -> String {
        let clean = URL(fileURLWithPath: proposed).lastPathComponent
        let source = URL(fileURLWithPath: clean)
        let stem = source.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (stem.isEmpty ? "Shared PDF" : String(stem.prefix(180))) + ".pdf"
    }

    private static func uniqueFilename(_ filename: String, reserved: Set<String>) -> String {
        guard !reserved.contains(filename) else {
            let source = URL(fileURLWithPath: filename)
            let stem = source.deletingPathExtension().lastPathComponent
            var number = 2
            while reserved.contains("\(stem) \(number).pdf") { number += 1 }
            return "\(stem) \(number).pdf"
        }
        return filename
    }

    private static func uniqueFilename(
        _ filename: String,
        in directory: URL,
        reserved: Set<String>,
        fileManager: FileManager
    ) -> String {
        var allReserved = reserved
        if let existing = try? fileManager.contentsOfDirectory(atPath: directory.path) {
            allReserved.formUnion(existing)
        }
        return uniqueFilename(filename, reserved: allReserved)
    }
}
