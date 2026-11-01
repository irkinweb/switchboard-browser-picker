import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SwitchboardCore

@MainActor
final class SettingsModel: ObservableObject {
    @Published var config: Config {
        didSet {
            if loadError == nil, config != oldValue { ConfigStore.save(config) }
        }
    }
    @Published private(set) var loadError: String?
    @Published private(set) var options: [BrowserOption] = []
    @Published private(set) var isDefaultBrowser = false

    init() {
        let loaded = ConfigStore.load()
        config = loaded.config
        loadError = loaded.error
        refreshEnvironment()
    }

    func reload() {
        let loaded = ConfigStore.load()
        loadError = loaded.error
        if loaded.error == nil, loaded.config != config { config = loaded.config }
        refreshEnvironment()
    }

    func refreshEnvironment() {
        options = Browsers.options(hiding: [], order: config)
        isDefaultBrowser = DefaultBrowser.isSwitchboard
    }

    func makeDefault() {
        DefaultBrowser.request { [weak self] in self?.refreshEnvironment() }
    }

    func startFresh() {
        loadError = nil
        config = .empty
        ConfigStore.save(config)
    }

    var browserApps: [BrowserOption] {
        var seen = Set<String>()
        return options.filter { seen.insert($0.target.browser).inserted }
    }

    func title(for target: Target) -> String {
        let id = BrowserOption.id(for: Target(browser: target.browser, profile: target.profile))
        let base = options.first { $0.id == id }?.title
            ?? [InstalledApps.name(for: target.browser), target.profile].compactMap { $0 }.joined(separator: " · ")
        return target.privateWindow == true ? "\(base) (private)" : base
    }

    func icon(for target: Target) -> NSImage? {
        options.first { $0.target.browser == target.browser }?.smallIcon ?? InstalledApps.icon(for: target.browser)
    }

    func save(_ draft: RuleDraft) {
        guard let rule = draft.rule(options: options) else { return }
        if let index = draft.index, config.rules.indices.contains(index) {
            config.rules[index] = rule
        } else {
            config.rules.append(rule)
        }
    }

    func moveRule(at index: Int, by offset: Int) {
        let destination = index + offset
        guard config.rules.indices.contains(index), config.rules.indices.contains(destination) else { return }
        config.rules.swapAt(index, destination)
    }

    func moveOption(_ id: String, onto targetID: String) {
        var ids = options.map(\.id)
        guard id != targetID, let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: targetID) else { return }
        ids.insert(ids.remove(at: from), at: to)
        config.pickerOrder = ids
        refreshEnvironment()
    }

    func moveOption(at index: Int, by offset: Int) {
        guard options.indices.contains(index), options.indices.contains(index + offset) else { return }
        moveOption(options[index].id, onto: options[index + offset].id)
    }

    func profileVisibleBinding(for option: BrowserOption) -> Binding<Bool> {
        Binding(
            get: { !self.config.hiddenProfiles.contains(option.id) && !self.config.hiddenBrowsers.contains(option.target.browser) },
            set: { visible in
                if visible {
                    self.config.hiddenProfiles.removeAll { $0 == option.id }
                } else if !self.config.hiddenProfiles.contains(option.id) {
                    self.config.hiddenProfiles.append(option.id)
                }
            }
        )
    }

    func hiddenBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { !self.config.hiddenBrowsers.contains(bundleID) },
            set: { visible in
                if visible {
                    self.config.hiddenBrowsers.removeAll { $0 == bundleID }
                } else if !self.config.hiddenBrowsers.contains(bundleID) {
                    self.config.hiddenBrowsers.append(bundleID)
                }
            }
        )
    }

    var defaultTargetID: Binding<String> {
        Binding(
            get: { self.config.defaultTarget.map(BrowserOption.id(for:)) ?? "" },
            set: { id in self.config.defaultTarget = self.options.first { $0.id == id }?.target }
        )
    }
}

struct RuleDraft: Identifiable {
    let id = UUID()
    var index: Int?
    var sites = ""
    var sourceApps: [String] = []
    var urlPattern = ""
    var targetID = ""
    var privateWindow = false

    init(index: Int? = nil, rule: Rule? = nil, fallbackTargetID: String = "") {
        self.index = index
        targetID = fallbackTargetID
        guard let rule else { return }
        sites = (rule.hosts ?? []).joined(separator: ", ")
        sourceApps = rule.sourceApps ?? []
        urlPattern = rule.urlPattern ?? ""
        targetID = BrowserOption.id(for: Target(browser: rule.open.browser, profile: rule.open.profile))
        privateWindow = rule.open.privateWindow == true
    }

