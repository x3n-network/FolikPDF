import Foundation

struct SignatureStore {
    private let directoryURL: URL
    private let legacyDefaults: UserDefaults
    private let fileManager: FileManager

    init(
        directoryURL: URL? = nil,
        legacyDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.legacyDefaults = legacyDefaults
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directoryURL = applicationSupport
                .appendingPathComponent("Folik", isDirectory: true)
                .appendingPathComponent("Signatures", isDirectory: true)
        }
    }

    func load(_ kind: SignatureKind) -> SignatureAsset? {
        if let data = try? Data(contentsOf: fileURL(for: kind)),
           let asset = try? JSONDecoder().decode(SignatureAsset.self, from: data),
           asset.isValid {
            return asset
        }

        guard
            let legacyData = legacyDefaults.data(forKey: legacyKey(for: kind)),
            let asset = try? JSONDecoder().decode(SignatureAsset.self, from: legacyData),
            asset.isValid,
            save(asset)
        else { return nil }

        legacyDefaults.removeObject(forKey: legacyKey(for: kind))
        return asset
    }

    @discardableResult
    func save(_ asset: SignatureAsset) -> Bool {
        guard asset.isValid, let data = try? JSONEncoder().encode(asset) else { return false }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
            let destination = fileURL(for: asset.kind)
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: destination.path
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func delete(_ kind: SignatureKind) -> Bool {
        legacyDefaults.removeObject(forKey: legacyKey(for: kind))
        let destination = fileURL(for: kind)
        guard fileManager.fileExists(atPath: destination.path) else { return true }
        do {
            try fileManager.removeItem(at: destination)
            return true
        } catch {
            return false
        }
    }

    func fileURL(for kind: SignatureKind) -> URL {
        directoryURL.appendingPathComponent("saved-\(kind.rawValue)-v1.json")
    }

    private func legacyKey(for kind: SignatureKind) -> String {
        "com.x3nllc.Folik.saved-\(kind.rawValue)-v1"
    }
}
