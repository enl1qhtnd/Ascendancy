import XCTest
@testable import Ascendancy

final class AppGroupSupportTests: XCTestCase {
    func testAppGroupIdentifier_matchesWidgetShared() {
        XCTAssertEqual(AppGroupSupport.appGroupIdentifier, AscendancyWidgetShared.appGroupIdentifier)
    }

    func testSharedContainerAvailability_canBeEvaluatedWithoutCrashing() {
        _ = AppGroupSupport.isSharedContainerAvailable
    }

    func testPlistDictionaryFromMobileProvision_extractsEntitlements() throws {
        let plist = try XCTUnwrap(
            AppGroupSupport.plistDictionary(fromMobileProvisionAt: Self.sampleProvisioningProfileURL)
        )
        let entitlements = try XCTUnwrap(plist["Entitlements"] as? [String: Any])
        let groups = try XCTUnwrap(entitlements["com.apple.security.application-groups"] as? [String])

        XCTAssertEqual(groups, ["group.de.enl1qhtnd.asce"])
    }

    func testAppGroupIdentifiersFromEntitlementsFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("entitlements")
        try Self.sampleEntitlementsPlistData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            AppGroupSupport.appGroupIdentifiers(fromEntitlementsAt: url),
            ["group.de.enl1qhtnd.asce"]
        )
    }

    func testDiagnostics_fallsBackWhenNoSignedProfileIsPresent() {
        let diagnostics = AppGroupSupport.diagnostics()

        XCTAssertEqual(diagnostics.identifier, AppGroupSupport.fallbackAppGroupIdentifier)
        XCTAssertEqual(diagnostics.source, .fallback)
    }

    func testCandidateAppGroupIdentifiers_readsHostProvisioningProfileForAppExtension() throws {
        let fixture = try Self.makeHostAppFixture(
            appGroupIdentifiers: ["group.18639f3d763f9fac.5"],
            includeLocalWidgetProvision: false
        )
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let candidates = AppGroupSupport.appGroupIdentifiers(
            fromProvisioningProfileAt: AppGroupSupport.hostEmbeddedProvisioningProfileURL(from: fixture.widgetBundle)
        )

        XCTAssertEqual(candidates, ["group.18639f3d763f9fac.5"])
    }

    private static var sampleEntitlementsPlistData: Data {
        Data(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            	<key>com.apple.security.application-groups</key>
            	<array>
            		<string>group.de.enl1qhtnd.asce</string>
            	</array>
            </dict>
            </plist>
            """.utf8
        )
    }

    private static var sampleProvisioningProfileURL: URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let profileURL = directory.appendingPathComponent("embedded.mobileprovision")
        let profile = Data("prefix".utf8) + sampleProvisioningPlistData + Data("suffix".utf8)
        try! profile.write(to: profileURL)
        return profileURL
    }

    private static let sampleProvisioningPlistData = Data(
        """
        <plist version="1.0"><dict><key>Entitlements</key><dict>\
        <key>com.apple.security.application-groups</key>\
        <array><string>group.de.enl1qhtnd.asce</string></array>\
        </dict></dict></plist>
        """.utf8
    )

    private static func makeHostAppFixture(
        appGroupIdentifiers: [String],
        includeLocalWidgetProvision: Bool
    ) throws -> (rootURL: URL, widgetBundle: Bundle) {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = rootURL.appendingPathComponent("Ascendancy.app", isDirectory: true)
        let pluginsURL = appURL.appendingPathComponent("PlugIns", isDirectory: true)
        let widgetURL = pluginsURL.appendingPathComponent("AscendancyWidget.appex", isDirectory: true)

        try FileManager.default.createDirectory(at: widgetURL, withIntermediateDirectories: true)

        let groupsXML = appGroupIdentifiers.map { "<string>\($0)</string>" }.joined()
        let provisionData = Data(
            """
            prefix<plist version="1.0"><dict><key>Entitlements</key><dict>\
            <key>com.apple.security.application-groups</key>\
            <array>\(groupsXML)</array>\
            </dict></dict></plist>suffix
            """.utf8
        )

        try provisionData.write(to: appURL.appendingPathComponent("embedded.mobileprovision"))
        if includeLocalWidgetProvision {
            try provisionData.write(to: widgetURL.appendingPathComponent("embedded.mobileprovision"))
        }

        let widgetBundle = Bundle(url: widgetURL)!
        return (rootURL, widgetBundle)
    }
}

private extension AppGroupSupport {
    static func hostEmbeddedProvisioningProfileURL(from bundle: Bundle) -> URL? {
        guard let hostAppBundleURL = hostAppBundleURL(from: bundle) else { return nil }
        let profileURL = hostAppBundleURL.appendingPathComponent("embedded.mobileprovision", isDirectory: false)
        return FileManager.default.fileExists(atPath: profileURL.path) ? profileURL : nil
    }
}
