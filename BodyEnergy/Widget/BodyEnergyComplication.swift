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
            inlineView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            rectangularView
        }
    }

    private var inlineView: some View {
        Text("电量\(entry.snapshot.energyScore) 压力\(entry.snapshot.stressScore)")
    }

    private var circularView: some View {
        Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
            Image(systemName: "bolt.heart")
        } currentValueLabel: {
            Text("\(entry.snapshot.energyScore)")
        }
        .gaugeStyle(.accessoryCircular)
        .tint(energyTint)
    }

    private var rectangularView: some View {
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

            HStack(spacing: 8) {
                metricLabel(title: "恢复", value: "\(entry.snapshot.recoveryScore)")
                metricLabel(title: "压力", value: "\(entry.snapshot.stressScore)")
            }

            Text(entry.snapshot.stressLevelTitle)
                .font(.caption2)
                .foregroundStyle(stressTint)
                .lineLimit(1)
        }
    }

    private func metricLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
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
}

struct BodyEnergyComplication: Widget {
    let kind = "BodyEnergyComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodyEnergyWidgetProvider()) { entry in
            BodyEnergyComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("身体电量")
        .description("快速查看身体电量、恢复与压力状态。")
        .supportedFamilies([
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

#Preview(as: .accessoryRectangular) {
    BodyEnergyComplication()
} timeline: {
    BodyEnergyWidgetEntry(date: .now, snapshot: .preview)
}
