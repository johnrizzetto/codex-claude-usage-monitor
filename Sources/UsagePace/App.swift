import AppKit
import SwiftUI
import ServiceManagement
import PaceCore

func durationText(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
    if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
    return "\(minutes)m"
}

struct Dashboard: View {
    @ObservedObject var store: AccountStore
    @State private var atLogin = SMAppService.mainApp.status == .enabled
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Usage Pace").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Your accounts, against the clock").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.refreshAll() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh all accounts")
                Menu {
                    Toggle("Pause automatic refresh", isOn: $store.paused)
                    Toggle("Launch at login", isOn: $atLogin).onChange(of: atLogin) { _, value in
                        do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { atLogin = SMAppService.mainApp.status == .enabled }
                    }
                    Divider()
                    Button("Open app data folder") { NSWorkspace.shared.activateFileViewerSelecting([Locations.root]) }
                    Button("Quit Usage Pace") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).fixedSize()
            }.padding(20)
            HStack(spacing: 12) {
                Text("Menu bar").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Picker("Account", selection: $store.menuAccount) {
                    ForEach(store.accounts) { account in Text(account.label).tag(account.id) }
                }.labelsHidden().frame(maxWidth: .infinity)
                Picker("Window", selection: $store.menuWindow) {
                    ForEach(MenuWindow.allCases, id: \.self) { window in Text(window.label).tag(window) }
                }.labelsHidden().frame(width: 100)
            }.controlSize(.small).padding(.horizontal, 20).padding(.bottom, 14)
                .help("Choose the account and usage window shown in the menu bar. Color reflects pacing, fill reflects quota used.")
            ScrollView {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 10) {
                        ForEach(store.accounts) { account in
                            AccountCard(account: account, now: context.date, store: store)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 12)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(store.paused ? Color.orange : Color.teal).frame(width: 5, height: 5)
                Text(store.paused ? "Automatic refresh paused" : "Refreshes every 5 minutes").font(.system(size: 10))
                Spacer()
                Text("Marker = time elapsed").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.frame(width: 440, height: 690)
    }
}

struct AccountCard: View {
    let account: AccountState
    let now: Date
    @ObservedObject var store: AccountStore
    var stale: Bool { account.error != nil || account.updated.map { now.timeIntervalSince($0) > 600 } ?? true }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2).fill(account.isClaude ? Color.orange : Color.teal).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(account.provider, text: Binding(get: { account.label }, set: { store.rename(account.id, $0) }))
                        .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold)).help("Click to rename this account")
                    Text(account.email ?? (account.isClaude ? "Claude subscription" : "ChatGPT subscription"))
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if account.busy { ProgressView().controlSize(.small) }
                else if !account.windows.isEmpty {
                    Text(stale ? "STALE" : "LIVE").font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(stale ? .orange : .teal)
                }
                Menu {
                    Button("Refresh") { store.refresh(account.id, allowPrompt: true) }.disabled(!account.connected)
                    if account.isClaude {
                        Button("Connect Claude Code login") { store.connectClaude() }
                        Button("Sign in through Claude Code") { store.signInClaude() }
                    } else { Button("Sign in with ChatGPT") { store.connectCodex(account.id) } }
                    if account.connected { Button("Disconnect from monitor") { store.disconnect(account.id) } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            }
            if account.signingIn {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Complete the login in your browser.").font(.system(size: 11))
                    Spacer()
                    Button("Cancel") { store.cancelLogin(account.id) }.controlSize(.small)
                }
            } else if account.windows.isEmpty {
                HStack {
                    Button(account.isClaude ? "Connect Claude" : "Sign in with ChatGPT") {
                        if account.isClaude { store.connectClaude() } else { store.connectCodex(account.id) }
                    }.buttonStyle(.borderedProminent).tint(account.isClaude ? .orange : .teal).controlSize(.small).disabled(account.busy)
                    if account.isClaude {
                        Button("Sign in") { store.signInClaude() }.controlSize(.small)
                    }
                }
                Text(account.isClaude ? "Uses the OAuth login from Claude Code." : "Separate OAuth login for this account.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                ForEach(account.windows) { window in
                    WindowLane(window: window, now: now, stale: stale)
                }
                if let updated = account.updated {
                    Text("Checked \(durationText(now.timeIntervalSince(updated))) ago")
                        .font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            if let error = account.error {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                if account.isClaude, account.connected, !account.windows.isEmpty { Button("Connect Claude") { store.connectClaude() }.controlSize(.small) }
            }
        }.padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06)))
    }
}

