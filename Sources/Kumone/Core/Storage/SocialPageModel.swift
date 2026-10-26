import Combine
import Foundation

/// A bounded page of account data. Both the request generation and login
/// binding are checked after suspension, so a late reply cannot repopulate a
/// page after sign-out, account switching, or refresh.
@MainActor
final class SocialPageModel<Item: Identifiable>: ObservableObject {
    typealias Loader = (Int?) async throws -> SocialPage<Item>
    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasLoaded = false
    @Published private(set) var hasMore = false
    private(set) var session: String?
    private var nextCursor: Int?
    private var generation = 0
    private let currentSession: @MainActor () -> String?
    private let loader: Loader

    init(session: @escaping @MainActor () -> String? = { AccountStore.shared.socialSession }, load: @escaping Loader) {
        currentSession = session
        loader = load
    }

    func reset() {
        generation += 1
        session = currentSession()
        items = []
        nextCursor = nil
        hasMore = false
        hasLoaded = false
        error = nil
        isLoading = false
    }

    func refresh() async {
        reset()
        await loadMore()
    }

    func loadMore() async {
        guard let binding = currentSession(), !isLoading else { return }
        if session != binding { reset() }
        guard !hasLoaded || hasMore else { return }
        let ticket = generation
        let cursor = nextCursor
        isLoading = true
        error = nil
        defer { if ticket == generation { isLoading = false } }
        do {
            let page = try await loader(cursor)
            guard ticket == generation, binding == currentSession(), !Task.isCancelled else { return }
            var seen = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
            nextCursor = page.nextCursor
            // A server repeating its cursor must not create an endless load loop.
            hasMore = !page.items.isEmpty && page.nextCursor != nil && page.nextCursor != cursor
            hasLoaded = true
        } catch {
            guard ticket == generation, binding == currentSession(), !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

@MainActor
final class MessageCenterStore: ObservableObject {
    static let shared = MessageCenterStore()
    @Published private(set) var counts: MessageCounts?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false
    private var session: String?
    private var generation = 0
    private let currentSession: @MainActor () -> String?
    private let loader: () async throws -> MessageCounts

    var unread: Int { session == currentSession() ? counts?.total ?? 0 : 0 }
    var currentCounts: MessageCounts? { session == currentSession() ? counts : nil }

    init(session: @escaping @MainActor () -> String? = { AccountStore.shared.socialSession },
         load: @escaping () async throws -> MessageCounts = { try await NeteaseAPI.messageCounts() }) {
        currentSession = session
        loader = load
    }

    func reset() {
        generation += 1
        session = currentSession()
        counts = nil
        error = nil
        isLoading = false
    }

    func refresh() async {
        if session != currentSession() { reset() }
        guard let binding = currentSession(), !isLoading else { return }
        let ticket = generation
        isLoading = true
        defer { if ticket == generation { isLoading = false } }
        do {
            let counts = try await loader()
            guard ticket == generation, binding == currentSession(), !Task.isCancelled else { return }
            self.counts = counts
            error = nil
        } catch {
            guard ticket == generation, binding == currentSession(), !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
