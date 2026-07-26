import SwiftUI
import QuickLook

/// Envoltura identificable para presentar la vista rápida.
struct QLItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Vista rápida del sistema (la misma que abre la barra espaciadora en macOS).
struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onClose: onClose) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let url: URL
        let onClose: () -> Void

        init(url: URL, onClose: @escaping () -> Void) {
            self.url = url
            self.onClose = onClose
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
        func previewControllerDidDismiss(_ controller: QLPreviewController) { onClose() }
    }
}

/// Panel derecho con la información y la miniatura del archivo elegido,
/// como la columna de vista previa del Finder.
struct PreviewPanel: View {
    let item: FinderItem?
    let previewURL: URL?
    let loading: Bool
    var onOpen: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let item {
                thumbnail(item)
                Text(item.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                VStack(spacing: 4) {
                    if !item.dir {
                        info("Tamaño", item.sizeLabel)
                    }
                    info("Tipo", item.dir ? "Carpeta" : tipoLegible(item.name))
                    if !item.dateLabel.isEmpty { info("Modificado", item.dateLabel) }
                }
                .padding(.top, 4)

                if !item.dir {
                    VStack(spacing: 8) {
                        Button(action: onOpen) {
                            Label(loading ? "Abriendo…" : "Abrir (espacio)",
                                  systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(loading)
                        Button(action: onSave) {
                            Label("Guardar en el iPad", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                Spacer()
            } else {
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Selecciona un archivo")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func thumbnail(_ item: FinderItem) -> some View {
        if let previewURL, let image = UIImage(contentsOfFile: previewURL.path) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: item.icon)
                .font(.system(size: 64))
                .foregroundStyle(item.iconColor)
                .frame(height: 120)
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }

    private func tipoLegible(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        let nombres = [
            "py": "Python", "ipynb": "Jupyter Notebook", "pdf": "PDF",
            "png": "Imagen PNG", "jpg": "Imagen JPEG", "jpeg": "Imagen JPEG",
            "md": "Markdown", "txt": "Texto", "json": "JSON", "sh": "Script",
            "zip": "Archivo ZIP", "mp4": "Vídeo", "csv": "CSV", "jl": "Julia",
        ]
        return nombres[ext] ?? (ext.isEmpty ? "Documento" : ext.uppercased())
    }
}
