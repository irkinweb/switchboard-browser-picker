import Foundation

public enum LinkCleaner {
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "li_fat_id", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok", "igshid", "vero_id", "vero_conv",
        "oly_anon_id", "oly_enc_id", "rb_clickid", "_openstat", "srsltid", "ga_source", "ga_medium",
        "ga_campaign", "ga_content", "ga_term",
    ]

    static let trackingPrefixes = ["utm_"]

    static let siteParameters: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature"],
        "youtu.be": ["si", "feature"],
        "instagram.com": ["igsh"],
        "spotify.com": ["si"],
        "twitter.com": ["ref_src", "ref_url", "s", "t"],
        "x.com": ["ref_src", "ref_url", "s", "t"],
        "linkedin.com": ["trk", "trackingid", "lipi"],
    ]

    static let redirectWrappers: [(host: String, path: String?, parameter: String)] = [
        ("safelinks.protection.outlook.com", nil, "url"),
        ("google.com", "/url", "q"),
        ("google.com", "/url", "url"),
        ("l.facebook.com", "/l.php", "u"),
        ("lm.facebook.com", "/l.php", "u"),
        ("l.instagram.com", nil, "u"),
        ("linkedin.com", "/redir/redirect", "url"),
        ("slack-redir.net", "/link", "url"),
        ("youtube.com", "/redirect", "q"),
        ("l.messenger.com", "/l.php", "u"),
    ]

    public static func clean(_ url: URL) -> URL {
        stripTracking(unwrap(url))
    }

    static func unwrap(_ url: URL, depth: Int = 0) -> URL {
        guard depth < 4,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased()
        else { return url }
        for wrapper in redirectWrappers where Rule.host(host, isWithin: wrapper.host) {
            if let path = wrapper.path, components.path != path { continue }
            guard
                let value = components.queryItems?.first(where: { $0.name == wrapper.parameter })?.value,
                let target = URL(string: value),
                let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https",
                target.host != nil
            else { continue }
            return unwrap(target, depth: depth + 1)
        }
        return url
    }

    static func stripTracking(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty
        else { return url }
        let host = components.host?.lowercased() ?? ""
        let siteSpecific = siteParameters.first { Rule.host(host, isWithin: $0.key) }?.value ?? []
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !trackingParameters.contains(name)
                && !siteSpecific.contains(name)
                && !trackingPrefixes.contains(where: name.hasPrefix)
        }
        guard kept.count != items.count else { return url }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }
}
