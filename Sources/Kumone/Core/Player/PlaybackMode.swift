import Foundation

/// The transport presents one mode even though the engine stores queue order
/// and repetition separately. Each selection writes both to avoid a hidden
/// repeat-one state surviving a switch to shuffle.
enum PlaybackMode: String, CaseIterable {
    case ordered, shuffled, repeatOne, autoMix

    init(queueOrder: QueueOrder, repeatMode: RepeatMode) {
        if repeatMode == .one { self = .repeatOne }
        else if queueOrder == .autoMix { self = .autoMix }
        else if queueOrder == .shuffled { self = .shuffled }
        else { self = .ordered }
    }

    var queueOrder: QueueOrder {
        switch self {
        case .ordered, .repeatOne: return .listed
        case .shuffled: return .shuffled
        case .autoMix: return .autoMix
        }
    }

    var repeatMode: RepeatMode {
        switch self {
        case .ordered, .autoMix: return .off
        case .shuffled: return .all
        case .repeatOne: return .one
        }
    }

    func next(autoMixAvailable: Bool) -> Self {
        switch self {
        case .ordered: return .shuffled
        case .shuffled: return .repeatOne
        case .repeatOne: return autoMixAvailable ? .autoMix : .ordered
        case .autoMix: return .ordered
        }
    }

    var displayName: String {
        switch self {
        case .ordered: return String(localized: "列表顺序")
        case .shuffled: return String(localized: "随机播放")
        case .repeatOne: return String(localized: "单曲循环")
        case .autoMix: return String(localized: "AutoMix 顺序")
        }
    }
}
