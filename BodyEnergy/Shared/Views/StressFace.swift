import SwiftUI

// Match the existing pressure score bands; HRV remains a separate value in ms.
enum StressMood: Int, CaseIterable {
    case relaxed, calm, tense, stressed

    init(score: Int) {
        switch score {
        case ..<30: self = .relaxed
        case 30..<55: self = .calm
        case 55..<75: self = .tense
        default: self = .stressed
        }
    }

    var title: String {
        switch self {
        case .relaxed: return "放松"
        case .calm: return "平静"
        case .tense: return "紧绷"
        case .stressed: return "压力较高"
        }
    }

    var color: Color {
        switch self {
        case .relaxed: return Color(red: 1.00, green: 0.82, blue: 0.32)
        case .calm: return Color(red: 1.00, green: 0.89, blue: 0.55)
        case .tense: return Color(red: 1.00, green: 0.69, blue: 0.43)
        case .stressed: return Color(red: 0.98, green: 0.52, blue: 0.49)
        }
    }

    var capybaraImageName: String {
        switch self {
        case .relaxed: return "CapybaraLuluRelaxed"
        case .calm: return "CapybaraLuluCalm"
        case .tense: return "CapybaraLuluTense"
        case .stressed: return "CapybaraLuluStressed"
        }
    }
}

struct StressFace: View {
    let score: Int
    private var mood: StressMood { StressMood(score: score) }

    var body: some View {
        Image(mood.capybaraImageName)
            .resizable()
            .scaledToFit()
            .aspectRatio(1, contentMode: .fit)
    }
}
