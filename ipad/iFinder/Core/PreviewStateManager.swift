import SwiftUI

/// Estado compartido entre la ventana del explorador y la de vista previa.
///
/// Las escenas de iPadOS no comparten estado por sí solas, pero **sí comparten
/// proceso**: un objeto único observable es la forma limpia de que la ventana
/// principal sepa si la previa está abierta (para alternar con la barra
/// espaciadora) y de pasarle el archivo sin serializarlo en la URL de escena.
@MainActor
final class PreviewStateManager: ObservableObject {
    static let shared = PreviewStateManager()

    /// Archivo que debe mostrar la ventana de vista previa.
    @Published var item: FileItem?
    /// ¿Hay una ventana de previa en pantalla? La actualiza la propia ventana.
    @Published var isOpen = false
    /// Preparando el archivo (descarga de la nube o copia temporal).
    @Published var preparing = false

    private init() {}

    var url: URL? { item?.url }

    func request(_ item: FileItem) {
        self.item = item
    }

    func closed() {
        isOpen = false
    }
}
