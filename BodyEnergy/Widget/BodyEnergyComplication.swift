import SwiftUI
import WidgetKit

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
            Text("Energy \(entry.snapshot.energyScore)")
        case .accessoryCircular:
            energyGauge
        case .accessoryCorner:
            energyCornerGauge
        case .accessoryRectangular:
            energyRectangular
#if os(iOS)
        case .systemSmall:
            energySystemSmall
        case .systemMedium:
            energySystemMedium
#endif
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
                Label("Body Energy", systemImage: "bolt.heart")
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
                metricLabel(title: "Recovery", value: "\(entry.snapshot.recoveryScore)", tint: .blue)
                metricLabel(title: "State", value: energyLevelTitle, tint: energyTint)
            }
        }
    }

#if os(iOS)
    private var energySystemSmall: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Body Energy", systemImage: "bolt.heart.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(entry.snapshot.energyScore)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(energyTint)

            Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
                EmptyView()
            }
            .tint(energyTint)

            HStack {
                compactMetric(title: "Recovery", value: "\(entry.snapshot.recoveryScore)")
                Spacer()
                compactMetric(title: "State", value: energyLevelTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background.tertiary, for: .widget)
    }

    private var energySystemMedium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Body Energy", systemImage: "bolt.heart.fill")
                    .font(.headline)

                Text(energyLevelTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(energyTint)

                Text("Updated \(entry.date, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                Text("\(entry.snapshot.energyScore)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(energyTint)

                Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
                    EmptyView()
                }
                .frame(width: 120)
                .tint(energyTint)

                HStack(spacing: 12) {
                    compactMetric(title: "Recovery", value: "\(entry.snapshot.recoveryScore)")
                    compactMetric(title: "Stress", value: "\(entry.snapshot.stressScore)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.background.tertiary, for: .widget)
    }
#endif

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
            return "Charged"
        case 40..<70:
            return "Steady"
        default:
            return "Low"
        }
    }
}

struct StressComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BodyEnergyWidgetProvider.Entry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Stress \(entry.snapshot.stressScore)")
        case .accessoryCircular:
            stressGauge
        case .accessoryCorner:
            stressCornerGauge
        case .accessoryRectangular:
            stressRectangular
#if os(iOS)
        case .systemSmall:
            stressSystemSmall
        case .systemMedium:
            stressSystemMedium
#endif
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
                Label("Stress", systemImage: "brain.head.profile")
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
                metricLabel(title: "Mood", value: stressMoodTitle, tint: stressTint)
                metricLabel(title: "Level", value: entry.snapshot.stressLevelTitle, tint: stressTint)
            }
        }
    }

#if os(iOS)
    private var stressSystemSmall: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Stress", systemImage: "brain.head.profile")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(entry.snapshot.stressScore)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(stressTint)

            Gauge(value: Double(entry.snapshot.stressScore), in: 0...100) {
                EmptyView()
            }
            .tint(stressTint)

            HStack {
                compactMetric(title: "Mood", value: stressMoodTitle)
                Spacer()
                compactMetric(title: "Level", value: entry.snapshot.stressLevelTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background.tertiary, for: .widget)
    }

    private var stressSystemMedium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Stress", systemImage: "brain.head.profile")
                    .font(.headline)

                Text(stressMoodTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(stressTint)

                Text("Updated \(entry.date, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                Text("\(entry.snapshot.stressScore)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(stressTint)

                Gauge(value: Double(entry.snapshot.stressScore), in: 0...100) {
                    EmptyView()
                }
                .frame(width: 120)
                .tint(stressTint)

                HStack(spacing: 12) {
                    compactMetric(title: "Energy", value: "\(entry.snapshot.energyScore)")
                    compactMetric(title: "Level", value: entry.snapshot.stressLevelTitle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.background.tertiary, for: .widget)
    }
#endif

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
            return "Full Power"
        case 30..<55:
            return "Stable"
        case 55..<75:
            return "Tense"
        default:
            return "Recover"
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

#if os(iOS)
private func compactMetric(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)

        Text(value)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
    }
}
#endif

private var energySupportedFamilies: [WidgetFamily] {
#if os(iOS)
    return [
        .systemSmall,
        .systemMedium
    ]
#else
    return [
        .accessoryInline,
        .accessoryCircular,
        .accessoryCorner,
        .accessoryRectangular
    ]
#endif
}

struct BodyEnergyComplication: Widget {
    let kind = "BodyEnergyComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodyEnergyWidgetProvider()) { entry in
            BodyEnergyComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Body Energy")
        .description("Shows current body energy and recovery.")
        .supportedFamilies(energySupportedFamilies)
    }
}

struct StressComplication: Widget {
    let kind = "StressComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodyEnergyWidgetProvider()) { entry in
            StressComplicationEntryView(entry: entry)
        }
        .configurationDisplayName("Stress")
        .description("Shows current stress level and mood.")
        .supportedFamilies(energySupportedFamilies)
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

#if os(iOS)
#Preview(as: .systemSmall) {
    BodyEnergyComplication()
} timeline: {
    BodyEnergyWidgetEntry(date: .now, snapshot: .preview)
}

#Preview(as: .systemMedium) {
    StressComplication()
} timeline: {
    BodyEnergyWidgetEntry(date: .now, snapshot: .preview)
}
#endif
