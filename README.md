# Ascendancy 🧬

Ascendancy is a comprehensive iOS health and compound tracking application built with SwiftUI and SwiftData. Designed to help users manage and monitor their active health protocols, it provides advanced pharmacokinetics level tracking, HealthKit integration, and media management, all wrapped in a premium, glassmorphic dark-mode UI.

## Features

- **Protocol Management**: Track active compounds, log your doses, and see exactly when your next dose is due.
- **Pharmacokinetics Engine**: Visualise your active compound levels over time using the built-in active levels graphing engine.
- **HealthKit Integration**: Automatically syncs and graphs your bodyweight directly from Apple Health to track your progress alongside your protocols.
- **Media Library**: Store related protocol photos, progress pictures, and PDF bloodwork documents within the app for a complete health overview.
- **Home Screen Widgets**: See your next scheduled dose at a glance right from your home screen.

## Technologies Used

- **SwiftUI**: For building the modern, responsive user interface.
- **SwiftData**: For local, persistent storage of protocols, logs, and media documents.
- **HealthKit**: For reading body weight trends.
- **WidgetKit**: For the "Next Dose" home screen widget.
- **PDFKit**: For rendering uploaded medical documents.
- **XcodeGen**: Used for generating the `.xcodeproj` programmatically to avoid git merge conflicts.

## Getting Started

### Prerequisites
- macOS with Xcode 15 or later
- iOS 17.0+ Simulator or Device
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed (`brew install xcodegen`)

### Running the App

1. Clone this repository.
2. In the root directory, generate the Xcode project:
   ```bash
   xcodegen generate
   ```
3. Open `Ascendancy.xcodeproj` in Xcode.
4. Select your simulator or device and hit **Run** (`Cmd + R`).

## 

Made with ❤️ by @enl1qhtnd
