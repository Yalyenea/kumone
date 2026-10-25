import Testing
@testable import KumoneCore

@Suite struct PlaybackModeTests {
    @Test func cycleWithoutAutoMixVisitsEveryStandardModeOnce() {
        var mode = PlaybackMode.ordered
        var visited: [PlaybackMode] = []
        for _ in 0..<3 {
            visited.append(mode)
            mode = mode.next(autoMixAvailable: false)
        }
        #expect(visited == [.ordered, .shuffled, .repeatOne])
        #expect(mode == .ordered)
    }

    @Test func autoMixOnlyJoinsWhenAvailable() {
        #expect(PlaybackMode.repeatOne.next(autoMixAvailable: true) == .autoMix)
        #expect(PlaybackMode.autoMix.next(autoMixAvailable: false) == .ordered)
    }

    @Test(arguments: PlaybackMode.allCases)
    func everySelectionRoundTripsThroughEngineState(_ mode: PlaybackMode) {
        #expect(PlaybackMode(queueOrder: mode.queueOrder, repeatMode: mode.repeatMode) == mode)
    }

    @Test func leavingSingleRepeatClearsItEvenAfterRestoringAShuffledSession() {
        let restored = PlaybackMode(queueOrder: .shuffled, repeatMode: .one)
        #expect(restored == .repeatOne)
        let next = restored.next(autoMixAvailable: false)
        #expect(next.queueOrder == .listed)
        #expect(next.repeatMode == .off)
        #expect(PlaybackMode.shuffled.repeatMode == .all)
    }

    @Test func removedListRepeatRestoresAsOrderedPlayback() {
        let restored = PlaybackMode(queueOrder: .listed, repeatMode: .all)
        #expect(restored == .ordered)
        #expect(restored.repeatMode == .off)
    }
}
