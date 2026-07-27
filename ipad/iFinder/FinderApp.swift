import SwiftUI

@main
struct iFinderApp: App {
    var body: some Scene {
        // Ventana principal del explorador
        WindowGroup {
            FinderWindow()
        }

        // Ventana de vista previa: el archivo viaja como VALOR de escena, así
        // cada ventana conserva el suyo y no se sobreescribe cuando la ventana
        // principal cambia de selección.
        WindowGroup("Vista previa", id: PreviewScene.id, for: URL.self) { $url in
            PreviewWindowView(url: url)
        }
        .defaultSize(width: PreviewScene.defaultSize.width,
                     height: PreviewScene.defaultSize.height)
    }
}
