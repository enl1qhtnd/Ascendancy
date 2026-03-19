import SwiftUI

extension Text {
    /// Looks up `string` in the app string catalog (English keys).
    init(catalogKey string: String) {
        self.init(LocalizedStringKey(string))
    }
}

extension LocalizedStringKey {
    /// Wraps a runtime string as a localization catalog key.
    static func catalog(_ string: String) -> LocalizedStringKey {
        LocalizedStringKey(string)
    }
}
