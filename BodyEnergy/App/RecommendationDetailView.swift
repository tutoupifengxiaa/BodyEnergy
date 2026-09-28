import SwiftUI

struct RecommendationDetailView: View {
    let recommendation: WorkoutRecommendation
    @ObservedObject var activities: ActivityStore
    @ObservedObject var preferences: PreferencesStore
    @State private var isShowingSession = false
    @State private var isShowingPreferences = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                purposeCard
                stepsCard
                cautionCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("训练详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("训练偏好") { isShowingPreferences = true }
            }
        }
        .sheet(isPresented: $isShowingSession) {
            ActivitySessionView(store: activities, recommendation: recommendation)
        }
        .sheet(isPresented: $isShowingPreferences) {
            TrainingPreferencesView(store: preferences)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recommendation.title)
                .font(.title3.weight(.semibold))

            Text(recommendation.summary)
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                infoChip(title: "时长", value: recommendation.durationText, tint: Color.accentColor)
                infoChip(title: "强度", value: recommendation.intensityText, tint: Color.accentColor)
            }

            Button {
                isShowingSession = true
            } label: {
                Label(activities.active == nil ? "开始计时" : "继续当前计时", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var purposeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("训练目的")
                .font(.headline)

            Text(recommendation.purposeText)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("训练步骤")
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
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
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
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
            RecommendationDetailView(recommendation: .preview, activities: ActivityStore(),
                                     preferences: PreferencesStore())
        }
    }
}
