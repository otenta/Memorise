import UIKit

/// Pre-warmed haptic generators.
@MainActor
final class Haptics {
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()
    var isEnabled = true

    func prepare() {
        guard isEnabled else { return }
        impact.prepare()
        notification.prepare()
    }

    /// Light tap on OK.
    func ok() {
        guard isEnabled else { return }
        impact.impactOccurred()
        notification.prepare()
    }

    /// Success / error on grade.
    func grade(correct: Bool) {
        guard isEnabled else { return }
        notification.notificationOccurred(correct ? .success : .error)
        impact.prepare()
    }
}
