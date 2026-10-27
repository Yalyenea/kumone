import AVFoundation
import Foundation
import Testing
@testable import KumoneCore

@Suite("AI EQ audio output")
struct AISoundEffectRenderingTests {
    @Test(arguments: [44_100.0, 96_000.0, 192_000.0])
    func officialGainsChangeAudioAtTheOriginalProcessingRate(_ rate: Double) throws {
        let effect = AISoundEffect(aev2: .init(eq: .init(on: true, eqs: [0, 0, 0, 0, 0, 6, 0, 0, 0, 0])), effectStyle: nil)
        let dry = try render(effect: nil, rate: rate)
        let zero = try render(effect: effect, strength: 0, rate: rate)
        let wet = try render(effect: effect, rate: rate)
        #expect(abs(dry.rms - zero.rms) < 0.00001)
        let measured = 20 * log10(wet.rms / dry.rms)
        let expected = 6 + AISoundEffect.preampDB(gains: effect.gains(strength: 1), sampleRate: rate)
        #expect(abs(measured - expected) < 0.15, "measured \(measured) dB; expected \(expected) dB at \(rate) Hz")
        #expect(wet.peak < 1)
    }

    @Test(arguments: [63.0, 250.0, 1000.0, 4000.0, 16000.0])
    func combinedBoostRetainsHeadroomAtFullScale(_ frequency: Double) throws {
        let effect = AISoundEffect(aev2: .init(eq: .init(on: true, eqs: Array(repeating: 6, count: 10))), effectStyle: nil)
        let rendered = try render(effect: effect, rate: 96_000, frequency: frequency, amplitude: 0.99)
        #expect(rendered.peak > 0.01)
        #expect(rendered.peak <= 1, "clipping at \(frequency) Hz, peak \(rendered.peak)")
    }

    private func render(effect: AISoundEffect?, strength: Double = 1, rate: Double,
                        frequency: Double = 1000, amplitude: Float = 0.2) throws -> (rms: Double, peak: Float) {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        let equalizer = AVAudioUnitEQ(numberOfBands: 10)
        AISoundEffect.configure(equalizer, effect: effect, strength: strength, sampleRate: rate)
        engine.attach(player)
        engine.attach(equalizer)
        engine.connect(player, to: equalizer, format: format)
        engine.connect(equalizer, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        let frames = AVAudioFrameCount(rate)
        let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        source.frameLength = frames
        for channel in 0..<2 {
            for i in 0..<Int(frames) {
                source.floatChannelData![channel][i] = amplitude * sin(2 * .pi * Float(frequency) * Float(i) / Float(rate))
            }
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(source)
        player.play()
        let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var rendered: AVAudioFrameCount = 0
        var sum = 0.0, count = 0
        var peak: Float = 0
        while rendered < frames {
            let status = try engine.renderOffline(min(4096, frames - rendered), to: output)
            #expect(status == .success)
            guard status == .success else { break }
            for i in 0..<Int(output.frameLength) where Int(rendered) + i > Int(frames) / 2 {
                let value = output.floatChannelData![0][i]
                sum += Double(value) * Double(value)
                peak = max(peak, abs(value))
                count += 1
            }
            rendered += output.frameLength
        }
        #expect(count > 0)
        return (sqrt(sum / Double(max(1, count))), peak)
    }
}
