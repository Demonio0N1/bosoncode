import SwiftUI

@main
struct iFinderApp: App {
    var body: some Scene {
        WindowGroup {
            FinderView()
        }
    }
}

/// Un lugar navegable: una carpeta de un servidor (o del propio iPad).
struct FinderLocation: Identifiable, Hashable {
    enum Kind: Hashable {
        case remote(serverID: UUID, machine: String)
        case local
    }

    let id = UUID()
    let name: String
    let icon: String
    let kind: Kind
    let path: String

    static func == (a: FinderLocation, b: FinderLocation) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Un elemento dentro de una columna.
struct FinderItem: Identifiable, Hashable {
    let name: String
    let dir: Bool
    let size: Int
    let mtime: Double
    let path: String

    var id: String { path }

    var icon: String {
        if dir { return "folder.fill" }
        switch (name as NSString).pathExtension.lowercased() {
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "ipynb": return "book.closed.fill"
        case "pdf": return "doc.richtext.fill"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "photo.fill"
        case "zip", "gz", "tar", "xz", "7z": return "doc.zipper"
        case "md", "txt", "log": return "doc.text.fill"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        case "sh", "bash", "zsh": return "terminal.fill"
        case "mp4", "mov", "mkv": return "film.fill"
        case "mp3", "wav", "flac": return "music.note"
        default: return "doc.fill"
        }
    }

    var iconColor: Color {
        if dir { return .cyan }
        switch (name as NSString).pathExtension.lowercased() {
        case "py", "ipynb": return .yellow
        case "pdf": return .red
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return .purple
        case "sh", "bash", "zsh": return .green
        case "zip", "gz", "tar", "xz", "7z": return .orange
        default: return .secondary
        }
    }

    var sizeLabel: String {
        guard !dir else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var dateLabel: String {
        guard mtime > 0 else { return "" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: mtime))
    }

    /// Grupo para los encabezados de columna, como en Finder.
    var group: String {
        if dir { return "Carpetas" }
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": return "Documentos PDF"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": return "Imágenes"
        case "py", "ipynb", "jl", "c", "cpp", "swift", "js", "ts", "go", "rs": return "Desarrollo"
        case "zip", "gz", "tar", "xz", "7z": return "Comprimidos"
        default: return "Otros"
        }
    }
}
