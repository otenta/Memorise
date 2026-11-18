import SwiftUI

/// Placeholder until L8 lands the real sheet.
struct AddToDeckSheet: View {
    let candidate: LyricAddCandidate
    let onSaved: (String) -> Void

    var body: some View {
        Text(candidate.tapped)
    }
}
