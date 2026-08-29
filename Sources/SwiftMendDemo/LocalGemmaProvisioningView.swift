import SwiftUI

struct LocalGemmaProvisioningView: View {
    let state: LocalGemmaModelState
    let selectionFailure: String?
    let chooseModel: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(statusText, systemImage: statusSymbol)
                    .font(.body)
                    .foregroundStyle(statusColor)

                if state.isBusy {
                    ProgressView()
                        .accessibilityLabel(statusText)
                }

                if let selectionFailure {
                    Label(selectionFailure, systemImage: "exclamationmark.triangle.fill")
                        .font(.body)
                        .foregroundStyle(.orange)
                }

                if state != .ready {
                    Button("Import Tuned Model", systemImage: "square.and.arrow.down", action: chooseModel)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(state.isBusy)
                        .accessibilityHint(
                            "Choose the verified SwiftMend litertlm model from Files."
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("On-Device Model")
                .font(.subheadline)
                .bold()
        }
    }

    private var statusText: String {
        switch state {
        case .unavailable:
            "Model not imported · deterministic fallback will be used"
        case .importing:
            "Importing and verifying the selected model…"
        case .loading:
            "Loading tuned on-device Gemma…"
        case .ready:
            "Tuned on-device Gemma ready · approved actions only"
        case .failed(let reason):
            "Model unavailable · \(reason)"
        }
    }

    private var statusSymbol: String {
        switch state {
        case .ready:
            "checkmark.circle.fill"
        case .importing, .loading:
            "hourglass.circle.fill"
        case .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch state {
        case .ready:
            .green
        case .importing, .loading:
            .secondary
        case .unavailable, .failed:
            .orange
        }
    }
}
