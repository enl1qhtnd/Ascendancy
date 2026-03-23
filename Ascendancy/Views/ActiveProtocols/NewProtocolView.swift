import SwiftUI
import SwiftData

struct NewProtocolView: View {
    /// Pass a protocol to pre-populate all fields and enable edit (update) mode.
    /// Nil means create a new protocol.
    var protocol_: CompoundProtocol? = nil
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    // Form state
    @State private var name = ""
    @State private var category: CompoundCategory = .medication
    @State private var administrationForm: AdministrationForm = .pill
    @State private var doseAmount = ""
    @State private var doseUnit: DoseUnit = .mg
    @State private var halfLifeValue = ""
    @State private var halfLifeUnit: HalfLifeUnit = .hours
    @State private var scheduleType: ScheduleType = .daily
    @State private var intervalDays = 1
    @State private var selectedWeekdays: Set<Weekday> = [.monday, .wednesday, .friday]
    @State private var timesPerWeek = 3
    @State private var doseTime: Date = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var startDate = Date()
    @State private var endDate: Date? = nil
    @State private var hasEndDate = false
    @State private var notes = ""
    // Inventory
    @State private var inventoryCount = ""
    @State private var formDosage = ""
    @State private var inventoryThreshold = ""
    @State private var remindersEnabled = true
    @State private var customNotes = ""
    
    private var isEditMode: Bool { protocol_ != nil }
    
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        NumericInputParser.parse(doseAmount) != nil &&
        NumericInputParser.parse(halfLifeValue) != nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Compound Info
                        formSection("Compound") {
                            VStack(spacing: 14) {
                                FormField(label: "Name", placeholder: "e.g. Testosterone Cypionate") {
                                    TextField("", text: $name)
                                        .foregroundStyle(.white)
                                }
                                
                                FormPicker(label: "Category", selection: $category, options: CompoundCategory.allCases)
                                
                                FormPicker(label: "Form", selection: $administrationForm, options: AdministrationForm.allCases)
                            }
                        }
                        
                        // Dosing
                        formSection("Dosing") {
                            VStack(spacing: 14) {
                                HStack(spacing: 12) {
                                    FormField(label: "Amount", placeholder: "0") {
                                        TextField("", text: $doseAmount)
                                            .keyboardType(.decimalPad)
                                            .foregroundStyle(.white)
                                    }
                                    
                                    FormPicker(label: "Unit", selection: $doseUnit, options: DoseUnit.allCases)
                                        .frame(maxWidth: 90)
                                }
                                
                                HStack(spacing: 12) {
                                    FormField(label: "Half-Life Value", placeholder: "24") {
                                        TextField("", text: $halfLifeValue)
                                            .keyboardType(.decimalPad)
                                            .foregroundStyle(.white)
                                    }
                                    
                                    FormPicker(label: "Unit", selection: $halfLifeUnit, options: HalfLifeUnit.allCases)
                                        .frame(maxWidth: 110)
                                }
                            }
                        }
                        
                        // Schedule
                        formSection("Schedule") {
                            VStack(spacing: 14) {
                                FormPicker(label: "Schedule Type", selection: $scheduleType, options: ScheduleType.allCases)
                                
                                switch scheduleType {
                                case .everyXDays:
                                    HStack {
                                        Text("Every")
                                            .foregroundStyle(.white.opacity(0.6))
                                        Stepper(value: $intervalDays, in: 1...365) {
                                            Text(String(format: String(localized: "%lld days"), intervalDays))
                                        }
                                        .foregroundStyle(.white)
                                    }
                                    
                                case .specificWeekdays:
                                    WeekdayPicker(selected: $selectedWeekdays)
                                    
                                case .timesPerWeek:
                                    Stepper(value: $timesPerWeek, in: 1...7) {
                                        Text(String(format: String(localized: "%lldx per week"), timesPerWeek))
                                    }
                                    .foregroundStyle(.white)
                                    
                                case .custom:
                                    FormField(label: "Schedule Description", placeholder: "e.g. Loading dose then weekly") {
                                        TextField("", text: $customNotes)
                                            .foregroundStyle(.white)
                                    }
                                    
                                default:
                                    EmptyView()
                                }
                                
                                DatePicker("Dose Time", selection: $doseTime, displayedComponents: .hourAndMinute)
                                    .foregroundStyle(.white)
                                    .tint(.white)
                                    .colorScheme(.dark)

                                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                                    .foregroundStyle(.white)
                                    .tint(.white)
                                
                                Toggle("Has End Date", isOn: $hasEndDate)
                                    .foregroundStyle(.white)
                                    .tint(.green)
                                
                                if hasEndDate {
                                    DatePicker("End Date & Time", selection: Binding(
                                        get: { endDate ?? Date() },
                                        set: { endDate = $0 }
                                    ), displayedComponents: [.date, .hourAndMinute])
                                    .foregroundStyle(.white)
                                    .tint(.white)
                                }
                            }
                        }
                        
