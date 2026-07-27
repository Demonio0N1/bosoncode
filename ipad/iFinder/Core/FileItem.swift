import SwiftUI
import UniformTypeIdentifiers

/// Modelo de un elemento del sistema de archivos.
///
/// Es un *value type* inmutable: la vista nunca toca el disco a través de él.
/// Todo lo caro (tamaño, tipo, fecha) se resuelve una sola vez al listar, con
/// `URLResourceValues`, para no hacer E/S durante el dibujado.
struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date?
    let type: UTType?
    /// Solo en la nube (OneDrive, Drive, iCloud…) mientras no se descargue
    let isRemoteOnly: Bool
    let isDownloading: Bool

    var id: String { url.path }

    init(url: URL, values: URLResourceValues?) {
        self.url = url
        self.name = values?.name ?? url.lastPathComponent
        self.isDirectory = values?.isDirectory ?? false
        self.size = Int64(values?.fileSize ?? 0)
        self.modified = values?.contentModificationDate
        self.type = values?.contentType
        self.isDownloading = values?.ubiquitousItemIsDownloading ?? false
        if values?.isUbiquitousItem == true {
            self.isRemoteOnly = values?.ubiquitousItemDownloadingStatus == .notDownloaded
        } else {
            self.isRemoteOnly = false
        }
    }

    /// Constructor para orígenes remotos, que no tienen URL local real.
    init(remotePath: String, name: String, isDirectory: Bool, size: Int64, modified: Date?) {
        self.url = URL(fileURLWithPath: remotePath)
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.type = UTType(filenameExtension: (name as NSString).pathExtension)
        self.isRemoteOnly = false
        self.isDownloading = false
    }

    // MARK: - Presentación

    var icon: String {
        if isDirectory { return "folder.fill" }
        guard let type else { return "doc.fill" }
        if type.conforms(to: .image) { return "photo.fill" }
        if type.conforms(to: .movie) { return "film.fill" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext.fill" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) {
            return "chevron.left.forwardslash.chevron.right"
        }
        if type.conforms(to: .text) { return "doc.text.fill" }
        return "doc.fill"
    }

    var iconColor: Color {
        if isDirectory { return Color(red: 0.35, green: 0.62, blue: 0.95) }  // azul Finder
        guard let type else { return .secondary }
        if type.conforms(to: .image) { return .purple }
        if type.conforms(to: .movie) { return .pink }
        if type.conforms(to: .audio) { return .orange }
        if type.conforms(to: .pdf) { return .red }
        if type.conforms(to: .archive) { return .orange }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .green }
        return .secondary
    }

    var sizeLabel: String {
        isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Distintivo de nube, como la nubecita del Finder
    var cloudBadge: String? {
        if isDownloading { return "arrow.down.circle.dotted" }
        if isRemoteOnly { return "icloud.and.arrow.down" }
        return nil
    }

    var dateLabel: String {
        guard let modified else { return "" }
        return Self.dateFormatter.string(from: modified)
    }

    var kindLabel: String {
        if isDirectory { return "Carpeta" }
        return type?.localizedDescription ?? "Documento"
    }

    /// Agrupación de la vista de columnas (como los encabezados del Finder).
    var group: String {
        if isDirectory { return "Carpetas" }
        guard let type else { return "Otros" }
        if type.conforms(to: .image) { return "Imágenes" }
        if type.conforms(to: .movie) || type.conforms(to: .audio) { return "Multimedia" }
        if type.conforms(to: .pdf) { return "Documentos PDF" }
        if type.conforms(to: .archive) { return "Comprimidos" }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return "Desarrollo" }
        return "Otros"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

// MARK: - Transferable

/// Permite arrastrar elementos dentro de la app y hacia otras (Archivos,
/// Correo, Split View). Para archivos locales se exporta el propio fichero;
/// para remotos, `FileTransfer` descarga bajo demanda.
extension FileItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .item) { item in
            SentTransferredFile(item.url)
        }
        ProxyRepresentation(exporting: \.name)
    }
}
