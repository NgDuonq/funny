import Foundation

struct MediaSnapshot: Identifiable {
    let id: String
    let source: String
    let track: String
    let title: String
    let artist: String
    let duration: Double
    let position: Double
    let playing: Bool
    let artwork: URL?
    let canSeek: Bool
    let canToggle: Bool
    let canNext: Bool
    let canPrevious: Bool
    let target: MediaTarget
}

enum MediaTarget {
    case native(String)
    case web(app: String, window: Int, tab: Int, url: String, track: String)
}

enum MediaCommand {
    case toggle, next, previous, seek(Double)
    var name: String {
        switch self { case .toggle: return "toggle"; case .next: return "next"
        case .previous: return "previous"; case .seek: return "seek" }
    }
    var seconds: Double { if case .seek(let x) = self, x.isFinite { return max(0, x) }; return 0 }
    var native: String {
        switch self { case .toggle: return "playpause"; case .next: return "next track"
        case .previous: return "previous track"; case .seek: return "set player position to \(seconds)" }
    }
}

struct MediaScan {
    var sources: [MediaSnapshot] = []
    var errors: [String] = []
}

private struct WebSnapshot: Decodable {
    let track, title, artist, artwork: String
    let duration, position: Double
    let playing, canSeek, canToggle, canNext, canPrevious: Bool
}

