import SwiftData

enum ProtocolSortMigration {
    /// After adding `sortOrder`, existing rows may all be `0` or contain duplicates. Renumber once.
    static func normalizeIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<CompoundProtocol>()
        guard let all = try? context.fetch(descriptor), !all.isEmpty else { return }

        let uniqueOrders = Set(all.map(\.sortOrder))
        let allZero = all.allSatisfy { $0.sortOrder == 0 }
        let hasDuplicates = uniqueOrders.count != all.count

        guard allZero || hasDuplicates else { return }

        let sorted = all.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        for (i, p) in sorted.enumerated() {
            p.sortOrder = i
        }

        try? context.save()
    }
}
