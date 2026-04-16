import Foundation
import Combine
import SwiftUI

@MainActor
final class WatchEnergyViewModel: ObservableObject {
    @Published private(set) var snapshot: EnergySnapshot = .preview
    @Published private(set) var status: WatchEnergyStatus = .medium
    @Published private(set) var connectionNote: String = "Waiting for iPhone sync"

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
        let text = snapshot.recommendation
        guard text.count > 72 else { return text }
        let cutoffIndex = text.index(text.startIndex, offsetBy: 69)
        return String(text[..<cutoffIndex]) + "..."
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
        case .high: return "High"
        case .medium: return "Moderate"
        case .low: return "Low"
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
