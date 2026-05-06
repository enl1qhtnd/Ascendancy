# AGENTS.md

Operational notes for humans and coding agents working in this repository.

## Scope

These instructions apply to the whole repo. App code lives under `Ascendancy/`, the WidgetKit extension lives under `AscendancyWidget/`, and unit tests live under `AscendancyTests/`.

## Prerequisites

- Xcode with an iOS 17+ SDK. CI pins Xcode 16.2 on `macos-14`; local Xcode 15+ is fine for compilation.
- XcodeGen (`brew install xcodegen`) to regenerate `Ascendancy.xcodeproj` after `project.yml` changes.
- Python 3 to run `Scripts/build_l10n.py` when adding or changing localized strings managed by that script.

## Project Snapshot

- Stack: SwiftUI, SwiftData, WidgetKit, iOS 17.0+.
- Targets: `Ascendancy` app, `AscendancyWidget` app extension, and `AscendancyTests` unit-test bundle.
- Bundle identifiers: `de.enl1qhtnd.asce`, `de.enl1qhtnd.asce.widget`, and `de.enl1qhtnd.asce.tests`.
- UI: iPhone app target (`TARGETED_DEVICE_FAMILY = 1`), portrait-primary for iPhone, dark-first (`UIUserInterfaceStyle` is `Dark`; app also sets `.preferredColorScheme(.dark)`).
- Integrations: HealthKit, User Notifications, CloudKit, WidgetKit, App Groups, PDFKit, PhotosUI, and SwiftData.
- App group: `group.de.enl1qhtnd.asce` is shared by the app and widget for widget snapshot JSON.
- CloudKit: normal signed App Store/TestFlight-style builds use private CloudKit (`iCloud.de.enl1qhtnd.asce`); tests and sideloaded builds disable CloudKit through `AppDistribution`.
- Project file: generated. `project.yml` is the source of truth; do not hand-edit `Ascendancy.xcodeproj` unless unavoidable.

## Repository Layout

| Path | Role |
|------|------|
| `Ascendancy/` | App sources, assets, plist, entitlements, and string catalogs |
| `Ascendancy/AscendancyApp.swift` | `@main`, SwiftData `ModelContainer`, CloudKit configuration |
| `Ascendancy/ContentView.swift` | Root tab UI, reminder scheduling entry point, widget snapshot publishing trigger |
| `Ascendancy/Models/` | SwiftData models (`CompoundProtocol`, `DoseLog`, `MediaDocument`) |
| `Ascendancy/Services/` | HealthKit, notifications, inventory, PK engine, backups, sorting migration, parsers, widget snapshots |
| `Ascendancy/Views/` | Screens: `Home/`, `ActiveProtocols/`, `Logs/`, `Metrics/`, `Settings/` |
| `Ascendancy/Components/` | Reusable UI (`GlassCard`, `ProtocolCard`, charts, PDF view, week dots) |
| `Ascendancy/Extensions/` | Swift extensions such as `LocalizedStringKey+Catalog.swift` |
| `Ascendancy/Shared/` | Cross-target code shared by app and widget (`AscendancyWidgetShared`) |
| `AscendancyWidget/` | WidgetKit extension source, plist, and entitlements |
| `AscendancyTests/` | Unit tests for backup, scheduling, inventory, PK, numeric parsing, sorting migration, and model behavior |
| `project.yml` | XcodeGen spec for app, widget, tests, resources, entitlements, plist keys, and known regions |
| `Scripts/build_l10n.py` | Generates `Localizable.xcstrings` and `InfoPlist.xcstrings` |
| `Scripts/build_ipa.sh` | Builds Release for device and packages an unsigned IPA in `build/` |
| `.github/workflows/build.yml` | CI project generation, build, tests, and IPA artifact packaging |
| `build/` | Disposable `xcodebuild` and IPA output; do not commit or rely on it |

