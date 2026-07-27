import SwiftUI
import QuickLook

/// Identificador de la escena de vista previa: se usa al declarar el
/// `WindowGroup` y en cada `openWindow` / `dismissWindow`.
enum PreviewScene {
    static let id = "PreviewWindow"
    static let defaultSize = CGSize(width: 820, height: 640)
}

// MARK: - Ventana de vista previa

/// Contenido de la ventana: Quick Look dentro de un `NavigationStack` con
/// barra y botón de cerrar, para que el usuario **siempre** tenga salida por
/// interfaz además de la barra espaciadora.
struct PreviewWindowView: View {
    @ObservedObject private var state = PreviewStateManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let item = state.item {
                    SafeQuickLookView(item: item)
                } else {
                    ContentUnavailableView("Sin archivo",
                                           systemImage: "doc",
                                           description: Text("Selecciona un archivo y pulsa la barra espaciadora."))
                }
            }
            .navigationTitle(state.item?.name ?? "Vista previa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Cerrar", systemImage: "xmark")
                    }
                    .keyboardShortcut("w", modifiers: .command)   // ⌘W como en macOS
                }
                if let url = state.item?.url {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
        .onAppear { state.isOpen = true }
        .onDisappear { state.closed() }
    }
}

// MARK: - Quick Look a prueba de sandbox

/// Prepara el archivo antes de entregárselo a Quick Look.
///
/// Quick Look renderiza en un **proceso aparte**, que no hereda el ámbito de
/// seguridad de esta app. Por eso hay un plan A y un plan B:
///   A. abrir el ámbito (archivo + raíz concedida) y comprobar que se lee
///   B. si no, copiar a `temporaryDirectory` — dentro del contenedor de la
///      app, siempre legible por cualquier proceso del sistema
struct SafeQuickLookView: View {
    let item: FileItem

    @State private var ready: URL?
    @State private var failure: String?
    @State private var preparing = true

    var body: some View {
        Group {
            if let ready {
                QuickLookPreview(url: ready)
                    .ignoresSafeArea(edges: .bottom)
            } else if preparing {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Preparando \(item.name)…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No se puede previsualizar",
                                       systemImage: "eye.slash",
                                       description: Text(failure ?? "Archivo no disponible"))
            }
        }
        .task(id: item.id) { await prepare() }
    }

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        failure = nil

        let url = item.url

        // --- Plan A: acceso directo con el ámbito abierto ---
        var scopes: [URL] = []
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        if let root = CloudFileHandler.root(containing: url), root != url,
           root.startAccessingSecurityScopedResource() {
            scopes.append(root)
        }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }

        do {
            if item.isRemoteOnly || item.isDownloading {
                try await CloudFileHandler.shared.materialize(url)
            }
            // --- Plan B: copia temporal para el proceso externo de Quick Look ---
            let data = try await CloudFileHandler.shared.read(url)
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
            try data.write(to: copy, options: .atomic)
            ready = copy
        } catch {
            // si la copia falla pero el archivo es legible tal cual, se usa
            if FileManager.default.isReadableFile(atPath: url.path) {
                ready = url
            } else {
                failure = error.localizedDescription
            }
        }
    }
}

// MARK: - Envoltura de QLPreviewController

/// El mismo componente que usa la app Archivos: soporta PDF, imágenes, vídeo,
/// audio, texto, iWork y ZIP sin escribir un visor por tipo.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onFinish: onFinish) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var url: URL
        let onFinish: () -> Void

        init(url: URL, onFinish: @escaping () -> Void) {
            self.url = url
            self.onFinish = onFinish
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            PreviewItem(url: url)
        }

        /// Solo lectura: evita que Quick Look intente escribir sobre un
        /// proveedor externo (y sobre la copia temporal, que se descarta).
        func previewController(_ controller: QLPreviewController,
                               editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
            .disabled
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) { onFinish() }
    }

    /// Permite mostrar un título legible en la barra en vez del nombre del
    /// archivo temporal.
    private final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL) {
            self.previewItemURL = url
            // se recorta el prefijo "preview-xxxxxx-" de la copia temporal
            let name = url.lastPathComponent
            if name.hasPrefix("preview-"), let range = name.range(of: "-", range: name.index(name.startIndex, offsetBy: 8)..<name.endIndex) {
                self.previewItemTitle = String(name[range.upperBound...])
            } else {
                self.previewItemTitle = name
            }
        }
    }
}
