import SwiftUI
import QuickLookThumbnailing

/// Generador de miniaturas reales.
///
/// Es lo que hace la app Archivos: no dibuja un icono genérico, sino que pide
/// al sistema una representación del contenido (primera página del PDF,
/// fotograma del vídeo, la imagen…). Funciona con cualquier tipo que Quick
/// Look sepa leer.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private var cache: [String: UIImage] = [:]
    private var inFlight: Set<String> = []

    /// Miniatura para un archivo. Devuelve nil si el sistema no sabe generarla
    /// (entonces la vista cae al icono por tipo).
    func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> UIImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        // El generador necesita leer el archivo: hay que abrir el ámbito de
        // seguridad y el de su raíz concedida mientras dura la generación.
        let scoped = url.startAccessingSecurityScopedResource()
        let root = CloudFileHandler.root(containing: url)
        let rootScoped = (root != nil && root != url)
            ? root!.startAccessingSecurityScopedResource() : false
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            if rootScoped, let root { root.stopAccessingSecurityScopedResource() }
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all)   // icono, miniatura o vista en baja
        guard let rep = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request) else { return nil }
        cache[key] = rep.uiImage
        if cache.count > 300 { cache.removeAll() }   // tope sencillo de memoria
        return rep.uiImage
    }
}

/// Vista de miniatura con reserva: muestra el icono por tipo hasta que el
/// sistema entrega la representación real.
struct ThumbnailView: View {
    let item: FileItem
    var size: CGSize = CGSize(width: 44, height: 44)

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: item.icon)
                    .font(.system(size: min(size.width, size.height) * 0.62))
                    .foregroundStyle(item.iconColor)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: item.id) {
            // las carpetas y lo que aún vive en la nube no tienen miniatura
            guard !item.isDirectory, !item.isRemoteOnly else { return }
            image = await ThumbnailService.shared.thumbnail(
                for: item.url, size: size, scale: UIScreen.main.scale)
        }
    }
}
