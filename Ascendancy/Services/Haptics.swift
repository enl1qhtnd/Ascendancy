import UIKit

/// Centralized haptic feedback with reused generators and semantic presets.
/// Wire `isEnabled` to Settings when you add a user toggle.
@MainActor
enum Haptics {
    /// When `false`, all haptics no-op.
    static var isEnabled = true

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let impactLightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let impactMediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let impactSoftGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let impactRigidGenerator = UIImpactFeedbackGenerator(style: .rigid)

    // MARK: - Selection

    /// Call shortly before a selection change (e.g. picker scroll) for snappier feedback.
    static func prepareSelection() {
        guard isEnabled else { return }
        selectionGenerator.prepare()
    }

    static func selection() {
        guard isEnabled else { return }
        selectionGenerator.selectionChanged()
    }

    // MARK: - Impact

    static func prepareImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        impactGenerator(for: style).prepare()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard isEnabled else { return }
        let generator = impactGenerator(for: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat) {
        guard isEnabled else { return }
        let generator = impactGenerator(for: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    // MARK: - Notification

    static func prepareNotification() {
        guard isEnabled else { return }
        notificationGenerator.prepare()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard isEnabled else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }

    static func success() {
        notification(.success)
    }

    static func warning() {
        notification(.warning)
    }

    static func error() {
        notification(.error)
    }

    // MARK: - Semantic presets

    /// Ordinary controls: toggles, chips, minor taps.
    static func tap() {
        impact(.light)
    }

    /// Primary actions and confirmations.
    static func confirm() {
        impact(.medium)
    }

    /// Rare or high-weight actions.
    static func emphasize() {
        impact(.heavy)
    }

    /// Softer physical feel (iOS 17+ style); good for nested or secondary controls.
    static func softTap() {
        impact(.soft)
    }

    /// Sharp, crisp tap; pairs with toggles and snapping UI.
    static func rigidTap() {
        impact(.rigid)
    }

    // MARK: - Private

    private static func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: impactLightGenerator
        case .medium: impactMediumGenerator
        case .heavy: impactHeavyGenerator
        case .soft: impactSoftGenerator
        case .rigid: impactRigidGenerator
        @unknown default: impactMediumGenerator
        }
    }
}
