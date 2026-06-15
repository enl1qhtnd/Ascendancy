# AGENTS.md

Operational notes for humans and coding agents working in this repository.

## Scope

These instructions apply to the whole repo. App code lives under `Ascendancy/`, the WidgetKit extension lives under `AscendancyWidget/`, and unit tests live under `AscendancyTests/`.

## Prerequisites

- Xcode with an iOS 17+ SDK. CI pins Xcode 16.2 on `macos-14`; local Xcode 15+ is fine for compilation.
- XcodeGen (`brew install xcodegen`) to regenerate `Ascendancy.xcodeproj` after `project.yml` changes.
- Python 3 to run `Scripts/build_l10n.py` when adding or changing localized strings managed by that script.

## Project Snapshot

- Stack: SwiftUI, SwiftData, WidgetKit, iOS 17.0+, Swift 5.9.
- Targets: `Ascendancy` app, `AscendancyWidget` app extension, and `AscendancyTests` unit-test bundle.
- Bundle identifiers: `de.enl1qhtnd.asce`, `de.enl1qhtnd.asce.widget`, and `de.enl1qhtnd.asce.tests`.
- UI: intended as an iPhone app target (`TARGETED_DEVICE_FAMILY = 1` in `project.yml`), portrait-primary for iPhone, dark-first (`UIUserInterfaceStyle` is `Dark`; app also sets `.preferredColorScheme(.dark)`).
- Integrations: HealthKit, User Notifications, CloudKit, WidgetKit, App Groups, PDFKit, PhotosUI, UniformTypeIdentifiers, and SwiftData.
- App group: `group.de.enl1qhtnd.asce` is shared by the app and widget for widget snapshot JSON.
- CloudKit: normal signed App Store/TestFlight-style builds use private CloudKit (`iCloud.de.enl1qhtnd.asce`); tests and sideloaded builds disable CloudKit through `AppDistribution`.
- Project file: generated. `project.yml` is the source of truth; do not hand-edit `Ascendancy.xcodeproj` unless unavoidable.
- Generated project drift can happen. If `Ascendancy.xcodeproj` disagrees with `project.yml` about versions, device families, resources, or entitlements, regenerate from `project.yml` and trust the regenerated result.

## Repository Layout

| Path | Role |
|------|------|
| `Ascendancy/` | App sources, assets, plist, entitlements, and string catalogs |
| `Ascendancy/AscendancyApp.swift` | `@main`, SwiftData `ModelContainer`, CloudKit configuration |
| `Ascendancy/ContentView.swift` | Root tab UI, backup open-in import, reminder scheduling, sort migration, widget snapshot publishing |
| `Ascendancy/Models/` | SwiftData models (`CompoundProtocol`, `DoseLog`, `MediaDocument`) |
| `Ascendancy/Services/` | HealthKit, notifications, inventory, PK engine, backups, sorting migration, parsers, widget snapshots |
| `Ascendancy/Views/` | Screens: `Home/`, `ActiveProtocols/`, `Logs/`, `Metrics/`, `Settings/` |
| `Ascendancy/Components/` | Reusable UI (`GlassCard`, `ProtocolCard`, charts, PDF view, week dots, vitals rows) |
| `Ascendancy/Extensions/` | Swift extensions and visual theme helpers |
| `Ascendancy/Shared/` | Cross-target widget DTOs, app-group support, and snapshot load/save helpers |
| `AscendancyWidget/` | WidgetKit extension source, plist, and entitlements |
| `AscendancyTests/` | Unit tests for backup, scheduling, inventory, PK, parsing, sorting migration, app groups, charts, and model behavior |
| `project.yml` | XcodeGen spec for app, widget, tests, resources, entitlements, plist keys, and known regions |
| `Scripts/build_l10n.py` | Generates `Localizable.xcstrings` and `InfoPlist.xcstrings` |
| `Scripts/build_ipa.sh` | Builds Release for device and packages an unsigned IPA in `build/` |
| `.github/workflows/build.yml` | CI project generation, build, tests, and IPA artifact packaging |
| `.github/workflows/release.yml` | Manual workflow that tests, builds unsigned IPA, and creates a draft GitHub release |
| `build/` | Disposable `xcodebuild` and IPA output; do not commit or rely on it |

String catalogs: `Ascendancy/Localizable.xcstrings` and `Ascendancy/InfoPlist.xcstrings` are listed as resources in `project.yml`. Swift sources under `Ascendancy/` intentionally exclude `**/*.xcstrings` from the compile phase so catalogs are not compiled as Swift.

## Target And Entitlement Wiring

