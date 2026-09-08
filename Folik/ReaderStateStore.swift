import Foundation

nonisolated struct ReaderState: Equatable, Sendable {
    var pageIndex: Int
    var layout: ReaderLayout
}

struct ReaderStateStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "folik.documentReaderStates") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func state(for documentURL: URL, pageCount: Int) -> ReaderState {
        guard let saved = allStates[documentKey(for: documentURL)] else {
            return ReaderState(pageIndex: 0, layout: .continuous)
        }
        let pageIndex = min(max(saved.pageIndex, 0), max(0, pageCount - 1))
        let layout = ReaderLayout(rawValue: saved.layout) ?? .continuous
        if pageIndex != saved.pageIndex || layout.rawValue != saved.layout {
            save(ReaderState(pageIndex: pageIndex, layout: layout), for: documentURL)
        }
        return ReaderState(pageIndex: pageIndex, layout: layout)
    }

    func save(_ state: ReaderState, for documentURL: URL) {
        var updated = allStates
        updated[documentKey(for: documentURL)] = StoredReaderState(
            pageIndex: max(0, state.pageIndex),
            layout: state.layout.rawValue
        )
        defaults.set(updated.mapValues { ["pageIndex": $0.pageIndex, "layout": $0.layout] }, forKey: storageKey)
    }

    func moveState(from oldURL: URL, to newURL: URL) {
        var updated = allStates
        guard let state = updated.removeValue(forKey: documentKey(for: oldURL)) else { return }
        updated[documentKey(for: newURL)] = state
        defaults.set(updated.mapValues { ["pageIndex": $0.pageIndex, "layout": $0.layout] }, forKey: storageKey)
    }

    func removeState(for documentURL: URL) {
        var updated = allStates
        updated.removeValue(forKey: documentKey(for: documentURL))
        defaults.set(updated.mapValues { ["pageIndex": $0.pageIndex, "layout": $0.layout] }, forKey: storageKey)
    }

    private var allStates: [String: StoredReaderState] {
        defaults.dictionary(forKey: storageKey)?.reduce(into: [:]) { result, entry in
            guard let value = entry.value as? [String: Any],
                  let pageIndex = (value["pageIndex"] as? NSNumber)?.intValue,
                  let layout = value["layout"] as? String else { return }
            result[entry.key] = StoredReaderState(pageIndex: pageIndex, layout: layout)
        } ?? [:]
    }

    private func documentKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private struct StoredReaderState {
        let pageIndex: Int
        let layout: String
    }
}
