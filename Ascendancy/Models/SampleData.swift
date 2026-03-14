import Foundation
import SwiftData

// MARK: - Mock Sample Data for Previews & First Launch

enum SampleData {
    
    @MainActor
    static func insertSampleData(into context: ModelContext) {
        // Insert sample protocols and logs
        let protocols = makeSampleProtocols()
        for p in protocols {
            context.insert(p)
        }
        
        // Add sample dose logs
        let logs = makeSampleLogs(protocols: protocols)
        for log in logs {
            context.insert(log)
        }
        
        try? context.save()
    }
    
    static func makeSampleProtocols() -> [CompoundProtocol] {
        let cal = Calendar.current
        let now = Date()
        
        // 1. Testosterone Cypionate - TRT
        let tcSchedule: DoseSchedule = {
            var s = DoseSchedule()
            s.type = .everyXDays
            s.intervalDays = 7
            s.timesOfDay = [cal.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? Date()]
            return s
        }()
        let tc = CompoundProtocol(
            name: "Testosterone Cypionate",
            category: .trt,
            administrationForm: .syringe,
            doseAmount: 1.0,
            doseUnit: .mL,
            schedule: tcSchedule,
            startDate: cal.date(byAdding: .month, value: -3, to: now) ?? now,
            notes: "200mg/mL concentration. Glute injection, alternate sides.",
            halfLifeValue: 8,
            halfLifeUnit: .days,
            status: .active,
            inventoryCount: 8.5,
            inventoryLowThreshold: 2
        )
        tc.inventoryUnitLabel = "mL"
        
        // 2. BPC-157 - Peptide
        let bpcSchedule: DoseSchedule = {
            var s = DoseSchedule()
            s.type = .daily
            s.timesOfDay = [cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? Date()]
            return s
        }()
        let bpc = CompoundProtocol(
            name: "BPC-157",
            category: .peptide,
            administrationForm: .syringe,
            doseAmount: 500,
            doseUnit: .mcg,
            schedule: bpcSchedule,
            startDate: cal.date(byAdding: .day, value: -21, to: now) ?? now,
            endDate: cal.date(byAdding: .day, value: 9, to: now),
            notes: "Subcutaneous injection, near injury site. 30-day protocol.",
            halfLifeValue: 4,
            halfLifeUnit: .hours,
            status: .active,
            inventoryCount: 4500,
            inventoryLowThreshold: 1000
        )
        bpc.inventoryUnitLabel = "mcg"
        
        // 3. Metformin - Medication
        let metSchedule: DoseSchedule = {
            var s = DoseSchedule()
            s.type = .daily
            s.timesOfDay = [
                cal.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? Date(),
                cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? Date()
            ]
            return s
        }()
        let met = CompoundProtocol(
            name: "Metformin",
            category: .medication,
            administrationForm: .pill,
            doseAmount: 500,
            doseUnit: .mg,
            schedule: metSchedule,
            startDate: cal.date(byAdding: .month, value: -6, to: now) ?? now,
            notes: "Take with food to reduce GI upset.",
            halfLifeValue: 6,
            halfLifeUnit: .hours,
            status: .active,
            inventoryCount: 46,
            inventoryLowThreshold: 10
        )
        
        // 4. Semaglutide - Medication
        let semSchedule: DoseSchedule = {
            var s = DoseSchedule()
            s.type = .everyXDays
            s.intervalDays = 7
            s.timesOfDay = [cal.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? Date()]
            return s
        }()
        let sem = CompoundProtocol(
            name: "Semaglutide",
            category: .medication,
            administrationForm: .syringe,
            doseAmount: 0.5,
            doseUnit: .mg,
            schedule: semSchedule,
            startDate: cal.date(byAdding: .month, value: -2, to: now) ?? now,
            notes: "Subcutaneous injection, abdomen. Titrating dose.",
            halfLifeValue: 7,
            halfLifeUnit: .days,
            status: .active,
            inventoryCount: 3.5,
            inventoryLowThreshold: 1.0
        )
        sem.inventoryUnitLabel = "mL"
        
        // 5. Sermorelin - Peptide (paused)
        let serSchedule: DoseSchedule = .mondayWednesdayFriday
        let ser = CompoundProtocol(
            name: "Sermorelin",
            category: .peptide,
            administrationForm: .syringe,
            doseAmount: 300,
            doseUnit: .mcg,
            schedule: serSchedule,
            startDate: cal.date(byAdding: .month, value: -1, to: now) ?? now,
            notes: "Pre-sleep injection for GH pulse.",
            halfLifeValue: 11,
            halfLifeUnit: .minutes,
            status: .paused,
            inventoryCount: 2000,
            inventoryLowThreshold: 300
        )
        ser.inventoryUnitLabel = "mcg"
        
        return [tc, bpc, met, sem, ser]
    }
    
    static func makeSampleLogs(protocols: [CompoundProtocol]) -> [DoseLog] {
        let cal = Calendar.current
        let now = Date()
        var logs: [DoseLog] = []
        
        // TC logs: weekly for 12 weeks
        if let tc = protocols.first(where: { $0.name == "Testosterone Cypionate" }) {
            for week in 0..<12 {
                let date = cal.date(byAdding: .weekOfYear, value: -week, to: now) ?? now
                let log = DoseLog(protocol_: tc, actualDoseAmount: 1.0, doseUnit: .mL, timestamp: adjustTime(date, hour: 9), notes: week == 0 ? "Right glute" : "")
                logs.append(log)
            }
        }
        
        // BPC logs: daily for 21 days
        if let bpc = protocols.first(where: { $0.name == "BPC-157" }) {
            for day in 0..<21 {
                let date = cal.date(byAdding: .day, value: -day, to: now) ?? now
                logs.append(DoseLog(protocol_: bpc, actualDoseAmount: 500, doseUnit: .mcg, timestamp: adjustTime(date, hour: 8)))
            }
        }
        
        // Metformin: twice daily for 30 days
        if let met = protocols.first(where: { $0.name == "Metformin" }) {
            for day in 0..<30 {
                let date = cal.date(byAdding: .day, value: -day, to: now) ?? now
                logs.append(DoseLog(protocol_: met, actualDoseAmount: 500, doseUnit: .mg, timestamp: adjustTime(date, hour: 8)))
                logs.append(DoseLog(protocol_: met, actualDoseAmount: 500, doseUnit: .mg, timestamp: adjustTime(date, hour: 20)))
            }
        }
        
        // Semaglutide: weekly for 8 weeks
        if let sem = protocols.first(where: { $0.name == "Semaglutide" }) {
            for week in 0..<8 {
                let date = cal.date(byAdding: .weekOfYear, value: -week, to: now) ?? now
                logs.append(DoseLog(protocol_: sem, actualDoseAmount: 0.5, doseUnit: .mg, timestamp: adjustTime(date, hour: 10)))
            }
        }
        
        return logs
    }
    
    private static func adjustTime(_ date: Date, hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }
    
    // MARK: - Static preview instances
    
    static var previewProtocol: CompoundProtocol {
        makeSampleProtocols()[0]
    }
    
    static var previewLogs: [DoseLog] {
        let p = previewProtocol
        return makeSampleLogs(protocols: [p])
    }
}
