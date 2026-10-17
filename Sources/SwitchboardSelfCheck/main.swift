import Foundation
import SwitchboardCore

var failures = 0

func check(_ condition: Bool, _ name: String) {
    if !condition {
        failures += 1
        print("FAIL: \(name)")
    }
}

let chrome = Target(browser: "com.google.Chrome")
let work = Target(browser: "com.google.Chrome", profile: "Profile 1")
let safari = Target(browser: "com.apple.Safari")

let hostRule = Rule(hosts: ["google.com"], open: chrome)
check(hostRule.matches(url: URL(string: "https://meet.google.com/abc")!, sourceApp: nil), "subdomain matches host rule")
check(hostRule.matches(url: URL(string: "https://GOOGLE.com")!, sourceApp: nil), "host rule is case-insensitive")
check(!hostRule.matches(url: URL(string: "https://notgoogle.com")!, sourceApp: nil), "suffix without dot does not match")

let patternRule = Rule(urlPattern: "github\\.com/acme-", open: work)
check(patternRule.matches(url: URL(string: "https://github.com/acme-corp/app")!, sourceApp: nil), "url pattern matches")
check(!patternRule.matches(url: URL(string: "https://github.com/morluto/rea")!, sourceApp: nil), "url pattern rejects other paths")

let slackRule = Rule(hosts: ["zoom.us"], sourceApps: ["com.tinyspeck.slackmacgap"], open: safari)
check(slackRule.matches(url: URL(string: "https://zoom.us/j/1")!, sourceApp: "com.tinyspeck.slackmacgap"), "all conditions match")
check(!slackRule.matches(url: URL(string: "https://zoom.us/j/1")!, sourceApp: nil), "missing source app fails source rule")
check(!Rule(open: chrome).matches(url: URL(string: "https://x.com")!, sourceApp: nil), "rule without conditions never matches")

let config = Config(defaultTarget: safari, rules: [patternRule, hostRule])
check(config.target(for: URL(string: "https://github.com/acme-corp/app")!, sourceApp: nil) == work, "first matching rule wins")
check(config.target(for: URL(string: "https://example.com")!, sourceApp: nil) == nil, "no rule leaves target to the default")

let json = #"{"rules":[{"hosts":["notion.so"],"open":{"browser":"com.brave.Browser","profile":"Default","private":true}}]}"#
let decoded = try! JSONDecoder().decode(Config.self, from: Data(json.utf8))
check(decoded.rules.first?.open == Target(browser: "com.brave.Browser", profile: "Default", privateWindow: true), "config decodes with missing keys")
check(decoded.hiddenBrowsers.isEmpty && decoded.defaultTarget == nil, "missing keys fall back to empty")

check(BrowserFamily.launchFlags(for: Target(browser: "com.google.Chrome", profile: "Profile 2", privateWindow: true)) == ["--profile-directory=Profile 2", "--incognito"], "chromium flags")
check(BrowserFamily.launchFlags(for: Target(browser: "org.mozilla.firefox", privateWindow: true)) == ["--private-window"], "firefox private flag")
check(BrowserFamily.launchFlags(for: Target(browser: "com.apple.Safari", privateWindow: true)).isEmpty, "safari takes no flags")

let localState = #"{"profile":{"info_cache":{"Profile 10":{"name":"Side Project"},"Profile 2":{"name":"Work"},"Default":{"name":"Personal"}}}}"#
let profiles = BrowserFamily.chromiumProfiles(localState: Data(localState.utf8))
check(profiles.map(\.directory) == ["Default", "Profile 2", "Profile 10"], "profiles sort Default first then naturally")
check(profiles.map(\.name) == ["Personal", "Work", "Side Project"], "profile display names")
check(BrowserFamily.chromiumProfiles(localState: Data("nope".utf8)).isEmpty, "bad Local State yields no profiles")

check(Rule.normalizedHost("https://www.GitHub.com/morluto/rea") == "github.com", "pasted URL normalizes to host")
check(Rule.normalizedHost(" notion.so/page ") == "notion.so", "bare host with path normalizes")
check(Rule.normalizedHost("   ") == nil, "blank host is rejected")

var remembering = Config(rules: [hostRule, Rule(hosts: ["github.com"], open: safari)])
remembering.remember(host: "www.github.com", target: work)
check(remembering.rules.count == 2, "remembering replaces the plain rule for that host")
check(remembering.rules.first == Rule(hosts: ["github.com"], open: work), "remembered rule goes first")

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("All checks passed")
