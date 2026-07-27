import SwiftUI

enum FinderScene {
    static let id = "FinderWindow"
}

@main
struct iFinderApp: App {
    var body: some Scene {
        // Ventana principal del explorador. Lleva id para que "Nueva ventana"
        // pueda pedir otra igual desde el menú.
        WindowGroup(id: FinderScene.id) {
            FinderWindow()
                // copias de Quick Look de sesiones anteriores: ya no hacen falta
                .task { TempCleaner.purgeOldCopies() }
        }
        // La barra de menús superior. Los comandos no ven el estado de
        // ninguna ventana: lo reciben por foco (ver FinderActions).
        .commands { FinderCommands() }

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
