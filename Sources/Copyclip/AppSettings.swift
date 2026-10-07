import AppKit
import Foundation

struct IgnoredApp: Codable, Hashable {
    let bundleID: String
    let name: String
}

final class AppSettings {
    static let menuLimitChoices = [5, 10, 15, 20, 30, 50]
    static let historyLimitChoices = [0, 50, 100, 250, 500, 1000, 5000]

    private let defaults: UserDefaults
    private let prefix = "app.copyclip."

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Copies settings saved under the bundle identifier used before version 1.3.0, once.
    func migrateLegacyDefaults(from domain: String = "app.copyclip.local") {
        let migratedKey = prefix + "migratedLegacyDefaults"
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        guard let legacy = defaults.persistentDomain(forName: domain) else { return }
        for (key, value) in legacy where key.hasPrefix(prefix) && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    var privateModeEnabled: Bool {
        get { defaults.bool(forKey: prefix + "privateModeEnabled") }
        set {
            defaults.set(newValue, forKey: prefix + "privateModeEnabled")
            defaults.synchronize()
        }
    }

    var menuLimit: Int {
        get {
            guard let saved = defaults.object(forKey: prefix + "menuLimit") as? Int,
                  Self.menuLimitChoices.contains(saved) else { return 15 }
            return saved
        }
        set { defaults.set(newValue, forKey: prefix + "menuLimit") }
    }

    var historyLimit: Int {
        get {
            // A saved 0 means Unlimited, so only a missing value falls back to the default.
            guard let saved = defaults.object(forKey: prefix + "historyLimit") as? Int,
                  Self.historyLimitChoices.contains(saved) else { return 100 }
            return saved
        }
        set { defaults.set(newValue, forKey: prefix + "historyLimit") }
    }

    var ignoredApps: [IgnoredApp] {
        get {
            guard let data = defaults.data(forKey: prefix + "ignoredApps") else { return [] }
            return (try? PropertyListDecoder().decode([IgnoredApp].self, from: data)) ?? []
        }
        set {
            if let data = try? PropertyListEncoder().encode(newValue) {
                defaults.set(data, forKey: prefix + "ignoredApps")
            }
        }
    }

    func ignores(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredApps.contains { $0.bundleID == bundleID }
    }

    @discardableResult
    func addIgnoredApp(at url: URL) -> Bool {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return false }
        var apps = ignoredApps
        guard !apps.contains(where: { $0.bundleID == bundleID }) else { return true }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        apps.append(IgnoredApp(bundleID: bundleID, name: name))
        apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        ignoredApps = apps
        return true
    }

    func removeIgnoredApp(bundleID: String) {
        ignoredApps = ignoredApps.filter { $0.bundleID != bundleID }
    }
}
