import CryptoKit
import Foundation

extension NeteaseAPI {
    static func aiSoundEffect(songID: Int, using client: NeteaseClient = .shared,
                              assets: URLSession = .shared) async throws -> AISoundEffect? {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Asset: Decodable { let url: URL; let md5: String; let size: Int }
                let id: Int
                let effect: Asset?
            }
            let data: [Item]
        }
        guard let session = client.authenticationFingerprint else { throw NeteaseAPIError.needLogin }
        let data = try await client.weapi("/vip-rights/svip/sound/effect/get", ["songIds": [songID]],
                                          absorbResponseCookies: false)
        let response = try client.decoded(Response.self, from: data)
        guard session == client.authenticationFingerprint else { throw CancellationError() }
        guard let asset = response.data.first(where: { $0.id == songID })?.effect else { return nil }
        guard asset.size > 0, asset.size <= NCAEContainer.maximumPackageBytes,
              var components = URLComponents(url: asset.url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""), components.host != nil
        else { throw NCAEContainer.DecodingError.invalidHeader }
        // The official API still returns HTTP asset URLs. The same CDN path
        // supports HTTPS, just like song downloads; keep transport security on.
        components.scheme = "https"
        guard let url = components.url else { throw NCAEContainer.DecodingError.invalidHeader }
        let (package, download) = try await assets.data(from: url)
        guard session == client.authenticationFingerprint else { throw CancellationError() }
        try Task.checkCancellation()
        guard (download as? HTTPURLResponse)?.statusCode == 200, package.count == asset.size,
              Insecure.MD5.hash(data: package).map({ String(format: "%02x", $0) }).joined() == asset.md5.lowercased()
        else { throw NCAEContainer.DecodingError.invalidPayload }
        return try AISoundEffect.decode(package: package)
    }
}

/// Account-scoped parameter cache. Only an active SVIP session may read it;
/// the player checks that entitlement before and after asynchronous work.
actor AISoundEffectStore {
    static let shared = AISoundEffectStore()
    private struct Entry: Codable { let fetchedAt: Date; let effect: AISoundEffect }
    private let directory: URL

    init(directory: URL = KumoneDirectories.caches("AISoundEffects")) { self.directory = directory }

    func effect(songID: Int, accountID: Int, offline: Bool, refresh: Bool = false,
                client: NeteaseClient = .shared) async throws -> AISoundEffect? {
        let folder = directory.appendingPathComponent(String(accountID), isDirectory: true)
        let file = folder.appendingPathComponent("\(songID).json")
        if (!refresh || offline), let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode(Entry.self, from: data),
           offline || Date().timeIntervalSince(cached.fetchedAt) < 7 * 86_400 {
            try cached.effect.validate()
            return cached.effect
        }
        guard !offline else { return nil }
        guard let effect = try await NeteaseAPI.aiSoundEffect(songID: songID, using: client) else { return nil }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Entry(fetchedAt: .now, effect: effect)).write(to: file, options: .atomic)
        // Tiny parameter documents still need a bound when a large library is played.
        let entries = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]).filter { $0.pathExtension == "json" }
        if entries.count > 256 {
            let oldest = entries.sorted {
                ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            }
            for old in oldest.prefix(entries.count - 256) { try FileManager.default.removeItem(at: old) }
        }
        return effect
    }
}
