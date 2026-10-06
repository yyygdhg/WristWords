import SwiftUI

struct ReviewView: View {
    @State private var session = StudySession(words: MockVocabulary.words)

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let word = session.currentWord {
                    Text("\(session.completedCount + 1) / \(session.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("第 \(session.completedCount + 1) 个，共 \(session.totalCount) 个单词")

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
                            session.rateCurrentWord(rating)
                        }
                        .accessibilityLabel(rating.rawValue)
                    }
                } else {
                    Text("Review Complete")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("\(session.completedCount) / \(session.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Restart") {
                        session.restart()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        // Return to the top for each word and after Restart on small screens.
        .id(session.completedCount)
    }
}
