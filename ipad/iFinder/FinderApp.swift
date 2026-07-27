import SwiftUI

@main
struct iFinderApp: App {
    var body: some Scene {
        // Ventana principal del explorador
        WindowGroup {
            FinderWindow()
        }

        // Ventana de vista previa. Sin valor asociado: el archivo viaja por
        // PreviewStateManager, que ambas escenas comparten (mismo proceso).
        WindowGroup("Vista previa", id: PreviewScene.id) {
            PreviewWindowView()
        }
        .defaultSize(width: PreviewScene.defaultSize.width,
                     height: PreviewScene.defaultSize.height)
    }
}
