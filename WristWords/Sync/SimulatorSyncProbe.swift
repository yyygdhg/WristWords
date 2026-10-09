#if DEBUG && targetEnvironment(simulator)
import Foundation
import WatchConnectivity

// A bounded CI-only probe. No token, API request or direct Watch data injection.
enum SimulatorSyncProbe {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--wristwords-sync-smoke")
    }

    struct Source: VocabularySource {
        func loadWords() async throws -> [VocabularyWord] {
            Array(MockVocabulary.words.reversed())
        }
    }

    @MainActor
    static func run(sender: PhoneVocabularySender, words: [VocabularyWord]) async {
        guard isEnabled else { return }
        var report: [String: Any] = [:]
        for _ in 0..<30 {
            if let id = sender.send(words: words) {
                report = ["status": "submitted", "transferID": id.uuidString,
                          "wordCount": words.count, "firstWordID": words.first?.id ?? ""]
                break
            }
            if sender.failureReason == "invalid-payload" { break }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
        if report.isEmpty {
            report = ["status": "unavailable", "reason": sender.failureReason]
        }
        if WCSession.isSupported() {
            let session = WCSession.default
            report["activationState"] = session.activationState.rawValue
            if session.activationState == .activated {
                report["isPaired"] = session.isPaired
                report["isWatchAppInstalled"] = session.isWatchAppInstalled
            }
        }
        let file = URL.documentsDirectory.appending(path: "phone-sync-probe.json")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report)
            try data.write(to: file, options: .atomic)
        } catch {
            print("CI phone sync probe could not write its report.")
        }
    }
}
#endif
