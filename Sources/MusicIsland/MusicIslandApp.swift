import AppKit
import SwiftUI
import Combine
import IslandCore
import QuartzCore

@main
struct MusicIslandApp: App {
    @NSApplicationDelegateAdaptor(IslandDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("Dynamic Notch", systemImage: "waveform") {
            VStack {
                Toggle("Giảm chuyển động toàn notch", isOn: Binding(get: { delegate.coordinator.settings.reduceMotion }, set: { delegate.coordinator.settings.reduceMotion = $0 }))
                Toggle("HUD âm lượng và pin", isOn: Binding(get: { delegate.coordinator.settings.systemHUDs }, set: { delegate.coordinator.settings.systemHUDs = $0 }))
                IslandView(player: delegate.player)
            }.padding(8)
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
    let coordinator = IslandCoordinator()
    private var systemModules: SystemModules?
    private var stateSubscription: AnyCancellable?
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
            NotchShell(player: player, coordinator: coordinator, settings: coordinator.settings).fixedSize())
        self.panel = panel
        updateScreen()
        fitPanel()
        coordinator.bindMusic(player)
        stateSubscription = coordinator.$engine.map { $0.state }.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.fitPanel() }
        }
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
        } else {
            player.connect()
            let module = SystemModules(bus: coordinator.bus); systemModules = module; module.start()
        }
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
        sleeping = value; player.setSuspended(value); coordinator.sleep(value)
        if value { systemModules?.stop() } else { systemModules?.start() }
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
        let state = coordinator.engine.state
        let wide = state == .expanded || state == .transientHUD
        let width = wide ? max(400, player.notchWidth + 130) : player.notchWidth + 94
        let extra: CGFloat = state == .expanded ? 370 : state == .transientHUD ? 74 : state == .multiActivity ? 28 : 0
        let height = player.notchHeight + extra
        guard let screen = targetScreen else { return }
        let center = (screen.auxiliaryTopLeftArea.map { $0.maxX } ?? screen.frame.midX)
            + ((screen.auxiliaryTopRightArea.map { $0.minX } ?? screen.frame.midX)
            - (screen.auxiliaryTopLeftArea.map { $0.maxX } ?? screen.frame.midX)) / 2
        let frame = NSRect(x: center - width / 2, y: screen.frame.maxY - height, width: width, height: height)
        if panel.isVisible && !coordinator.settings.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
    }
    func applicationWillTerminate(_ notification: Notification) {
        systemModules?.stop()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}
