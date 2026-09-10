import Foundation
import PDFKit

nonisolated struct ProtectedPDF: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let pageCount: Int
}

nonisolated enum PDFProtectionError: LocalizedError, Equatable {
    case invalidPassword
    case couldNotProtect

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            "Use 6–128 characters and avoid control characters. Spaces alone are not a password."
        case .couldNotProtect:
            "Folik couldn’t verify the protected copy. The original was not changed."
        }
    }
}

nonisolated enum PDFProtection {
    static func validate(_ password: String) throws {
        guard (6...128).contains(password.count),
              !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              password.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw PDFProtectionError.invalidPassword
        }
    }

    static func protect(_ data: Data, password: String) throws -> ProtectedPDF {
        try validate(password)
        let source = try PDFProcessing.document(data)
        let options: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: password,
            .ownerPasswordOption: password
        ]
        guard let output = source.dataRepresentation(options: options),
              output.count <= PDFProcessing.maximumBytes,
              let verification = PDFDocument(data: output),
              verification.isEncrypted,
              verification.isLocked,
              !verification.unlock(withPassword: ""),
              verification.unlock(withPassword: password),
              verification.pageCount == source.pageCount else {
            throw PDFProtectionError.couldNotProtect
        }
        return ProtectedPDF(data: output, pageCount: source.pageCount)
    }
}