String catalogs: `Ascendancy/Localizable.xcstrings` and `Ascendancy/InfoPlist.xcstrings` are listed as resources in `project.yml`. Swift sources under `Ascendancy/` intentionally exclude `**/*.xcstrings` from the compile phase so catalogs are not compiled as Swift.

## Widget Architecture

- `AscendancyWidget` is wired into `project.yml` as an iOS app extension and embedded by the `Ascendancy` app target.
- The widget supports `.systemSmall`, `.systemMedium`, and `.systemLarge` families.
- Widget content includes the next scheduled dose, today's logged/total dose progress, upcoming doses, and low-inventory items.
- The widget does not open or query the app's SwiftData store directly. The app writes a compact `AscendancyWidgetSnapshot` JSON file into the app-group container.
- Shared widget DTOs, app-group constants, and snapshot load/save helpers live in `Ascendancy/Shared/AscendancyWidgetShared.swift` and are compiled into both targets.
- App-side snapshot generation lives in `Ascendancy/Services/WidgetSnapshotService.swift`. It uses `CompoundProtocol.nextDoseDate`, `DoseScheduleDayHelper`, `InventoryService.daysOfSupply`, and current logs.
- `ContentView` queries active protocols and logs, then publishes snapshots on launch/task and when the snapshot fingerprint changes.
- The widget `TimelineProvider` reads the latest app-group snapshot and reloads near the next scheduled dose or at a fallback interval.
- Widget and app entitlements must keep `group.de.enl1qhtnd.asce` aligned in `project.yml`, `Ascendancy/Ascendancy.entitlements`, and `AscendancyWidget/AscendancyWidget.entitlements`.
- App Groups require a signed app to exercise fully. Unsigned `CODE_SIGNING_ALLOWED=NO` builds validate compilation and embedding, but not real app-group persistence. `WidgetSnapshotService` skips publishing during XCTest runs.
- If dose, schedule, inventory, or low-stock semantics change, update `WidgetSnapshotService`, widget UI, and relevant tests together.

## Localization Workflow

English is the development language; `project.yml` lists all known regions.

1. UI strings owned by the generator: add the English key to `KEYS` in `Scripts/build_l10n.py`, add or update per-locale strings in the script tables, then run `python3 Scripts/build_l10n.py`.
2. Runtime or dynamic keys: use `LocalizedStringKey.catalog("...")` or `Text(catalogKey:)` from `LocalizedStringKey+Catalog.swift` so the string remains a catalog key.
3. Info.plist copy such as HealthKit usage descriptions: update `build_infoplist()` in `Scripts/build_l10n.py`, then rerun the script.
4. Version localizations: keep `APP_MARKETING_VERSION` and `APP_BUILD_NUMBER` in `Scripts/build_l10n.py` aligned with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
5. Region changes: align `project.yml` `knownRegions` and the `LOCALES` list in `build_l10n.py`.

Do not only hand-edit `.xcstrings` if the key is expected to be owned by `build_l10n.py`; the next script run can overwrite it. The widget currently uses code-local SwiftUI literals; if widget localization is required, explicitly wire widget localization resources in `project.yml`.

## Build And Run

From the repo root:

1. Regenerate after `project.yml` changes: `xcodegen generate`.
2. Debug app/widget build without signing:
   ```bash
   xcodebuild -project Ascendancy.xcodeproj -scheme Ascendancy -configuration Debug \
     -destination "generic/platform=iOS" \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
   ```
3. Unit tests on an installed simulator:
   ```bash
   xcodebuild test -project Ascendancy.xcodeproj -scheme Ascendancy \
     -destination "platform=iOS Simulator,name=<installed iPhone>,OS=<installed OS>" \
     CODE_SIGNING_ALLOWED=NO
   ```
4. IPA packaging: `Scripts/build_ipa.sh` writes an unsigned IPA to `build/`.

## Working Rules For Agents

