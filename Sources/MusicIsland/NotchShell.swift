import SwiftUI
import IslandCore

struct NotchShell: View {
    @ObservedObject var player: PlayerModel
    @ObservedObject var coordinator: IslandCoordinator
    @ObservedObject var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var collapse: Task<Void, Never>?
    var expanded: Bool { coordinator.engine.state == .expanded }
    var hud: IslandEvent? { coordinator.engine.state == .transientHUD ? coordinator.engine.transient : nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: hud?.symbol ?? (player.playing ? "music.note" : "circle.dotted"))
                    .foregroundStyle(.mint).frame(width: 47)
                Color.clear.frame(width: player.notchWidth, height: player.notchHeight)
                Button { coordinator.togglePin() } label: {
                    Image(systemName: expanded ? "chevron.up" : coordinator.engine.activities.count > 1 ? "square.stack.3d.up" : "chevron.down")
                        .frame(width: 47, height: player.notchHeight)
                }.buttonStyle(.plain).accessibilityLabel("Mở / đóng notch")
            }.frame(maxWidth: .infinity)
            if let hud {
                VStack(spacing: 8) {
                    HStack { Text(hud.title).font(.callout); Spacer()
                        Button { coordinator.remove(hud.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                    if let value = hud.progress { ProgressView(value: value).tint(.mint) }
                }.padding(16).frame(height: 74).id(hud.id).transition(.opacity.combined(with: .move(edge: .top)))
            } else if expanded {
                VStack(spacing: 12) {
                    HStack {
                        Text("Dynamic Notch").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { coordinator.togglePin() } label: { Image(systemName: coordinator.pinnedOpen ? "pin.fill" : "pin") }
                            .help("Giữ mở")
                        Button { NSApp.terminate(nil) } label: { Image(systemName: "xmark.circle.fill") }.help("Thoát ứng dụng")
                    }.buttonStyle(.plain)
                    IslandView(player: player, contentOnly: true)
                    Divider()
                    timerControls
                    if !coordinator.engine.activities.isEmpty {
                        HStack { ForEach(coordinator.engine.activities) { item in
                            Label(item.title, systemImage: item.symbol).font(.caption).lineLimit(1)
                        }}.foregroundStyle(.secondary)
                    }
                }.padding(18).frame(height: 370).transition(.opacity.combined(with: .move(edge: .top)))
            } else if coordinator.engine.state == .multiActivity {
                HStack {
                    Image(systemName: "music.note")
                    Spacer()
                    if let end = coordinator.timerEnd { Text(end, style: .timer).monospacedDigit() }
                    else { Text("Timer tạm dừng") }
                }.font(.caption).padding(.horizontal, 20).frame(height: 28)
            }
        }
        .frame(width: expanded || hud != nil ? max(400, player.notchWidth + 130) : player.notchWidth + 94)
        .background(.black).clipShape(NotchShape()).preferredColorScheme(.dark)
        .animation(reduced || settings.reduceMotion ? nil : .interpolatingSpring(stiffness: 250, damping: 28), value: coordinator.engine.state)
        .onHover { hover in
            collapse?.cancel()
            if hover { coordinator.expand(true) }
            else { collapse = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                if !Task.isCancelled { coordinator.expand(false) }
            }}
        }
        .contextMenu {
            Button("Ẩn notch") { player.showIsland = false }
            Button("Thoát Dynamic Notch") { NSApp.terminate(nil) }
        }
    }
    private var timerControls: some View {
        HStack {
            if let end = coordinator.timerEnd {
                Text(end, style: .timer).font(.title3.monospacedDigit())
            } else if let remaining = coordinator.timerPaused { Text("\(Int(remaining))s · Tạm dừng") }
            else { Text("Timer").font(.caption) }
            Spacer()
            if coordinator.timerEnd != nil || coordinator.timerPaused != nil {
                Button(coordinator.timerEnd == nil ? "Tiếp tục" : "Dừng") { coordinator.pauseTimer() }
                Button("Hủy") { coordinator.cancelTimer() }
            } else {
                Button("5 phút") { coordinator.startTimer(seconds: 300) }
                Button("25 phút") { coordinator.startTimer(seconds: 1500) }
            }
        }.controlSize(.small)
    }
}
