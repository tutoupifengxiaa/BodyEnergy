import WidgetKit
import SwiftUI

struct BodyEnergyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetMetricsSnapshot
}

struct BodyEnergyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BodyEnergyWidgetEntry {
        BodyEnergyWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (BodyEnergyWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BodyEnergyWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date)
            ?? entry.date.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func currentEntry() -> BodyEnergyWidgetEntry {
        BodyEnergyWidgetEntry(
            date: .now,
            snapshot: WidgetMetricsStore.load() ?? .preview
        )
    }
}

struct BodyEnergyComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BodyEnergyWidgetProvider.Entry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("电量\(entry.snapshot.energyScore)")
        case .accessoryCircular:
            energyGauge
        case .accessoryCorner:
            energyCornerGauge
        case .accessoryRectangular:
            energyRectangular
        default:
            energyRectangular
        }
    }

    private var energyGauge: some View {
        Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
            Image(systemName: "bolt.heart")
        } currentValueLabel: {
            Text("\(entry.snapshot.energyScore)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(energyTint)
    }

    private var energyCornerGauge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.snapshot.energyScore)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(energyTint)

            Text(energyLevelTitle)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .widgetLabel {
            Text(energyLevelTitle)
        }
    }

    private var energyRectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("身体电量", systemImage: "bolt.heart")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(entry.snapshot.energyScore)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(energyTint)
            }

            Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(energyTint)

            HStack(spacing: 8) {
                metricLabel(title: "恢复", value: "\(entry.snapshot.recoveryScore)", tint: .blue)
                metricLabel(title: "状态", value: energyLevelTitle, tint: energyTint)
            }
        }
    }

    private var energyTint: Color {
        switch entry.snapshot.energyScore {
        case 70...100:
            return .green
        case 40..<70:
            return .yellow
        default:
            return .red
        }
    }

    private var energyLevelTitle: String {
        switch entry.snapshot.energyScore {
        case 70...100:
            return "充足"
        case 40..<70:
            return "平稳"
        default:
            return "偏低"
        }
    }
}

struct StressComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BodyEnergyWidgetProvider.Entry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("压力\(entry.snapshot.stressScore)")
        case .accessoryCircular:
            stressGauge
        case .accessoryCorner:
            stressCornerGauge
        case .accessoryRectangular:
            stressRectangular
        default:
            stressRectangular
        }
    }

    private var stressGauge: some View {
        Gauge(value: Double(entry.snapshot.stressScore), in: 0...100) {
            Image(systemName: "brain.head.profile")
        } currentValueLabel: {
            Text("\(entry.snapshot.stressScore)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(stressTint)
    }

    private var stressCornerGauge: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.snapshot.stressScore)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(stressTint)

            Text(stressMoodTitle)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .widgetLabel {
            Text(stressMoodTitle)
        }
    }

    private var stressRectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("压力状态", systemImage: "brain.head.profile")
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(entry.snapshot.stressScore)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(stressTint)
            }

            Gauge(value: Double(entry.snapshot.stressScore), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(stressTint)

            HStack(spacing: 8) {
                metricLabel(title: "评语", value: stressMoodTitle, tint: stressTint)
                metricLabel(title: "等级", value: entry.snapshot.stressLevelTitle, tint: stressTint)
            }
        }
    }

    private var stressTint: Color {
        switch entry.snapshot.stressScore {
        case 0..<30:
            return .green
        case 30..<55:
            return .yellow
        case 55..<75:
            return .orange
        default:
            return .red
        }
    }

    private var stressMoodTitle: String {
        switch entry.snapshot.stressScore {
        case 0..<30:
            return "元气满满"
        case 30..<55:
            return "节奏稳定"
        case 55..<75:
            return "稍微紧绷"
        default:
            return "需要缓缓"
        }
    }
}

private func metricLabel(title: String, value: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

struct BodyEnergyComplication: Widget {
    let kind = "BodyEnergyComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodyEnergyWidgetProvider()) { entry in
            BodyEnergyComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("身体电量")
        .description("表盘复杂功能中显示身体电量。")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular
        ])
    }
}

struct StressComplication: Widget {
    let kind = "StressComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodyEnergyWidgetProvider()) { entry in
            StressComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("压力")
        .description("表盘复杂功能中显示当前压力值。")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular
        ])
    }
}

#Preview(as: .accessoryRectangular) {
    BodyEnergyComplication()
} timeline: {
    BodyEnergyWidgetEntry(date: .now, snapshot: .preview)
}

#Preview(as: .accessoryRectangular) {
    StressComplication()
} timeline: {
    BodyEnergyWidgetEntry(date: .now, snapshot: .preview)
}
