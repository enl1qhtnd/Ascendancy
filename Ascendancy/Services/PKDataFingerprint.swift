import Foundation

enum PKDataFingerprint {
    static func combined(protocols: [CompoundProtocol], periodDays: Int? = nil) -> Int {
        var hasher = Hasher()
        hasher.combine(periodDays)

        for protocol_ in protocols.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            combineProtocol(protocol_, into: &hasher)
        }

        return hasher.finalize()
    }

    static func single(_ protocol_: CompoundProtocol) -> Int {
        var hasher = Hasher()
        combineProtocol(protocol_, into: &hasher)
        return hasher.finalize()
    }

    private static func combineProtocol(_ protocol_: CompoundProtocol, into hasher: inout Hasher) {
        hasher.combine(protocol_.id)
        hasher.combine(protocol_.startDate)
        hasher.combine(protocol_.endDate)
        hasher.combine(protocol_.halfLifeValue)
        hasher.combine(protocol_.halfLifeUnitRaw)
        hasher.combine(protocol_.statusRaw)

        let logs = (protocol_.doseLogs ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
        hasher.combine(logs.count)
        for log in logs {
            hasher.combine(log.id)
            hasher.combine(log.timestamp)
            hasher.combine(log.actualDoseAmount)
            hasher.combine(log.doseUnitRaw)
        }
    }
}
