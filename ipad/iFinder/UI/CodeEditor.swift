import SwiftUI
import UIKit

/// Editor de código nativo, sin conexión ni servidor.
///
/// Es la respuesta realista a "VS Code en el propio iPad": iOS no permite JIT,
/// así que Node —y con él code-server— no puede correr aquí a velocidad usable.
/// Lo que sí se puede es un editor de verdad, nativo, que funciona en un avión:
/// escribir, resaltar y guardar archivos del iPad.
struct CodeEditorView: View {
    let url: URL

    @State private var text = ""
    @State private var original = ""
    @State private var loaded = false
    @State private var failure: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    private var ext: String { url.pathExtension.lowercased() }
    private var dirty: Bool { text != original }

    var body: some View {
        NavigationStack {
            Group {
                if let failure {
                    ContentUnavailableView("No se puede editar", systemImage: "pencil.slash",
                                           description: Text(failure))
                } else if loaded {
                    HighlightingTextView(text: $text, extension: ext)
                } else {
                    ProgressView()
                }
            }
            // El punto delante del nombre es la señal de "sin guardar", como en
            // cualquier editor. Antes era una etiqueta suelta a la izquierda
            // que competía por sitio con "Cerrar" y acababa recortada a
            // "guar…" — y encima repetía lo que ya dice el botón Guardar al
            // estar activo o no.
            .navigationTitle(dirty ? "● \(url.lastPathComponent)" : url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Guardar") { save() }
                            .disabled(!dirty)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
            }
            .task { await load() }
        }
    }

    /// Cierra guardando lo que haya pendiente.
    ///
    /// El guardado iba en `onDisappear`, y ahí llega tarde: la vista ya se está
    /// retirando y la escritura —que es asíncrona— podía quedarse a medias. Al
    /// hacerlo aquí, el cierre espera a que el archivo esté en disco.
    ///
    /// Y perder lo escrito por cerrar sin pensar sería el peor fallo posible en
    /// un editor, así que cerrar guarda; no pregunta.
    private func close() {
        guard dirty else { dismiss(); return }
        Task {
            await saveNow()
            dismiss()
        }
    }

    private func load() async {
        do {
            let data = try await CloudFileHandler.shared.read(url)
            let content = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
            guard let content else {
                failure = "Este archivo no es texto."
                return
            }
            text = content
            original = content
            loaded = true
        } catch {
            failure = error.localizedDescription
        }
    }

    private func save() {
        Task { await saveNow() }
    }

    @MainActor
    private func saveNow() async {
        let snapshot = text
        saving = true
        defer { saving = false }
        do {
                // Se guarda por el mismo camino por el que se lee.
                //
                // Abrir aquí el ámbito del propio archivo no basta: un archivo
                // DENTRO de una carpeta concedida no tiene ámbito propio, lo
                // hereda de su raíz. Guardar un .sh de un OneDrive montado
                // fallaba por eso, y encima en silencio. `CloudFileHandler`
                // abre las dos cosas y coordina la escritura con el proveedor.
            try await CloudFileHandler.shared.write(Data(snapshot.utf8), to: url)
            original = snapshot
        } catch {
            failure = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}

/// `UITextView` con resaltado aplicado sobre el propio texto.
///
/// Se usa UIKit y no `TextEditor` porque SwiftUI no deja pintar rangos con
/// colores distintos dentro del texto editable, que es justo lo que hace falta.
struct HighlightingTextView: UIViewRepresentable {
    @Binding var text: String
    let `extension`: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.alwaysBounceVertical = true
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.smartQuotesType = .no          // comillas rectas: son código
        view.smartDashesType = .no
        view.spellCheckingType = .no
        view.keyboardType = .asciiCapable
        view.backgroundColor = .systemBackground
        view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 40, right: 10)
        view.text = text
        context.coordinator.apply(to: view, extension: self.extension)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        // Solo si el cambio viene de fuera: reescribir mientras se teclea
        // movería el cursor al final en cada pulsación.
        if view.text != text {
            view.text = text
            context.coordinator.apply(to: view, extension: self.extension)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        private var pending: DispatchWorkItem?

        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ view: UITextView) {
            text.wrappedValue = view.text

            // El resaltado se aplica con retardo: analizar el archivo entero en
            // cada tecla se nota en cuanto pasa de unos cientos de líneas.
            pending?.cancel()
            let work = DispatchWorkItem { [weak self, weak view] in
                guard let view else { return }
                self?.apply(to: view, extension: (view.accessibilityHint ?? ""))
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        /// Pinta los tramos conservando la posición del cursor.
        func apply(to view: UITextView, extension ext: String) {
            view.accessibilityHint = ext          // el retardo lo necesita luego
            let selection = view.selectedRange
            let font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let result = NSMutableAttributedString()

            for span in CodeHighlighter.spans(view.text, extension: ext) {
                result.append(NSAttributedString(string: span.text, attributes: [
                    .font: font,
                    .foregroundColor: Self.color(for: span.token),
                ]))
            }
            view.attributedText = result
            view.selectedRange = selection
        }

        private static func color(for token: CodeHighlighter.Token) -> UIColor {
            switch token {
            case .plain: return .label
            case .keyword: return UIColor(red: 0.78, green: 0.31, blue: 0.61, alpha: 1)
            case .string: return UIColor(red: 0.79, green: 0.25, blue: 0.20, alpha: 1)
            case .number: return UIColor(red: 0.20, green: 0.35, blue: 0.85, alpha: 1)
            case .comment: return .secondaryLabel
            }
        }
    }
}
