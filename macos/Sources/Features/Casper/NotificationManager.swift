import AppKit
import UserNotifications
import GhosttyKit
import OSLog

/// Sends macOS banner notifications when a terminal pane enters the
/// `waitingForInput` state (e.g. Claude asking "Proceed? [y/n]").
///
/// Clicking the notification brings the right Casper window to the front.
/// We track which windows have already been notified so we don't spam.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NotificationManager")

    /// Windows that have already received a notification for the current
    /// waiting episode. Cleared when the state returns to idle/executing.
    private var notifiedIDs: Set<ObjectIdentifier> = []

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { Self.logger.error("Notification permission error: \(error)") }
        }
    }

    // MARK: - State change hook (called by PaneActivityMonitor)

    func handleStateChange(controller: TerminalController, state: PaneActivity) {
        let id = ObjectIdentifier(controller)
        switch state {
        case .waitingForInput:
            guard !notifiedIDs.contains(id) else { return }
            notifiedIDs.insert(id)
            // Only notify when Casper is not the key window (user is elsewhere)
            guard NSApp.keyWindow !== controller.window else { return }
            send(for: controller)
        case .idle, .executing:
            notifiedIDs.remove(id)
            // Cancel any pending notification for this controller
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [notificationID(for: controller)]
            )
        }
    }

    // MARK: - Build & send

    private func send(for controller: TerminalController) {
        let content = UNMutableNotificationContent()

        // Window / session identity
        let windowTitle = controller.window?.title ?? "Terminal"
        content.title = "Casper — \(windowTitle)"

        // Extract Claude task description from visible terminal text
        if let task = claudeTaskDescription(from: controller) {
            content.subtitle = task
        }

        // CWD hint in body
        let cwd = controller.focusedSurface?.pwd ?? ""
        content.body = cwd.isEmpty ? "Waiting for your input" : "Waiting for input in \(abbreviate(cwd))"

        content.sound = .default

        // Store window number so click handler can focus the right window
        if let window = controller.window {
            content.userInfo = [
                "windowNumber": window.windowNumber,
                "sessionTitle": windowTitle,
            ]
        }

        let request = UNNotificationRequest(
            identifier: notificationID(for: controller),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Self.logger.error("Failed to send notification: \(error)") }
        }
    }

    // MARK: - Click handler

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let info = response.notification.request.content.userInfo
        guard let windowNumber = info["windowNumber"] as? Int else { return }

        DispatchQueue.main.async {
            for window in NSApp.windows where window.windowNumber == windowNumber {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when Casper is in the foreground (different window has focus)
        completionHandler([.banner, .sound])
    }

    // MARK: - Text extraction

    /// Scans the focused surface for the most recent Claude Code task description.
    /// Claude Code marks current actions with a "●" bullet on the left.
    private func claudeTaskDescription(from controller: TerminalController) -> String? {
        guard let surface = controller.focusedSurface,
              let surf = surface.surface else { return nil }

        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false)
        guard ghostty_surface_read_text(surf, sel, &text) else { return nil }
        defer { ghostty_surface_free_text(surf, &text) }

        return WindowTitleExtractor.claudeTask(from: String(cString: text.text))
    }

    // MARK: - Helpers

    private func notificationID(for controller: TerminalController) -> String {
        "casper.waiting.\(ObjectIdentifier(controller))"
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
