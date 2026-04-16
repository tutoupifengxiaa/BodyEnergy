import Foundation
import Combine
import SwiftUI

@MainActor
final class WatchEnergyViewModel: ObservableObject {
    @Published private(set) var snapshot: EnergySnapshot = .preview
    @Published private(set) var workoutRecommendation: WorkoutRecommendation = .preview
    @Published private(set) var status: WatchEnergyStatus = .medium
    @Published private(set) var syncBadge: WatchSyncBadge = .waiting
    @Published private(set) var connectionNote: String = "等待 iPhone 同步"

    private let manager: WatchConnectivityManager
    private var cancellables: Set<AnyCancellable> = []

    convenience init() {
        self.init(manager: WatchConnectivityManager())
    }

    init(manager: WatchConnectivityManager) {
        self.manager = manager

        manager.$snapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                self.snapshot = snapshot
                self.status = WatchEnergyStatus(score: snapshot.energyScore)
            }
            .store(in: &cancellables)

        manager.$workoutRecommendation
            .assign(to: &$workoutRecommendation)

        manager.$syncBadge
            .assign(to: &$syncBadge)

        manager.$connectionNote
            .assign(to: &$connectionNote)
    }

    func onAppear() {
        manager.activate()
        manager.requestLatest()
    }

    func refresh() {
        manager.requestLatest()
    }

    var shortRecommendation: String {
        workoutRecommendation.summary.shortened(limit: 72)
    }

    var recommendationTitle: String {
        workoutRecommendation.title
    }

    var recommendationDurationText: String {
        workoutRecommendation.durationText
    }

    var recommendationIntensityText: String {
        workoutRecommendation.intensityText
    }

    var compactSteps: [String] {
        Array(workoutRecommendation.steps.prefix(2))
    }

    var updatedTimeText: String {
        snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
    }
}

enum WatchEnergyStatus {
    case high
    case medium
    case low

    init(score: Int) {
        switch score {
        case 70...100: self = .high
        case 40..<70: self = .medium
        default: self = .low
        }
    }

    var title: String {
        switch self {
        case .high: return "高"
        case .medium: return "中"
        case .low: return "低"
        }
    }

    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        }
    }
}

private extension String {
    func shortened(limit: Int) -> String {
        guard count > limit else { return self }
        let cutoffIndex = index(startIndex, offsetBy: max(limit - 3, 0))
        return String(self[..<cutoffIndex]) + "..."
    }
}