                        // Inventory
                        formSection("Inventory") {
                            VStack(spacing: 14) {
                                FormField(label: "Starting Count (\(administrationForm.inventoryPluralLabel))", placeholder: "e.g. 3") {
                                    TextField("", text: $inventoryCount)
                                        .keyboardType(.decimalPad)
                                        .foregroundStyle(.white)
                                }
                                FormField(label: "Amount per \(administrationForm.inventorySingularLabel) (\(doseUnit.rawValue))", placeholder: "e.g. 40") {
                                    TextField("", text: $formDosage)
                                        .keyboardType(.decimalPad)
                                        .foregroundStyle(.white)
                                }
                                FormField(label: "Low Stock Warning at", placeholder: "e.g. 1") {
                                    TextField("", text: $inventoryThreshold)
                                        .keyboardType(.decimalPad)
                                        .foregroundStyle(.white)
                                }
                                Toggle("Enable Reminders", isOn: $remindersEnabled)
                                    .foregroundStyle(.white)
                                    .tint(.green)
                            }
                        }
                        
                        // Notes
                        formSection("Notes (Optional)") {
                            TextEditor(text: $notes)
                                .frame(minHeight: 80)
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                        }
                        
                        // Save
                        Button {
                            save()
                        } label: {
                            Text(isEditMode ? "Save Changes" : "Create Protocol")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(isValid ? .black : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isValid ? Color.white : Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!isValid)
                        .padding(.bottom, 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(isEditMode ? "Edit Protocol" : "New Protocol")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        Haptics.tap()
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            if isEditMode { populate() }
        }
    }
    
    // MARK: - Helpers
    
    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(catalogKey: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.8)
            
