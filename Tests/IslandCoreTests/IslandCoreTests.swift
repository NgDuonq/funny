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
