import XCTest
@testable import IslandCore

final class IslandCoreTests: XCTestCase {
    func testUnicodeMultipleStampsAndOffset() {
        let lines = LRC.parse("[offset:-250]\n[00:02.50][00:05.005]Đêm Hà Nội 🌙\n[00:01]Xin chào")
        XCTAssertEqual(lines.map(\.time), [0.75, 2.25, 4.755])
        XCTAssertNil(LRC.current(in: lines, at: 0))
        XCTAssertEqual(LRC.current(in: lines, at: 3), "Đêm Hà Nội 🌙")
    }
    func testMalformedInputAndBlankLine() {
        let lines = LRC.parse("[ar:Someone]\n[00:99]invalid\n[xx:yy]bad\n[00:01]Hello\n[00:02]")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(LRC.current(in: lines, at: 2), "")
    }
    func testPlaybackDoesNotDriftWhenPausedOrExceedDuration() {
        XCTAssertEqual(PlaybackClock.position(base: 20, elapsed: 4, playing: false, duration: 30), 20)
        XCTAssertEqual(PlaybackClock.position(base: 20, elapsed: 40, playing: true, duration: 30), 30)
        XCTAssertEqual(PlaybackClock.position(base: -5, elapsed: 0, playing: true, duration: 30), 0)
    }
}

final class SourceSelectionTests: XCTestCase {
    func testPlayingSourceWinsOverPausedAndSelectionStaysStable() {
        let sources = [SourceCandidate(id: "Spotify", playing: false), SourceCandidate(id: "Music", playing: true)]
        XCTAssertEqual(SourceSelection.choose(sources, current: "Spotify", pinned: nil), "Music")
        let both = [SourceCandidate(id: "Spotify", playing: true), SourceCandidate(id: "Music", playing: true)]
        XCTAssertEqual(SourceSelection.choose(both, current: "Music", pinned: nil), "Music")
    }
    func testPinnedSourceNeverFallsThroughToAnotherPlayer() {
        let sources = [SourceCandidate(id: "Spotify", playing: true)]
        XCTAssertNil(SourceSelection.choose(sources, current: "Spotify", pinned: "closed-tab"))
        XCTAssertNil(SourceSelection.choose([], current: "Spotify", pinned: nil))
    }
}

final class IslandEngineTests: XCTestCase {
    func testTransientRestoresActivitiesAndDoesNotLoseExpandedState() {
        let now = Date(timeIntervalSince1970: 100)
        var engine = IslandEngine()
        engine.post(IslandEvent(id: "music", title: "Song", symbol: "music.note", priority: 10))
        engine.post(IslandEvent(id: "timer", title: "Timer", symbol: "timer", priority: 20))
        XCTAssertEqual(engine.state, .multiActivity)
        engine.post(IslandEvent(id: "volume", title: "50%", symbol: "speaker", priority: 30, expiresAt: now.addingTimeInterval(2)))
        XCTAssertEqual(engine.state, .transientHUD)
        engine.userExpanded = true
        XCTAssertEqual(engine.state, .expanded)
        engine.expire(at: now.addingTimeInterval(3))
        XCTAssertEqual(engine.state, .expanded)
        engine.userExpanded = false
        XCTAssertEqual(engine.state, .multiActivity)
        XCTAssertEqual(engine.activities.count, 2)
    }
    func testCoalescingExtendsTTLAndPriorityIsStable() {
        let now = Date(timeIntervalSince1970: 100)
        var engine = IslandEngine()
        engine.post(IslandEvent(id: "volume", title: "10%", symbol: "speaker", priority: 30, expiresAt: now))
        engine.post(IslandEvent(id: "volume", title: "50%", symbol: "speaker", priority: 30, expiresAt: now.addingTimeInterval(4)))
        engine.post(IslandEvent(id: "battery", title: "Low", symbol: "battery", priority: 70, expiresAt: now.addingTimeInterval(2)))
        XCTAssertEqual(engine.events.count, 2)
        XCTAssertEqual(engine.transient?.id, "battery")
        engine.expire(at: now.addingTimeInterval(3))
        XCTAssertEqual(engine.transient?.title, "50%")
        engine.expire(at: now.addingTimeInterval(5))
        XCTAssertEqual(engine.state, .idle)
    }
}
