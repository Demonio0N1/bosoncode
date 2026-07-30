import SwiftUI

/// Contenido de la papelera, con restaurar y vaciar.
struct TrashView: View {
    @ObservedObject var model: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [Trash.Entry] = []
    @State private var loading = true
    @State private var confirmEmpty = false

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if entries.isEmpty {
                    ContentUnavailableView("La papelera está vacía", systemImage: "trash",
                                           description: Text("Lo que elimines aparecerá aquí y podrás devolverlo a su sitio."))
                } else {
                    List {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .navigationTitle("Papelera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Vaciar", role: .destructive) { confirmEmpty = true }
                        .disabled(entries.isEmpty)
                }
            }
            .confirmationDialog("¿Vaciar la papelera?", isPresented: $confirmEmpty,
                                titleVisibility: .visible) {
                Button("Vaciar (\(entries.count))", role: .destructive) {
                    Task { try? await Trash.shared.empty(); await load() }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Esto sí borra para siempre.")
            }
            .task { await load() }
        }
    }

    private func row(_ entry: Trash.Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).lineLimit(1)
                // De dónde venía: sin esto, dos archivos con el mismo nombre
                // son indistinguibles justo cuando hay que elegir cuál volver.
                Text(entry.originalFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Text(entry.deletedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { try? await Trash.shared.restore(entry); await load(); await model.reload() }
            } label: {
                Label("Restaurar", systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { try? await Trash.shared.purge(entry); await load() }
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                Task { try? await Trash.shared.restore(entry); await load(); await model.reload() }
            } label: {
                Label("Restaurar en su carpeta", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                Task { try? await Trash.shared.purge(entry); await load() }
            } label: {
                Label("Borrar definitivamente", systemImage: "trash")
            }
        }
    }

    private func load() async {
        loading = true
        entries = (try? await Trash.shared.contents()) ?? []
        await model.refreshTrashCount()
        loading = false
    }
}
