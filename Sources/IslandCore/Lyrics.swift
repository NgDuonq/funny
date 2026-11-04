import Foundation

public struct LyricLine: Equatable, Sendable {
    public let time: Double
    public let text: String
}

public enum LRC {
    /// Supports multiple timestamps, fractional seconds and the global millisecond offset.
    public static func parse(_ source: String) -> [LyricLine] {
        let pattern = #"\[(\d+):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let offsetRegex = try? NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#)
        else { return [] }
        let ns = source as NSString
        let offset = offsetRegex.firstMatch(in: source, range: NSRange(location: 0, length: ns.length))
            .flatMap { Double(ns.substring(with: $0.range(at: 1))) }.map { $0 / 1000 } ?? 0
        var result: [LyricLine] = []
        for line in source.components(separatedBy: .newlines) {
            let string = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: string.length))
            guard let last = matches.last else { continue }
            let text = string.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Double(string.substring(with: match.range(at: 1))),
                      let seconds = Double(string.substring(with: match.range(at: 2))), seconds < 60 else { continue }
                let fractionRange = match.range(at: 3)
                let fraction = fractionRange.location == NSNotFound ? 0 :
                    (Double("0." + string.substring(with: fractionRange)) ?? 0)
                result.append(LyricLine(time: max(0, minutes * 60 + seconds + fraction + offset), text: text))
            }
        }
        return result.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }.map(\.element)
    }

    public static func current(in lines: [LyricLine], at time: Double) -> String? {
        lines.last(where: { $0.time <= time })?.text
    }
}

public enum PlaybackClock {
    public static func position(base: Double, elapsed: Double, playing: Bool, duration: Double) -> Double {
        min(max(0, duration), max(0, base + (playing ? max(0, elapsed) : 0)))
    }
}
