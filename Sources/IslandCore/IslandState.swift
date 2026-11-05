import Foundation

public struct IslandEvent: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var symbol: String
    public var priority: Int
    public var progress: Double?
    public var expiresAt: Date?
    public init(id: String, title: String, symbol: String, priority: Int, progress: Double? = nil, expiresAt: Date? = nil) {
        self.id = id; self.title = title; self.symbol = symbol; self.priority = priority
        self.progress = progress.map { min(1, max(0, $0)) }; self.expiresAt = expiresAt
    }
}
public enum IslandState: Equatable { case idle, transientHUD, expanded, multiActivity }
public enum PriorityEngine {
    public static func top(_ events: [IslandEvent]) -> IslandEvent? {
        events.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }.first
    }
}
public struct IslandEngine {
    public private(set) var events: [String: IslandEvent] = [:]
    public var userExpanded = false
    public init() {}
    public mutating func post(_ event: IslandEvent) { events[event.id] = event }
    public mutating func remove(_ id: String) { events[id] = nil }
    public mutating func expire(at now: Date) { events = events.filter { $0.value.expiresAt.map { $0 > now } ?? true } }
    public var nextExpiry: Date? { events.values.compactMap(\.expiresAt).min() }
    public var transient: IslandEvent? { PriorityEngine.top(events.values.filter { $0.expiresAt != nil }) }
    public var activities: [IslandEvent] { events.values.filter { $0.expiresAt == nil }.sorted { $0.id < $1.id } }
    public var state: IslandState {
        if userExpanded { return .expanded }
        if transient != nil { return .transientHUD }
        return activities.count > 1 ? .multiActivity : .idle
    }
}
