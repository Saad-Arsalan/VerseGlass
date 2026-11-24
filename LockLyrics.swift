import AppKit
import Combine
import UserNotifications

struct LockLine: Equatable {
    let title: String
    let artist: String
    let index: Int
    let text: String
}

@MainActor
final class LockLyrics: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var permissionHint = ""

    private let center = UNUserNotificationCenter.current()
    private let identifier = "verseglass.current-lyric"
    private var desired: LockLine?
    private var submitted: LockLine?
    private var allowed = false
    private var clearVersion = 0
    private var sending = false
    private var requesting = false
    private var settingsVersion = 0
    private var foreground: AnyCancellable?

    override init() {
        super.init()
        center.delegate = self
        clearNotification()
        foreground = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refreshSettings() }
        refreshSettings()
    }

    func authorize() {
        guard !requesting else { return }
        requesting = true
        Task {
            defer { requesting = false }
            do {
                _ = try await center.requestAuthorization(options: [.alert])
                refreshSettings()
            } catch {
                permissionHint = "Couldn’t request notification access. \(error.localizedDescription)"
            }
        }
    }

    private func refreshSettings() {
        settingsVersion += 1
        let version = settingsVersion
        Task {
            let settings = await center.notificationSettings()
            guard version == settingsVersion else { return }
            allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if !allowed {
                permissionHint = settings.authorizationStatus == .denied
                    ? "Enable Allow notifications for Verseglass in System Settings."
                    : "Allow notifications when macOS asks."
            } else if settings.lockScreenSetting == .disabled {
                permissionHint = "Enable Show on Lock Screen for Verseglass in Notifications settings."
            } else if settings.showPreviewsSetting != .always {
                permissionHint = "Set Show previews to Always for Verseglass to see its lyrics while locked."
            } else {
                permissionHint = "Lock-screen lyric notifications are allowed."
            }
            reconcile()
        }
    }

    func update(_ line: LockLine?) {
        guard desired != line else { return }
        desired = line
        reconcile()
    }

    func stop() {
        desired = nil
        submitted = nil
        clearNotification()
    }

    private func clearNotification() {
        clearVersion += 1
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func reconcile() {
        guard allowed, let line = desired else {
            if submitted != nil || sending {
                submitted = nil
                clearNotification()
            }
            return
        }
        guard submitted != line, !sending else { return }
        let content = UNMutableNotificationContent()
        content.title = [line.title, line.artist].filter { !$0.isEmpty }.joined(separator: " · ")
        content.body = line.text
        content.sound = nil
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        sending = true
        let version = clearVersion
        Task {
            do {
                try await center.add(request)
                submitted = line
            } catch {
                permissionHint = "Couldn’t show the lyric notification. \(error.localizedDescription)"
            }
            sending = false
            // An unlock or a seek can arrive while the system accepts a request.
            // Remove or replace that request before submitting anything else.
            if clearVersion != version {
                clearNotification()
                submitted = nil
                reconcile()
            } else if desired != line || !allowed {
                reconcile()
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            guard let line = desired, allowed, notification.request.identifier == identifier,
                  notification.request.content.body == line.text else { return [] }
            return [.banner, .list]
        }
    }
}
