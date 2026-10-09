import SwiftUI

@MainActor
struct VocabularyListView: View {
    @StateObject private var model = VocabularyListModel(tokenStore: KeychainTokenStore())
    @ObservedObject var watchSender: PhoneVocabularySender
    @State private var tokenInput = ""

    var body: some View {
        NavigationStack {
            List {
                Section("数据来源") {
                    Text("Data Source: \(model.sourceName)")
                    Text("Loaded: \(model.words.count) words")
                    if model.isLoading { ProgressView("正在加载…") }
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                    Button("使用 Mock 数据") {
                        Task { await model.useMock() }
                    }
                    .disabled(model.isLoading)
                }

                Section("开发阶段 · 墨墨 API") {
                    DisclosureGroup("请求凭证（仅本机）") {
                        SecureField("粘贴原始请求凭证", text: $tokenInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .privacySensitive()
                            .disabled(model.isLoading)
                        Text(model.hasSavedToken ? "已有本机 Keychain 凭证" : "尚未保存凭证")
                            .font(.caption)
                        Button("保存到 Keychain") {
                            if model.saveToken(tokenInput) { tokenInput = "" }
                        }
                        .disabled(model.isLoading)
                        Button("删除已保存凭证", role: .destructive) {
                            model.deleteToken()
                            tokenInput = ""
                        }
                        .disabled(model.isLoading)
                        if let message = model.credentialMessage {
                            Text(message).font(.caption)
                        }
                    }
                    Button("Test Connection / 加载真实数据") {
                        Task { await model.testConnection(tokenInput: tokenInput) }
                    }
                    .disabled(model.isLoading)
                }

                Section("Apple Watch") {
                    Button("Send to Apple Watch") {
                        watchSender.send(words: model.words)
                    }
                    .disabled(model.isLoading || model.errorMessage != nil)
                    Text(watchSender.statusMessage).font(.caption)
                }

                WatchResultsView(model: watchSender.resultsModel)

                Section("单词") {
                    ForEach(model.words) { word in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(word.term)
                                .font(.headline)
                            Text(word.phonetic.isEmpty ? "官方 API 未提供音标" : word.phonetic)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(word.meaning.isEmpty ? "暂无个人释义" : word.meaning)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("WristWords")
            .task {
                #if DEBUG && targetEnvironment(simulator)
                if SimulatorSyncProbe.isEnabled {
                    await model.start(source: SimulatorSyncProbe.Source())
                    await SimulatorSyncProbe.run(sender: watchSender, words: model.words)
                } else {
                    await model.start()
                }
                #else
                await model.start()
                #endif
            }
        }
    }
}
