import Foundation

/// A local practice document with a complete, standards-defined AcroForm tree.
nonisolated enum SampleForm {
    static func data() throws -> Data {
        guard let url = Bundle.main.url(forResource: "SampleForm", withExtension: "pdf") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
