import SwiftUI

struct IslandView: View {
    @ObservedObject var player: PlayerModel
    var compact = false
    var contentOnly = false
    var onExpansion: ((Bool) -> Void)?
    @State private var expanded = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var seeking: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.69, green: 0.96, blue: 0.62)

    var body: some View {
        Group {
            if contentOnly { controls } else if compact {
                VStack(spacing: 0) {
                    notchHeader
                    if expanded {
                        controls.frame(height: 240).padding(20)
                    }
                }
                .frame(width: expanded ? max(400, player.notchWidth + 130) : player.notchWidth + 94)
                .background(.black)
                .clipShape(NotchShape())
                .onHover { inside in
                    collapseTask?.cancel()
                    if inside { setExpanded(true) }
                    else {
                        collapseTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            guard !Task.isCancelled else { return }; setExpanded(false)
                        }
                    }
                }
                .contextMenu {
                    Button("Tự động / Thử lại") { player.connect() }
                    Button("Ẩn Dynamic Notch") { player.showIsland = false }
                    Button("Thoát Dynamic Notch") { NSApplication.shared.terminate(nil) }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Dynamic Notch").font(.headline)
                            Spacer()
                            Button("Thoát") { NSApplication.shared.terminate(nil) }
                        }
                        controls
                        Divider()
                        Text(player.message).font(.caption).foregroundStyle(.secondary)
                        sourcePicker
                        Text("Nguồn được phép kết nối").font(.caption.bold())
                        ForEach(MediaBridge.providers, id: \.self) { app in
                            Toggle(app == "Music" ? "Apple Music" : app, isOn: Binding(
                                get: { player.enabled.contains(app) },
                                set: { player.setProvider(app, enabled: $0) }))
                        }
                        Text("Web nhạc: bật Allow JavaScript from Apple Events trong trình duyệt. Chỉ đọc các tab YouTube, SoundCloud, Spotify Web và Apple Music Web.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(player.providerErrors, id: \.self) { error in
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("Tự động / Thử lại") { player.connect() }
                            Button("Demo") { player.selectDemo() }
                            Button("Nhập .lrc") { player.importLyrics() }.disabled(!player.canControl)
                        }.controlSize(.small)
                        Toggle("Hiện Dynamic Notch", isOn: $player.showIsland)
                        Toggle("Giảm chuyển động", isOn: $player.lowPower)
                    }.padding(20)
                }.frame(width: 400, height: 650).background(Color(white: 0.05))
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion || player.lowPower ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: expanded)
    }

    private func setExpanded(_ value: Bool) {
        expanded = value; onExpansion?(value)
    }
    private var notchHeader: some View {
        HStack(spacing: 0) {
            cover(size: 24).frame(width: 47)
            // Leave the camera housing completely empty; never put controls under the physical notch.
            Color.clear.frame(width: player.notchWidth, height: player.notchHeight)
            Button { player.command(.toggle) } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                    .frame(width: 47, height: player.notchHeight)
            }.buttonStyle(.plain).disabled(!player.canToggle)
                .accessibilityLabel(player.playing ? "Tạm dừng" : "Phát")
        }.frame(maxWidth: .infinity)
    }
    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                cover(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(player.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(player.sourceName).font(.system(size: 9)).foregroundStyle(accent).lineLimit(1)
                }
                Spacer(minLength: 0)
                if compact {
                    Button { NSApplication.shared.terminate(nil) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                    }.buttonStyle(.plain).help("Thoát Dynamic Notch").accessibilityLabel("Thoát Dynamic Notch")
                }
            }
            TimelineView(.periodic(from: .now, by: player.playing ? 0.5 : 2)) { _ in
                VStack(spacing: 5) {
                    if !player.lyric.isEmpty {
                        Text(player.lyric).font(.caption).foregroundStyle(accent).lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    Slider(value: Binding(get: { seeking ?? player.position }, set: { seeking = $0 }),
                           in: 0...max(1, player.duration), onEditingChanged: { editing in
                        if !editing, let value = seeking { player.command(.seek(value)); seeking = nil }
                    }).tint(accent).disabled(!player.canSeek).accessibilityLabel("Vị trí phát")
                    HStack {
                        Text(player.canSeek ? clock(seeking ?? player.position) : "Không hỗ trợ tua")
                        Spacer(); Text(player.duration > 0 ? clock(player.duration) : "—")
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 35) {
                transport("backward.end.fill", "Bài trước", .previous, player.canPrevious)
                transport(player.playing ? "pause.fill" : "play.fill", "Phát / Tạm dừng", .toggle, player.canToggle)
                transport("forward.end.fill", "Bài tiếp", .next, player.canNext)
            }.font(.system(size: 18)).padding(.vertical, 4)
            if compact { sourcePicker }
        }
    }
    private var sourcePicker: some View {
        Picker("Trình phát", selection: $player.pinned) {
            Text("Tự động").tag("auto")
            ForEach(player.sources) { source in
                Text(source.source + " · " + source.title).tag(source.id)
            }
            if player.pinned != "auto" && !player.sources.contains(where: { $0.id == player.pinned }) {
                Text("Nguồn đã đóng").tag(player.pinned)
            }
        }.font(.caption)
    }
    private func cover(size: CGFloat) -> some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let art = player.artwork { Image(nsImage: art).resizable().scaledToFill() }
            else { Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.white) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
    private func transport(_ icon: String, _ label: String, _ command: MediaCommand, _ enabled: Bool) -> some View {
        Button { player.command(command) } label: { Image(systemName: icon).frame(width: 32, height: 28) }
            .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label)
    }
    private func clock(_ seconds: Double) -> String {
        let value = Int(max(0, seconds)); return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// Flat top connected to the display edge, round lower shoulders like a hardware notch.
struct NotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = min(22, rect.height / 2)
        var p = Path()
        p.move(to: .zero); p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - r), control: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath(); return p
    }
}
