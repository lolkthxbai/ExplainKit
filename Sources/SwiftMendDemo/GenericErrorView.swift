import SwiftMend
import SwiftUI

struct GenericErrorView: View {
    let snapshot: ErrorSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Generic error")
                .font(.headline)
            Text(snapshot.message)
            Text("\(snapshot.domain) · \(snapshot.code)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
