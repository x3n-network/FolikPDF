import Foundation

struct BookmarkStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "folik.documentBookmarks") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func bookmarks(for documentURL: URL, pageCount: Int) -> Set<Int> {
        let saved = Set(allBookmarks[documentKey(for: documentURL)] ?? [])
        let valid = saved.filter { $0 >= 0 && $0 < pageCount }
        if valid != saved {
            save(valid, for: documentURL)
        }
        return valid
    }

    func save(_ bookmarks: Set<Int>, for documentURL: URL) {
        var updated = allBookmarks
        let key = documentKey(for: documentURL)
        if bookmarks.isEmpty {
            updated.removeValue(forKey: key)
        } else {
            updated[key] = bookmarks.sorted()
        }
        defaults.set(updated, forKey: storageKey)
    }

    func removeBookmarks(for documentURL: URL) {
        save([], for: documentURL)
    }

    func moveBookmarks(from oldURL: URL, to newURL: URL) {
        var updated = allBookmarks
        guard let bookmarks = updated.removeValue(forKey: documentKey(for: oldURL)) else { return }
        updated[documentKey(for: newURL)] = bookmarks
        defaults.set(updated, forKey: storageKey)
    }

    private var allBookmarks: [String: [Int]] {
        defaults.dictionary(forKey: storageKey)?.reduce(into: [:]) { result, entry in
            if let values = entry.value as? [Int] {
                result[entry.key] = values
            } else if let values = entry.value as? [NSNumber] {
                result[entry.key] = values.map(\.intValue)
            }
        } ?? [:]
    }

    private func documentKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
