import Foundation
import SwiftData

@Model
final class DoseLog {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var actualDoseAmount: Double = 0.0
    var doseUnitRaw: String = DoseUnit.mg.rawValue
    var notes: String = ""
    var protocolName: String = ""  // Denormalized for display
    var protocolCategory: String = ""
    
    @Relationship(inverse: \CompoundProtocol.doseLogs)
    var protocol_: CompoundProtocol?
    
    init(
        protocol_: CompoundProtocol?,
        actualDoseAmount: Double,
        doseUnit: DoseUnit,
        timestamp: Date = Date(),
        notes: String = "",
        protocolName: String? = nil,
        protocolCategory: String? = nil
    ) {
        self.id = UUID()
        self.protocol_ = protocol_
        self.actualDoseAmount = actualDoseAmount
        self.doseUnitRaw = doseUnit.rawValue
        self.timestamp = timestamp
        self.notes = notes
        self.protocolName = protocolName ?? protocol_?.name ?? ""
        self.protocolCategory = protocolCategory ?? protocol_?.categoryRaw ?? ""
    }
    
    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .mg }
        set { doseUnitRaw = newValue.rawValue }
    }
    
    var formattedDose: String {
        "\(actualDoseAmount.formatted(.number.precision(.fractionLength(0...2)))) \(doseUnit.rawValue)"
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
