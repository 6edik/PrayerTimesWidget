import SwiftUI

/// "Meine Notizen" — every personal note the user has ever created, past
/// and future, sorted chronologically, shown as compact (2-line) previews.
/// Reachable from the calendar's toolbar. Tapping an entry hands its date
/// to `onSelectEntry` instead of editing inline — the caller (
/// `IslamicCalendarView`) dismisses this sheet and opens that day's full
/// day sheet instead, where the note appears alongside that day's prayer
/// times and events and can be edited.
struct PersonalCalendarOverviewView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PersonalCalendarViewModel
    var onSelectEntry: (PersonalCalendarEntry) -> Void = { _ in }

    @State private var entryPendingDeletion: PersonalCalendarEntry?
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.allEntriesSortedByDate.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Color("AppBackground").ignoresSafeArea())
            .navigationTitle("Meine Notizen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Schließen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Notiz hinzufügen")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                PersonalCalendarEntryFormView(viewModel: viewModel, mode: .create(date: Date()))
            }
            .alert(
                "Notiz löschen?",
                isPresented: Binding(
                    get: { entryPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { entryPendingDeletion = nil }
                    }
                ),
                presenting: entryPendingDeletion
            ) { entry in
                Button("Löschen", role: .destructive) {
                    viewModel.delete(entry)
                    entryPendingDeletion = nil
                }
                Button("Abbrechen", role: .cancel) {
                    entryPendingDeletion = nil
                }
            } message: { _ in
                Text("Diese Notiz wird dauerhaft gelöscht.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("Keine persönlichen Notizen")
                .font(.headline)

            Text("Tippe auf einen Kalendertag oder auf das Plus oben, um deine erste Notiz zu erstellen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(viewModel.allEntriesSortedByDate) { entry in
                Button {
                    onSelectEntry(entry)
                } label: {
                    PersonalCalendarEntryRow(entry: entry, showsDate: true, isCompact: true)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        entryPendingDeletion = entry
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    .accessibilityLabel("Notiz löschen")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
