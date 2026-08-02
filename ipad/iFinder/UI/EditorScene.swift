import SwiftUI

enum EditorScene {
    static let id = "EditorWindow"
    static let defaultSize = CGSize(width: 900, height: 700)
}

/// Contenido de la ventana de edición.
///
/// Es una **escena** de iPadOS, no una hoja dentro del explorador. La
/// diferencia importa: una hoja secuestra la ventana —no puedes mirar la
/// carpeta mientras editas, ni tener dos archivos abiertos— mientras que una
/// escena aparece por separado en el conmutador de apps y se coloca junto a lo
/// demás. Editar un script suele ir acompañado de mirar otra cosa a la vez.
///
/// El archivo viaja como VALOR de la escena y no como estado del explorador:
/// así cada ventana conserva el suyo aunque en la principal cambies de carpeta
/// o de selección.
struct EditorWindowView: View {
    let url: URL?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let url {
                // Cada tipo abre con lo que de verdad le sirve. Un notebook
                // como texto es una pared de JSON escapado; un .sh renderizado
                // no se puede tocar.
                switch DocumentKind.of(url) {
                case .notebook:
                    NotebookWindowContent(url: url)
                default:
                    CodeEditorView(url: url)
                }
            } else {
                ContentUnavailableView("Sin archivo", systemImage: "doc.text",
                                       description: Text("Abre un archivo desde el explorador."))
            }
        }
        .frame(minWidth: 380, minHeight: 320)
        .background(CascadingWindowSize(base: EditorScene.defaultSize))
        // ⌘W cierra ESTA ventana cuando tiene el foco
        .focusedSceneValue(\.windowClose,
                           WindowCloseAction(id: url?.path ?? "editor") { dismiss() })
    }
}

/// Notebook en su propia ventana: celdas renderizadas y, al lado, la salida.
///
/// Se apoya en `DocumentViewer`, que ya sabe convertir el `.ipynb` en una
/// página con su código resaltado, su Markdown y sus resultados. Lo que añade
/// esta ventana es el marco: título, cierre y la posibilidad de mandarlo a
/// ejecutar al equipo, que es lo que se acaba queriendo hacer con un notebook.
struct NotebookWindowContent: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            DocumentViewer(url: url)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if sending {
                            ProgressView()
                        } else {
                            Button {
                                Task { await run() }
                            } label: {
                                Label("Ejecutar", systemImage: "play.circle")
                            }
                        }
                    }
                }
                .alert("Ejecutar en BosonCode",
                       isPresented: Binding(get: { message != nil },
                                            set: { if !$0 { message = nil } })) {
                    Button("Entendido", role: .cancel) { message = nil }
                } message: {
                    Text(message ?? "")
                }
        }
    }

    /// El iPad no puede ejecutar el notebook —no hay kernel ni JIT—, así que
    /// "ejecutar" significa subirlo al equipo y abrirlo allí.
    private func run() async {
        sending = true
        defer { sending = false }
        do {
            let path = try await RunInBosonCode.run(url)
            message = "Subido a \(path). Se abrirá en BosonCode."
        } catch {
            message = error.localizedDescription
        }
    }
}
