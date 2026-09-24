import WidgetKit
import SwiftUI

@main
struct BodyEnergyWidgetBundle: WidgetBundle {
    var body: some Widget {
        BodyEnergyComplication()
        StressComplication()
#if os(watchOS)
        StressCircularComplication()
#endif
    }
}
