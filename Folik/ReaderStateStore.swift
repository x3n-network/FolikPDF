import Foundation

nonisolated struct ReaderState: Equatable, Sendable {
    var pageIndex: Int
    var layout: ReaderLayout
}

nonisolated struct LibraryResume: Equatable {
    let document: LibraryDocument
    let pageIndex: Int
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
        let key = documentKey(for: documentURL)
        let previous = updated[key]
        updated[key] = StoredReaderState(
            pageIndex: max(0, state.pageIndex), layout: state.layout.rawValue,
            lastOpened: previous?.lastOpened, resumeDismissed: previous?.resumeDismissed ?? false
        )
        persist(updated)
    }

    func markOpened(_ documentURL: URL, at date: Date = Date()) {
        var updated = allStates
        let key = documentKey(for: documentURL)
        var state = updated[key] ?? StoredReaderState(pageIndex: 0, layout: ReaderLayout.continuous.rawValue)
        state.lastOpened = date
        state.resumeDismissed = false
        updated[key] = state
        persist(updated)
    }

    func mostRecent(in documents: [LibraryDocument]) -> LibraryResume? {
        let states = allStates
        let recent = documents.compactMap { document -> (LibraryDocument, StoredReaderState)? in
            guard let state = states[documentKey(for: document.url)], state.lastOpened != nil else { return nil }
            return (document, state)
        }.max { ($0.1.lastOpened ?? .distantPast) < ($1.1.lastOpened ?? .distantPast) }
        guard let (document, state) = recent, !state.resumeDismissed else { return nil }
        return LibraryResume(document: document, pageIndex: min(max(0, state.pageIndex), max(0, document.pageCount - 1)))
    }

    func dismissResume(for documentURL: URL) {
        var updated = allStates
        let key = documentKey(for: documentURL)
        guard var state = updated[key] else { return }
        state.resumeDismissed = true
        updated[key] = state
        persist(updated)
    }

    func moveState(from oldURL: URL, to newURL: URL) {
        var updated = allStates
        guard let state = updated.removeValue(forKey: documentKey(for: oldURL)) else { return }
        updated[documentKey(for: newURL)] = state
        persist(updated)
    }

    func snapshot(for url: URL) -> StoredReaderState? { allStates[documentKey(for: url)] }

    func restore(_ snapshot: StoredReaderState?, for url: URL) {
        var updated = allStates
        updated[documentKey(for: url)] = snapshot
        persist(updated)
    }

    func removeState(for documentURL: URL) {
        var updated = allStates
        updated.removeValue(forKey: documentKey(for: documentURL))
        persist(updated)
    }

    private var allStates: [String: StoredReaderState] {
        defaults.dictionary(forKey: storageKey)?.reduce(into: [:]) { result, entry in
            guard let value = entry.value as? [String: Any],
                  let pageIndex = (value["pageIndex"] as? NSNumber)?.intValue,
                  let layout = value["layout"] as? String else { return }
            result[entry.key] = StoredReaderState(
                pageIndex: pageIndex, layout: layout,
                lastOpened: (value["lastOpened"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) },
                resumeDismissed: value["resumeDismissed"] as? Bool ?? false
            )
        } ?? [:]
    }

    private func persist(_ states: [String: StoredReaderState]) {
        defaults.set(states.mapValues { state -> [String: Any] in
            var value: [String: Any] = ["pageIndex": state.pageIndex, "layout": state.layout, "resumeDismissed": state.resumeDismissed]
            if let opened = state.lastOpened { value["lastOpened"] = opened.timeIntervalSince1970 }
            return value
        }, forKey: storageKey)
    }

    private func documentKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    struct StoredReaderState: Codable, Equatable, Sendable {
        var pageIndex: Int
        var layout: String
        var lastOpened: Date? = nil
        var resumeDismissed = false
    }
}
