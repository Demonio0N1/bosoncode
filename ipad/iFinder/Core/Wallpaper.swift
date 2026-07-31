import SwiftUI

/// Fondo de pantalla **de ZeroSpin**.
///
/// Importante y conviene que quede escrito: una app de iPadOS **no puede
/// cambiar el fondo del sistema**. No hay API pública para ello —ni para la
/// pantalla de inicio ni para la de bloqueo— y el aislamiento entre apps lo
/// impide por diseño; solo Ajustes y Fotos pueden. Así que esto cambia el fondo
/// de la ventana de archivos, que es el que sí nos pertenece.
///
/// La imagen se copia al contenedor de la app en lugar de guardar una
/// referencia al original. Dos motivos: el original puede vivir en una nube y
/// no estar descargado cuando toque dibujarlo, y borrarlo o desmontar su
/// carpeta dejaría la ventana sin fondo sin que se entienda por qué.
@MainActor
final class Wallpaper: ObservableObject {
    static let shared = Wallpaper()

    @Published private(set) var image: UIImage?
    /// Cuánto se ve. Un fondo a plena intensidad compite con los archivos, que
    /// son lo que se viene a leer.
    @AppStorage("finderWallpaperOpacity") var opacity: Double = 0.35

    private var stored: URL {
        SystemLocation.documentsFolder.appendingPathComponent(".fondo", isDirectory: false)
    }

    private init() {
        if let data = try? Data(contentsOf: stored) {
            image = UIImage(data: data)
        }
    }

    /// Toma la imagen elegida y la deja como fondo.
    ///
    /// Se reescala antes de guardarla: una foto de 12 megapíxeles ocupa memoria
    /// para siempre y no aporta nada detrás de una lista de archivos.
    func set(from source: URL) async throws {
        let data = try await CloudFileHandler.shared.read(source)
        guard let original = UIImage(data: data) else {
            throw WallpaperError.notAnImage(source.lastPathComponent)
        }
        let reduced = Self.downscaled(original, maxSide: 2048)
        guard let jpeg = reduced.jpegData(compressionQuality: 0.85) else {
            throw WallpaperError.notAnImage(source.lastPathComponent)
        }
        try jpeg.write(to: stored, options: .atomic)
        image = reduced
    }

    func clear() {
        try? FileManager.default.removeItem(at: stored)
        image = nil
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum WallpaperError: LocalizedError {
    case notAnImage(String)

    var errorDescription: String? {
        switch self {
        case .notAnImage(let name):
            return "No pude leer \(name) como imagen."
        }
    }
}

/// Capa de fondo de la ventana de archivos.
struct WallpaperBackground: View {
    @ObservedObject private var wallpaper = Wallpaper.shared

    var body: some View {
        if let image = wallpaper.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .opacity(wallpaper.opacity)
                // el fondo no debe interceptar nada: los toques en el hueco son
                // del menú de la carpeta
                .allowsHitTesting(false)
                .clipped()
                .ignoresSafeArea()
        }
    }
}
