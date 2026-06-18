# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
# Regenerate Xcode project after project.yml changes (required before building)
xcodegen generate

# Rebuild localization catalogs after script-managed string changes
python3 Scripts/build_l10n.py

# Build for simulator (unsigned, matches CI)
xcodebuild build -project Ascendancy.xcodeproj -scheme Ascendancy \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO

# Run all unit tests
xcodebuild test -project Ascendancy.xcodeproj -scheme Ascendancy \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO

# Run a single test class
xcodebuild test -project Ascendancy.xcodeproj -scheme Ascendancy \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  -only-testing:AscendancyTests/InventoryServiceTests

# Package unsigned IPA for device
Scripts/build_ipa.sh
```

If the iPhone 17 Pro simulator is unavailable, run `xcrun simctl list devices available` and substitute an installed iPhone simulator.

## Architecture

**Stack**: SwiftUI + SwiftData + WidgetKit, targeting iOS 17.0+, Swift 5.9. No external dependencies — all frameworks are Apple SDKs.

**Targets**: `Ascendancy` (app), `AscendancyWidget` (widget extension), `AscendancyTests` (unit tests). All wired into a single `Ascendancy` scheme in `project.yml`.

**Project file is generated**: `project.yml` is the source of truth. Never hand-edit `Ascendancy.xcodeproj` — run `xcodegen generate` after any `project.yml` change.

**App entry**: `AscendancyApp.swift` sets up SwiftData `ModelContainer` and CloudKit config. `ContentView.swift` is the root tab UI with backup import, reminder scheduling, sort migration, and widget snapshot publishing.

### Data Layer

- **SwiftData models** (`Ascendancy/Models/`): `CompoundProtocol`, `DoseLog`, `MediaDocument`
- Persisted enums use `*Raw` fields with typed computed properties — keep this pattern for migration safety
- `DoseSchedule` stored as JSON in `CompoundProtocol.scheduleData`
- `DoseLog` denormalizes `protocolName` and `protocolCategory` for display/backups — preserve these when creating or restoring logs
- `MediaDocument.imageData` uses SwiftData external storage
- `AppDistribution` gates persistence: in-memory for tests, CloudKit disabled for sideloaded builds, private CloudKit for signed builds

### Services (`Ascendancy/Services/`)

- **PKEngine**: Pharmacokinetics calculations with thread-safe LRU cache keyed on `(protocolId, logsHash, dateRange, resolution)`. `CompoundProtocol.cachedStableLevelInfo()` adds a per-protocol cache; call `clearStableLevelCache()` when mutating logs without changing count (e.g. timestamp edits).
- **InventoryService**: Inventory math and days-of-supply. Consumption rules differ by form: vials never auto-decrement; `formDosage > 0` enables fractional consumption; pill/capsule/patch/cream consume one unit; syringe/custom consume the logged dose amount.
- **NotificationService**: Centralized reminder scheduling via `scheduleAll(protocols:)`. Cancels pending reminders, skips protocols with reminders disabled, merges overlapping minute-level dose times.
- **WidgetSnapshotService**: Writes compact JSON snapshots to app-group container. Skips during XCTest runs.
- **BackupService**: Versioned JSON format. Restore deletes all existing data before inserting. Rejects unsupported future backup versions.

### Widget Architecture

The widget does **not** query SwiftData directly. Data flows one way: app → `WidgetSnapshotService` → app-group JSON → widget `TimelineProvider`. Shared code (`Ascendancy/Shared/`) is intentionally narrow: `AscendancyWidgetShared.swift`, `AppGroupSupport.swift`, `AscendancyTheme.swift`. Widget code must remain extension-safe (`APPLICATION_EXTENSION_API_ONLY = YES`). Never reference app-only SwiftData models or services from widget code.

### Key Invariants

- `CompoundProtocol.nextDoseDate(from:)` is the single source of truth for next dose timing; it anchors interval/weekly schedules to `startDate` so editing past doses never shifts future ones.
- `DoseScheduleDayHelper` derives scheduled rows, merges off-schedule logs, prevents duplicates, and caches. Clear it after protocol or log mutations.
- Low inventory = `inventoryCount <= inventoryLowThreshold && inventoryCount > 0`; zero is out-of-stock, not low.
- Dose logging flow: create `DoseLog` → decrement inventory → save → clear PK/day/stable caches → optional low-inventory notification.
- Protocol create/edit/status changes must reschedule reminders for all active protocols.
- `@AppStorage` keys: `userName`, `userGoal`, `profileImageData`, `globalNotificationsEnabled`, `protocolListFilter`.

## Testing

Test target: `AscendancyTests`. Focused test classes by area:

| Change area | Test class |
|---|---|
| Schedule model, nextDoseDate, half-life, inventory flags | `CompoundProtocolTests` |
| Day rows, week dots, off-schedule merging, cache | `DoseScheduleDayHelperTests` |
| Inventory decrement/restore/edit, days-of-supply | `InventoryServiceTests` |
| PK decay, stable levels, cache, combined levels | `PharmacokineticsEngineTests` |
| Backup export/import, pasted backup parsing | `BackupServiceTests` |
| Protocol ordering migration | `ProtocolSortMigrationTests` |
| App-group diagnostics, provisioning-profile parsing | `AppGroupSupportTests` |
| Locale-tolerant decimal input | `NumericInputParserTests` |
| Health metric chart domain/baseline | `HealthMetricChartStyleTests` |

No unit tests exist for: `WidgetSnapshotService.makeSnapshot`, `NotificationService.scheduleAll`, HealthKit query execution, or SwiftUI interaction flows. For those, verify via simulator build and manual smoke test.

## Localization

English is the development language. String catalogs are managed by `Scripts/build_l10n.py` — do not hand-edit `.xcstrings` files for keys owned by the script. The script preserves unmanaged catalog keys but doesn't translate them. Region changes must align `project.yml` `knownRegions` with `LOCALES` in `build_l10n.py`.

## Code Conventions

- Use `protocol_` naming where `protocol` would clash with the Swift keyword.
- Use `NumericInputParser` for user-entered decimals (handles comma/dot locales).
- Use `Haptics` service for touch feedback, not ad-hoc feedback generators.
- Use `AscendancyTheme` and `.glassCard()` / `.glassCardFilling()` for new cards.
- Reuse existing components (`GlassCard`, `ProtocolCard`, `TileHeader`, `SectionHeader`, charts, week dots) unless a redesign is requested.
- Root tab behavior differs by OS: iOS 18+ uses value-based `Tab`; iOS 17 uses standard `TabView` plus floating log-dose button.
- Home and Metrics calculate PK charts from lightweight snapshots in background tasks — don't pass live SwiftData models into detached tasks.

## Sensitive Domain

This is a health-adjacent tracking app. Avoid medical claims, dosing recommendations, diagnostic language, or promises of health outcomes. Keep calculator and HealthKit copy factual and utility-focused. When adding HealthKit types or permission strings, keep entitlements, Info.plist keys, and localized plist strings aligned.