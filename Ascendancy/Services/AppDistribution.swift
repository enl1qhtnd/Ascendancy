import Foundation

enum AppDistribution {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var isSideloaded: Bool {
        Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
    }

    static var supportsCloudKitSync: Bool {
        !isRunningTests && !isSideloaded
    }
}
