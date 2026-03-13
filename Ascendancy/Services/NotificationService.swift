import Foundation
import UserNotifications

@MainActor
class NotificationService {
    
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