- Prefer `project.yml` over editing generated Xcode project files.
- After changing `project.yml`, run `xcodegen generate` before building.
- Do not commit or depend on `build/`, DerivedData output, local result bundles, or local signing/export files.
- Keep diffs scoped; avoid drive-by refactors unless asked.
- Preserve iOS 17+ APIs and existing SwiftUI/SwiftData patterns.
- Keep widget target code extension-safe (`APPLICATION_EXTENSION_API_ONLY = YES`).
- Respect the naming pattern `protocol_` where `protocol` would clash with the Swift keyword.
- Execute builds/tests yourself when possible; do not only suggest commands.

## Codebase Conventions

- SwiftData schema currently includes `CompoundProtocol`, `DoseLog`, and `MediaDocument`.
- Persisted enums are stored in `*Raw` fields with typed computed properties; keep this for migration safety.
- `DoseSchedule` is stored as JSON in `CompoundProtocol.scheduleData`.
- Schedule behavior changes usually require updates to `DoseSchedule`, `CompoundProtocol.nextDoseDate`, `DoseScheduleDayHelper`, protocol create/edit UI, `NotificationService`, `WidgetSnapshotService`, and tests.
- `CompoundProtocol.nextDoseDate(from:)` is the single source of truth for "when is the next dose" and anchors interval/weekly schedules to `startDate` so editing past doses never shifts future ones — preserve that invariant.
- `PharmacokineticsEngine` keeps a thread-safe LRU cache keyed on `(protocolId, logsHash, dateRange, resolution)` and `CompoundProtocol.cachedStableLevelInfo()` adds a count-keyed cache; call `clearStableLevelCache()` when mutating logs in a way that does not change `count` (e.g. timestamp edits).
- Dose logging flow: create `DoseLog`, decrement inventory via `InventoryService`, save context, then optionally send a low-inventory notification.
- Protocol create/edit flow: after save, reminder scheduling should stay consistent with persisted active protocol data.
- Widget data flow: SwiftData changes should result in a fresh app-group snapshot and `WidgetCenter` timeline reload through `WidgetSnapshotService`.
- Inventory math and days-of-supply estimates belong in `InventoryService`.
- Reminder scheduling is centralized in `NotificationService.scheduleAll(protocols:)`, which groups overlapping dose times into shared notifications.
- Protocol ordering is persisted in `CompoundProtocol.sortOrder`; `ProtocolSortMigration.normalizeIfNeeded(in:)` fixes duplicates or all-zero legacy order values.
- Backup restore deletes all existing `DoseLog`, `MediaDocument`, and `CompoundProtocol` records before inserting the imported payload. It also restores profile defaults.
- `MediaDocument` supports images and PDFs; PDF rendering lives in `PDFKitView`.

## UX And Design Guardrails

- Dark-first, glassmorphic cards, high-contrast light text accents.
- Reuse existing components (`GlassCard`, `ProtocolCard`, charts, week dots, etc.) unless a redesign is requested.
- Preserve the established visual language for new app UI.
- Widget UI should remain compact, dark, glanceable, and useful without medical or dosing advice.

## Validation Expectations

- There is a unit-test target: `AscendancyTests`.
- For non-trivial logic: run the relevant unit tests or the full `xcodebuild test` suite.
- For app or widget integration changes: run a successful `xcodebuild` for scheme `Ascendancy` so the embedded widget is compiled and validated.
- For `project.yml` changes: run `xcodegen generate`, then build.
- For HealthKit, notifications, inventory, scheduling, backups, or widgets: do a manual simulator/device smoke test when feasible.
- Widget/app-group behavior requires signed installation on simulator or device for a true persistence smoke test; unsigned builds are compile/embed validation only.

## Sensitive Domain Notes

- This is a health-adjacent tracking app. Avoid medical claims, dosing recommendations, diagnostic language, or promises of health outcomes.
- When adding HealthKit types or permission strings, keep entitlements, Info.plist keys, and localized plist strings aligned.
