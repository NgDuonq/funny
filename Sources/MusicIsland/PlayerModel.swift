import AppKit
import SwiftUI
import IslandCore

@MainActor
final class PlayerModel: ObservableObject {
    @Published var title = "Midnight in Hanoi"
    @Published var artist = "Music Island · Demo"
    @Published var duration: Double = 180
    @Published var playing = true
    @Published var demo = true
    @Published var artwork: NSImage?
    @Published var message = "Demo giao diện · không phát âm thanh"
    @Published var lyrics: [LyricLine] = []
    @Published var showIsland = true
    @Published var lowPower = true
    @Published private var base: Double = 0
    private var anchor = ProcessInfo.processInfo.systemUptime
    private let spotify = SpotifyBridge()
    private var timer: Timer?
    private var busy = false
    private var suspended = false
    private var generation = 0
    private var trackID = "demo"
    private var artworkTask: URLSessionDataTask?

    init() { loadDemoLyrics() }

    var position: Double {
        PlaybackClock.position(base: base, elapsed: ProcessInfo.processInfo.systemUptime - anchor,
                               playing: playing && !suspended, duration: duration)
    }
    var lyric: String { LRC.current(in: lyrics, at: position) ?? "" }
    var canControl: Bool { demo || !trackID.isEmpty }

    func setSuspended(_ value: Bool) {
        base = position
        anchor = ProcessInfo.processInfo.systemUptime
        suspended = value
        if !value { refresh() }
    }

    func selectDemo() {
        generation += 1
        timer?.invalidate(); timer = nil
        artworkTask?.cancel()
        demo = true; title = "Midnight in Hanoi"; artist = "Music Island · Demo"
        duration = 180; playing = true; artwork = nil; trackID = "demo"
        setPosition(0); loadDemoLyrics()
        message = "Demo giao diện · không phát âm thanh"
    }

    func connect() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            message = "Mở Spotify desktop và phát một bài trước khi kết nối."
            return
        }
        generation += 1
        demo = false; playing = false; trackID = ""; lyrics = []; artwork = nil
        title = "Đang kết nối Spotify…"; artist = ""; duration = 0; setPosition(0)
        message = "Cho phép Music Island điều khiển Spotify khi macOS hỏi."
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.4
        refresh()
    }

    func refresh() {
        guard !demo, !busy, !suspended else { return }
        busy = true
        let request = generation
        spotify.read { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                self.busy = false
                guard self.generation == request, !self.demo else { return }
                switch result {
                case .success(let snapshot):
                    guard let snapshot = snapshot else {
                        self.clearTrack()
                        self.message = "Mở Spotify và phát một bài nhạc."
                        return
                    }
                    if self.trackID != snapshot.id {
                        self.trackID = snapshot.id; self.lyrics = []; self.artwork = nil
                        self.loadArtwork(snapshot.artwork, track: snapshot.id)
                    }
                    self.title = snapshot.title; self.artist = snapshot.artist
                    self.duration = snapshot.duration; self.playing = snapshot.playing
                    self.setPosition(snapshot.position)
                    self.message = "Spotify · Nhập .lrc để hiện lời đồng bộ"
                case .failure(let error):
                    self.clearTrack()
                    self.message = error.localizedDescription
                    // Permission failures must not repeatedly prompt in the background.
                    self.timer?.invalidate(); self.timer = nil
                }
            }
        }
    }

    func command(_ command: SpotifyCommand) {
        guard canControl else { return }
        if demo {
            switch command {
            case .toggle: let current = position; playing.toggle(); setPosition(current)
            case .seek(let time): setPosition(time)
            case .next, .previous: setPosition(0)
            }
            return
        }
        let request = generation
        spotify.send(command) { [weak self] result in
            Task { @MainActor in
                guard let self = self, request == self.generation else { return }
                if case .failure(let error) = result { self.message = error.localizedDescription }
                else { self.refresh() }
            }
        }
    }

    func importLyrics() {
        let panel = NSOpenPanel()
        panel.title = "Chọn lời .lrc cho bài đang phát"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) < 1_000_000 else { message = "File lời phải nhỏ hơn 1 MB."; return }
            let parsed = LRC.parse(try String(contentsOf: url, encoding: .utf8))
            guard !parsed.isEmpty else { message = "File chưa có timestamp LRC hợp lệ hoặc không phải UTF-8."; return }
            lyrics = parsed
            message = "Đã nhập \(url.lastPathComponent) · lời được gắn với bài hiện tại"
        } catch { message = "Không đọc được file lời: \(error.localizedDescription)" }
    }

    private func clearTrack() {
        playing = false; trackID = ""; title = "Chờ Spotify"; artist = ""
        duration = 0; setPosition(0); lyrics = []; artwork = nil; artworkTask?.cancel()
    }
    private func setPosition(_ value: Double) {
        base = min(max(0, value), max(0, duration))
        anchor = ProcessInfo.processInfo.systemUptime
    }
    private func loadDemoLyrics() {
        lyrics = LRC.parse("[00:00]Một chút nhạc, một khoảng trời riêng.\n[00:08]Đèn thành phố trôi qua thật chậm.\n[00:16]Giữ nhịp này, rồi làm tiếp thôi.\n[00:26]Music Island — made for your Mac.")
    }
    private func loadArtwork(_ url: URL?, track: String) {
        artworkTask?.cancel()
        guard let url = url, url.scheme == "https" else { return }
        artworkTask = URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)) { [weak self] data, _, _ in
            guard let data = data, data.count < 5_000_000 else { return }
            Task { @MainActor in
                guard let self = self, !self.demo, self.trackID == track else { return }
                self.artwork = NSImage(data: data)
            }
        }
        artworkTask?.resume()
    }
}
