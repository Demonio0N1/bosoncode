import SwiftUI
import PencilKit

/// Editor de imagen: dibujar encima con PencilKit y guardar el resultado.
///
/// El trazo NO se funde con la foto hasta que se guarda. Mientras editas, el
/// dibujo vive en su propia capa sobre la imagen, así que se puede deshacer,
/// borrar y cambiar de herramienta sin haber tocado el archivo. Fundir en cada
/// trazo destruiría el original a la primera pincelada.
struct ImageEditorView: View {
    let url: URL
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var canvas = PKCanvasView()
    @State private var loadError: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    editor(image)
                } else if let loadError {
                    ContentUnavailableView("No se pudo abrir", systemImage: "photo",
                                           description: Text(loadError))
                } else {
                    ProgressView("Abriendo…")
                }
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .principal) {
                    // Deshacer y borrar viven aquí y no en el selector de
                    // herramientas: el de PencilKit los ofrece solo con lápiz
                    // conectado, y esto también se usa con el dedo.
                    HStack(spacing: 18) {
                        Button {
                            canvas.undoManager?.undo()
                        } label: { Image(systemName: "arrow.uturn.backward") }
                        Button {
                            canvas.drawing = PKDrawing()
                        } label: { Image(systemName: "trash") }
                    }
                    .disabled(image == nil || saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Guardar") { Task { await save() } }
                            .disabled(image == nil)
                    }
                }
            }
            .task { await load() }
        }
    }

    /// El lienzo va EXACTAMENTE encima de la imagen dibujada, no de la vista
    /// entera: si ocupara toda la pantalla, un trazo junto al borde caería
    /// fuera de la foto y se perdería al guardar.
    private func editor(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let fitted = Self.fit(image.size, in: geo.size)
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .overlay(
                        PencilCanvas(canvas: canvas)
                            .frame(width: fitted.width, height: fitted.height)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Tamaño de la imagen encajada dentro del área, conservando proporción.
    private static func fit(_ size: CGSize, in area: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, area.width > 0, area.height > 0 else { return area }
        let scale = min(area.width / size.width, area.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func load() async {
        do {
            // puede estar en una nube sin descargar: se materializa antes
            let data = try await CloudFileHandler.shared.read(url)
            guard let decoded = UIImage(data: data) else {
                loadError = "El archivo no contiene una imagen que se pueda abrir."
                return
            }
            image = decoded
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Funde el dibujo con la imagen y reescribe el archivo.
    ///
    /// Se compone al tamaño en PÍXELES del original, no al de la pantalla: si
    /// no, guardar reduciría la foto a la resolución con la que se estaba
    /// viendo, y perderías calidad cada vez que anotaras algo.
    private func save() async {
        guard let image else { return }
        saving = true
        defer { saving = false }

        let drawing = canvas.drawing
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let composed = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            if !drawing.bounds.isEmpty {
                // el trazo se escala desde el lienzo, que mide lo que la imagen
                // ocupaba en pantalla, al tamaño real de la imagen
                let canvasSize = canvas.bounds.size
                let scale = canvasSize.width > 0 ? size.width / canvasSize.width : 1
                drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: format.scale)
                    .draw(in: CGRect(origin: .zero,
                                     size: CGSize(width: canvasSize.width * scale,
                                                  height: canvasSize.height * scale)))
            }
        }

        let isPNG = url.pathExtension.lowercased() == "png"
        guard let data = isPNG ? composed.pngData()
                               : composed.jpegData(compressionQuality: 0.92) else {
            loadError = "No pude codificar la imagen."
            return
        }
        do {
            try await CloudFileHandler.shared.write(data, to: url)
            onSaved()
            dismiss()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// `PKCanvasView` para SwiftUI, con el selector de herramientas del sistema.
struct PencilCanvas: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // `.anyInput` y no `.pencilOnly`: en un iPad sin Apple Pencil, el modo
        // por defecto ignora el dedo y el lienzo parecería no funcionar.
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .systemRed, width: 6)
        DispatchQueue.main.async {
            guard let window = canvas.window else { return }
            let picker = PKToolPicker.shared(for: window)
            picker?.setVisible(true, forFirstResponder: canvas)
            picker?.addObserver(canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
