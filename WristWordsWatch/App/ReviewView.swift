import SwiftUI

@MainActor
struct ReviewView: View {
    @ObservedObject var model: WatchStudyModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Source: \(model.sourceName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let message = model.syncMessage {
                    Text(message).font(.caption)
                }
                if let word = model.session.currentWord {
                    Text("\(model.session.completedCount + 1) / \(model.session.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("第 \(model.session.completedCount + 1) 个，共 \(model.session.totalCount) 个单词")

                    VStack(spacing: 6) {
                        Text(word.term)
                            .font(.title3.weight(.semibold))
                            .minimumScaleFactor(0.7)
                            .lineLimit(2)
                        Text(word.phonetic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(word.meaning)
                            .font(.body)
                    }
                    .multilineTextAlignment(.center)

                    ForEach(StudyRating.allCases) { rating in
                        Button(rating.rawValue) {
                            model.rate(rating)
                        }
                        .accessibilityLabel(rating.rawValue)
                    }
                } else if model.session.totalCount == 0 {
                    Text("暂无单词，请从 iPhone 同步。")
                        .multilineTextAlignment(.center)
                } else {
                    Text("Review Complete")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("\(model.session.completedCount) / \(model.session.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Restart") {
                        model.restart()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        // Return to the top for each word and after Restart on small screens.
        .id("\(model.receivedTransferID?.uuidString ?? "mock")-\(model.session.completedCount)")
    }
}
