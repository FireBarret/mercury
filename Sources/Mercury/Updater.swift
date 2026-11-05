import Sparkle

/// Thin wrapper around Sparkle. The feed URL and public key live in
/// Info.plist (SUFeedURL, SUPublicEDKey).
enum Updater {
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    /// Call once at launch so scheduled checks start.
    static func start() { _ = controller }

    static func checkForUpdates() { controller.checkForUpdates(nil) }

    static var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
