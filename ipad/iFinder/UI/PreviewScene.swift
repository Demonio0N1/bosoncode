import SwiftUI
import QuickLook

/// Identificador de la escena de vista previa. Se usa en el `WindowGroup` del
/// `App` y en cada `openWindow(id:value:)`, así que vive en un solo sitio.
enum PreviewScene {
    static let id = "com.garyguaman.ifinder.PreviewWindow"
    /// Tamaño inicial, parecido al de la ventana de Quick Look en macOS.
    static let defaultSize = CGSize(width: 820, height: 620)
}

/// Contenido de la ventana de vista previa.
///
/// Recibe solo una URL: una ventana nueva es otra escena, y no puede heredar
/// estado del navegador. Antes de mostrar el archivo se asegura de que sea
/// legible — puede venir de un proveedor externo (iCloud, OneDrive, SMB) y
/// no estar materializado todavía.
struct PreviewWindowView: View {
    let url: URL?

    @State private var ready: URL?
    @State private var failure: String?
    @State private var preparing = true

    var body: some View {
        Group {
            if let ready {
                QuickLookView(url: ready) {}
                    .ignoresSafeArea()
            } else if preparing {
                VStack(spacing: 14) {
                    ProgressView()
                    Text(url.map { "Preparando \($0.lastPathComponent)…" } ?? "Preparando…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text("No se puede previsualizar")
                        .font(.headline)
                    Text(failure ?? "Archivo no disponible")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .task(id: url) { await prepare() }
    }

    /// Deja el archivo listo para Quick Look:
    /// 1. Si es local y legible, se usa tal cual.
    /// 2. Si vive en un proveedor externo, se materializa (descarga bajo demanda).
    /// 3. Si el ámbito de seguridad no alcanza a esta escena, se copia a la
    ///    carpeta temporal de la app, que siempre es legible.
    private func prepare() async {
        guard let url else { preparing = false; return }
        preparing = true
        defer { preparing = false }

        if FileManager.default.isReadableFile(atPath: url.path) {
            ready = url
            return
        }
        do {
            try await CloudFileHandler.shared.materialize(url)
            if FileManager.default.isReadableFile(atPath: url.path) {
                ready = url
                return
            }
            // Respaldo: copia local (una URL cruza escenas, el permiso no siempre)
            let data = try await CloudFileHandler.shared.read(url)
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(url.lastPathComponent)
            try data.write(to: copy, options: .atomic)
            ready = copy
        } catch {
            failure = error.localizedDescription
        }
    }
}
