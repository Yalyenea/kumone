import Foundation
import Testing
@testable import KumoneCore

@Suite("Social payloads")
struct SocialDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func profileContainsCountsWithoutBreakingOlderSnapshots() throws {
        let old = try decode(UserProfile.self, "{\"userId\":1,\"nickname\":\"Listener\"}")
        #expect(old.follows == nil)
        let overview = try decode(UserOverview.self, """
        {"profile":{"userId":1,"nickname":"Listener","follows":12,"followeds":4,"eventCount":2},
         "level":7,"listenSongs":1234,"peopleCanSeeMyPlayRecord":false}
        """)
        #expect(overview.profile.follows == 12 && overview.profile.followeds == 4)
        #expect(overview.peopleCanSeeMyPlayRecord == false)
        let restored = try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(overview.profile))
        #expect(restored == overview.profile)
    }

    @Test func encodedSharesAndForwardedPostsDecode() throws {
        let content = try #require(try SocialContent.parse("{\"msg\":\"Listen to this\",\"song\":{\"id\":42,\"name\":\"Song\"}}"))
        #expect(content.text == "Listen to this" && content.resource?.id == 42)
        #expect(content.resourceKind == .song)
        let post = try decode(SocialEvent.self, #"{"id":2,"user":{"userId":1},"eventTime":1800000000000,"json":"{\"msg\":\"Forward\",\"event\":{\"json\":\"{\\\"msg\\\":\\\"Original\\\"}\"}}"}"#)
        #expect(post.payload?.text == "Forward")
        #expect(post.forwardedContent?.text == "Original")
        let unsupported = try #require(try SocialContent.parse("{\"unknownKind\":{\"id\":12}}"))
        #expect(!unsupported.text.isEmpty)
        #expect(throws: DecodingError.self) { _ = try SocialContent.parse("not json") }
    }

    @Test func conversationsResolveTheOtherParticipant() throws {
        let record = try decode(PrivateConversationRecord.self, #"{"fromUser":{"userId":1,"nickname":"Me"},"toUser":{"userId":2,"nickname":"Peer"},"lastMsg":"{\"msg\":\"hello\"}","lastMsgTime":1800000000000,"newMsgCount":3}"#)
        let sent = try record.conversation(ownerID: 1)
        #expect(sent.id == 2 && sent.unread == 3 && sent.content?.text == "hello")
        let received = try record.conversation(ownerID: 2)
        #expect(received.id == 1)
    }

    @Test func commentContextAndResourceTypesArePreserved() throws {
        let comment = try decode(CommentNotification.self, #"{"commentId":3,"combindId":"reply:3","user":{"userId":2},"time":1800000000000,"content":"Reply","beRepliedContent":"Original","resourceJson":"{\"resourceType\":3,\"id\":7,\"name\":\"Album\"}"}"#)
        let notice = try comment.notification()
        #expect(notice.id == "reply:3" && notice.context == "Original")
        #expect(notice.resource?.id == 7 && notice.resourceKind == .album)
    }

    @Test func privateMessageHistoryKeepsItsAuthorAndMusicShare() throws {
        let message = try decode(PrivateMessage.self, #"{"id":8,"fromUser":{"userId":2},"time":1800000000000,"msg":"{\"msg\":\"hello\",\"playlist\":{\"id\":9,\"name\":\"Mix\"}}"}"#)
        #expect(message.id == 8 && message.fromUser.id == 2)
        #expect(message.content?.resourceKind == .playlist)
    }

    @Test func noticesRenderTheirActualContentAndQuotedComment() throws {
        let comment = try decode(NoticeNotification.self, #"{"id":1,"time":1800000000000,"notice":"{\"type\":6,\"user\":{\"userId\":2},\"comment\":{\"content\":\"My original comment\"}}"}"#)
        let item = try comment.notification()
        #expect(item.context == "My original comment" && item.user?.id == 2)
        let general = try decode(NoticeNotification.self, #"{"id":2,"time":1800000000000,"notice":"{\"type\":10,\"generalNotice\":{\"actionDesc\":\"Activity\",\"content\":\"Details\"}}"}"#)
        #expect(try general.notification().text == "Activity\nDetails")
        let playlist = try decode(NoticeNotification.self, #"{"id":3,"time":1800000000000,"notice":"{\"type\":2,\"playlist\":{\"id\":42,\"name\":\"My mix\"}}"}"#)
        #expect(try playlist.notification().resourceKind == .playlist)
    }
}

@MainActor private final class SocialTestSession { var value: String? = "account-a" }
private struct SocialTestItem: Identifiable { let id: Int }
private actor SocialResponseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}

@Suite("Social account isolation")
struct SocialStateTests {
    @Test @MainActor func paginationDeduplicatesAndStopsAtTheEnd() async {
        let session = SocialTestSession()
        var cursors: [Int?] = []
        let model = SocialPageModel<SocialTestItem>(session: { session.value }) { cursor in
            cursors.append(cursor)
            return cursor == nil ? .init(items: [.init(id: 1), .init(id: 2)], nextCursor: 20)
                : .init(items: [.init(id: 2), .init(id: 3)], nextCursor: nil)
        }
        await model.refresh()
        await model.loadMore()
        await model.loadMore()
        #expect(model.items.map(\.id) == [1, 2, 3])
        #expect(cursors.count == 2 && cursors[1] == 20 && !model.hasMore)
    }

    @Test @MainActor func retryRetainsLoadedItemsAndTheFailedCursor() async {
        let session = SocialTestSession()
        var failed = false
        let model = SocialPageModel<SocialTestItem>(session: { session.value }) { cursor in
            if cursor == 20, !failed { failed = true; throw URLError(.notConnectedToInternet) }
            return .init(items: [.init(id: cursor == nil ? 1 : 2)], nextCursor: cursor == nil ? 20 : nil)
        }
        await model.refresh()
        await model.loadMore()
        #expect(model.error != nil && model.items.map(\.id) == [1] && !model.isLoading)
        await model.loadMore()
        #expect(model.error == nil && model.items.map(\.id) == [1, 2])
    }

    @Test @MainActor func lateAccountResponseCannotReplaceNewAccountData() async {
        let session = SocialTestSession(), gate = SocialResponseGate()
        var request = 0
        let model = SocialPageModel<SocialTestItem>(session: { session.value }) { _ in
            request += 1
            let first = request == 1
            if first { await gate.wait() }
            return .init(items: [.init(id: first ? 1 : 2)], nextCursor: nil)
        }
        let old = Task { await model.refresh() }
        for _ in 0..<100 { if await gate.entered { break }; await Task.yield() }
        session.value = "account-b"
        await model.refresh()
        await gate.open()
        await old.value
        #expect(model.items.map(\.id) == [2] && model.session == "account-b")
        session.value = nil
        model.reset()
        #expect(model.items.isEmpty && !model.hasLoaded)
    }

    @Test @MainActor func repeatedCursorCannotLoopForever() async {
        let session = SocialTestSession()
        let model = SocialPageModel<SocialTestItem>(session: { session.value }) { cursor in
            .init(items: [.init(id: cursor == nil ? 1 : 2)], nextCursor: 20)
        }
        await model.refresh()
        await model.loadMore()
        #expect(!model.hasMore)
    }

    @Test @MainActor func unreadCountsDisappearAsSoonAsTheLoginChanges() async throws {
        let session = SocialTestSession()
        let counts = try JSONDecoder().decode(MessageCounts.self, from: Data("{\"msg\":2,\"comment\":1,\"forward\":0,\"notice\":3,\"follow\":1}".utf8))
        let model = MessageCenterStore(session: { session.value }, load: { counts })
        await model.refresh()
        #expect(model.unread == 7)
        session.value = "account-b"
        #expect(model.unread == 0 && model.currentCounts == nil)
        session.value = nil
        await model.refresh()
        #expect(model.counts == nil && !model.isLoading)
    }
}

@Suite("Live social API")
struct SocialLiveTests {
    private struct SanitizedProbeError: Error, CustomStringConvertible {
        let domain: String
        let code: Int
        var description: String { "Social probe failed: \(domain) \(code); account content omitted" }
    }
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KUMONE_LIVE_SOCIAL_PROBE"] == "1"))
    func existingSessionDecodesProfilesListsAndMessages() async throws {
        let url = KumonePaths.applicationSupport.appendingPathComponent("cookies.json")
        let original = try Data(contentsOf: url)
        let cookies = try JSONDecoder().decode([String: String].self, from: original)
        let client = NeteaseClient(configuration: .ephemeral, persistsCookies: false)
        client.setCookies(cookies.filter { !$0.key.hasPrefix("__kumone") })
        defer {
            let unchanged = (try? Data(contentsOf: url)) == original
            #expect(unchanged)
        }
        do {
            let profile = try #require(try await NeteaseAPI.userAccount(using: client))
            _ = try await NeteaseAPI.userOverview(uid: profile.userId, using: client)
            _ = try await NeteaseAPI.socialUsers(uid: profile.userId, followers: false, cursor: nil, using: client)
            _ = try await NeteaseAPI.socialUsers(uid: profile.userId, followers: true, cursor: nil, using: client)
            _ = try await NeteaseAPI.socialPlaylists(uid: profile.userId, cursor: nil, using: client)
            _ = try await NeteaseAPI.socialEvents(uid: profile.userId, cursor: nil, using: client)
            _ = try await NeteaseAPI.socialEvents(uid: nil, cursor: nil, using: client)
            _ = try await NeteaseAPI.privateConversations(ownerID: profile.userId, cursor: nil, using: client)
            _ = try await NeteaseAPI.commentMessages(uid: profile.userId, cursor: nil, using: client)
            _ = try await NeteaseAPI.mentionMessages(cursor: nil, using: client)
            _ = try await NeteaseAPI.noticeMessages(cursor: nil, using: client)
            _ = try await NeteaseAPI.messageCounts(using: client)
            print("Live social API: profile, following, followers, playlists, posts, feed and all message categories decoded")
        } catch {
            let error = error as NSError
            throw SanitizedProbeError(domain: error.domain, code: error.code)
        }
    }
}
