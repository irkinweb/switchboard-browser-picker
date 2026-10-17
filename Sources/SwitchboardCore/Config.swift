import Foundation

public struct Target: Codable, Equatable, Hashable {
    public var browser: String
    public var profile: String?
    public var privateWindow: Bool?

    public init(browser: String, profile: String? = nil, privateWindow: Bool? = nil) {
        self.browser = browser
        self.profile = profile
        self.privateWindow = privateWindow
    }

    enum CodingKeys: String, CodingKey {
        case browser, profile
        case privateWindow = "private"
    }
}

public struct Rule: Codable, Equatable {
    public var hosts: [String]?
    public var urlPattern: String?
    public var sourceApps: [String]?
    public var open: Target

    public init(hosts: [String]? = nil, urlPattern: String? = nil, sourceApps: [String]? = nil, open: Target) {
        self.hosts = hosts
        self.urlPattern = urlPattern
        self.sourceApps = sourceApps
        self.open = open
    }

    public func matches(url: URL, sourceApp: String?) -> Bool {
        guard hosts != nil || urlPattern != nil || sourceApps != nil else { return false }
        if let hosts {
            guard let host = url.host?.lowercased(), hosts.contains(where: { Rule.host(host, isWithin: $0) }) else { return false }
        }
        if let urlPattern {
            guard url.absoluteString.range(of: urlPattern, options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        }
        if let sourceApps {
            guard let sourceApp, sourceApps.contains(where: { $0.caseInsensitiveCompare(sourceApp) == .orderedSame }) else { return false }
        }
        return true
    }

    static func host(_ host: String, isWithin domain: String) -> Bool {
        let domain = domain.lowercased()
        return host == domain || host.hasSuffix("." + domain)
    }

    public static func normalizedHost(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let host = trimmed.contains("://")
            ? URL(string: trimmed)?.host
            : trimmed.split(separator: "/").first.map(String.init)
        guard var host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

public struct Config: Codable, Equatable {
    public var defaultTarget: Target?
    public var rules: [Rule]
    public var hiddenBrowsers: [String]

    public static let empty = Config()

    public init(defaultTarget: Target? = nil, rules: [Rule] = [], hiddenBrowsers: [String] = []) {
        self.defaultTarget = defaultTarget
        self.rules = rules
        self.hiddenBrowsers = hiddenBrowsers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultTarget = try container.decodeIfPresent(Target.self, forKey: .defaultTarget)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        hiddenBrowsers = try container.decodeIfPresent([String].self, forKey: .hiddenBrowsers) ?? []
    }

    public func target(for url: URL, sourceApp: String?) -> Target? {
        rules.first { $0.matches(url: url, sourceApp: sourceApp) }?.open
    }

    public mutating func remember(host: String, target: Target) {
        guard let host = Rule.normalizedHost(host) else { return }
        rules.removeAll { $0.hosts == [host] && $0.urlPattern == nil && $0.sourceApps == nil }
        rules.insert(Rule(hosts: [host], open: target), at: 0)
    }
}
