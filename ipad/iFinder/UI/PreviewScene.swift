import SwiftUI
import QuickLook

/// Identificador de la escena de vista previa: se usa al declarar el
/// `WindowGroup` y en cada `openWindow` / `dismissWindow`.
enum PreviewScene {
    static let id = "PreviewWindow"
    static let defaultSize = CGSize(width: 820, height: 640)
}

// MARK: - Ventana de vista previa

/// Contenido de la ventana: Quick Look limpio, sin botón de cerrar.
///
/// La salida es por teclado (espacio, Esc, ⌘W) o por los gestos del sistema
/// para descartar ventanas, igual que la vista rápida de macOS.
struct PreviewWindowView: View {
    /// URL propia de ESTA ventana: llega como valor de escena y no cambia
    /// aunque la ventana principal seleccione otro archivo.
    let url: URL?
    @State private var editing = false
    /// Copia que Quick Look ya dejó legible. Es la que se comparte.
    ///
    /// Compartir la URL original era el fallo: la hoja de compartir corre en
    /// OTRO proceso y no hereda nuestro ámbito de seguridad, así que con un
    /// archivo de una nube o de una carpeta concedida recibía una ruta que no
    /// puede leer. El visor ya prepara una copia dentro del contenedor —lo hace
    /// por el mismo motivo—, así que se reutiliza en vez de repetir el trabajo.
    @State private var shareable: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    SafeQuickLookView(url: url, onClose: { dismiss() },
                                      onReady: { shareable = $0 })
                } else {
                    ContentUnavailableView("Sin archivo",
                                           systemImage: "doc",
                                           description: Text("Selecciona un archivo y pulsa la barra espaciadora."))
                }
            }
            .navigationTitle(url?.lastPathComponent ?? "Vista previa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let url {
                    if CodeHighlighter.isCode(url) {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { editing = true } label: {
                                Image(systemName: "pencil.and.outline")
                            }
                        }
                    }
                    // Un solo botón. El de "abrir en otra app" hacía lo mismo:
                    // la hoja de compartir del sistema YA lista las apps que
                    // abren el archivo, así que eran dos caminos al mismo sitio.
                    //
                    // Aparece cuando hay copia legible: sin ella, compartir
                    // entregaría una ruta que el otro proceso no puede abrir.
                    if let shareable {
                        ToolbarItem(placement: .topBarTrailing) {
                            DocumentActionsButton(url: shareable)
                                .frame(width: 30, height: 30)
                        }
                    }
                }
            }
            .sheet(isPresented: $editing) {
                if let url { CodeEditorView(url: url) }
            }
        }
        .frame(minWidth: 320, minHeight: 320)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        // cada previa nueva nace un escalón más pequeña: iPadOS no deja fijar
        // posición, así que la cascada se consigue por tamaño
        .background(CascadingWindowSize(base: PreviewScene.defaultSize))
        // ⌘W del menú cierra ESTA ventana cuando tiene el foco
        .focusedSceneValue(\.windowClose,
                           WindowCloseAction(id: url?.path ?? "preview") { dismiss() })
        // Tercera red para el teclado: atajos de SwiftUI a nivel de ventana.
        // Se consultan cuando la cadena de respondedores de UIKit no consumió
        // la tecla, así que cubren el caso de que el foco esté fuera del visor.
        .background(
            ZStack {
                Button("") { dismiss() }.keyboardShortcut(.space, modifiers: [])
                Button("") { dismiss() }.keyboardShortcut("w", modifiers: .command)
                Button("") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        )
        // el registro solo sirve para saber si hay ventanas abiertas (para
        // alternar con la barra espaciadora); NO decide qué muestra cada una
        .onAppear {
            // ventana resucitada por iPadOS al relanzar: la app arranca limpia
            if AppLaunch.isRestoredWindow {
                dismiss()
                return
            }
            if let url { PreviewStateManager.shared.opened(url) }
        }
        .onDisappear { if let url { PreviewStateManager.shared.closed(url) } }
    }
}

// MARK: - Quick Look a prueba de sandbox

/// Prepara el archivo antes de entregárselo a Quick Look.
///
/// Quick Look renderiza en un **proceso aparte**, que no hereda el ámbito de
/// seguridad de esta app. Por eso hay un plan A y un plan B:
///   A. abrir el ámbito (archivo + raíz concedida) y comprobar que se lee
///   B. si no, copiar a `temporaryDirectory` — dentro del contenedor de la
///      app, siempre legible por cualquier proceso del sistema
struct SafeQuickLookView: View {
    let url: URL
    var onClose: () -> Void = {}
    /// Avisa de la copia realmente legible, para que la ventana comparta ESA
    var onReady: (URL) -> Void = { _ in }

    @State private var ready: URL?
    @State private var failure: String?
    @State private var preparing = true

