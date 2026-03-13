import WidgetKit
import SwiftUI

@main
struct AscendancyWidget: Widget {
    let kind: String = "AscendancyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AscendancyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Dose")
        .description("See your next scheduled compound dose at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
