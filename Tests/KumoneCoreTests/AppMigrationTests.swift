import Foundation
import Testing
@testable import KumoneCore

@Suite("Liltiva preference migration")
struct AppMigrationTests {
    @Test func importsSettingsShortcutsAndSyncAuthorizationWithoutReplacingNewValues() throws {
        let legacy = "liltiva-migration-old-\(UUID())"
        let current = "liltiva-migration-new-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: current))
        defer {
            defaults.removePersistentDomain(forName: legacy)
            defaults.removePersistentDomain(forName: current)
        }
        let shortcutData = Data([1, 2, 3])
        let bookmark = Data([4, 5, 6])
        defaults.setPersistentDomain([
            "settings.appearance": "dark", "settings.volume": 0.7,
            "settings.showDesktopLyrics": true, "shortcuts": shortcutData,
            "sync.directoryBookmark": bookmark
        ], forName: legacy)
        defaults.setPersistentDomain([
            "settings.volume": 0.0, "settings.showDesktopLyrics": false
        ], forName: current)

        AppMigration.migratePreferences(in: defaults, from: legacy, to: current)

        #expect(defaults.string(forKey: "settings.appearance") == "dark")
        #expect(defaults.double(forKey: "settings.volume") == 0)
        #expect(!defaults.bool(forKey: "settings.showDesktopLyrics"))
        #expect(defaults.data(forKey: "shortcuts") == shortcutData)
        #expect(defaults.data(forKey: "sync.directoryBookmark") == bookmark)
        #expect(defaults.persistentDomain(forName: legacy)?["settings.volume"] as? Double == 0.7)
    }

    @Test func doesNotRestoreRemovedPreferencesOnSubsequentLaunches() throws {
        let legacy = "liltiva-migration-old-\(UUID())"
        let current = "liltiva-migration-new-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: current))
        defer {
            defaults.removePersistentDomain(forName: legacy)
            defaults.removePersistentDomain(forName: current)
        }
        defaults.setPersistentDomain(["settings.appearance": "dark"], forName: legacy)
        AppMigration.migratePreferences(in: defaults, from: legacy, to: current)
        defaults.removeObject(forKey: "settings.appearance")
        AppMigration.migratePreferences(in: defaults, from: legacy, to: current)

        #expect(defaults.object(forKey: "settings.appearance") == nil)
        #expect(defaults.bool(forKey: AppMigration.preferencesMarker))
    }

    @Test func freshInstallCompletesWithoutImportingAnotherApplicationsDomain() throws {
        let legacy = "liltiva-migration-absent-\(UUID())"
        let current = "liltiva-migration-new-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: current))
        defer { defaults.removePersistentDomain(forName: current) }

        AppMigration.migratePreferences(in: defaults, from: legacy, to: current)

        let result = try #require(defaults.persistentDomain(forName: current))
        #expect(result.count == 1)
        #expect(result[AppMigration.preferencesMarker] as? Bool == true)
    }
}
