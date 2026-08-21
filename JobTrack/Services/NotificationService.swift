import Foundation
import UserNotifications

/// Schedules local notifications reminding the user to follow up on
/// applications that have received no reply. No server, no background fetch —
/// just local reminders computed from each offer's follow-up date.
struct NotificationService {

    private let center = UNUserNotificationCenter.current()
    private let prefix = "followup."

    /// Ask the user for notification permission (no-op if already decided).
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Whether notifications are authorized.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Posts an immediate local notification (on the device running the app).
    func notifyNow(title: String, body: String) async {
        await requestAuthorization()
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "instant.\(UUID().uuidString)", content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Rebuilds the pending follow-up reminders from the current offers.
    /// Clears our previous reminders first so nothing goes stale.
    func rescheduleFollowUps(for offers: [JobOffer]) async {
        // Remove our previously scheduled reminders.
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard await isAuthorized() else { return }

        let now = Date()
        for offer in offers {
            guard offer.status == .applied, !offer.hasReply,
                  let due = offer.nextFollowUpDate() else { continue }
            // Only schedule future reminders (past-due ones are shown in-app).
            guard due > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Relance à faire"
            content.body = "Pas de réponse de \(offer.company.isEmpty ? offer.displayTitle : offer.company). "
                + "Pense à relancer."
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: prefix + offer.id.uuidString,
                content: content,
                trigger: trigger)
            try? await center.add(request)
        }
    }
}
