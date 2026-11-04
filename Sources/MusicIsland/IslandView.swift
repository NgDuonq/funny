import SwiftUI

struct IslandView: View {
    @ObservedObject var player: PlayerModel
    var compact = false
    @State private var hovered = false
    @State private var seeking: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var expanded: Bool { !compact || hovered }
    private let accent = Color(red: 0.67, green: 0.93, blue: 0.58)

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(player.artist).font(.system(size: 11)).foregroundStyle(.gray).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { player.command(.toggle) } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold)).frame(width: 32, height: 32)
                        .background(accent, in: Circle()).foregroundStyle(.black)
                }
                .buttonStyle(.plain).disabled(!player.canControl)
                .accessibilityLabel(player.playing ? "Tạm dừng" : "Phát")
            }
            if expanded {
                TimelineView(.periodic(from: .now, by: player.playing ? 0.5 : 2)) { _ in
                    VStack(spacing: 8) {
                        Text(player.lyric.isEmpty ? "Your little corner of music." : player.lyric)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(accent)
                            .lineLimit(2).multilineTextAlignment(.center).frame(height: 36)
                        Slider(value: Binding(get: { seeking ?? player.position }, set: { seeking = $0 }),
                               in: 0...max(1, player.duration), onEditingChanged: { editing in
                            if !editing, let value = seeking { player.command(.seek(value)); seeking = nil }
                        }).tint(accent).disabled(!player.canControl || player.duration <= 0)
                            .accessibilityLabel("Vị trí phát")
                        HStack {
                            Text(clock(seeking ?? player.position))
                            Spacer()
                            Text(clock(player.duration))
                        }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray)
                    }
                }
                HStack(spacing: 28) {
                    transport("backward.end.fill", label: "Bài trước", command: .previous)
                    Text(player.demo ? "DEMO" : "SPOTIFY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(3).foregroundStyle(accent)
                    transport("forward.end.fill", label: "Bài tiếp", command: .next)
                }
            }
            if !compact {
                Divider().overlay(.white.opacity(0.1))
                Text(player.message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Kết nối Spotify") { player.connect() }
                    Button("Demo") { player.selectDemo() }
                    Spacer()
                    Button { player.importLyrics() } label: { Image(systemName: "text.badge.plus") }
                        .help("Nhập lời .lrc").disabled(!player.canControl)
                }.controlSize(.small)
                Toggle("Hiện Music Island", isOn: $player.showIsland)
                Toggle("Tiết kiệm chuyển động", isOn: $player.lowPower)
                HStack {
                    Text("MUSIC ISLAND / PREVIEW 0.1").font(.system(size: 9, design: .monospaced)).foregroundStyle(.gray)
                    Spacer()
                    Button("Thoát") { NSApplication.shared.terminate(nil) }.controlSize(.small)
                }
            }
        }
        .padding(18)
        .frame(width: compact ? 340 : 360)
        .background(Color(red: 0.035, green: 0.04, blue: 0.045))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 1))
        .preferredColorScheme(.dark)
        .onHover { hovered = $0 }
        .animation(reduceMotion || player.lowPower ? nil : .easeInOut(duration: 0.2), value: hovered)
    }

    private var cover: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .purple, accent.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let artwork = player.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                Image(systemName: "waveform").font(.system(size: 20)).foregroundStyle(.white)
            }
        }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func transport(_ icon: String, label: String, command: SpotifyCommand) -> some View {
        Button { player.command(command) } label: { Image(systemName: icon).frame(width: 30, height: 24) }
            .buttonStyle(.plain).disabled(!player.canControl).accessibilityLabel(label)
    }
    private func clock(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