- `project.yml` wires the app, widget, and tests into the shared `Ascendancy` scheme.
- The app embeds `AscendancyWidget`; unsigned builds validate compilation and embedding but not real app-group persistence.
- Keep app-group values aligned in `project.yml`, `Ascendancy/Ascendancy.entitlements`, `AscendancyWidget/AscendancyWidget.entitlements`, and `AppGroupSupport.fallbackAppGroupIdentifier`.
- CloudKit entitlements are app-only. Do not add CloudKit to the widget.
- Widget extension code must remain extension-safe (`APPLICATION_EXTENSION_API_ONLY = YES`).
- Shared code compiled into the widget is intentionally narrow: `AscendancyWidgetShared.swift`, `AppGroupSupport.swift`, `AscendancyTheme.swift`, and the shared catalog resource. Do not reference app-only SwiftData models or services from widget code.

## Widget Architecture

- `AscendancyWidget` supports `.systemSmall`, `.systemMedium`, and `.systemLarge`.
- Widget content includes next scheduled dose, today's logged/total dose progress, upcoming doses, and low-inventory items.
- The widget does not open or query the app's SwiftData store directly. The app writes a compact `AscendancyWidgetSnapshot` JSON file into the app-group container.
- Shared widget DTOs, app-group constants, and snapshot load/save helpers live in `Ascendancy/Shared/AscendancyWidgetShared.swift` and `Ascendancy/Shared/AppGroupSupport.swift`.
- App-side snapshot generation lives in `Ascendancy/Services/WidgetSnapshotService.swift`. It uses `CompoundProtocol.nextDoseDate`, `DoseScheduleDayHelper`, `InventoryService.daysOfSupply`, and current logs.
- `ContentView` queries active protocols and logs, then publishes snapshots on launch/task and when the snapshot fingerprint changes.
- Settings also exposes app-group diagnostics and can publish a snapshot when the shared container is available but no snapshot exists.
- `AppGroupSupport` resolves app-group identifiers from provisioning profiles plus the fallback, writes snapshots atomically to all writable groups, and loads the first decodable snapshot.
- The widget `TimelineProvider` reads the latest app-group snapshot and reloads near the next scheduled dose or at a fallback interval.
- `WidgetSnapshotService.publish` skips publishing during XCTest runs.
- If dose, schedule, inventory, or low-stock semantics change, update `WidgetSnapshotService`, widget UI, and relevant tests together.

## Localization Workflow

English is the development language; `project.yml` lists all known regions.

1. UI strings owned by the generator: add the English key to `KEYS` in `Scripts/build_l10n.py`, add or update per-locale strings in the script tables, then run `python3 Scripts/build_l10n.py`.
2. Runtime or dynamic keys: use `LocalizedStringKey.catalog("...")` or `Text(catalogKey:)` from `LocalizedStringKey+Catalog.swift` so the string remains a catalog key.
3. Info.plist copy such as HealthKit usage descriptions: update `build_infoplist()` in `Scripts/build_l10n.py`, then rerun the script.
4. Version localizations: keep `APP_MARKETING_VERSION` and `APP_BUILD_NUMBER` in `Scripts/build_l10n.py` aligned with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
5. Region changes: align `project.yml` `knownRegions` and the `LOCALES` list in `build_l10n.py`.

Do not only hand-edit `.xcstrings` if the key is expected to be owned by `build_l10n.py`; the next script run can overwrite it. The script preserves unmanaged catalog keys, but unmanaged keys are not automatically translated by the script. The widget target already includes `Localizable.xcstrings`, so widget-localized strings should use the same catalog workflow instead of separate widget resources.

## Build And Run

From the repo root:

1. Regenerate after `project.yml` changes:
   ```bash
   xcodegen generate
   ```
2. Rebuild localization catalogs after script-managed localization changes:
   ```bash
   python3 Scripts/build_l10n.py
   ```
3. Debug app/widget build without signing, matching CI's simulator style:
   ```bash
   xcodebuild build -project Ascendancy.xcodeproj -scheme Ascendancy \
     -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" \
     -derivedDataPath build \
     CODE_SIGNING_ALLOWED=NO
   ```
4. Unit tests:
   ```bash
   xcodebuild test -project Ascendancy.xcodeproj -scheme Ascendancy \
     -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" \
     -derivedDataPath build \
     CODE_SIGNING_ALLOWED=NO
   ```
   If that simulator is unavailable, use `xcodebuild -showdestinations -project Ascendancy.xcodeproj -scheme Ascendancy` and `xcrun simctl list devices available`, then substitute an installed iPhone simulator.
5. IPA packaging:
   ```bash
   Scripts/build_ipa.sh
   ```

