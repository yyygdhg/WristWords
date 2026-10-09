import SwiftUI

@MainActor
struct WatchResultsView: View {
    @ObservedObject var model: WatchResultsModel

    var body: some View {
        Section("Watch Results") {
            Text("Received Results: \(model.results.count)")
            Text(model.statusMessage).font(.caption)
            ForEach(model.snapshotIDs, id: \.self) { transferID in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snapshot \(transferID.uuidString.prefix(8))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.results(for: transferID)) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(model.term(for: event))
                                Spacer()
                                Text(event.result.rating.rawValue)
                            }
                            Text("Session \(event.sessionID.uuidString.prefix(8)) · #\(event.sequence)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
