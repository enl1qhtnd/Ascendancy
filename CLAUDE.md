# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Ascendancy is an iOS 17+ SwiftUI / SwiftData app for tracking health protocols (medications, peptides, TRT). It includes a pharmacokinetics engine for active-level visualisation, HealthKit integration, a media library (photos + PDFs), and a WidgetKit "next dose" home-screen widget. The Xcode project is generated from `project.yml` via XcodeGen — never edit `Ascendancy.xcodeproj` by hand.

## Common commands

All builds run on macOS with Xcode 16.2 (CI) / Xcode 15+ (local) and target the iPhone simulator.

```bash
# Regenerate Ascendancy.xcodeproj from project.yml — run after any project.yml change,
# after adding/removing source files, or right after cloning.
xcodegen generate

# Build for the simulator (matches CI)
xcodebuild build \
  -project Ascendancy.xcodeproj \
  -scheme Ascendancy \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO

# Run the full test suite
xcodebuild test \
  -project Ascendancy.xcodeproj \
  -scheme Ascendancy \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO

# Run a single test class or method
xcodebuild test \
  -project Ascendancy.xcodeproj \
  -scheme Ascendancy \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:AscendancyTests/PharmacokineticsEngineTests \
  -only-testing:AscendancyTests/CompoundProtocolTests/testNextDoseDate_DailySchedule \
  CODE_SIGNING_ALLOWED=NO

# Build an unsigned IPA into ./build (used for sideloading; CI also produces this)
./Scripts/build_ipa.sh

# Regenerate string catalogs (Localizable.xcstrings + InfoPlist.xcstrings) from source-of-truth Python
python3 Scripts/build_l10n.py
```

