import Foundation

enum AppGroupSupport {
    static let fallbackAppGroupIdentifier = "group.de.enl1qhtnd.asce"
    static let widgetSnapshotFileName = "AscendancyWidgetSnapshot.json"

    enum ResolutionSource: Equatable {
        case signedProvisioningProfile
        case fallback
    }

    struct Diagnostics: Equatable {
        var identifier: String
        var candidateIdentifiers: [String]
        var source: ResolutionSource
        var sharedContainerURL: URL?
        var isWritable: Bool
        var snapshotExists: Bool
        var snapshotGeneratedAt: Date?

        var isSharedContainerAvailable: Bool {
            sharedContainerURL != nil && isWritable
        }
    }

    static var appGroupIdentifier: String {
        diagnostics().identifier
    }

    static var isSharedContainerAvailable: Bool {
        diagnostics().isSharedContainerAvailable
    }

    static func diagnostics() -> Diagnostics {
        let candidates = candidateAppGroupIdentifiers()
        let identifier = preferredAppGroupIdentifier(from: candidates)
        let containerURL = sharedContainerURL(for: identifier)
        let isWritable = containerURL.map(canWriteToContainer(at:)) ?? false
        let snapshot = loadWidgetSnapshot(from: candidates)

        return Diagnostics(
            identifier: identifier,
            candidateIdentifiers: candidates,
            source: candidates.first == fallbackAppGroupIdentifier && candidates.count == 1
                ? .fallback
                : .signedProvisioningProfile,
            sharedContainerURL: containerURL,
            isWritable: isWritable,
            snapshotExists: snapshot != nil,
            snapshotGeneratedAt: snapshot?.generatedAt
        )
    }

    static func candidateAppGroupIdentifiers() -> [String] {
        var candidates: [String] = []
        var seen = Set<String>()

        func appendUnique(_ identifiers: [String]) {
            for identifier in identifiers where seen.insert(identifier).inserted {
                candidates.append(identifier)
            }
        }

        appendUnique(appGroupIdentifiers(fromProvisioningProfileAt: localEmbeddedProvisioningProfileURL) ?? [])
        appendUnique(appGroupIdentifiers(fromProvisioningProfileAt: hostEmbeddedProvisioningProfileURL) ?? [])
        appendUnique([fallbackAppGroupIdentifier])

        return candidates
    }

    static func writableAppGroupIdentifiers() -> [String] {
        candidateAppGroupIdentifiers().filter { identifier in
            guard let containerURL = sharedContainerURL(for: identifier) else { return false }
            return canWriteToContainer(at: containerURL)
        }
    }

    static func sharedContainerURL(for identifier: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func widgetSnapshotURL(for identifier: String) -> URL? {
        sharedContainerURL(for: identifier)?
            .appendingPathComponent(widgetSnapshotFileName, isDirectory: false)
    }

    static func loadWidgetSnapshot(from identifiers: [String] = candidateAppGroupIdentifiers()) -> AscendancyWidgetSnapshot? {
        for identifier in identifiers {
            guard
                let snapshotURL = widgetSnapshotURL(for: identifier),
                FileManager.default.fileExists(atPath: snapshotURL.path),
                let data = try? Data(contentsOf: snapshotURL)
            else {
                continue
            }

            if let snapshot = try? JSONDecoder().decode(AscendancyWidgetSnapshot.self, from: data) {
                return snapshot
            }
        }

        return nil
    }

    static func saveWidgetSnapshot(_ snapshot: AscendancyWidgetSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        let writableIdentifiers = writableAppGroupIdentifiers()

        guard !writableIdentifiers.isEmpty else {
            throw WidgetSnapshotError.missingAppGroupContainer(preferredAppGroupIdentifier(from: candidateAppGroupIdentifiers()))
        }

        for identifier in writableIdentifiers {
            guard let snapshotURL = widgetSnapshotURL(for: identifier) else { continue }
            try data.write(to: snapshotURL, options: [.atomic])
        }
    }

    static func hostAppBundleURL(from bundle: Bundle = .main) -> URL? {
        if bundle.bundleURL.pathExtension == "appex" {
            let appURL = bundle.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            return appURL.pathExtension == "app" ? appURL : nil
        }

        if bundle.bundleURL.pathExtension == "app" {
            return bundle.bundleURL
        }

        return nil
    }

    static var localEmbeddedProvisioningProfileURL: URL? {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
    }

    static var hostEmbeddedProvisioningProfileURL: URL? {
        guard let hostAppBundleURL = hostAppBundleURL() else { return nil }
        let profileURL = hostAppBundleURL.appendingPathComponent("embedded.mobileprovision", isDirectory: false)
        return FileManager.default.fileExists(atPath: profileURL.path) ? profileURL : nil
    }

    static func appGroupIdentifiers(fromProvisioningProfileAt url: URL?) -> [String]? {
        guard let plist = plistDictionary(fromMobileProvisionAt: url) else { return nil }
        return appGroupIdentifiers(fromEntitlementsDictionary: plist["Entitlements"] as? [String: Any])
    }

    static func appGroupIdentifiers(fromEntitlementsAt url: URL?) -> [String]? {
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }

        return appGroupIdentifiers(fromEntitlementsDictionary: plist)
    }

    static func plistDictionary(fromMobileProvisionAt url: URL?) -> [String: Any]? {
        guard
            let url,
            let data = try? Data(contentsOf: url),
            let start = data.range(of: Data("<plist".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else {
            return nil
        }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        return try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
    }

    private static func preferredAppGroupIdentifier(from candidates: [String]) -> String {
        for identifier in candidates {
            guard let containerURL = sharedContainerURL(for: identifier), canWriteToContainer(at: containerURL) else {
                continue
            }
            return identifier
        }

        return candidates.first ?? fallbackAppGroupIdentifier
    }

    private static func appGroupIdentifiers(fromEntitlementsDictionary entitlements: [String: Any]?) -> [String]? {
        guard let groups = entitlements?["com.apple.security.application-groups"] as? [String], !groups.isEmpty else {
            return nil
        }
        return groups
    }

    private static func canWriteToContainer(at containerURL: URL) -> Bool {
        let probeURL = containerURL.appendingPathComponent(".widgetContainerProbe", isDirectory: false)
        do {
            try Data().write(to: probeURL, options: [.atomic])
            try FileManager.default.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }
}
