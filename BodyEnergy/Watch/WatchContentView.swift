import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var viewModel: WatchEnergyViewModel

    var body: some View {
        VStack(spacing: 8) {
            headerRow
            scoreCard
            coachCard
            footerRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.04))
        .task {
            viewModel.onAppear()
        }
    }

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Energy")
                    .font(.headline)
                Text("Updated \(viewModel.updatedTimeText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: viewModel.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var scoreCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.snapshot.energyScore) / 100)
                    .stroke(viewModel.status.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(viewModel.snapshot.energyScore)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(viewModel.status.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(viewModel.status.color)
                }
            }
            .frame(width: 92, height: 92)

            HStack(spacing: 6) {
                statPill(title: "Recovery", value: "\(viewModel.snapshot.recoveryScore)", tint: .blue)
                statPill(title: "Sync", value: syncBadgeText, tint: syncBadgeColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Coach", systemImage: "figure.walk")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text(viewModel.shortRecommendation)
                .font(.footnote)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var footerRow: some View {
        Text(viewModel.connectionNote)
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }

    private var syncBadgeText: String {
        if viewModel.connectionNote.localizedCaseInsensitiveContains("error") {
            return "Issue"
        }
        if viewModel.connectionNote.localizedCaseInsensitiveContains("wait") {
            return "Wait"
        }
        return "Live"
    }

    private var syncBadgeColor: Color {
        if viewModel.connectionNote.localizedCaseInsensitiveContains("error") {
            return .orange
        }
        if viewModel.connectionNote.localizedCaseInsensitiveContains("wait") {
            return .gray
        }
        return .green
    }

    private func statPill(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}

struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView()
            .environmentObject(WatchEnergyViewModel())
    }
}
