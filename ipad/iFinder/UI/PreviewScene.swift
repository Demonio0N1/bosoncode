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
    /// URL propia de ESTA ventana: llega como valor de escena y no cambia
    /// aunque la ventana principal seleccione otro archivo.
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    SafeQuickLookView(url: url) { dismiss() }
                } else {
                    ContentUnavailableView("Sin archivo",
                                           systemImage: "doc",
                                           description: Text("Selecciona un archivo y pulsa la barra espaciadora."))
                }
            }
            .navigationTitle(url?.lastPathComponent ?? "Vista previa")
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
                if let url {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
        // el registro solo sirve para saber si hay ventanas abiertas (para
        // alternar con la barra espaciadora); NO decide qué muestra cada una
        .onAppear { if let url { PreviewStateManager.shared.opened(url) } }
        .onDisappear { if let url { PreviewStateManager.shared.closed(url) } }
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
    let url: URL
    var onClose: () -> Void = {}

    @State private var ready: URL?
    @State private var failure: String?
    @State private var preparing = true

    var body: some View {
        Group {
            if let ready {
                QuickLookPreview(url: ready, onClose: onClose)
                    .ignoresSafeArea(edges: .bottom)
            } else if preparing {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Preparando \(url.lastPathComponent)…")
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
        .task(id: url) { await prepare() }
    }

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        failure = nil

        // --- Plan A: acceso directo con el ámbito abierto ---
        var scopes: [URL] = []
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        if let root = CloudFileHandler.root(containing: url), root != url,
           root.startAccessingSecurityScopedResource() {
            scopes.append(root)
        }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }

        do {
            if case .remote = CloudFileHandler.state(of: url) {
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
    var onClose: () -> Void = {}

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = KeyAwareQLPreviewController()
        controller.onClose = onClose          // espacio / esc / ⌘W cierran
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        (controller as? KeyAwareQLPreviewController)?.onClose = onClose
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

/// `QLPreviewController` que responde al teclado.
///
/// UIKit se queda el foco cuando la vista previa aparece, así que el
/// `.onKeyPress` de SwiftUI ya no llega. La vía fiable es declarar
/// `UIKeyCommand` en el propio controlador: espacio (como macOS), Esc y ⌘W.
final class KeyAwareQLPreviewController: QLPreviewController {
    var onClose: () -> Void = {}

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        let close = [
            UIKeyCommand(input: " ", modifierFlags: [], action: #selector(closePreview)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closePreview)),
            UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(closePreview)),
        ]
        close.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return close
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()   // sin esto los UIKeyCommand no se consultan
    }

    @objc private func closePreview() { onClose() }
}
