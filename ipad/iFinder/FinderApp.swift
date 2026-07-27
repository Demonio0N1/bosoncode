import SwiftUI

@main
struct iFinderApp: App {
    var body: some Scene {
        // Ventana principal del explorador
        WindowGroup {
            FinderWindow()
        }

        // Ventana de vista previa: escena independiente que recibe una URL.
        // La barra espaciadora abre una de estas, como el Quick Look de macOS.
        WindowGroup(id: PreviewScene.id, for: URL.self) { $url in
            PreviewWindowView(url: url)
        }
        .defaultSize(width: PreviewScene.defaultSize.width,
                     height: PreviewScene.defaultSize.height)
    }
}
