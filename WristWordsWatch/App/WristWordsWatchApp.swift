import SwiftUI

@main
struct WristWordsWatchApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("WristWords")
                    .font(.headline)
                Text("Apple Watch App")
            }
            .padding()
        }
    }
}
