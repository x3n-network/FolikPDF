import Foundation

nonisolated struct LibraryMetadata: Codable, Equatable, Sendable {
    var folder = ""
    var tags: [String] = []
    var isFavorite = false
    var documentID: UUID?

    private enum CodingKeys: String, CodingKey {
        case folder, tags, isFavorite, documentID
    }

    init(folder: String = "", tags: [String] = [], isFavorite: Bool = false, documentID: UUID? = nil) {
        self.folder = folder
        self.tags = tags
        self.isFavorite = isFavorite
        self.documentID = documentID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folder = try container.decodeIfPresent(String.self, forKey: .folder) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        documentID = try container.decodeIfPresent(UUID.self, forKey: .documentID)
    }
    static func validated(folder: String, tags: [String]) throws -> Self {
        let folder = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard folder.count <= 80, tags.count <= 20, tags.allSatisfy({ $0.count <= 40 }),
              ([folder] + tags).allSatisfy({ $0.rangeOfCharacter(from: .controlCharacters) == nil }) else {
            throw LibraryOrganizationError.invalidLabels
        }
        var seen: Set<String> = []
        return Self(folder: folder, tags: tags.filter { seen.insert($0.lowercased()).inserted }.sorted())
    }
    func matches(_ query: String) -> Bool {
        ([folder] + tags).contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
nonisolated enum LibraryOrganizationError: LocalizedError {
    case invalidLabels, invalidStore, nameAlreadyExists
    var errorDescription: String? {
        switch self {
        case .invalidLabels: "Use a folder name up to 80 characters and up to 20 tags of 40 characters each."
        case .invalidStore: "Library organization data could not be read. Your PDFs are unchanged."
        case .nameAlreadyExists: "A document with that name is already in your library."
        }
    }
}
nonisolated enum LibraryOrganization {
    static func load(from url: URL) throws -> [String: LibraryMetadata] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024,
              let decoded = try? JSONDecoder().decode([String: LibraryMetadata].self, from: data) else { throw LibraryOrganizationError.invalidStore }
        return decoded
    }
    static func save(_ records: [String: LibraryMetadata], to url: URL) throws {
        let data = try JSONEncoder().encode(records)
        guard data.count <= 2 * 1024 * 1024 else { throw LibraryOrganizationError.invalidStore }
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