CI (`.github/workflows/build.yml`) runs the build, tests, and IPA packaging on `macos-14` for every push/PR to `main`. Marketing / build version (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` in `project.yml`) must be kept in sync with the constants `APP_MARKETING_VERSION` / `APP_BUILD_NUMBER` at the top of `Scripts/build_l10n.py`.

## Architecture

### Targets (defined in `project.yml`)

- **Ascendancy** (app) — main SwiftUI app, bundle id `de.enl1qhtnd.asce`.
- **AscendancyWidget** (app extension) — WidgetKit extension, bundle id `de.enl1qhtnd.asce.widget`. It re-uses `Ascendancy/Shared/AscendancyWidgetShared.swift` (the only file shared via direct source inclusion).
- **AscendancyTests** (XCTest) — depends on the app target with `@testable import Ascendancy`.

The app and widget communicate via the App Group `group.de.enl1qhtnd.asce`. CloudKit sync uses container `iCloud.de.enl1qhtnd.asce` (private DB).

### App entry & data layer

- `AscendancyApp.swift` builds a single shared `ModelContainer` over the schema `[CompoundProtocol, DoseLog, MediaDocument]`.
  - In tests (`AppDistribution.isRunningTests`, detected via `XCTestConfigurationFilePath`), the store is in-memory and CloudKit is disabled.
  - In sideloaded builds (`AppDistribution.isSideloaded`, detected via embedded provisioning profile), CloudKit is also disabled. CloudKit is only on for App Store builds. When adding new SwiftData models, every property must have a default value (CloudKit requirement).
- `ContentView` is a `TabView` with four tabs: Home, Protocols, Logs, Metrics. It owns the top-level `@Query` for active protocols and all dose logs, and computes a `widgetSnapshotFingerprint` to trigger widget snapshot republishing on data changes.
- One-time data-shape fixups run from `ContentView.task` via `ProtocolSortMigration.normalizeIfNeeded(in:)` — when adding more such migrations, follow the same pattern (idempotent, fetch-and-renumber/normalize, save).

### SwiftData model conventions (important)

`@Model` classes (`CompoundProtocol`, `DoseLog`, `MediaDocument`) follow these rules:

- Enum-valued fields are stored as `…Raw: String` with a computed `var category: CompoundCategory { get/set }` wrapper. **Always read/write through the wrapper**; the raw string exists only for SwiftData/CloudKit storage and `#Predicate` filtering (e.g. `#Predicate { $0.statusRaw == "Active" }`).
- Complex value types are stored as encoded JSON `Data` (see `scheduleData: Data?` ↔ `var schedule: DoseSchedule`).
- Every property has a default value so CloudKit can add it as a non-required column.
- The dose-log relationship is named `protocol_` (with trailing underscore) because `protocol` is a Swift keyword. Watch for this when writing predicates or new code that touches relationships.
- Stable list ordering uses `CompoundProtocol.listSortDescriptors` (sortOrder, then name). Always reuse it instead of inventing local sorts so the widget, queries, and migrations stay consistent.

### Pharmacokinetics & schedule helpers

- `PharmacokineticsEngine` computes active-compound levels using exponential decay from `halfLifeInHours` and dose logs. It has its own thread-safe LRU cache keyed on `(protocolId, logsHash, dateRange, resolution)`. `CompoundProtocol.cachedStableLevelInfo()` adds a second tiny cache keyed on `logsCount`. When mutating logs in a way that wouldn't change `count` (e.g. editing a timestamp), call `clearStableLevelCache()`.
- `CompoundProtocol.nextDoseDate(from:)` is the single source of truth for "when is the next dose". It anchors interval/weekly schedules to the protocol `startDate` so editing past doses never shifts future ones — preserve that behaviour.
- `DoseScheduleDayHelper` produces today/week rows for the home view, sheet, and widget; it has its own size-bounded cache. Always call its `mergedRows` / `isLogged` helpers rather than re-deriving "logged today" logic.

### Widget pipeline

The widget never accesses SwiftData directly. The flow is:

1. App computes a snapshot via `WidgetSnapshotService.publish(protocols:logs:)` (called from `ContentView` when `widgetSnapshotFingerprint` changes, and on `task`).
2. `AscendancyWidgetShared.saveSnapshot` writes JSON to the App Group container (`AscendancyWidgetSnapshot.json`).
3. The widget reads via `AscendancyWidgetShared.loadSnapshot()` and `WidgetCenter.shared.reloadTimelines(ofKind:)` is invoked from the app.

If you add fields the widget needs to read, extend the `AscendancyWidgetSnapshot` Codable struct in `Shared/AscendancyWidgetShared.swift` (compiled into both targets) — do not import app-target types into the widget.

### Services layer

`Ascendancy/Services/` holds singletons / enums for cross-cutting concerns: `HealthKitService` (ObservableObject, `@Published` arrays for body weight / HR / steps / etc.), `NotificationService` (`actor`, schedules merged dose reminders), `InventoryService` (`@MainActor`, decrements on dose log respecting `formDosage` and form type — vials are restocked manually), `BackupService` (`@MainActor` enum, exports/imports `.ascendancybackup` JSON via `FileDocument`), `Haptics` (centralized generators, gated by `isEnabled`), `NumericInputParser` (locale-tolerant decimal parsing — use this everywhere the user types a number).

### Localization

The app supports 17 locales. `Localizable.xcstrings` and `InfoPlist.xcstrings` are **generated** from `Scripts/build_l10n.py` — do not hand-edit the catalogs. To add or change a string:

1. Add the English source string to the `KEYS` list (and any per-locale overrides) in `Scripts/build_l10n.py`.
2. Run `python3 Scripts/build_l10n.py` to regenerate both catalogs.
3. Use the string in code via `String(localized: "…")`, `Text("…")`, or the `Text(catalogKey:)` / `LocalizedStringKey.catalog(_:)` helpers in `Extensions/LocalizedStringKey+Catalog.swift` for runtime keys.

In `project.yml` the catalogs are wired via explicit `buildPhase: resources` entries (XcodeGen's top-level `resources:` doesn't apply correctly here) — keep that shape if you add another catalog.

## Conventions

- UI is dark-mode only (`UIUserInterfaceStyle: Dark`, `preferredColorScheme(.dark)`). Glassmorphic look comes from `Components/GlassCard.swift`; reuse it instead of rolling new card chrome.
- Portrait-only on iPhone; iPad supports all orientations.
- Deployment target is iOS 17.0; Swift 5.9. SwiftUI + SwiftData first — avoid bringing in UIKit unless mirroring an Apple sample (e.g. `Components/PDFKitView.swift` wraps PDFKit).
- Color per `CompoundCategory` comes from `category.uiColor` — that is the canonical source for any new UI surface that colors by category.
- Source files live under `Ascendancy/{Models,Services,Views,Components,Extensions,Shared}`. XcodeGen picks them up automatically; just `xcodegen generate` after adding a file.
