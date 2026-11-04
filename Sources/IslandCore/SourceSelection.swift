import Foundation

public struct SourceCandidate: Equatable {
    public let id: String
    public let playing: Bool
    public init(id: String, playing: Bool) { self.id = id; self.playing = playing }
}

public enum SourceSelection {
    public static func choose(_ sources: [SourceCandidate], current: String?, pinned: String?) -> String? {
        if let pinned { return sources.first(where: { $0.id == pinned })?.id }
        if let active = sources.first(where: { $0.id == current && $0.playing }) { return active.id }
        if let active = sources.first(where: \.playing) { return active.id }
        return sources.first(where: { $0.id == current })?.id ?? sources.first?.id
    }
}
