import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    private var energyScore: Int {
        bounded(store.snapshot.energyScore, to: 0...100)
    }

    private var recoveryScore: Int {
        bounded(store.snapshot.recoveryScore, to: 0...100)
    }

    private var energyProgress: CGFloat {
        CGFloat(energyScore) / 100
    }

    private var status: EnergyStatus {
        switch energyScore {
        case 70...100: return .high
        case 40..<70: return .medium
        default: return .low
        }
    }

    private var trendPoints: [Int] {
        [-9, -6, -4, -2, 0, -1, 0].map { bounded(energyScore + $0, to: 0...100) }
    }

    private var weekdayLabels: [String] {
        ["M", "T", "W", "T", "F", "S", "S"]
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    systemStateCard
                    summaryHeaderCard
                    ringCard
                    trendCard
                    metricsGrid
                    recommendationCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Body Energy")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refreshData) {
                        if store.isLoadingHealth {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
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
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func refreshData() {
        Task {
            await store.refreshHealthData()
        }
    }

    @ViewBuilder
    private var systemStateCard: some View {
        if let message = store.healthErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                )
        } else if store.isLoadingHealth {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Syncing HealthKit...")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
    }

    private var summaryHeaderCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.headline)
                Text(store.snapshot.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            quickTag(title: "Energy", value: "\(energyScore)", tint: status.color)
            quickTag(title: "Recovery", value: "\(recoveryScore)", tint: .blue)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func quickTag(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private var ringCard: some View {
        VStack(spacing: 12) {
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
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                    Text(status.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(status.color)
                }
            }
            .frame(height: 220)

            Text("Updated \(store.snapshot.updatedAt, style: .time)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.06), radius: 12, y: 5)
        )
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("7-Day Trend")
                    .font(.headline)
                Spacer()
                Text("\(trendPoints.last ?? energyScore)/100")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(status.color)
            }

            TrendSparkline(values: trendPoints, tint: status.color)
                .frame(height: 110)

            HStack {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var metricsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                metricTile(title: "Recovery", value: "\(recoveryScore)", unit: "/100", tint: .blue, icon: "heart.text.square")
                metricTile(title: "HRV", value: "\(Int(store.health.heartRateVariabilityMS))", unit: "ms", tint: .teal, icon: "waveform.path.ecg")
            }

            HStack(spacing: 10) {
                metricTile(title: "Resting HR", value: "\(Int(store.health.restingHeartRateBPM))", unit: "bpm", tint: .pink, icon: "heart")
                metricTile(title: "Sleep", value: String(format: "%.1f", store.health.sleepHours), unit: "h", tint: .indigo, icon: "bed.double")
            }

            HStack(spacing: 10) {
                metricTile(title: "Heart Rate", value: "\(Int(store.health.heartRateBPM))", unit: "bpm", tint: .red, icon: "bolt.heart")
                metricTile(title: "Activity", value: "\(Int(store.health.activeEnergyKcal))", unit: "kcal", tint: .green, icon: "flame")
            }
        }
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Coach", systemImage: "figure.run")
                .font(.headline)
            Text(store.snapshot.recommendation)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func metricTile(title: String, value: String, unit: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold))
                Text(unit)
                    .font(.footnote)
                    .foregroundColor(.secondary)
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

private struct TrendSparkline: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let maxValue = CGFloat(Swift.max(values.max() ?? 1, 1))
            let minValue = CGFloat(values.min() ?? 0)
            let range = Swift.max(maxValue - minValue, 1)

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.08))

                Path { path in
                    for (index, value) in values.enumerated() {
                        let x = size.width * CGFloat(index) / CGFloat(Swift.max(values.count - 1, 1))
                        let normalized = (CGFloat(value) - minValue) / range
                        let y = size.height * (1 - normalized)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
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

private func bounded(_ value: Int, to range: ClosedRange<Int>) -> Int {
    Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppStore.preview)
    }
}
