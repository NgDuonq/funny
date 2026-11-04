import AppKit
import SwiftUI
import IslandCore

@MainActor
final class PlayerModel: ObservableObject {
    @Published var title = "Dynamic Notch"
    @Published var artist = "Mở nhạc để bắt đầu"
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var demo = false
    @Published var artwork: NSImage?
    @Published var message = "Tự tìm Spotify và Apple Music đang mở."
    @Published var lyrics: [LyricLine] = []
    @Published var showIsland = true
    @Published var lowPower = true
    @Published var sources: [MediaSnapshot] = []
    @Published var pinned = "auto" { didSet { chooseSource() } }
    @Published var providerErrors: [String] = []
    @Published var enabled: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "enabledProviders") ?? ["Spotify", "Music"])
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    @Published var hasNotch = true
    @Published private var base: Double = 0
    private var anchor = ProcessInfo.processInfo.systemUptime
    private let bridge = MediaBridge()
    private var timer: Timer?
    private var busy = false
    private var suspended = false
    private var generation = 0
    private var current: MediaSnapshot?
    private var trackID = ""
    private var artworkTask: URLSessionDataTask?

    var sourceName: String { demo ? "Demo · không phát âm thanh" : current?.source ?? "Chờ trình phát" }
    var position: Double {
        PlaybackClock.position(base: base, elapsed: ProcessInfo.processInfo.systemUptime - anchor,
                               playing: playing && !suspended, duration: duration)
    }
    var lyric: String { LRC.current(in: lyrics, at: position) ?? "" }
    var canControl: Bool { demo || current != nil }
    var canToggle: Bool { demo || current?.canToggle == true }
    var canSeek: Bool { demo || current?.canSeek == true }
    var canNext: Bool { demo || current?.canNext == true }
    var canPrevious: Bool { demo || current?.canPrevious == true }

    func setProvider(_ app: String, enabled value: Bool) {
        if value { enabled.insert(app) } else { enabled.remove(app) }
        UserDefaults.standard.set(Array(enabled), forKey: "enabledProviders")
        sources.removeAll { item in
            switch item.target { case .native(let name): return !enabled.contains(name)
            case .web(let name, _, _, _, _): return !enabled.contains(name) }
        }
        chooseSource()
        connect()
    }
    func setSuspended(_ value: Bool) {
        base = position; anchor = ProcessInfo.processInfo.systemUptime; suspended = value
        if !value { refresh() }
    }
    func selectDemo() {
        generation += 1
        timer?.invalidate(); timer = nil; artworkTask?.cancel()
        demo = true; title = "Midnight in Hanoi"; artist = "Dynamic Notch · Demo"
        duration = 180; playing = true; artwork = nil; current = nil; trackID = "demo"
        setPosition(0)
        lyrics = LRC.parse("[00:00]Một chút nhạc, một khoảng trời riêng.\n[00:08]Đèn thành phố trôi qua thật chậm.\n[00:16]Giữ nhịp này, rồi làm tiếp thôi.")
        message = "Demo giao diện · không phát âm thanh"
    }
    func connect() {
        generation += 1; demo = false; bridge.retry()
        clearTrack(); providerErrors = []; sources = []
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        timer?.tolerance = 0.5
        refresh()
    }
    func refresh() {
        guard !demo, !busy, !suspended else { return }
        busy = true
        let request = generation
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let providers = MediaBridge.providers.filter { enabled.contains($0) && running.contains(MediaBridge.bundleIDs[$0] ?? "") }
        bridge.scan(providers: providers) { [weak self] scan in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.busy = false
                guard self.generation == request, !self.demo else { return }
                self.sources = scan.sources; self.providerErrors = scan.errors
                self.chooseSource()
            }
        }
    }
    private func chooseSource() {
        guard !demo else { return }
        let id = SourceSelection.choose(sources.map { SourceCandidate(id: $0.id, playing: $0.playing) },
            current: current?.id, pinned: pinned == "auto" ? nil : pinned)
        guard let s = sources.first(where: { $0.id == id }) else {
            clearTrack()
            message = pinned == "auto" ? "Chưa thấy bài nhạc. Mở trình phát hoặc bật trình duyệt ở phần Nguồn." : "Nguồn đã chọn không còn khả dụng. Chọn Tự động để đổi nguồn."
            return
        }
        let key = s.id + "|" + s.track
        if key != trackID {
            trackID = key; lyrics = []; artwork = nil
            loadArtwork(s.artwork, track: key)
        }
        current = s; title = s.title; artist = s.artist
        duration = s.duration; playing = s.playing; setPosition(s.position)
        message = s.canSeek ? "Đang theo dõi " + s.source : "Nguồn này chưa cung cấp tua/thời lượng; vẫn dùng các nút khả dụng."
    }
    func command(_ command: MediaCommand) {
        guard canControl else { return }
        if demo {
            switch command {
            case .toggle: let time = position; playing.toggle(); setPosition(time)
            case .seek(let time): setPosition(time)
            case .next, .previous: setPosition(0)
            }
            return
        }
        guard let target = current?.target else { return }
        let request = generation
        bridge.send(command, to: target) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, request == self.generation else { return }
                if case .failure = result { self.message = "Không điều khiển được nguồn này. Kiểm tra quyền hoặc chọn lại tab/trình phát." }
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
        playing = false; current = nil; trackID = ""; title = "Dynamic Notch"; artist = "Chờ nhạc…"
        duration = 0; setPosition(0); lyrics = []; artwork = nil; artworkTask?.cancel()
    }
    private func setPosition(_ value: Double) {
        base = value.isFinite ? min(max(0, value), max(0, duration)) : 0
        anchor = ProcessInfo.processInfo.systemUptime
    }
    private func loadArtwork(_ url: URL?, track: String) {
        artworkTask?.cancel()
        guard let url, url.scheme == "https" else { return }
        artworkTask = URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)) { [weak self] data, _, _ in
            guard let data, data.count < 5_000_000 else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.demo, self.trackID == track else { return }
                self.artwork = NSImage(data: data)
            }
        }
        artworkTask?.resume()
    }
}
