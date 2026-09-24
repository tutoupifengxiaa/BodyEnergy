import SwiftUI
import WidgetKit

struct BodyEnergyWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetMetricsSnapshot
}

struct BodyEnergyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BodyEnergyWidgetEntry {
        BodyEnergyWidgetEntry(date: .now, snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (BodyEnergyWidgetEntry) -> Void) {
        completion(context.isPreview ? BodyEnergyWidgetEntry(date: .now, snapshot: .empty) : currentEntry())
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
            snapshot: WidgetMetricsStore.load() ?? .empty
        )
    }
}

struct BodyEnergyComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: BodyEnergyWidgetProvider.Entry

    var body: some View {
        Group {
            if entry.snapshot.hasData { dataContent } else {
                Text("暂无数据").font(.caption).foregroundStyle(.secondary)
            }
        }
        .widgetURL(URL(string: "bodyenergy://energy"))
        .containerBackground(.background.tertiary, for: .widget)
    }

    @ViewBuilder
    private var dataContent: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.snapshot.isStale ? "上次电量" : "电量") \(entry.snapshot.energyScore)")
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
            VStack(spacing: 0) {
                Text("\(entry.snapshot.energyScore)")
                if entry.snapshot.isStale { Text("上次").font(.system(size: 8)) }
            }
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Label("身体电量", systemImage: "bolt.heart")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text("\(entry.snapshot.energyScore)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(energyTint)
            }

            Gauge(value: Double(entry.snapshot.energyScore), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(energyTint)

            Text(energyLevelTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(energyTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

#if os(iOS)
    private var energySystemSmall: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("身体电量", systemImage: "bolt.heart.fill")
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
                compactMetric(title: "恢复", value: "\(entry.snapshot.recoveryScore)")
                Spacer()
                compactMetric(title: "状态", value: energyLevelTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background.tertiary, for: .widget)
    }

    private var energySystemMedium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("身体电量", systemImage: "bolt.heart.fill")
                    .font(.headline)

                Text(energyLevelTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(energyTint)

                Text("采样于 \(entry.snapshot.updatedAt, style: .time)")
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
                    compactMetric(title: "恢复", value: "\(entry.snapshot.recoveryScore)")
                    compactMetric(title: "压力", value: "\(entry.snapshot.stressScore)")
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
        if entry.snapshot.isSampleData { return "示例数据" }
        if entry.snapshot.isStale { return "上次记录" }
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
        content
            .widgetURL(URL(string: "bodyenergy://stress"))
    }

    @ViewBuilder
    private var content: some View {
        if entry.snapshot.hasStressData {
            dataContent
        } else {
            emptyContent
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch family {
        case .accessoryInline:
            Text("压力暂无数据")
        case .accessoryCorner:
            Image("CapybaraLuluCalm")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .widgetLabel { Text("压力暂无数据") }
        default:
            HStack(spacing: 6) {
                Image("CapybaraLuluCalm")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                Text("压力暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var dataContent: some View {
        switch family {
        case .accessoryInline:
            Text("\(entry.snapshot.isStressStale ? "上次压力" : "压力") \(entry.snapshot.stressScore)")
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

    private var stressCornerGauge: some View {
        HStack(spacing: 2) {
            StressFace(score: entry.snapshot.stressScore)
                .frame(width: 24, height: 24)

            Text("\(entry.snapshot.stressScore)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(stressTint)
        }
        .widgetLabel {
            Text(stressMoodTitle)
        }
    }

    private var stressRectangular: some View {
        HStack(spacing: 8) {
            StressFace(score: entry.snapshot.stressScore)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("压力")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(entry.snapshot.stressScore)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(stressTint)
                Text(stressMoodTitle)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if entry.snapshot.hasData {
                VStack(alignment: .leading, spacing: 4) {
                    Text("身体电量")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(entry.snapshot.energyScore)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

#if os(iOS)
    private var stressSystemSmall: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StressFace(score: entry.snapshot.stressScore).frame(width: 34, height: 34)
                Text("压力")
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(entry.snapshot.stressScore)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(stressTint)

            Gauge(value: Double(entry.snapshot.stressScore), in: 0...100) {
                EmptyView()
            }
            .tint(stressTint)

            VStack(alignment: .leading, spacing: 2) {
                compactMetric(title: "评语", value: stressMoodTitle)
                compactMetric(title: "等级", value: entry.snapshot.stressLevelTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background.tertiary, for: .widget)
    }

    private var stressSystemMedium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("压力", systemImage: "brain.head.profile")
                    .font(.headline)

                Text(stressMoodTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(stressTint)

                Text("采样于 \(entry.snapshot.stressUpdatedAt, style: .time)")
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
                    compactMetric(title: "电量", value: entry.snapshot.hasData ? "\(entry.snapshot.energyScore)" : "—")
                    compactMetric(title: "等级", value: entry.snapshot.stressLevelTitle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.background.tertiary, for: .widget)
    }
#endif

    private var stressTint: Color { StressMood(score: entry.snapshot.stressScore).color }

    private var stressMoodTitle: String {
        if entry.snapshot.isSampleData { return "示例数据" }
        let title = StressMood(score: entry.snapshot.stressScore).title
        return entry.snapshot.isStressStale ? "上次 · " + title : title
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
        .configurationDisplayName("身体电量")
        .description("显示当前身体电量与恢复状态。")
        .supportedFamilies(energySupportedFamilies)
    }
}

struct StressComplication: Widget {
    let kind = "StressComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodyEnergyWidgetProvider()) { entry in
#if os(watchOS)
            StressComplicationEntryView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
#else
            StressComplicationEntryView(entry: entry)
                .containerBackground(.background.tertiary, for: .widget)
#endif
        }
        .configurationDisplayName("压力")
        .description("显示当前压力值与状态评语。")
        .supportedFamilies(stressSupportedFamilies)
    }
}

private var stressSupportedFamilies: [WidgetFamily] {
#if os(iOS)
    return energySupportedFamilies
#else
    return [.accessoryInline, .accessoryCorner, .accessoryRectangular]
#endif
}

#if os(watchOS)
private struct StressCircularEntryView: View {
    let entry: BodyEnergyWidgetProvider.Entry

    var body: some View {
        VStack(spacing: 0) {
            Text("压力")
                .font(.system(size: 10, weight: .medium))
            Text(entry.snapshot.hasStressData ? "\(entry.snapshot.stressScore)" : "--")
                .font(.system(size: 24, weight: .bold, design: .rounded))
        }
        .widgetURL(URL(string: "bodyenergy://stress"))
    }
}

struct StressCircularComplication: Widget {
    let kind = "StressCircularComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BodyEnergyWidgetProvider()) { entry in
            StressCircularEntryView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("压力（圆形）")
        .description("显示当前压力分数。")
        .supportedFamilies([.accessoryCircular])
    }
}
#endif

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
