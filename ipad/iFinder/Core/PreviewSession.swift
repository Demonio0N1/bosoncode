import SwiftUI
import QuickLook

/// Ciclo de vida del acceso protegido durante una vista previa.
///
/// El patrón es exactamente el que exige el sandbox:
///   1. `begin`  → materializa si hace falta y **abre** el ámbito de seguridad
///   2. la hoja modal muestra `QLPreviewController` mientras el ámbito sigue abierto
///   3. `end`    → se llama desde `onDismiss` y **cierra** el ámbito
///
/// Cerrarlo antes de tiempo es la causa clásica de "no tienes permiso": Quick
/// Look sigue leyendo el archivo mientras la hoja está en pantalla.
@MainActor
final class PreviewSession: ObservableObject {
    /// Archivo listo para previsualizar (dispara la hoja modal).
    @Published var previewURL: URL?
    @Published var preparing = false
    @Published var error: String?

    private var openedScopes: [URL] = []

    /// Prepara el archivo y abre el acceso. No presenta nada por sí solo:
    /// publica `previewURL` y la vista reacciona con `.sheet(item:)`.
    func begin(_ item: FileItem) async {
        preparing = true
        defer { preparing = false }

        let url = item.url
        // 1. permiso: la propia URL y la raíz concedida de la que hereda
        var scopes: [URL] = []
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        if let root = CloudFileHandler.root(containing: url), root != url,
           root.startAccessingSecurityScopedResource() {
            scopes.append(root)
        }
        openedScopes = scopes

        // 2. contenido: si vive en un proveedor externo hay que materializarlo
        do {
            if item.isRemoteOnly || item.isDownloading {
                try await CloudFileHandler.shared.materialize(url)
            }
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                // último recurso: copia legible en la carpeta temporal
                let data = try await CloudFileHandler.shared.read(url)
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)
                try data.write(to: copy, options: .atomic)
                previewURL = copy
                return
            }
            previewURL = url
        } catch {
            self.error = "No se pudo preparar \(item.name): \(error.localizedDescription)"
            end()
        }
    }

    /// Se invoca desde `onDismiss` de la hoja: libera el acceso cuando el
    /// usuario ya cerró la vista previa, ni antes ni después.
    func end() {
        for url in openedScopes { url.stopAccessingSecurityScopedResource() }
        openedScopes = []
        previewURL = nil
    }
}

/// Envoltura de `QLPreviewController`.
///
/// Es el componente que usa la app Archivos: soporta PDF, imágenes, vídeo,
/// audio, texto, iWork, ZIP… sin escribir un visor por tipo. Se envuelve en un
/// `UINavigationController` para conservar la barra con el título, el botón de
/// compartir y el de cerrar.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        let nav = UINavigationController(rootViewController: controller)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        context.coordinator.url = url
        (nav.viewControllers.first as? QLPreviewController)?.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onFinish: onFinish) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var url: URL
        let onFinish: () -> Void

        init(url: URL, onFinish: @escaping () -> Void) {
            self.url = url
            self.onFinish = onFinish
        }

        // MARK: DataSource
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            PreviewItem(url: url)
        }

        // MARK: Delegate
        func previewController(_ controller: QLPreviewController,
                               editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
            .disabled     // solo lectura: evita escrituras sobre proveedores externos
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            onFinish()
        }
    }

    /// `QLPreviewItem` propio: permite dar un título legible en la barra.
    private final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL) {
            self.previewItemURL = url
            self.previewItemTitle = url.lastPathComponent
        }
    }
}
