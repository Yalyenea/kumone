import Testing
import Foundation
import QuartzCore
@testable import KumoneCore

@Suite("Vinyl Record Tests")
struct VinylRecordTests {
    @Test @MainActor func tonearmTracksProgressWithoutNeedingAPlayPauseChange() throws {
        let layer = CALayer()
        let motion = TonearmMotionController(layer: layer, engaged: true, progress: 0)
        let start = try #require(layer.value(forKeyPath: "transform.rotation.z") as? Double)
        motion.setEngaged(true, progress: 0.5, animated: false)
        let middle = try #require(layer.value(forKeyPath: "transform.rotation.z") as? Double)
        motion.setEngaged(true, progress: 1, animated: false)
        let end = try #require(layer.value(forKeyPath: "transform.rotation.z") as? Double)
        #expect(start > middle && middle > end)

        // Seeking backward must move the same layer back to its earlier groove.
        motion.setEngaged(true, progress: 0, animated: false)
        let rewound = try #require(layer.value(forKeyPath: "transform.rotation.z") as? Double)
        #expect(abs(rewound - start) < 1e-12)
        motion.setEngaged(false, progress: 0, animated: false)
        let parked = layer.value(forKeyPath: "transform.rotation.z") as? Double
        motion.setEngaged(false, progress: 1, animated: false)
        #expect(layer.value(forKeyPath: "transform.rotation.z") as? Double == parked)
        motion.setEngaged(true, progress: 1, animated: false)
        let resumed = try #require(layer.value(forKeyPath: "transform.rotation.z") as? Double)
        #expect(abs(resumed - end) < 1e-12)
    }

    @Test @MainActor func tonearmClampsProgressAndClearsAnimationForImmediateUpdates() throws {
        let layer = CALayer()
        let motion = TonearmMotionController(layer: layer, engaged: true, progress: 0)
        let start = layer.value(forKeyPath: "transform.rotation.z") as? Double
        for progress in [-1.0, .nan, .infinity] {
            motion.setEngaged(true, progress: progress, animated: false)
            #expect(layer.value(forKeyPath: "transform.rotation.z") as? Double == start)
        }
        motion.setEngaged(true, progress: 1, animated: true)
        #expect(layer.animation(forKey: "tonearm-engage") != nil)
        let end = layer.value(forKeyPath: "transform.rotation.z") as? Double
        motion.setEngaged(true, progress: 2, animated: false)
        #expect(layer.value(forKeyPath: "transform.rotation.z") as? Double == end)
        motion.setEngaged(true, progress: 0, animated: false)
        #expect(layer.animation(forKey: "tonearm-engage") == nil)
    }

    @Test func rotationStateAngleCalculation() {
        var state = RecordRotationState(degreesPerSecond: 20)
        let t0 = Date(timeIntervalSince1970: 1000)

        // Before starting: angle is 0
        #expect(state.currentAngle(at: t0) == 0)
        #expect(!state.isAnimating)

        // Start at t0
        state.start(at: t0)
        #expect(state.isAnimating)

        // After 2.5 seconds: angle should be 50 degrees
        let t1 = Date(timeIntervalSince1970: 1002.5)
        #expect(state.currentAngle(at: t1) == 50.0)

        // Stop at t1
        state.stop(at: t1)
        #expect(!state.isAnimating)
        #expect(state.currentAngle(at: t1) == 50.0)

        // Even after time passes while stopped, angle stays at 50 degrees (no jumping)
        let t2 = Date(timeIntervalSince1970: 1010.0)
        #expect(state.currentAngle(at: t2) == 50.0)

        // Resume at t2: continues smoothly from 50 degrees
        state.start(at: t2)
        #expect(state.isAnimating)
        let t3 = Date(timeIntervalSince1970: 1011.0)
        #expect(state.currentAngle(at: t3) == 70.0)
    }

    @Test func nowPlayingModeCases() {
        #expect(NowPlayingMode.allCases.contains(.vinyl))
        #expect(NowPlayingMode.vinyl.displayName == "黑胶模式")
    }
}
