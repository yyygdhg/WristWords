import SwiftUI

@main
@MainActor
struct WristWordsApp: App {
    @StateObject private var watchSession: PhoneVocabularySender

    init() {
        let session = PhoneVocabularySender()
        _watchSession = StateObject(wrappedValue: session)
    }

    var body: some Scene {
        WindowGroup {
            VocabularyListView(watchSender: watchSession)
        }
    }
}