Avoid recommending `xcodebuild -dry-run`; it is not supported by the Xcode version observed in this repo and can leave local result bundles.

## Targeted Tests

Use targeted tests for focused changes before falling back to the full suite:

```bash
xcodebuild test -project Ascendancy.xcodeproj -scheme Ascendancy \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=latest" \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  -only-testing:AscendancyTests/InventoryServiceTests
```

| Change area | Test file |
|-------------|-----------|
| Schedule model, `nextDoseDate`, half-life, inventory flags | `CompoundProtocolTests` |
| Day rows, week dots, off-schedule log merging, schedule cache behavior | `DoseScheduleDayHelperTests` |
| Inventory decrement/restore/edit deltas and days-of-supply | `InventoryServiceTests` |
| PK decay, stable levels, cache behavior, combined active levels | `PharmacokineticsEngineTests` |
| Backup export/import, pasted backup parsing, media import helpers | `BackupServiceTests` |
| Protocol ordering migration | `ProtocolSortMigrationTests` |
| App-group diagnostics and provisioning-profile parsing | `AppGroupSupportTests` |
| Locale-tolerant decimal input | `NumericInputParserTests` |
| Health metric chart domain and baseline behavior | `HealthMetricChartStyleTests` |

Current unit-test gaps: no direct unit tests for `WidgetSnapshotService.makeSnapshot`, `NotificationService.scheduleAll`, HealthKit query execution, or SwiftUI interaction flows. For those areas, require a successful app/widget build and do a simulator or device smoke test when feasible.

## Working Rules For Agents

- Use subagents for broad analysis or parallel inspection when useful; keep each subtask concrete and bounded.
- Prefer `project.yml` over editing generated Xcode project files.
- After changing `project.yml`, run `xcodegen generate` before building.
- After changing script-managed localization, run `python3 Scripts/build_l10n.py`.
- Do not commit or depend on `build/`, DerivedData output, local result bundles, unsigned IPAs, or local signing/export files.
- Keep diffs scoped; avoid drive-by refactors unless asked.
- Preserve iOS 17+ APIs and existing SwiftUI/SwiftData patterns.
- Keep widget target code extension-safe.
- Respect the naming pattern `protocol_` where `protocol` would clash with the Swift keyword.
- Use `NumericInputParser` for user-entered decimal numbers; it handles comma and dot decimals.
- Use `Haptics` for touch feedback instead of creating one-off feedback generators.
- Execute builds/tests yourself when possible; do not only suggest commands.

## Codebase Conventions

