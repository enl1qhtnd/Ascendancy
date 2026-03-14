import Foundation
import UserNotifications

actor NotificationService {

    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification auth error: \(error)")
            return false
        }
    }

    // MARK: - Schedule Reminders for Protocol

    func scheduleReminders(for protocol_: CompoundProtocol) async {
        guard protocol_.remindersEnabled else { return }

        // Remove existing reminders for this protocol first
        await cancelReminders(for: protocol_)

        let doseStr = "\(protocol_.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(protocol_.doseUnit.rawValue)"

        // Schedule next 14 doses
        var doseDates: [Date] = []
        var cursor = Date()

        for _ in 0..<14 {
            if let next = protocol_.nextDoseDate(from: cursor) {
                doseDates.append(next)
                cursor = next
            }
        }

        for (index, doseDate) in doseDates.enumerated() {
            guard doseDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Time for \(protocol_.name)"
            content.body = "Your scheduled dose: \(doseStr)"
            content.sound = .default
            content.userInfo = ["protocolId": protocol_.id.uuidString]

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: doseDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

            let id = "\(protocol_.id.uuidString)-dose-\(index)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                print("[NotificationService] Failed to schedule reminder \(id): \(error)")
            }
        }
    }
    
    // MARK: - Schedule Reminders for All Protocols (coordinated)

    /// Cancels all pending dose reminders and reschedules them for all given protocols,
    /// merging notifications for protocols with the same dose time into a single alert.
    func scheduleAll(protocols: [CompoundProtocol]) async {
        // Cancel all pending dose reminders regardless of format
        let pending = await center.pendingNotificationRequests()
        let doseIds = pending.filter {
            $0.identifier.hasPrefix("dose-slot-") || $0.identifier.contains("-dose-")
        }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: doseIds)

        let enabled = protocols.filter { $0.remindersEnabled }
        guard !enabled.isEmpty else { return }

        // Collect upcoming dose events for each enabled protocol
        struct DoseEvent {
            let date: Date
            let protocol_: CompoundProtocol
            let doseStr: String
        }
        let now = Date()
        var events: [DoseEvent] = []
        for p in enabled {
            let doseStr = "\(p.doseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(p.doseUnit.rawValue)"
            var cursor = now
            for _ in 0..<14 {
                guard let next = p.nextDoseDate(from: cursor) else { break }
                events.append(DoseEvent(date: next, protocol_: p, doseStr: doseStr))
                cursor = next
            }
        }

        // Group events by minute-level slot key
        let cal = Calendar.current
        func slotKey(_ date: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(c.hour ?? 0)-\(c.minute ?? 0)"
        }
        var slotGroups: [String: [DoseEvent]] = [:]
        for event in events {
            slotGroups[slotKey(event.date), default: []].append(event)
        }

        // Schedule one notification per unique time slot
        for (slotKeyStr, group) in slotGroups {
            guard let fireDate = group.first?.date, fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.sound = .default

            if group.count == 1 {
                let event = group[0]
                content.title = "Time for \(event.protocol_.name)"
                content.body = "Your scheduled dose: \(event.doseStr)"
                content.userInfo = ["protocolId": event.protocol_.id.uuidString]
            } else {
                content.title = "Time for your scheduled doses"
                content.body = group.map { "\($0.protocol_.name): \($0.doseStr)" }.joined(separator: " · ")
            }

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let id = "dose-slot-\(slotKeyStr)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                print("[NotificationService] Failed to schedule slot \(id): \(error)")
            }
        }
    }

    // MARK: - Cancel Reminders

    func cancelReminders(for protocol_: CompoundProtocol) async {
        let prefix = protocol_.id.uuidString
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Low Inventory Alert

    func sendLowInventoryAlert(for protocol_: CompoundProtocol) async {
        let content = UNMutableNotificationContent()
        content.title = "Low Inventory: \(protocol_.name)"
        content.body = "Only \(protocol_.inventoryCount.formatted()) \(protocol_.inventoryDisplayUnitLabel) remaining."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let id = "\(protocol_.id.uuidString)-low-inventory"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            print("[NotificationService] Failed to send low inventory alert: \(error)")
        }
    }
}
