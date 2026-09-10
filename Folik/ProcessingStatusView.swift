import SwiftUI
import UIKit

struct ProcessingStatusView: View {
    let status: String
    let cancel: () -> Void
    @State private var cancellationRequested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(cancellationRequested ? "Stopping…" : status)
                .accessibilityIdentifier("processing.status")
            if cancellationRequested {
                Text("Finishing the current step. No new copy will be saved.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button(cancellationRequested ? "Cancellation requested" : "Cancel Processing") {
                cancellationRequested = true
                cancel()
                UIAccessibility.post(notification: .announcement, argument: "Cancellation requested. Finishing the current step.")
            }
            .frame(minHeight: 44)
            .disabled(cancellationRequested)
            .accessibilityIdentifier("processing.cancel")
        }
    }
}

struct ProcessingErrorView: View {
    let message: String
    @AccessibilityFocusState private var focused: Bool
    var body: some View {
        Text(message).foregroundStyle(.red)
            .accessibilityFocused($focused)
            .task { await Task.yield(); focused = true }
    }
}