    var hosts: [String] {
        sites.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Rule.normalizedHost(String($0)) }
    }

    var problem: String? {
        if hosts.isEmpty, sourceApps.isEmpty, urlPattern.isEmpty { return "Add at least one site, app or pattern." }
        if !urlPattern.isEmpty, (try? NSRegularExpression(pattern: urlPattern)) == nil { return "The pattern isn't a valid regular expression." }
        if targetID.isEmpty { return "Pick a browser." }
        return nil
    }

    func rule(options: [BrowserOption]) -> Rule? {
        guard problem == nil, let option = options.first(where: { $0.id == targetID }) else { return nil }
        var target = option.target
        target.privateWindow = privateWindow ? true : nil
        return Rule(
            hosts: hosts.isEmpty ? nil : hosts,
            urlPattern: urlPattern.isEmpty ? nil : urlPattern,
            sourceApps: sourceApps.isEmpty ? nil : sourceApps,
            open: target
        )
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var draft: RuleDraft?
    @State private var dropTarget: String?
    @State private var dragging: String?

    /// The dragged row takes the target's place, so the indicator sits on the side it comes from.
    private func dropsAbove(_ targetIndex: Int) -> Bool {
        guard let dragging, let from = model.options.firstIndex(where: { $0.id == dragging }) else { return true }
        return from > targetIndex
    }

    var body: some View {
        Form {
            Section {
                if model.isDefaultBrowser {
                    Label("Switchboard is your default browser", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("Switchboard isn't your default browser yet", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Make Default") { model.makeDefault() }
                    }
                }
                Toggle(isOn: $model.config.cleanLinks) {
                    Text("Clean links")
                    Text("Remove tracking parameters like utm_source and fbclid, and unwrap Outlook, Google, Facebook and Slack redirect links before opening.")
                }
                Picker("Links without a rule", selection: model.defaultTargetID) {
                    Text("Ask me every time").tag("")
                    Divider()
                    ForEach(model.options) { option in
                        Label { Text(option.title) } icon: { Image(nsImage: option.smallIcon) }.tag(option.id)
                    }
                }
            }

            if let error = model.loadError {
                Section {
                    HStack {
                        Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                        Spacer()
                        Button("Start Fresh") { model.startFresh() }
                    }
                }
            }

            Section {
                if model.config.rules.isEmpty {
                    Text("No rules yet. Add one, or hold ⌘ while picking a browser to always use it for that site.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.config.rules.enumerated()), id: \.offset) { index, rule in
                    RuleRow(rule: rule, model: model, isFirst: index == 0, isLast: index == model.config.rules.count - 1) { action in
                        switch action {
                        case .edit: draft = RuleDraft(index: index, rule: rule)
                        case .moveUp: model.moveRule(at: index, by: -1)
                        case .moveDown: model.moveRule(at: index, by: 1)
                        case .delete: model.config.rules.remove(at: index)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Rules")
                    Spacer()
                    Button {
                        draft = RuleDraft(fallbackTargetID: model.options.first?.id ?? "")
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .disabled(model.loadError != nil)
                }
            } footer: {
                Text("Rules are checked top to bottom; the first match wins. Hold Shift when clicking a link to see the picker anyway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(spacing: 0) {
                ForEach(Array(model.options.enumerated()), id: \.element.id) { index, option in
                    let appHidden = model.config.hiddenBrowsers.contains(option.target.browser)
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Label { Text(option.title) } icon: { Image(nsImage: option.smallIcon) }
                            .opacity(appHidden ? 0.5 : 1)
                        Spacer()
                        Menu {
                            Button("Move Up") { model.moveOption(at: index, by: -1) }.disabled(index == 0)
                            Button("Move Down") { model.moveOption(at: index, by: 1) }.disabled(index == model.options.count - 1)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        Toggle("", isOn: model.profileVisibleBinding(for: option))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(appHidden)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(dropTarget == option.id && dragging != option.id ? Color.accentColor.opacity(0.15) : .clear)
                    .overlay(alignment: dropsAbove(index) ? .top : .bottom) {
                        if dropTarget == option.id, dragging != option.id {
                            Capsule().fill(Color.accentColor).frame(height: 3)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if index < model.options.count - 1 { Divider() }
                    }
                    .contentShape(Rectangle())
                    .onDrag {
                        dragging = option.id
                        return NSItemProvider(object: option.id as NSString)
                    }
                    .onDrop(of: [.plainText], delegate: OptionDropDelegate(id: option.id, dragging: $dragging, target: $dropTarget) {
                        model.moveOption($0, onto: $1)
                    })
                }
                }
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Picker order")
            } footer: {
                Text("Drag a row onto another to move it there, or use the menu. Turn a profile off to hide it from the picker. The first nine get the keys 1–9; the rest go under Others.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Show in picker") {
                ForEach(model.browserApps) { app in
                    Toggle(isOn: model.hiddenBinding(for: app.target.browser)) {
                        Label { Text(app.appName) } icon: { Image(nsImage: app.smallIcon) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 520)
        .sheet(item: $draft) { draft in
            RuleEditor(draft: draft, model: model) { saved in
                model.save(saved)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reload()
        }
    }
}

struct OptionDropDelegate: DropDelegate {
    let id: String
    @Binding var dragging: String?
    @Binding var target: String?
    let move: (String, String) -> Void

    func dropEntered(info: DropInfo) { target = id }
    func dropExited(info: DropInfo) { if target == id { target = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil; target = nil }
        guard let dragging else { return false }
        move(dragging, id)
        return true
    }
}

enum RuleAction {
    case edit, moveUp, moveDown, delete
}

struct RuleRow: View {
    let rule: Rule
    @ObservedObject var model: SettingsModel
    let isFirst: Bool
    let isLast: Bool
    let perform: (RuleAction) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conditionSummary).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                    if let icon = model.icon(for: rule.open) { Image(nsImage: icon) }
                    Text(model.title(for: rule.open)).foregroundStyle(.secondary)
                }
                .font(.callout)
            }
            Spacer()
            Button("Edit") { perform(.edit) }
            Menu {
                Button("Move Up") { perform(.moveUp) }.disabled(isFirst)
                Button("Move Down") { perform(.moveDown) }.disabled(isLast)
                Divider()
                Button("Delete", role: .destructive) { perform(.delete) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { perform(.edit) }
    }

    private var conditionSummary: String {
        var parts: [String] = []
        if let hosts = rule.hosts { parts.append(hosts.joined(separator: ", ")) }
        if let pattern = rule.urlPattern { parts.append("matches \(pattern)") }
        if let apps = rule.sourceApps { parts.append("from \(apps.map(InstalledApps.name(for:)).joined(separator: ", "))") }
        return parts.joined(separator: "  ·  ")
    }
}

struct RuleEditor: View {
    @State var draft: RuleDraft
    @ObservedObject var model: SettingsModel
    let onSave: (RuleDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("When a link") {
                    TextField("is on", text: $draft.sites, prompt: Text("github.com, notion.so"))
                    LabeledContent("was clicked in") {
                        VStack(alignment: .trailing, spacing: 6) {
                            ForEach(draft.sourceApps, id: \.self) { bundleID in
                                HStack(spacing: 6) {
                                    if let icon = InstalledApps.icon(for: bundleID) { Image(nsImage: icon) }
                                    Text(InstalledApps.name(for: bundleID))
                                    Button {
                                        draft.sourceApps.removeAll { $0 == bundleID }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            if draft.sourceApps.isEmpty {
                                Text("any app").foregroundStyle(.secondary)
                            }
                            Button(draft.sourceApps.isEmpty ? "Choose App…" : "Add Another…") { chooseApp() }
                        }
                    }
                    DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                        TextField("matches pattern", text: $draft.urlPattern, prompt: Text("github\\.com/acme"))
                            .font(.body.monospaced())
                    }
                }
                Section("Open it in") {
                    Picker("Browser", selection: $draft.targetID) {
                        ForEach(model.options) { option in
                            Label { Text(option.title) } icon: { Image(nsImage: option.smallIcon) }.tag(option.id)
                        }
                    }
                    Toggle("Private window", isOn: $draft.privateWindow)
                        .disabled(!supportsPrivateWindow)
                }
                if let problem = draft.problem {
                    Text(problem).font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.index == nil ? "Add Rule" : "Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.problem != nil)
            }
            .padding(12)
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { showsAdvanced = !draft.urlPattern.isEmpty }
    }

    private var supportsPrivateWindow: Bool {
        guard let browser = model.options.first(where: { $0.id == draft.targetID })?.target.browser else { return false }
        return BrowserFamily.isChromium(browser) || BrowserFamily.firefoxBundleIDs.contains(browser)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        if !draft.sourceApps.contains(bundleID) { draft.sourceApps.append(bundleID) }
    }
}
