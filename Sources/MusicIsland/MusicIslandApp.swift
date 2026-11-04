import AppKit
import SwiftUI
import Combine

@main
struct MusicIslandApp: App {
    @NSApplicationDelegateAdaptor(IslandDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("Dynamic Notch", systemImage: "waveform") {
            IslandView(player: delegate.player)
        }.menuBarExtraStyle(.window)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandDelegate: NSObject, NSApplicationDelegate {
    let player = PlayerModel()
    private var panel: IslandPanel?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var subscription: AnyCancellable?
    private var sleeping = false
    private var expanded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 80),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            IslandView(player: player, compact: true, onExpansion: { [weak self] value in
                self?.expanded = value
                self?.fitPanel()
            }).fixedSize())
        self.panel = panel
        updateScreen()
        fitPanel()
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let frame = self.panel?.frame,
                      frame.width > 100, frame.height >= 30, MediaBridge().hasWebScript else {
                    fputs("App smoke test failed: geometry or packaged web resource missing\n", stderr)
                    exit(1)
                }
                print("Dynamic Notch smoke test passed: panel + packaged WebPlayer.js")
                NSApp.terminate(nil)
            }
        } else { player.connect() }
        subscription = player.$showIsland.sink { [weak self] show in
            guard let self = self else { return }
            if show && !self.sleeping { self.panel?.orderFrontRegardless() }
            else { self.panel?.orderOut(nil) }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.updateScreen(); self?.fitPanel() } })
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sleep(true) }
            })
        }
        for event in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sleep(false) }
            })
        }
    }
    private func sleep(_ value: Bool) {
        sleeping = value; player.setSuspended(value)
        if value { panel?.orderOut(nil) }
        else if player.showIsland { placePanel(); panel?.orderFrontRegardless() }
    }
    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }
    private func updateScreen() {
        guard let screen = targetScreen else { return }
        player.hasNotch = screen.safeAreaInsets.top > 0
        player.notchHeight = max(30, screen.safeAreaInsets.top)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           player.hasNotch {
            player.notchWidth = max(120, right.minX - left.maxX)
        } else { player.notchWidth = 100 }
        placePanel()
    }
    private func placePanel() {
        guard let screen = targetScreen, let panel else { return }
        let center: CGFloat
        if player.hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            center = (left.maxX + right.minX) / 2
        } else { center = screen.frame.midX }
        panel.setFrameOrigin(NSPoint(x: center - panel.frame.width / 2, y: screen.frame.maxY - panel.frame.height))
    }
    private func fitPanel() {
        guard let panel else { return }
        // Explicit dimensions avoid a race with SwiftUI intrinsic-size updates after hover.
        let width = expanded ? max(400, player.notchWidth + 130) : player.notchWidth + 94
        let height = player.notchHeight + (expanded ? 280 : 0)
        panel.setContentSize(NSSize(width: width, height: height))
        placePanel()
    }
    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
