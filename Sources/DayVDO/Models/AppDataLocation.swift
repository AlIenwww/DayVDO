import Foundation

/// Compatibility builds must also be isolated in Release and on another Mac.
enum AppDataLocation {
    static func isolatedTestingURL(bundleIdentifier: String?, enabled: Bool, applicationSupport: URL) -> URL? {
        guard enabled, let bundleIdentifier,
              bundleIdentifier.hasPrefix("com.wuyuchen.DayVDO.CompatibilityTest."),
              !bundleIdentifier.contains("/"), !bundleIdentifier.contains("\\") else { return nil }
        return applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("todos.json")
    }
}
