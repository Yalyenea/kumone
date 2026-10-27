import AVFoundation
import Foundation

/// Only the official per-song EQ parameters are rendered here. Other groups
/// in the document (reverb, stereo enhancement, feature analysis) belong to
/// NetEase's native DSP and are deliberately not presented as supported.
struct AISoundEffect: Codable, Equatable, Sendable {
    struct Parameters: Codable, Equatable, Sendable {
        struct Equalizer: Codable, Equatable, Sendable {
            let on: Bool
            let eqs: [Double]
        }
        let eq: Equalizer
    }
    let aev2: Parameters
    let effectStyle: String?

    enum CodingKeys: String, CodingKey { case aev2; case effectStyle = "effect_style" }

    func validate() throws {
        guard aev2.eq.eqs.count == 10,
              aev2.eq.eqs.allSatisfy({ $0.isFinite && (-24...24).contains($0) }) else {
            throw NCAEContainer.DecodingError.invalidPayload
        }
    }

    static func decode(package: Data) throws -> Self {
        let effect = try JSONDecoder().decode(Self.self, from: NCAEContainer.decode(package))
        try effect.validate()
        return effect
    }

    static let frequencies: [Double] = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    func gains(strength: Double) -> [Double] {
        let scale = strength.isFinite ? min(1, max(0, strength)) : 0
        return aev2.eq.eqs.map { aev2.eq.on ? $0 * scale : 0 }
    }

    static func configure(_ equalizer: AVAudioUnitEQ, effect: Self?, strength: Double, sampleRate: Double) {
        guard let effect, effect.aev2.eq.on, strength.isFinite, strength > 0 else {
            equalizer.globalGain = 0
            equalizer.bypass = true
            return
        }
        let gains = effect.gains(strength: strength)
        for (index, band) in equalizer.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = Float(min(frequencies[index], sampleRate * 0.45))
            band.bandwidth = 1
            band.gain = Float(gains[index])
            band.bypass = false
        }
        equalizer.globalGain = Float(preampDB(gains: gains, sampleRate: sampleRate))
        equalizer.bypass = gains.allSatisfy { $0 == 0 }
    }

    /// Leave headroom for the combined response, including adjacent bands.
    /// This is a fixed EQ preamp; it never measures or normalizes song loudness.
    static func preampDB(gains: [Double], sampleRate: Double) -> Double {
        guard gains.count == frequencies.count, sampleRate.isFinite, sampleRate > 0 else { return 0 }
        var maximum = 0.0
        for index in 0..<1024 {
            let frequency = 20 * pow(min(24_000, sampleRate * 0.49) / 20, Double(index) / 1023)
            let response = zip(frequencies, gains).reduce(0.0) { sum, band in
                sum + responseDB(frequency: frequency, center: min(band.0, sampleRate * 0.45), gain: band.1, sampleRate: sampleRate)
            }
            maximum = max(maximum, response)
        }
        return maximum > 0.01 ? -(maximum + 1) : 0
    }

    private static func responseDB(frequency: Double, center: Double, gain: Double, sampleRate: Double) -> Double {
        guard gain != 0 else { return 0 }
        let a = pow(10, gain / 40)
        let w = 2 * Double.pi * center / sampleRate
        let alpha = sin(w) * sinh(log(2) / 2 * w / sin(w)) // one octave
        let b = [1 + alpha * a, -2 * cos(w), 1 - alpha * a]
        let d = [1 + alpha / a, -2 * cos(w), 1 - alpha / a]
        let omega = 2 * Double.pi * frequency / sampleRate
        func power(_ coefficients: [Double]) -> Double {
            let real = coefficients[0] + coefficients[1] * cos(omega) + coefficients[2] * cos(2 * omega)
            let imaginary = -coefficients[1] * sin(omega) - coefficients[2] * sin(2 * omega)
            return real * real + imaginary * imaginary
        }
        return 10 * log10(power(b) / power(d))
    }
}

enum AISoundEffectState: Equatable {
    case off, requiresSVIP, waiting, loading, ready, unavailable, offlineMissing, unsupportedSource, failed

    var displayName: String {
        switch self {
        case .off: return String(localized: "已关闭")
        case .requiresSVIP: return String(localized: "需要黑胶 SVIP")
        case .waiting: return String(localized: "播放后自动加载调音")
        case .loading: return String(localized: "正在加载调音…")
        case .ready: return String(localized: "官方均衡曲线已应用")
        case .unavailable: return String(localized: "这首歌暂无 AI 调音")
        case .offlineMissing: return String(localized: "联网后可加载这首歌的调音")
        case .unsupportedSource: return String(localized: "空间音质暂不支持 AI 调音")
        case .failed: return String(localized: "调音加载失败，可点击重试")
        }
    }
}
