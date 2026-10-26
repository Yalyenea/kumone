import Foundation

extension NeteaseAPI {
    /// Social data belongs to a particular login, including renewed logins to
    /// the same account. Reject late results before any view can display them.
    private static func socialRequest<T: Decodable>(_ type: T.Type, _ path: String,
        _ payload: [String: Any] = [:], using client: NeteaseClient = .shared) async throws -> T {
        guard let session = client.authenticationFingerprint else { throw NeteaseAPIError.needLogin }
        let data = try await client.weapi(path, payload)
        guard session == client.authenticationFingerprint else { throw CancellationError() }
        return try client.decoded(type, from: data)
    }

    static func userOverview(uid: Int, using client: NeteaseClient = .shared) async throws -> UserOverview {
        try await socialRequest(UserOverview.self, "/v1/user/detail/\(uid)", using: client)
    }

    static func socialUsers(uid: Int, followers: Bool, cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<UserProfile> {
        struct Response: Decodable { let follow: [UserProfile]?; let followeds: [UserProfile]?; let more: Bool }
        let offset = cursor ?? 0, limit = 30
        let path = followers ? "/user/getfolloweds/\(uid)" : "/user/getfollows/\(uid)"
        let response = try await socialRequest(Response.self, path,
            ["userId": uid, "offset": offset, "limit": limit, "order": true, "time": "0", "getcounts": "true"], using: client)
        let items = followers ? response.followeds : response.follow
        guard let items else { throw NeteaseAPIError.decoding("Missing user list") }
        return .init(items: items, nextCursor: response.more && !items.isEmpty ? offset + items.count : nil)
    }

    static func socialPlaylists(uid: Int, cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<PlaylistSummary> {
        let offset = cursor ?? 0
        let response = try await socialRequest(UserPlaylistsResponse.self, "/user/playlist",
            ["uid": uid, "offset": offset, "limit": 60, "includeVideo": false], using: client)
        return .init(items: response.playlist,
                     nextCursor: response.more == true && !response.playlist.isEmpty ? offset + response.playlist.count : nil)
    }

    static func socialEvents(uid: Int?, cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<SocialEvent> {
        struct Response: Decodable { let events: [SocialEvent]?; let event: [SocialEvent]?; let more: Bool; let lasttime: Int }
        let payload: [String: Any] = uid != nil
            ? ["time": cursor ?? -1, "limit": 30, "getcounts": true, "total": false, "fromRN": "true"]
            : ["lasttime": cursor ?? -1, "pagesize": 30]
        let path = uid.map { "/event/get/\($0)" } ?? "/v1/event/get"
        let response = try await socialRequest(Response.self, path, payload, using: client)
        guard let items = uid != nil ? response.events : response.event else { throw NeteaseAPIError.decoding("Missing events") }
        return .init(items: items, nextCursor: response.more && !items.isEmpty ? response.lasttime : nil)
    }

    static func privateConversations(ownerID: Int, cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<PrivateConversation> {
        struct Response: Decodable { let msgs: [PrivateConversationRecord]; let more: Bool }
        let offset = cursor ?? 0
        let response = try await socialRequest(Response.self, "/msg/private/users",
            ["offset": offset, "limit": 30, "total": "true"], using: client)
        return .init(items: try response.msgs.map { try $0.conversation(ownerID: ownerID) },
                     nextCursor: response.more && !response.msgs.isEmpty ? offset + response.msgs.count : nil)
    }

    static func privateHistory(uid: Int, cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<PrivateMessage> {
        struct Response: Decodable { let msgs: [PrivateMessage]; let more: Bool }
        let response = try await socialRequest(Response.self, "/msg/private/history",
            ["userId": uid, "time": cursor ?? 0, "limit": 30, "total": "true"], using: client)
        return .init(items: response.msgs, nextCursor: response.more ? response.msgs.map { Int($0.time) }.min() : nil)
    }

    static func commentMessages(uid: Int, cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<SocialNotification> {
        struct Response: Decodable { let comments: [CommentNotification]; let more: Bool }
        let response = try await socialRequest(Response.self, "/v1/user/comments/\(uid)",
            ["uid": uid, "beforeTime": cursor ?? -1, "limit": 30, "total": "true"], using: client)
        return .init(items: try response.comments.map { try $0.notification() },
                     nextCursor: response.more ? response.comments.map { Int($0.time) }.min() : nil)
    }

    static func mentionMessages(cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<SocialNotification> {
        struct Response: Decodable { let forwards: [MentionNotification]; let more: Bool }
        let offset = cursor ?? 0
        let response = try await socialRequest(Response.self, "/forwards/get",
            ["offset": offset, "limit": 30, "total": "true"], using: client)
        return .init(items: try response.forwards.map { try $0.notification() },
                     nextCursor: response.more && !response.forwards.isEmpty ? offset + response.forwards.count : nil)
    }

    static func noticeMessages(cursor: Int?, using client: NeteaseClient = .shared) async throws -> SocialPage<SocialNotification> {
        struct Response: Decodable { let notices: [NoticeNotification]; let more: Bool; let lastTime: Int }
        let response = try await socialRequest(Response.self, "/msg/notices", ["time": cursor ?? -1, "limit": 30], using: client)
        return .init(items: try response.notices.map { try $0.notification() },
                     nextCursor: response.more && !response.notices.isEmpty ? response.lastTime : nil)
    }

    static func messageCounts(using client: NeteaseClient = .shared) async throws -> MessageCounts {
        try await socialRequest(MessageCounts.self, "/pl/count", using: client)
    }
}
