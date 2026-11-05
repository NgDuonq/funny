import SwiftUI
import Combine
import IslandCore

@MainActor final class EventBus {
    let events = PassthroughSubject<IslandEvent, Never>()
    func post(_ event: IslandEvent) { events.send(event) }
}
@MainActor final class EventScheduler {
    private var task: Task<Void, Never>?
    func schedule(at date: Date?, action: @escaping @MainActor () -> Void) {
        task?.cancel()
        guard let date else { return }
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, min(86400, date.timeIntervalSinceNow)) * 1_000_000_000))
            guard !Task.isCancelled else { return }; action()
        }
    }
    func cancel() { task?.cancel() }
}
@MainActor final class SettingsStore: ObservableObject {
    @Published var reduceMotion = UserDefaults.standard.bool(forKey: "reduceMotion") {
        didSet { UserDefaults.standard.set(reduceMotion, forKey: "reduceMotion") }
    }
    @Published var systemHUDs = UserDefaults.standard.object(forKey: "systemHUDs") as? Bool ?? true {
        didSet { UserDefaults.standard.set(systemHUDs, forKey: "systemHUDs") }
    }
}
@MainActor final class IslandCoordinator: ObservableObject {
    let bus = EventBus()
    let settings = SettingsStore()
    let scheduler = EventScheduler()
    @Published private(set) var engine = IslandEngine()
    @Published var pinnedOpen = false
    @Published var timerEnd: Date?
    @Published var timerPaused: TimeInterval?
    private var timerTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()
    private var sleeping = false
    init() {
        bus.events.sink { [weak self] event in self?.receive(event) }.store(in: &subscriptions)
    }
    func bindMusic(_ player: PlayerModel) {
        player.$title.combineLatest(player.$playing).debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] title, playing in
                guard let self else { return }
                if playing {
                    self.receive(IslandEvent(id: "music", title: title, symbol: "music.note", priority: 10))
                } else { self.remove("music") }
            }.store(in: &subscriptions)
    }
    func receive(_ event: IslandEvent) {
        if !settings.systemHUDs && event.id.hasPrefix("system.") { return }
        guard engine.events[event.id] != event else { return }
        engine.post(event); schedule()
    }
    func remove(_ id: String) { engine.remove(id); schedule() }
    func expand(_ value: Bool) { engine.userExpanded = value || pinnedOpen }
    func togglePin() { pinnedOpen.toggle(); engine.userExpanded = pinnedOpen }
    func schedule() {
        guard !sleeping else { return }
        scheduler.schedule(at: engine.nextExpiry) { [weak self] in
            guard let self else { return }; self.engine.expire(at: Date()); self.schedule()
        }
    }
    func sleep(_ value: Bool) {
        sleeping = value
        if value { scheduler.cancel(); timerTask?.cancel() }
        else { engine.expire(at: Date()); schedule(); armTimer() }
    }
    func startTimer(seconds: TimeInterval) {
        timerEnd = Date().addingTimeInterval(seconds); timerPaused = nil
        receive(IslandEvent(id: "timer", title: "Timer", symbol: "timer", priority: 20))
        armTimer()
    }
    func pauseTimer() {
        if let end = timerEnd {
            timerPaused = max(0, end.timeIntervalSinceNow); timerEnd = nil; timerTask?.cancel()
        } else if let remaining = timerPaused { startTimer(seconds: remaining) }
    }
    func cancelTimer() {
        timerTask?.cancel(); timerEnd = nil; timerPaused = nil; remove("timer"); remove("timer.done")
    }
    private func armTimer() {
        timerTask?.cancel()
        guard let end = timerEnd else { return }
        timerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, min(86400, end.timeIntervalSinceNow)) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            timerEnd = nil; remove("timer")
            receive(IslandEvent(id: "timer.done", title: "Timer hoàn thành", symbol: "checkmark.circle.fill", priority: 80, expiresAt: Date().addingTimeInterval(30)))
        }
    }
}
