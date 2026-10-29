import Foundation

/// Run before SwiftUI constructs the player and settings singletons, so their
/// first reads already see the preferences stored under the previous app ID.
public enum AppMigration {
    static let preferencesMarker = "migration.kumonePreferences.v1"

    public static func prepareForLaunch() {
        guard Bundle.main.bundleIdentifier == "io.github.yalyenea.Liltiva" else { return }
        migratePreferences(in: .standard, from: "im.missuo.Kumone", to: "io.github.yalyenea.Liltiva")
    }

    static func migratePreferences(in defaults: UserDefaults, from legacyDomain: String, to domain: String) {
        let current = defaults.persistentDomain(forName: domain) ?? [:]
        guard current[preferencesMarker] as? Bool != true else { return }
        let legacy = defaults.persistentDomain(forName: legacyDomain) ?? [:]
        // Existing Liltiva values win, including explicit false/zero values.
        // Keep the old domain intact, and never reimport deliberately reset keys.
        var migrated = legacy.merging(current) { _, current in current }
        migrated[preferencesMarker] = true
        defaults.setPersistentDomain(migrated, forName: domain)
    }
}
