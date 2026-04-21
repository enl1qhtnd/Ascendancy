import XCTest
import SwiftData
@testable import Ascendancy

final class InventoryServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: CompoundProtocol.self, DoseLog.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    // MARK: - Helpers

    func makeProtocol(
        form: AdministrationForm = .pill,
        doseAmount: Double = 10.0,
        inventory: Double = 20.0,
        formDosage: Double = 0.0,
        lowThreshold: Double = 5.0,
        schedule: DoseSchedule = .daily
    ) -> CompoundProtocol {
        let p = CompoundProtocol(
            name: "Test", category: .medication, administrationForm: form,
            doseAmount: doseAmount, doseUnit: .mg, schedule: schedule,
            inventoryCount: inventory, inventoryLowThreshold: lowThreshold, formDosage: formDosage
        )
        context.insert(p)
        return p
    }

    func makeLog(for p: CompoundProtocol, amount: Double = 10.0) -> DoseLog {
        let log = DoseLog(protocol_: p, actualDoseAmount: amount, doseUnit: .mg)
        context.insert(log)
        return log
    }

    // MARK: - decrementInventory: administration form rules

    func test_decrementInventory_vial_neverDecrements() async {
        let p = makeProtocol(form: .vial, inventory: 10.0)
        let log = makeLog(for: p)
        let warning = await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertNil(warning)
        XCTAssertEqual(p.inventoryCount, 10.0)
    }

    func test_decrementInventory_pill_decrementsByOne() async {
        let p = makeProtocol(form: .pill, inventory: 10.0)
        let log = makeLog(for: p, amount: 5.0)  // dose amount doesn't affect count for pills
        await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 9.0)
    }

    func test_decrementInventory_capsule_decrementsByOne() async {
        let p = makeProtocol(form: .capsule, inventory: 8.0)
        let log = makeLog(for: p)
        await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 7.0)
    }

    func test_decrementInventory_syringe_decrementsByDoseAmount() async {
        let p = makeProtocol(form: .syringe, doseAmount: 2.5, inventory: 10.0)
        let log = makeLog(for: p, amount: 2.5)
        await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 7.5, accuracy: 0.001)
    }

    func test_decrementInventory_custom_decrementsByDoseAmount() async {
        let p = makeProtocol(form: .custom, doseAmount: 3.0, inventory: 12.0)
        let log = makeLog(for: p, amount: 3.0)
        await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 9.0, accuracy: 0.001)
    }

    // MARK: - decrementInventory: formDosage path

    func test_decrementInventory_withFormDosage_usesFractionalCount() async {
        // 40mg per pill; taking 10mg uses 0.25 pills
        let p = makeProtocol(form: .pill, doseAmount: 10.0, inventory: 10.0, formDosage: 40.0)
        let log = makeLog(for: p, amount: 10.0)
        await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 9.75, accuracy: 0.001)
    }

    func test_decrementInventory_withFormDosage_fullUnitConsumed() async {
        // 10mg per pill; taking 10mg uses exactly 1 pill
        let p = makeProtocol(form: .pill, doseAmount: 10.0, inventory: 5.0, formDosage: 10.0)
        let log = makeLog(for: p, amount: 10.0)
        await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 4.0, accuracy: 0.001)
    }

    // MARK: - decrementInventory: warning thresholds

    func test_decrementInventory_goesToZero_returnsOutOfStockWarning() async {
        let p = makeProtocol(form: .pill, inventory: 1.0, lowThreshold: 5.0)
        let log = makeLog(for: p)
        let warning = await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 0.0)
        guard case .outOfStock(let name) = warning else {
            XCTFail("Expected .outOfStock, got \(String(describing: warning))")
            return
        }
        XCTAssertEqual(name, "Test")
    }

    func test_decrementInventory_dropsToLowThreshold_returnsLowWarning() async {
        let p = makeProtocol(form: .pill, inventory: 6.0, lowThreshold: 5.0)
        let log = makeLog(for: p)
        let warning = await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 5.0)
        guard case .low(let name, _, _) = warning else {
            XCTFail("Expected .low, got \(String(describing: warning))")
            return
        }
        XCTAssertEqual(name, "Test")
    }

    func test_decrementInventory_aboveLowThreshold_returnsNil() async {
        let p = makeProtocol(form: .pill, inventory: 20.0, lowThreshold: 5.0)
        let log = makeLog(for: p)
        let warning = await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertNil(warning)
    }

    func test_decrementInventory_doesNotGoBelowZero() async {
        let p = makeProtocol(form: .syringe, doseAmount: 10.0, inventory: 3.0)
        let log = makeLog(for: p, amount: 10.0)
        await InventoryService.shared.decrementInventory(for: p, dose: log)
        XCTAssertEqual(p.inventoryCount, 0.0)
    }

    // MARK: - addInventory

    func test_addInventory_increasesCount() async {
        let p = makeProtocol(inventory: 10.0)
        await InventoryService.shared.addInventory(to: p, amount: 20.0)
        XCTAssertEqual(p.inventoryCount, 30.0)
    }

    func test_addInventory_fromZero() async {
        let p = makeProtocol(inventory: 0.0)
        await InventoryService.shared.addInventory(to: p, amount: 5.0)
        XCTAssertEqual(p.inventoryCount, 5.0)
    }

    // MARK: - daysOfSupply

    func test_daysOfSupply_daily_oneDosePerDay() async {
        // Daily, 1 time of day, 10 pills → 10 days
        let p = makeProtocol(form: .pill, doseAmount: 100.0, inventory: 10.0)
        let result = await InventoryService.shared.daysOfSupply(for: p)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 10.0, accuracy: 0.01)
    }

    func test_daysOfSupply_everyXDays_stretchesSupply() async {
        var sched = DoseSchedule()
        sched.type = .everyXDays
        sched.intervalDays = 3
        sched.timesOfDay = []
        let p = makeProtocol(form: .pill, doseAmount: 100.0, inventory: 10.0, schedule: sched)
        let result = await InventoryService.shared.daysOfSupply(for: p)
        // dosesPerDay = 1/3 → 10 / (1/3) = 30 days
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 30.0, accuracy: 0.1)
    }

    func test_daysOfSupply_specificWeekdays_threeDaysPerWeek() async {
        var sched = DoseSchedule()
        sched.type = .specificWeekdays
        sched.weekdays = [.monday, .wednesday, .friday]
        sched.timesOfDay = []
        let p = makeProtocol(form: .pill, doseAmount: 100.0, inventory: 7.0, schedule: sched)
        let result = await InventoryService.shared.daysOfSupply(for: p)
        // dosesPerDay = 3/7 → 7 / (3/7) ≈ 16.33
        let expected = 7.0 / (3.0 / 7.0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, expected, accuracy: 0.1)
    }

    func test_daysOfSupply_timesPerWeek_twoPerWeek() async {
        var sched = DoseSchedule()
        sched.type = .timesPerWeek
        sched.timesPerWeek = 2
        sched.timesOfDay = []
        let p = makeProtocol(form: .pill, doseAmount: 100.0, inventory: 7.0, schedule: sched)
        let result = await InventoryService.shared.daysOfSupply(for: p)
        // dosesPerDay = 2/7 → 7 / (2/7) = 24.5
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 24.5, accuracy: 0.1)
    }

    func test_daysOfSupply_withFormDosage_usesTotalAmount() async {
        // 40mg per pill, doseAmount = 10mg/day (1×), inventory = 4 pills
        // totalAmount = 4 * 40 = 160mg; dailyRequirement = 10; days = 16
        let p = makeProtocol(form: .pill, doseAmount: 10.0, inventory: 4.0, formDosage: 40.0)
        let result = await InventoryService.shared.daysOfSupply(for: p)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 16.0, accuracy: 0.01)
    }

    func test_daysOfSupply_zeroDoseAmount_returnsNil() async {
        let p = makeProtocol(form: .pill, doseAmount: 0.0, inventory: 10.0)
        let result = await InventoryService.shared.daysOfSupply(for: p)
        XCTAssertNil(result)
    }

    func test_daysOfSupply_syringeForm_usesDoseAmount() async {
        // Syringe: days = (inventory / doseAmount) / dosesPerDay
        // inventory = 10mL, doseAmount = 2.5mL, daily (1 dose/day)
        // → (10 / 2.5) / 1 = 4 days
        let p = makeProtocol(form: .syringe, doseAmount: 2.5, inventory: 10.0)
        let result = await InventoryService.shared.daysOfSupply(for: p)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 4.0, accuracy: 0.01)
    }
}
