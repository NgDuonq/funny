import AppKit
import SwiftUI
import Combine

@main
struct MusicIslandApp: App {
    @NSApplicationDelegateAdaptor(IslandDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("Music Island", systemImage: "waveform") {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let panel = IslandPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 250),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            VStack(spacing: 0) { IslandView(player: player, compact: true); Spacer(minLength: 0) }
                .frame(width: 340, height: 250, alignment: .top))
        self.panel = panel
        placePanel()
        subscription = player.$showIsland.sink { [weak self] show in
            guard let self = self else { return }
            if show && !self.sleeping { self.panel?.orderFrontRegardless() }
            else { self.panel?.orderOut(nil) }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.placePanel() } })
        let center = NSWorkspace.shared.notificationCenter
        for event in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleep(true) }
            })
        }
        for event in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleep(false) }
            })
        }
    }
    private func sleep(_ value: Bool) {
        sleeping = value; player.setSuspended(value)
        if value { panel?.orderOut(nil) }
        else if player.showIsland { placePanel(); panel?.orderFrontRegardless() }
    }
    private func placePanel() {
        // Below the menu bar / notch safe area, including external displays without a notch.
        guard let screen = NSScreen.screens.first, let panel = panel else { return }
        let top = min(screen.visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - 8
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - panel.frame.width / 2, y: top - panel.frame.height))
    }
    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
