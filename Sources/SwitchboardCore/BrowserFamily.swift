import Foundation

public struct BrowserProfile: Equatable {
    public let directory: String
    public let name: String
}

public enum BrowserFamily {
    public static let chromiumSupportPaths: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "com.operasoftware.Opera",
        "org.chromium.Chromium": "Chromium",
        "net.imput.helium": "net.imput.helium",
    ]

    public static let firefoxBundleIDs: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "app.zen-browser.zen",
        "net.waterfox.waterfox",
        "net.mullvad.mullvadbrowser",
    ]

    public static func isChromium(_ bundleID: String) -> Bool {
        chromiumSupportPaths[bundleID] != nil
    }

    public static func launchFlags(for target: Target) -> [String] {
        var flags: [String] = []
        if isChromium(target.browser) {
            if let profile = target.profile { flags.append("--profile-directory=\(profile)") }
            if target.privateWindow == true { flags.append("--incognito") }
        } else if firefoxBundleIDs.contains(target.browser) {
            if let profile = target.profile { flags += ["-P", profile] }
            if target.privateWindow == true { flags.append("--private-window") }
        }
        return flags
    }

    public static func chromiumProfiles(localState: Data) -> [BrowserProfile] {
        guard
            let root = try? JSONSerialization.jsonObject(with: localState) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: Any]
        else { return [] }
        return cache.compactMap { directory, value -> BrowserProfile? in
            guard let info = value as? [String: Any] else { return nil }
            let name = (info["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory
            return BrowserProfile(directory: directory, name: name)
        }
        .sorted { lhs, rhs in
            if lhs.directory == "Default" { return true }
            if rhs.directory == "Default" { return false }
            return lhs.directory.localizedStandardCompare(rhs.directory) == .orderedAscending
        }
    }
}