struct WindowLane: View {
    let window: UsageWindow
    let now: Date
    let stale: Bool
    var pace: Pacing? { stale ? nil : window.pacing(at: now) }
    var accent: Color {
        switch PaceSignal.evaluate(window, at: now, stale: stale) {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .unavailable: return .secondary
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.name).font(.system(size: 11, weight: .medium))
                Text(String(format: "%.0f%% used", window.used)).font(.system(size: 11, weight: .semibold, design: .monospaced))
                Spacer()
                if let reset = window.reset {
                    Text(reset > now ? "Resets in \(durationText(reset.timeIntervalSince(now)))" : "Reset passed, refresh needed")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else { Text("Reset unavailable").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(accent.gradient).frame(width: geometry.size.width * min(100, max(0, window.used)) / 100)
                    if let pace {
                        RoundedRectangle(cornerRadius: 1).fill(Color.primary).frame(width: 2, height: 12)
                            .offset(x: min(geometry.size.width - 2, max(0, geometry.size.width * pace.expected / 100)))
                    }
                }
            }.frame(height: 8)
            if let pace {
                HStack {
                    Text(abs(pace.delta) < 0.5 ? "On pace" : String(format: "%.1f pp %@ pace", abs(pace.delta), pace.delta > 0 ? "ahead of" : "behind"))
                        .foregroundStyle(accent).font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(pace.elapsed >= 60 ? String(format: "%.1f× average pace", pace.multiplier) : "Window just started")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack {
                    Text(String(format: "%.1f%% / hr left to spend", pace.allowedPerHour)).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    if window.used >= 100 { Text("Limit reached").foregroundStyle(.red).font(.system(size: 10)) }
                    else if let exhausts = pace.exhaustsIn, exhausts < pace.remaining {
                        Text("Est. limit in \(durationText(exhausts))").foregroundStyle(accent).font(.system(size: 10))
                    }
                }
            } else {
                Text(stale ? "Refresh to update pacing." : "Pacing needs a valid active reset window.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.help("pp means percentage points. Pace compares usage with time elapsed. The limit estimate assumes the window's average consumption rate continues.")
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var store: AccountStore!
    private var titleTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = AccountStore()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.toolTip = "Usage Pace: two Codex accounts and Claude"
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 440, height: 690)
        popover.contentViewController = NSHostingController(rootView: Dashboard(store: store))
        store.onChange = { [weak self] in self?.updateTitle() }
        titleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        updateTitle()
        if CommandLine.arguments.contains("--show") { toggle() }
    }
    private func updateTitle() {
        let now = Date()
        let account = store.accounts[store.menuAccount]
        let window = store.menuWindow.select(from: account.windows)
        let stale = account.error != nil || account.updated.map { now.timeIntervalSince($0) > 600 } ?? true
        let signal = PaceSignal.evaluate(window, at: now, stale: stale)
        let pace = signal == .unavailable ? nil : window?.pacing(at: now)
        let percentage = pace.map { String(format: " %+.0f%%", abs($0.delta) < 0.5 ? 0 : $0.delta) } ?? " ?%"
        let accountBadge = account.isClaude ? "CL" : "C\(account.id + 1)"
        let title = NSMutableAttributedString(string: " \(accountBadge)", attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        ])
        title.append(NSAttributedString(string: percentage, attributes: [
            .foregroundColor: MenuBarMeter.color(for: signal),
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        ]))
        item.button?.attributedTitle = title
        item.button?.image = MenuBarMeter.image(used: window?.used, expected: pace?.expected, signal: signal)
        let identity = "\(account.label) · \(store.menuWindow.label)"
        if let window, let pace {
            item.button?.toolTip = identity + String(format: ": %+.1f percentage points against perfect pacing (%.0f%% used, %.1f%% expected). Resets in %@.", pace.delta, window.used, pace.expected, durationText(pace.remaining))
        } else {
            item.button?.toolTip = identity + (window == nil ? ": this window is unavailable for this account." : ": refresh needed for current pacing.")
        }
        item.button?.setAccessibilityLabel(item.button?.toolTip ?? "Usage Pace")
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    func applicationWillTerminate(_ notification: Notification) { titleTimer?.invalidate(); store.stop() }
}

@main struct UsagePaceMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
