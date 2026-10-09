import SwiftUI

@main
@MainActor
struct WristWordsWatchApp: App {
    @StateObject private var model: WatchStudyModel
    private let receiver: WatchVocabularyReceiver

    init() {
        let model = WatchStudyModel()
        _model = StateObject(wrappedValue: model)
        receiver = WatchVocabularyReceiver(model: model)
    }

    var body: some Scene {
        WindowGroup {
            ReviewView(model: model)
        }
    }
}
