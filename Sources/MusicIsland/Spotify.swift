import Foundation

struct SpotifySnapshot {
    let id: String
    let title: String
    let artist: String
    let duration: Double
    let position: Double
    let playing: Bool
    let artwork: URL?
}

enum SpotifyCommand {
    case toggle, next, previous, seek(Double)
    var script: String {
        switch self {
        case .toggle: return "playpause"
        case .next: return "next track"
        case .previous: return "previous track"
        case .seek(let seconds): return "set player position to \(seconds.isFinite ? max(0, seconds) : 0)"
        }
    }
}

/// All Apple events execute serially off the main thread; no shell interpolation.
final class SpotifyBridge {
    private let queue = DispatchQueue(label: "musicisland.spotify", qos: .utility)

    func read(completion: @escaping (Result<SpotifySnapshot?, Error>) -> Void) {
        execute(#"""
        if application "Spotify" is not running then return ""
        tell application "Spotify"
            if player state is stopped then return ""
            set t to current track
            set sep to ASCII character 31
            return (id of t) & sep & (name of t) & sep & (artist of t) & sep & ((duration of t) as text) & sep & ((player position) as text) & sep & ((player state) as text) & sep & (artwork url of t)
        end tell
        """#) { result in
            completion(result.flatMap { output in
                if output.isEmpty { return .success(nil) }
                let fields = output.components(separatedBy: "\u{1f}")
                // AppleScript's numeric text may use the user's decimal separator.
                func number(_ value: String) -> Double? { Double(value.replacingOccurrences(of: ",", with: ".")) }
                guard fields.count == 7, let duration = number(fields[3]), let position = number(fields[4]) else {
                    return .failure(NSError(domain: "Spotify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không đọc được dữ liệu Spotify."]))
                }
                return .success(SpotifySnapshot(id: fields[0], title: fields[1], artist: fields[2],
                    duration: duration / 1000, position: position, playing: fields[5] == "playing",
                    artwork: URL(string: fields[6])))
            })
        }
    }

    func send(_ command: SpotifyCommand, completion: @escaping (Result<String, Error>) -> Void) {
        execute("if application \"Spotify\" is not running then return \"\"\ntell application \"Spotify\"\n\(command.script)\nend tell", completion: completion)
    }

    private func execute(_ body: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            let process = Process()
            let output = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "with timeout of 3 seconds\n\(body)\nend timeout"]
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    completion(.success(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)))
                } else {
                    let detail = String(decoding: errorData, as: UTF8.self)
                    let message = detail.contains("-1743")
                        ? "Cấp quyền Spotify trong System Settings → Privacy & Security → Automation, rồi kết nối lại."
                        : "Spotify chưa phản hồi. Mở Spotify desktop, phát một bài rồi kết nối lại."
                    completion(.failure(NSError(domain: "Spotify", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])))
                }
            } catch { completion(.failure(error)) }
        }
    }
}
