import Foundation
import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    private var energyScore: Int {
        store.snapshot.energyScore.clamped(to: 0...100)
    }

    private var recoveryScore: Int {
        store.snapshot.recoveryScore.clamped(to: 0...100)
    }

    private var energyProgress: Double {
        Double(energyScore) / 100
    }

    private var status: EnergyStatus {
        switch energyScore {
        case 70...100: return .high
        case 40..<70: return .medium
        default: return .low
        }
    }

    private var trendPoints: [TrendPoint] {
        let offsets = [-9, -6, -4, -2, 0, -1, 0]
        let calendar = Calendar.current
        return offsets.enumerated().compactMap { index, delta in
            guard let day = calendar.date(byAdding: .day, value: -(6 - index), to: .now) else { return nil }
            return TrendPoint(day: day, energy: (energyScore + delta).clamped(to: 0...100))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    systemStateCard
                    ringCard
                    trendCard
                    metricsGrid
                    recommendationCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Body Energy")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshHealthData() }
                    } label: {
                        if store.isLoadingHealth {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Refresh Health Data")
                }
            }
            .refreshable {
                await store.refreshHealthData()
            }
        }
    }

    @ViewBuilder
    private var systemStateCard: some View {
        if let message = store.healthErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
        } else if store.isLoadingHealth {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Syncing HealthKit...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
    }

    private var ringCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                Circle()
                    .trim(from: 0, to: energyProgress)
                    .stroke(
                        AngularGradient(
                            colors: [Color.green, Color.yellow, Color.orange, Color.red],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: energyProgress)

                VStack(spacing: 4) {
                    Text("\(energyScore)")
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                    Text(status.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(status.color)
                }
            }
            .frame(height: 220)

            Text("Updated \(store.snapshot.updatedAt, style: .time)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        )
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("7-Day Trend")
                .font(.headline)

            Chart(trendPoints) { point in
                AreaMark(
                    x: .value("Day", point.day),
                    y: .value("Energy", point.energy)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [status.color.opacity(0.25), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Energy", point.energy)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(status.color)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100])
            }
            .frame(height: 170)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
    }

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metricTile(title: "Recovery", value: "\(recoveryScore)", unit: "/100", tint: .blue)
                metricTile(title: "HRV", value: "\(Int(store.health.heartRateVariabilityMS))", unit: "ms", tint: .teal)
            }

            HStack(spacing: 10) {
                metricTile(title: "Resting HR", value: "\(Int(store.health.restingHeartRateBPM))", unit: "bpm", tint: .pink)
                metricTile(title: "Sleep", value: String(format: "%.1f", store.health.sleepHours), unit: "h", tint: .indigo)
            }

            HStack(spacing: 10) {
                metricTile(title: "Heart Rate", value: "\(Int(store.health.heartRateBPM))", unit: "bpm", tint: .red)
                metricTile(title: "Activity", value: "\(Int(store.health.activeEnergyKcal))", unit: "kcal", tint: .green)
            }
        }
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Coach", systemImage: "figure.run")
                .font(.headline)
            Text(store.snapshot.recommendation)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.background)
        )
    }

    @ViewBuilder
    private func metricTile(title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold))
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

private struct TrendPoint: Identifiable {
    let day: Date
    let energy: Int

    var id: Date { day }
}

private enum EnergyStatus {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: return "High"
        case .medium: return "Moderate"
        case .low: return "Low"
        }
    }

    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .red
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore.preview)
}