    var body: some View {
        Group {
            if let ready {
                // Notebooks y código los enseña ZeroSpin: Quick Look los abre
                // como texto plano y un .ipynb así es ilegible.
                switch DocumentKind.of(url) {
                case .notebook, .code:
                    DocumentViewer(url: ready)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .office, .web, .other:
                    QuickLookPreview(url: ready, onClose: onClose)
                        // el visor gestiona sus propios márgenes: debe ocupar todo
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .background(Color(uiColor: .systemBackground))
                }
            } else if preparing {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Preparando \(url.lastPathComponent)…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No se puede previsualizar",
                                       systemImage: "eye.slash",
                                       description: Text(failure ?? "Archivo no disponible"))
            }
        }
        .task(id: url) { await prepare() }
    }

    private func prepare() async {
        preparing = true
        defer { preparing = false }
        failure = nil

        // --- Plan A: acceso directo con el ámbito abierto ---
        var scopes: [URL] = []
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        if let root = CloudFileHandler.root(containing: url), root != url,
           root.startAccessingSecurityScopedResource() {
            scopes.append(root)
        }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }

        do {
            // se abre en cuanto los datos están disponibles, sin esperar a que
            // iCloud dé la sincronización por terminada
            if !ICloudAvailability.isUsable(url) {
                try await CloudFileHandler.shared.materialize(url)
            }
            // --- Plan B: copia temporal para el proceso externo de Quick Look ---
            let data = try await CloudFileHandler.shared.read(url)
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("preview-\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
            try data.write(to: copy, options: .atomic)
            ready = copy
            onReady(copy)
        } catch {
            // si la copia falla pero el archivo es legible tal cual, se usa
            if FileManager.default.isReadableFile(atPath: url.path) {
                ready = url
                onReady(url)
            } else {
                failure = error.localizedDescription
            }
        }
    }
}

// MARK: - Envoltura de QLPreviewController

/// El mismo componente que usa la app Archivos: soporta PDF, imágenes, vídeo,
/// audio, texto, iWork y ZIP sin escribir un visor por tipo.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}
    var onClose: () -> Void = {}

    func makeUIViewController(context: Context) -> PreviewHostController {
        let preview = KeyAwareQLPreviewController()
        preview.onClose = onClose             // espacio / esc / ⌘W cierran
        preview.dataSource = context.coordinator
        preview.delegate = context.coordinator
        // Sin esto, la vista del controlador es transparente y se ve el negro
        // de la ventana en los márgenes que el documento no cubre.
        preview.view.backgroundColor = .systemBackground
        preview.view.clipsToBounds = true

        let host = PreviewHostController(preview: preview)
        host.onClose = onClose
        return host
    }

    func updateUIViewController(_ host: PreviewHostController, context: Context) {
        host.onClose = onClose
        host.preview.onClose = onClose
        if context.coordinator.url != url {
            context.coordinator.url = url
            host.preview.reloadData()
        }
    }

    /// La causa de raíz del desplazamiento: sin esto, SwiftUI pregunta al
    /// representable qué tamaño quiere y UIKit responde con el suyo *ideal*,
    /// no con el de la ventana. Aceptar la propuesta entera hace que la vista
    /// ocupe el 100 % del contenedor.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiViewController: PreviewHostController,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onFinish: onFinish) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var url: URL
        let onFinish: () -> Void

        init(url: URL, onFinish: @escaping () -> Void) {
            self.url = url
            self.onFinish = onFinish
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            PreviewItem(url: url)
        }

        /// Solo lectura: evita que Quick Look intente escribir sobre un
        /// proveedor externo (y sobre la copia temporal, que se descarta).
        func previewController(_ controller: QLPreviewController,
                               editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
            .disabled
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) { onFinish() }
    }

    /// Permite mostrar un título legible en la barra en vez del nombre del
    /// archivo temporal.
    private final class PreviewItem: NSObject, QLPreviewItem {
        let previewItemURL: URL?
        let previewItemTitle: String?

        init(url: URL) {
            self.previewItemURL = url
            // se recorta el prefijo "preview-xxxxxx-" de la copia temporal
            let name = url.lastPathComponent
            if name.hasPrefix("preview-"), let range = name.range(of: "-", range: name.index(name.startIndex, offsetBy: 8)..<name.endIndex) {
                self.previewItemTitle = String(name[range.upperBound...])
            } else {
                self.previewItemTitle = name
            }
        }
    }
}

// MARK: - Captura de teclado sobre Quick Look