- SwiftData schema currently includes `CompoundProtocol`, `DoseLog`, and `MediaDocument`.
- Persisted enums are stored in `*Raw` fields with typed computed properties; keep this for migration safety.
- `DoseSchedule` is stored as JSON in `CompoundProtocol.scheduleData`.
- `DoseLog` keeps `protocolName` and `protocolCategory` denormalized for display/backups while also relating to `protocol_`; preserve those fields when creating or restoring logs.
- `MediaDocument.imageData` uses SwiftData external storage and stores imported images, PDFs, and other supported file bytes.
- `AppDistribution` gates persistence behavior: tests use in-memory SwiftData, sideloaded/test builds disable CloudKit, and normal signed builds use private CloudKit.
- Schedule behavior changes usually require updates to `DoseSchedule`, `CompoundProtocol.nextDoseDate`, `DoseScheduleDayHelper`, protocol create/edit UI, `NotificationService`, `WidgetSnapshotService`, and tests.
- `CompoundProtocol.nextDoseDate(from:)` is the single source of truth for "when is the next dose" and anchors interval/weekly schedules to `startDate` so editing past doses never shifts future ones. Preserve that invariant.
- Current concrete schedule calculations use `timesOfDay.first`; the UI currently saves one dose time. Multi-dose-per-day support would be cross-cutting, not a one-file change.
- `endDate` is stored, backed up, displayed, and fingerprinted, but is not currently enforced by `nextDoseDate`; active-status filtering does most schedule eligibility work.
- `DoseScheduleDayHelper` derives scheduled rows, merges off-schedule same-day logs, prevents duplicate scheduled/logged rows, and keeps small static caches. Clear it after protocol or log mutations.
- `PharmacokineticsEngine` keeps a thread-safe LRU cache keyed on `(protocolId, logsHash, dateRange, resolution)`.
- `CompoundProtocol.cachedStableLevelInfo()` adds a per-protocol cache; call `clearStableLevelCache()` when mutating logs in a way that does not change count, such as timestamp edits.
- `PKDataFingerprint` drives chart recalculation in Home, Metrics, and Protocol Detail. Update it when chart-affecting protocol or log fields are added.
- Stable level progress is based on the earliest of `startDate` or first log; 5 half-lives counts as stable.
- Inventory math and days-of-supply estimates belong in `InventoryService`.
- Inventory consumption rules: vials never auto-decrement; `formDosage > 0` enables fractional unit consumption; pill/capsule/patch/cream consume one unit; syringe/custom consume the actual logged dose amount.
- Low inventory is `inventoryCount <= inventoryLowThreshold && inventoryCount > 0`; zero is out of inventory, not low inventory.
- Dose logging flow: create `DoseLog`, decrement inventory via `InventoryService`, save context, clear PK/day/stable caches, then optionally send a low-inventory notification.
- Dose edit flow: adjust inventory from the previous amount to the updated amount, save context, clear caches, then optionally send a low-inventory notification.
- Dose delete flow: restore inventory, delete the log, save context, and clear caches.
- Protocol create/edit/status changes should reschedule reminders for all active protocols after save.
- Reminder scheduling is centralized in `NotificationService.scheduleAll(protocols:)`, which cancels pending dose reminders, skips protocols with reminders disabled, generates upcoming events, and merges overlapping minute-level dose times into shared notifications.
- Widget data flow: SwiftData changes should result in a fresh app-group snapshot and `WidgetCenter` timeline reload through `WidgetSnapshotService`.
- Protocol ordering is persisted in `CompoundProtocol.sortOrder`; `ProtocolSortMigration.normalizeIfNeeded(in:)` fixes duplicates or all-zero legacy order values. Reordering is only enabled under the unfiltered "All" protocols list.
- Backup restore deletes all existing `DoseLog`, `MediaDocument`, and `CompoundProtocol` records before inserting the imported payload. It restores IDs/raw fields, restores profile defaults, saves, and clears PK/day/stable caches.
- Backup format is versioned and accepts raw JSON or base64-pasted JSON. Unsupported future backup versions must be rejected.
- File import uses security-scoped resource access and `NSFileCoordinator`; media file picking uses a custom document picker wrapper to avoid defaulting into the app's iCloud container.
- `@AppStorage` keys are part of app behavior: `userName`, `userGoal`, `profileImageData`, `globalNotificationsEnabled`, and `protocolListFilter`.
- HealthKit reads body mass, resting heart rate, steps, body fat, active energy, height, and BMI over 90-day windows. It may write body mass, body fat, height, and BMI. Keep entitlements and usage strings aligned when changing HealthKit types.

## UI And Design Guardrails

- Dark-first, dense, glassmorphic cards, high-contrast light text accents, compact SF Symbols.
- Reuse existing components (`GlassCard`, `ProtocolCard`, `TileHeader`, `SectionHeader`, charts, week dots, etc.) unless a redesign is requested.
- Use `AscendancyTheme` and `.glassCard()` / `.glassCardFilling()` for new app cards instead of one-off card styling.
- Preserve local screen ownership: major feature views own their own `NavigationStack`, sheets, and local side effects.
- Root tab behavior is split by OS: iOS 18+ uses value-based `Tab`, while iOS 17 uses a standard `TabView` plus floating log-dose button.
- Home and Metrics calculate PK charts from lightweight snapshots in background tasks; avoid passing live SwiftData models into detached tasks.
- `DoseScheduleDayHelper` drives the root log-dose picker, Today's Dose tile, Day Schedule sheet, and Week Dot row. Schedule semantics changes should be reflected across all of those surfaces.
- Widget UI should remain compact, dark, glanceable, and useful without medical or dosing advice.

## Validation Expectations

- There is a unit-test target: `AscendancyTests`.
- For non-trivial logic: run the relevant targeted unit tests or the full `xcodebuild test` suite.
- For app or widget integration changes: run a successful `xcodebuild build` for scheme `Ascendancy` so the embedded widget is compiled and validated.
- For `project.yml` changes: run `xcodegen generate`, then build.
- For localization generator changes: run `python3 Scripts/build_l10n.py`, then review catalog diffs.
- For HealthKit, notifications, inventory, scheduling, backups, widgets, or app-group changes: do a manual simulator/device smoke test when feasible.
- Widget/app-group behavior requires signed installation on simulator or device for a true persistence smoke test; unsigned builds are compile/embed validation only.

## Sensitive Domain Notes

- This is a health-adjacent tracking app. Avoid medical claims, dosing recommendations, diagnostic language, or promises of health outcomes.
- Keep calculator and HealthKit copy factual and utility-focused; do not expand it into advice.
- When adding HealthKit types or permission strings, keep entitlements, Info.plist keys, and localized plist strings aligned.