/// Single background worker. Only user-enabled providers are contacted; errors are isolated.
final class MediaBridge {
    static let providers = ["Spotify", "Music", "Google Chrome", "Safari", "Brave Browser", "Microsoft Edge"]
    static let bundleIDs = ["Spotify": "com.spotify.client", "Music": "com.apple.Music",
        "Google Chrome": "com.google.Chrome", "Safari": "com.apple.Safari",
        "Brave Browser": "com.brave.Browser", "Microsoft Edge": "com.microsoft.edgemac"]
    private let queue = DispatchQueue(label: "dynamicnotch.media", qos: .utility)
    private var blocked: [String: String] = [:]
    private let webScript: String = {
        let packaged = Bundle.main.url(forResource: "MusicIsland_MusicIsland", withExtension: "bundle").flatMap { Bundle(url: $0) }
        let resources = packaged ?? Bundle.module
        guard let url = resources.url(forResource: "WebPlayer", withExtension: "js") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    var hasWebScript: Bool { !webScript.isEmpty }

    func retry() { queue.async { self.blocked.removeAll() } }

    func scan(providers: [String], completion: @escaping (MediaScan) -> Void) {
        queue.async {
            var result = MediaScan()
            for app in providers where Self.providers.contains(app) {
                if let error = self.blocked[app] { result.errors.append(error); continue }
                do {
                    if app == "Spotify" || app == "Music" {
                        if let item = try self.readNative(app) { result.sources.append(item) }
                    } else { result.sources += try self.readBrowser(app) }
                } catch {
                    let hint = app == "Spotify" || app == "Music"
                        ? "\(app): kiểm tra quyền Automation, rồi bấm Thử lại."
                        : "\(app): cần quyền Automation và Allow JavaScript from Apple Events, rồi bấm Thử lại."
                    self.blocked[app] = hint
                    result.errors.append(hint)
                }
            }
            completion(result)
        }
    }

    func send(_ command: MediaCommand, to target: MediaTarget, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            do {
                switch target {
                case .native(let app):
                    _ = try self.run("if application \(Self.quote(app)) is not running then error \"Player closed\"\ntell application \(Self.quote(app))\n\(command.native)\nend tell")
                case .web(let app, let window, let tab, let url, let track):
                    let js = self.javascript(command.name, track: track, time: command.seconds)
                    let execute = app == "Safari" ? "do JavaScript \(Self.quote(js)) in t" : "execute t javascript \(Self.quote(js))"
                    let response = try self.run("""
                    tell application \(Self.quote(app))
                        set w to first window whose id is \(window)
                        set t to tab \(tab) of w
                        if (URL of t) is not \(Self.quote(url)) then error "Tab changed"
                        return \(execute)
                    end tell
                    """)
                    guard response == "ok" else { throw NSError(domain: "WebPlayer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Tab/bài đã đổi hoặc thao tác chưa được trang hỗ trợ. Hãy chọn lại nguồn."]) }
                }
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }

    private func readNative(_ app: String) throws -> MediaSnapshot? {
        let spotify = app == "Spotify"
        let output = try run("""
        if application \(Self.quote(app)) is not running then return ""
        tell application \(Self.quote(app))
            if player state is stopped then return ""
            set t to current track
            set sep to ASCII character 31
            set art to ""
            \(spotify ? "try\nset art to artwork url of t\nend try" : "")
            return (\(spotify ? "id" : "persistent ID") of t) & sep & (name of t) & sep & (artist of t) & sep & ((duration of t) as text) & sep & ((player position) as text) & sep & ((player state) as text) & sep & art
        end tell
        """)
        if output.isEmpty { return nil }
        let f = output.components(separatedBy: "\u{1f}")
        func number(_ s: String) -> Double { let n = Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0; return n.isFinite ? max(0, n) : 0 }
        guard f.count == 7 else { throw NSError(domain: "Media", code: 2) }
        let duration = number(f[3]) / (spotify ? 1000 : 1)
        return MediaSnapshot(id: app, source: spotify ? "Spotify" : "Apple Music", track: f[0], title: f[1], artist: f[2],
            duration: duration, position: number(f[4]), playing: f[5] == "playing", artwork: URL(string: f[6]),
            canSeek: duration > 0, canToggle: true, canNext: true, canPrevious: true, target: .native(app))
    }

    private func javascript(_ command: String, track: String = "", time: Double = 0) -> String {
        func json(_ value: String) -> String {
            let data = try! JSONEncoder().encode(value)
            return String(decoding: data, as: UTF8.self)
        }
        return webScript + "(\(json(command)), \(json(track)), \(time));"
    }

    private func readBrowser(_ app: String) throws -> [MediaSnapshot] {
        let js = Self.quote(javascript("read"))
        let execute = app == "Safari" ? "do JavaScript \(js) in t" : "execute t javascript \(js)"
        // Domain checks run before JavaScript. The JS repeats the hostname validation.
        let hosts = ["soundcloud.com", "www.soundcloud.com", "youtube.com", "www.youtube.com", "music.youtube.com", "open.spotify.com", "music.apple.com"]
        let checks = hosts.map { "u starts with \(Self.quote("https://" + $0 + "/"))" }.joined(separator: " or ")
        let output = try run("""
        if application \(Self.quote(app)) is not running then return ""
        tell application \(Self.quote(app))
            set output to ""
            set inspected to 0
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    set u to URL of t
                    if \(checks) then
                        set inspected to inspected + 1
                        if inspected > 12 then return output
                        set payload to \(execute)
                        if payload is not "" and payload is not missing value then
                            set output to output & ((id of w) as text) & (ASCII character 31) & (i as text) & (ASCII character 31) & u & (ASCII character 31) & payload & linefeed
                        end if
                    end if
                end repeat
            end repeat
            return output
        end tell
        """)
        return output.components(separatedBy: .newlines).compactMap { line in
            let f = line.components(separatedBy: "\u{1f}")
            guard f.count == 4, let window = Int(f[0]), let tab = Int(f[1]),
                  let s = try? JSONDecoder().decode(WebSnapshot.self, from: Data(f[3].utf8)) else { return nil }
            let host = URL(string: f[2])?.host ?? "Web"
            return MediaSnapshot(id: "\(app):\(window):\(tab):\(f[2])", source: "\(host) · \(app)", track: s.track,
                title: s.title, artist: s.artist, duration: s.duration, position: s.position, playing: s.playing,
                artwork: URL(string: s.artwork), canSeek: s.canSeek, canToggle: s.canToggle,
                canNext: s.canNext, canPrevious: s.canPrevious,
                target: .web(app: app, window: window, tab: tab, url: f[2], track: s.track))
        }
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func run(_ script: String) throws -> String {
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "with timeout of 4 seconds\n\(script)\nend timeout"]
        p.standardOutput = out; p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let error = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "AppleEvents", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: String(decoding: error, as: UTF8.self)])
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }
}
