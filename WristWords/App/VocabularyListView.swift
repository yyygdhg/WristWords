import SwiftUI

struct VocabularyListView: View {
    private let words = MockVocabulary.words

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("本地测试单词：\(words.count) 个")
                }

                Section("Mock 单词") {
                    ForEach(words) { word in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(word.term)
                                .font(.headline)
                            Text(word.phonetic)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(word.meaning)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("WristWords")
        }
    }
}
