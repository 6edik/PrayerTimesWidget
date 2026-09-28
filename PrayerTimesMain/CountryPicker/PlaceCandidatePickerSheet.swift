import SwiftUI

/// Disambiguation sheet shown whenever a typed city name resolves to more
/// than one place within the selected country. The caller must pick one —
/// there is no "take the first result" shortcut, matching the requirement
/// that an ambiguous free-text place is never silently guessed.
struct PlaceCandidatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [GeocodedPlaceCandidate]
    let onSelect: (GeocodedPlaceCandidate) -> Void

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.displayName)
                            .foregroundStyle(.primary)

                        Text(LocationDisplayFormatter.coordinateText(for: candidate.coordinate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("AppBackground").ignoresSafeArea())
            .navigationTitle("Ort auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
