import Foundation
import SwiftUI

struct FitnessAgeReference: Equatable {
    let chronologicalAge: Int
    let estimatedAge: Double
    let boundary: Int

    static func make(context: FitnessContext?, now: Date = .now, calendar: Calendar = .current) -> Self? {
        guard let context, let value = context.vo2MaxMLKgMin, value.isFinite, value > 0,
              let sampleDate = context.sampledAt, sampleDate <= now,
              now.timeIntervalSince(sampleDate) <= 90 * 24 * 3600,
              let parts = context.dateOfBirth, let birth = calendar.date(from: parts), birth <= now,
              let age = calendar.dateComponents([.year], from: birth, to: now).year, (20...79).contains(age),
              let sex = context.biologicalSex, sex != .other else { return nil }
        // FRIEND 2015 treadmill CPX medians, ages 20–79. Reproduced in
        // Rossi Neto et al. 2019, table 2, doi:10.1371/journal.pone.0209897.
        // Linear interpolation is a descriptive comparison implemented here,
        // not a validated biological-age or disease-risk model.
        let medians = sex == .male ? [48.0, 42.4, 37.8, 32.6, 28.2, 24.4] : [37.6, 30.2, 26.7, 23.4, 20.0, 18.3]
        if value >= medians[0] { return Self(chronologicalAge: age, estimatedAge: 25, boundary: -1) }
        if value <= medians[5] { return Self(chronologicalAge: age, estimatedAge: 75, boundary: 1) }
        for index in 0..<5 where value <= medians[index] && value >= medians[index + 1] {
            let fraction = (medians[index] - value) / (medians[index] - medians[index + 1])
            return Self(chronologicalAge: age, estimatedAge: Double(25 + index * 10) + fraction * 10, boundary: 0)
        }
        return nil
    }
    var title: String {
        switch boundary {
        case -1: return "达到 20–29 岁组中位水平或更高"
        case 1: return "接近 70–79 岁组中位水平或更低"
        default: return "参考心肺适能年龄约 \(Int(estimatedAge.rounded())) 岁"
        }
    }
}

struct FitnessAgeView: View {
    let health: HealthSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("心肺适能年龄参考", systemImage: "figure.run").font(.headline)
            if let reference = FitnessAgeReference.make(context: health.fitnessContext) {
                Text(reference.title).font(.subheadline.weight(.semibold))
                Text("实际年龄 \(reference.chronologicalAge) 岁").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("暂无年龄参考").font(.subheadline)
                Text("需要最近 90 天的 VO₂ max、出生日期与生理性别。参考范围为 20–79 岁；资料不足或不适用时不估算。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let context = health.fitnessContext, let vo2 = context.vo2MaxMLKgMin, vo2.isFinite {
                Text("VO₂ max \(vo2.formatted(.number.precision(.fractionLength(1)))) mL/kg/min").font(.caption).monospacedDigit()
                if let source = context.sourceTitle { Text("来源 \(source)").font(.caption2).foregroundStyle(.secondary) }
            }
            Text("与 FRIEND 2015 美国跑台测试的年龄组中位数比较，组间作线性估计；人群与测量方式存在差异。仅描述心肺适能，不代表生物年龄或医学诊断。")
                .font(.caption).foregroundStyle(.secondary)
            Link("查看参考研究与数据表", destination: URL(string: "https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0209897")!)
                .font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
