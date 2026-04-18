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
        case .accessoryCorner:
            cornerView
        case .accessoryRectangular:
            rectangularView
        default:
            rectangularView
        }
    }

    private var inlineView: some View {
        Text("电\(entry.snapshot.energyScore) 压\(entry.snapshot.stressScore)")
    }

    private var circularView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 8)

            Circle()
                .trim(from: 0, to: CGFloat(entry.snapshot.energyScore) / 100)
                .stroke(energyTint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text("\(entry.snapshot.energyScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                HStack(spacing: 2) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 6, weight: .semibold))

                    Text("\(entry.snapshot.stressScore)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(stressTint)
            }
        }
    }

    private var cornerView: some View {
        Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
            Image(systemName: "bolt.heart")
        } currentValueLabel: {
            Text("\(entry.snapshot.energyScore)")
        }
        .gaugeStyle(.accessoryCorner)
        .tint(energyTint)
        .widgetLabel {
            Text("压\(entry.snapshot.stressScore)")
                .foregroundStyle(stressTint)
        }
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
                metricLabel(title: "电量", value: "\(entry.snapshot.energyScore)", tint: energyTint)
                metricLabel(title: "压力", value: "\(entry.snapshot.stressScore)", tint: stressTint)
            }

            Text(entry.snapshot.stressLevelTitle)
                .font(.caption2)
                .foregroundStyle(stressTint)
                .lineLimit(1)
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
        .configurationDisplayName("身体电量与压力")
        .description("快速查看身体电量和压力值。")
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
