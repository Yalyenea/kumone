import SwiftUI

/// Only the ambient tint follows the content column's horizontal geometry.
/// Observing it separately keeps sidebar changes from rebuilding navigation.
@MainActor
final class MainColumnGeometry: ObservableObject {
    struct Layout: Equatable {
        var width: CGFloat = 0
        var leadingInset: CGFloat = 0

        init(frame: CGRect = .zero) {
            width = frame.width
            leadingInset = frame.minX
        }
    }

    @Published private(set) var layout = Layout()

    func update(_ next: Layout) {
        guard next != layout else { return }
        layout = next
    }
}