/// Contenedor de `QLPreviewController` que atrapa la barra espaciadora.
///
/// **Por qué hace falta.** Un `UIKeyCommand` solo se consulta en los objetos
/// que están en la cadena de respondedores, y esa cadena se recorre desde el
/// primer respondedor hacia arriba. Quick Look monta su contenido en
/// controladores internos propios (uno distinto por tipo de archivo: web para
/// texto, PDFKit para PDF…), que se quedan el foco y, en algunos tipos,
/// consumen el espacio para desplazar la página. Por eso el `.onKeyPress` de
/// SwiftUI de la ventana principal deja de recibir nada.
///
/// La solución es rodear al visor por los dos lados:
///   1. `KeyAwareQLPreviewController` — justo encima del contenido interno.
///   2. Este anfitrión — por encima del visor entero, atrapa lo que el visor
///      no consumió, tanto por `keyCommands` como por `pressesBegan`.
///   3. Los atajos de SwiftUI en `PreviewWindowView` — última red.
///
/// `wantsPriorityOverSystemBehavior` es lo que hace que el espacio llegue aquí
/// antes de que el sistema lo interprete como "desplazar".
final class PreviewHostController: UIViewController {
    let preview: KeyAwareQLPreviewController
    var onClose: () -> Void = {}

    init(preview: KeyAwareQLPreviewController) {
        self.preview = preview
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no disponible") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        addChild(preview)
        // Máscara de redimensionado en lugar de constraints: el visor de Quick
        // Look reconstruye su jerarquía interna al cambiar de documento y, con
        // constraints, esa jerarquía nueva se quedaba con el ancho anterior —
        // de ahí el contenido pegado a la izquierda y el bloque negro.
        preview.view.translatesAutoresizingMaskIntoConstraints = true
        preview.view.frame = view.bounds
        preview.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(preview.view)
        preview.didMove(toParent: self)
    }

    /// Segunda garantía: en cada pasada de layout el visor vuelve a ocupar
    /// exactamente el contenedor, venga el cambio de donde venga (rotación,
    /// Stage Manager, Split View).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if preview.view.frame != view.bounds { preview.view.frame = view.bounds }
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? { UIKeyCommand.closePreviewCommands(#selector(closePreview)) }

    /// Segunda red por si el evento llega como pulsación en bruto en lugar de
    /// como comando (ocurre con algunos visores internos de Quick Look).
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let closes = presses.contains { press in
            guard let key = press.key else { return false }
            return key.charactersIgnoringModifiers == " " && key.modifierFlags.isEmpty
        }
        if closes { closePreview() } else { super.pressesBegan(presses, with: event) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    @objc private func closePreview() { onClose() }
}

/// `QLPreviewController` que responde al teclado, colocado inmediatamente por
/// encima del contenido interno del visor.
final class KeyAwareQLPreviewController: QLPreviewController {
    var onClose: () -> Void = {}

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? { UIKeyCommand.closePreviewCommands(#selector(closePreview)) }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()   // sin esto los UIKeyCommand no se consultan
    }

    @objc private func closePreview() { onClose() }
}

private extension UIKeyCommand {
    /// Espacio (como macOS), Esc y ⌘W, con prioridad sobre el comportamiento
    /// que el sistema daría a esas teclas dentro del visor.
    static func closePreviewCommands(_ action: Selector) -> [UIKeyCommand] {
        let commands = [
            UIKeyCommand(input: " ", modifierFlags: [], action: action),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: action),
            UIKeyCommand(input: "w", modifierFlags: .command, action: action),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }
}


/// Botón único de acciones del documento.
///
/// No usa `ShareLink`. Con una URL, `ShareLink` la comparte como un ENLACE
/// genérico: el sistema no deduce el tipo del archivo —de ahí el "File · 156 KB"
/// en la cabecera— y las apps que sí sabrían abrirlo, como Word, no se ofrecen.
///
/// `UIDocumentInteractionController` sí declara el tipo a partir del archivo, y
/// por eso su menú pone delante la app que lo abre. Es lo que hacía el botón de
/// la flecha, y es el comportamiento que se quiere conservar ahora que hay uno
/// solo. Su menú incluye además copiar, imprimir y guardar en Archivos, así que
/// no se pierde nada de la hoja de compartir.
///
/// Va en UIKit y no en SwiftUI por el anclaje: en iPadOS el menú es un popover
/// y necesita una vista de origen. Siendo el propio botón esa vista, el menú
/// sale pegado a él — antes se anclaba a una vista cualquiera de la jerarquía y
/// aparecía flotando en mitad de la pantalla.
struct DocumentActionsButton: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped(_:)),
                         for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.url = url
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, UIDocumentInteractionControllerDelegate {
        var url: URL
        /// Se retiene mientras el menú está en pantalla; si no, desaparece.
        private var interaction: UIDocumentInteractionController?

        init(url: URL) { self.url = url }

        @objc func tapped(_ sender: UIButton) {
            let controller = UIDocumentInteractionController(url: url)
            controller.delegate = self
            interaction = controller
            // el propio botón es el ancla: el menú sale de donde se tocó
            controller.presentOptionsMenu(from: sender.bounds, in: sender, animated: true)
        }

        func documentInteractionControllerDidDismissOptionsMenu(
            _ controller: UIDocumentInteractionController) {
            interaction = nil
        }
    }
}
