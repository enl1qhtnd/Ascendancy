import XCTest
import SwiftData
@testable import Ascendancy

final class ProtocolSortMigrationTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: CompoundProtocol.self, DoseLog.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    // MARK: - Helpers

    @discardableResult
    func insertProtocol(name: String, sortOrder: Int = 0) -> CompoundProtocol {
        let p = CompoundProtocol(
            name: name, category: .medication, administrationForm: .pill,
            doseAmount: 1.0, doseUnit: .mg, schedule: .daily, sortOrder: sortOrder
        )
        context.insert(p)
        return p
    }

    // MARK: - Tests

    func test_normalizeIfNeeded_allZero_renumbersFromZero() throws {
        insertProtocol(name: "B", sortOrder: 0)
        insertProtocol(name: "A", sortOrder: 0)
        insertProtocol(name: "C", sortOrder: 0)
        try context.save()

        ProtocolSortMigration.normalizeIfNeeded(in: context)

        let all = try context.fetch(FetchDescriptor<CompoundProtocol>())
        let orders = all.map { $0.sortOrder }.sorted()
        XCTAssertEqual(orders, [0, 1, 2])
    }

    func test_normalizeIfNeeded_allZero_sortedAlphabetically() throws {
        insertProtocol(name: "C", sortOrder: 0)
        insertProtocol(name: "A", sortOrder: 0)
        insertProtocol(name: "B", sortOrder: 0)
        try context.save()

        ProtocolSortMigration.normalizeIfNeeded(in: context)

        let all = try context.fetch(FetchDescriptor<CompoundProtocol>())
        let sorted = all.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(sorted.map { $0.name }, ["A", "B", "C"])
    }

    func test_normalizeIfNeeded_duplicateSortOrders_producesUniqueOrders() throws {
        let p1 = insertProtocol(name: "A", sortOrder: 1)
        let p2 = insertProtocol(name: "B", sortOrder: 1)  // duplicate
        let p3 = insertProtocol(name: "C", sortOrder: 2)
        try context.save()

        ProtocolSortMigration.normalizeIfNeeded(in: context)

        let orders = Set([p1.sortOrder, p2.sortOrder, p3.sortOrder])
        XCTAssertEqual(orders.count, 3, "Sort orders must be unique after migration")
    }

    func test_normalizeIfNeeded_alreadyUnique_doesNotRenumber() throws {
        let p1 = insertProtocol(name: "A", sortOrder: 0)
        let p2 = insertProtocol(name: "B", sortOrder: 1)
        let p3 = insertProtocol(name: "C", sortOrder: 2)
        try context.save()

        ProtocolSortMigration.normalizeIfNeeded(in: context)

        XCTAssertEqual(p1.sortOrder, 0)
        XCTAssertEqual(p2.sortOrder, 1)
        XCTAssertEqual(p3.sortOrder, 2)
    }

    func test_normalizeIfNeeded_alreadyUnique_nonContiguous_doesNotRenumber() throws {
        // Gaps in sort order are OK as long as there are no duplicates
        let p1 = insertProtocol(name: "A", sortOrder: 0)
        let p2 = insertProtocol(name: "B", sortOrder: 5)
        let p3 = insertProtocol(name: "C", sortOrder: 10)
        try context.save()

        ProtocolSortMigration.normalizeIfNeeded(in: context)

        XCTAssertEqual(p1.sortOrder, 0)
        XCTAssertEqual(p2.sortOrder, 5)
        XCTAssertEqual(p3.sortOrder, 10)
    }

    func test_normalizeIfNeeded_emptyContext_doesNotCrash() {
        XCTAssertNoThrow(ProtocolSortMigration.normalizeIfNeeded(in: context))
    }

    func test_normalizeIfNeeded_singleProtocol_assignsZero() throws {
        let p = insertProtocol(name: "Solo", sortOrder: 0)
        try context.save()

        ProtocolSortMigration.normalizeIfNeeded(in: context)

        XCTAssertEqual(p.sortOrder, 0)
    }

    func test_normalizeIfNeeded_duplicates_preservesRelativeOrderByExistingSortOrder() throws {
        // When there are duplicates, migration sorts by (sortOrder, name, id)
        // p1 has lower sortOrder than p3, so after renumber p1 should still precede p3
        let p1 = insertProtocol(name: "Z", sortOrder: 0)
        let p2 = insertProtocol(name: "A", sortOrder: 0)  // same order as p1, but earlier alphabetically
        let p3 = insertProtocol(name: "M", sortOrder: 5)
        try context.save()

        ProtocolSortMigration.normalizeIfNeeded(in: context)

        // After migration: order is by (sortOrder, name) → A(0), Z(0), M(5)
        XCTAssertLessThan(p2.sortOrder, p1.sortOrder)  // A < Z alphabetically
        XCTAssertLessThan(p1.sortOrder, p3.sortOrder)  // original sortOrder 0 < 5
    }
}