            VStack(spacing: 14) {
                content()
            }
            .glassCard()
        }
    }
    
    /// Populate form state from an existing protocol (edit mode entry point).
    private func populate() {
        guard let p = protocol_ else { return }
        name = p.name
        category = p.category
        administrationForm = p.administrationForm
        doseAmount = p.doseAmount.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
        doseUnit = p.doseUnit
        halfLifeValue = p.halfLifeValue.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
        halfLifeUnit = p.halfLifeUnit
        startDate = p.startDate
        endDate = p.endDate
        hasEndDate = p.endDate != nil
        notes = p.notes
        inventoryCount = p.inventoryCount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        formDosage = p.formDosage > 0 ? p.formDosage.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) : ""
        inventoryThreshold = p.inventoryLowThreshold.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        remindersEnabled = p.remindersEnabled
        // Schedule
        let sched = p.schedule
        scheduleType = sched.type
        intervalDays = sched.intervalDays
        selectedWeekdays = Set(sched.weekdays)
        timesPerWeek = sched.timesPerWeek
        doseTime = sched.timesOfDay.first
            ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())
            ?? Date()
        customNotes = sched.customNotes
    }
    
    private func buildSchedule() -> DoseSchedule {
        var schedule = DoseSchedule()
        schedule.type = scheduleType
        schedule.intervalDays = intervalDays
        schedule.weekdays = Array(selectedWeekdays)
        schedule.timesPerWeek = timesPerWeek
        schedule.timesOfDay = [doseTime]
        schedule.customNotes = customNotes
        return schedule
    }
    
    private func save() {
        let didSave = isEditMode ? updateExisting() : createNew()
        if didSave { dismiss() }
    }
    
    private func nextSortOrder() -> Int {
        let descriptor = FetchDescriptor<CompoundProtocol>()
        let all = (try? context.fetch(descriptor)) ?? []
        let maxOrder = all.map(\.sortOrder).max() ?? -1
        return maxOrder + 1
    }
    
    @discardableResult
    private func createNew() -> Bool {
        let nextOrder = nextSortOrder()
        let p = CompoundProtocol(
            name: name,
            category: category,
            administrationForm: administrationForm,
            doseAmount: NumericInputParser.parse(doseAmount) ?? 0,
            doseUnit: doseUnit,
            schedule: buildSchedule(),
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            notes: notes,
            halfLifeValue: NumericInputParser.parse(halfLifeValue) ?? 24,
            halfLifeUnit: halfLifeUnit,
            status: .active,
            inventoryCount: NumericInputParser.parse(inventoryCount) ?? 0,
            inventoryLowThreshold: NumericInputParser.parse(inventoryThreshold) ?? 5,
            remindersEnabled: remindersEnabled,
            formDosage: NumericInputParser.parse(formDosage) ?? 0,
            sortOrder: nextOrder
        )
        context.insert(p)
        do {
            try context.save()
            Haptics.success()
        } catch {
            print("[NewProtocolView] Failed to save new protocol: \(error)")
            Haptics.error()
            return false
        }
        Task {
            let descriptor = FetchDescriptor<CompoundProtocol>(
                predicate: #Predicate { $0.statusRaw == "Active" }
            )
            let allActive = (try? context.fetch(descriptor)) ?? []
            await NotificationService.shared.scheduleAll(protocols: allActive)
        }
        return true
    }
    
    @discardableResult
    private func updateExisting() -> Bool {
        guard let p = protocol_ else { return false }
        p.name = name
        p.category = category
        p.administrationForm = administrationForm
        p.doseAmount = NumericInputParser.parse(doseAmount) ?? p.doseAmount
        p.doseUnit = doseUnit
        p.halfLifeValue = NumericInputParser.parse(halfLifeValue) ?? p.halfLifeValue
        p.halfLifeUnit = halfLifeUnit
        p.schedule = buildSchedule()
        p.startDate = startDate
        p.endDate = hasEndDate ? endDate : nil
        p.notes = notes
        p.inventoryCount = NumericInputParser.parse(inventoryCount) ?? p.inventoryCount
        p.inventoryLowThreshold = NumericInputParser.parse(inventoryThreshold) ?? p.inventoryLowThreshold
        p.remindersEnabled = remindersEnabled
        p.formDosage = NumericInputParser.parse(formDosage) ?? p.formDosage
        p.refreshInventoryUnitLabel()
        do {
            try context.save()
            Haptics.success()
        } catch {
            print("[NewProtocolView] Failed to save protocol update: \(error)")
            Haptics.error()
            return false
        }
        // Re-schedule reminders for all active protocols in case times overlap
        Task {
            let descriptor = FetchDescriptor<CompoundProtocol>(
                predicate: #Predicate { $0.statusRaw == "Active" }
            )
            let allActive = (try? context.fetch(descriptor)) ?? []
            await NotificationService.shared.scheduleAll(protocols: allActive)
        }
        return true
    }
}

// MARK: - Form Field

struct FormField<Content: View>: View {
    let label: String
    var placeholder: String = ""
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(catalogKey: label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
                .tracking(0.4)
            content()
                .font(.system(size: 15))
        }
    }
}

// MARK: - Form Picker

struct FormPicker<T: Hashable & RawRepresentable>: View where T.RawValue == String {
    let label: String
    @Binding var selection: T
    let options: [T]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(catalogKey: label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
                .tracking(0.4)
            
            Menu {
                ForEach(options, id: \.rawValue) { option in
                    Button(LocalizedStringKey(option.rawValue)) {
                        Haptics.selection()
                        selection = option
                    }
                }
            } label: {
                HStack {
                    Text(catalogKey: selection.rawValue)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }
}

// MARK: - Weekday Picker

struct WeekdayPicker: View {
    @Binding var selected: Set<Weekday>
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases) { day in
                let isSelected = selected.contains(day)
                Button {
                    Haptics.selection()
                    if isSelected { selected.remove(day) }
                    else { selected.insert(day) }
                } label: {
                    Text(day.localizedShort)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.5))
                        .frame(width: 34, height: 34)
                        .background(isSelected ? Color.white : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }
        }
    }
}

#Preview {
    NewProtocolView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [CompoundProtocol.self, DoseLog.self], inMemory: true)
}
