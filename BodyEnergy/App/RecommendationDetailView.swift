import SwiftUI

struct RecommendationDetailView: View {
    let recommendation: WorkoutRecommendation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                overviewCard
                stepsCard
                cautionCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("训练详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recommendation.title)
                .font(.title3.weight(.semibold))

            Text(recommendation.summary)
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                infoChip(title: "时长", value: recommendation.durationText, tint: .blue)
                infoChip(title: "强度", value: recommendation.intensityText, tint: .orange)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("训练目的")
                .font(.headline)

            Text(recommendation.purposeText)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("建议做法")
                .font(.headline)

            ForEach(Array(recommendation.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor, in: Circle())

                    Text(step)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var cautionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("注意事项")
                .font(.headline)

            Text(recommendation.cautionText)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private func infoChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }
}

struct RecommendationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RecommendationDetailView(recommendation: .preview)
        }
    }
}
