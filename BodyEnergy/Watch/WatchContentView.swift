import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var viewModel: WatchEnergyViewModel

    private var statusColor: Color {
        switch viewModel.status {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("Energy")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("\(viewModel.snapshot.energyScore)")
                .font(.system(size: 42, weight: .bold, design: .rounded))

            Text(viewModel.status.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.22), in: Capsule())
                .foregroundStyle(statusColor)

            Text(viewModel.snapshot.recommendation)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundStyle(.secondary)

            Text(viewModel.connectionNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .task {
            viewModel.onAppear()
        }
    }
}

#Preview {
    WatchContentView()
        .environmentObject(WatchEnergyViewModel())
}
