import SwiftUI
import SwiftTerm
import Network

/// Conexión al canal PTY del gestor (puerto 39600 del PC, solo tailnet).
/// Protocolo: 1ª línea JSON {password, machine, cols, rows}\n; después bytes
/// pty crudos. Resize: frame de 10 bytes 0x00 'R' cccc rrrr.
final class PTYConnection: NSObject, TerminalViewDelegate {
    private var conn: NWConnection?
    private weak var view: TerminalView?
    private let host: String
    private let password: String
    private let machine: String
    /// Identifica la sesión de tmux del host. Ventanas distintas usan valores
    /// distintos: es lo que hace que sean shells independientes en vez de la
    /// misma sesión espejada.
    private let session: String
    /// Destino `usuario@host[:puerto]`. Vacío = shell del propio equipo.
    private let sshTarget: String
    private var manualClose = false
    private var reconnectScheduled = false
    /// Datos (teclas/resize) producidos antes de que el handshake viaje: se
    /// encolan aquí para que el JSON de login sea SIEMPRE lo primero que lee
    /// el servidor (si no, un resize temprano rompía el login).
    private var handshakeSent = false
    private var pending: [Data] = []

    var terminalView: TerminalView? { view }

    /// Se llama cuando el host rechaza la contraseña del saludo.
    ///
    /// Sin esto el error llegaba como texto suelto dentro del terminal y no se
    /// distinguía de la salida de un comando: parecía que "no conectaba".
    var onAuthFailure: (() -> Void)?
    private var sawAuthFailure = false

    init(host: String, password: String, machine: String,
         session: String = "", sshTarget: String = "") {
        self.host = host
        self.password = password
        self.machine = machine
        self.session = session
        self.sshTarget = sshTarget
    }

    deinit {
        manualClose = true
        conn?.cancel()
    }

    func attach(_ terminalView: TerminalView) {
        view = terminalView
        terminalView.terminalDelegate = self
        let term = terminalView.getTerminal()
        connect(cols: term.cols, rows: term.rows)
    }

    private func connect(cols: Int, rows: Int) {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: 39600, using: .tcp)
        conn = connection
        handshakeSent = false
        pending.removeAll()
        // [weak connection] evita el ciclo NWConnection ⇄ su propio handler
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.conn === connection else { return }
            switch state {
            case .ready:
                let hello: [String: Any] = [
                    "password": self.password,
                    "machine": self.machine,
                    "session": self.session,
                    "ssh": self.sshTarget,
                    "cols": cols, "rows": rows,
                ]
                if var data = try? JSONSerialization.data(withJSONObject: hello) {
                    data.append(0x0A)
                    connection.send(content: data, completion: .contentProcessed { _ in })
                }
                self.handshakeSent = true
                for chunk in self.pending {
                    connection.send(content: chunk, completion: .contentProcessed { _ in })
                }
                self.pending.removeAll()
                self.receiveLoop(on: connection)
            case .failed:
                self.scheduleReconnect(from: connection)
            case .waiting(let error):
                self.feedText("\r\n[esperando red: \(error.localizedDescription)]\r\n")
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    /// El bucle va atado a SU conexión: un callback tardío de una conexión
    /// vieja no puede duplicar la lectura ni cancelar la conexión nueva.
    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isDone, error in
            guard let self, self.conn === connection else { return }
            if let data, !data.isEmpty {
                // el host responde "auth incorrecta" y cierra: se detecta aquí
                // para poder avisar de verdad en lugar de dejarlo pasar como
                // si fuera salida del shell
                if !self.sawAuthFailure,
                   let text = String(data: data.prefix(64), encoding: .utf8),
                   text.contains("auth incorrecta") {
                    self.sawAuthFailure = true
                    self.manualClose = true          // no reintentar con la misma clave
                    DispatchQueue.main.async { self.onAuthFailure?() }
                    connection.cancel()
                    return
                }
                self.view?.feed(byteArray: ArraySlice([UInt8](data)))
            }
            if isDone || error != nil {
                self.scheduleReconnect(from: connection)
                return
            }
            self.receiveLoop(on: connection)
        }
    }

    /// La sesión se recompone sola (p. ej. tras suspenderse la app); con tmux
    /// en el host, incluso el shell y sus procesos sobreviven.
    private func scheduleReconnect(from connection: NWConnection) {
        guard !manualClose, !reconnectScheduled, conn === connection else { return }
        reconnectScheduled = true
        feedText("\r\n[conexión perdida — reconectando…]\r\n")
        connection.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.manualClose else { return }
            self.reconnectScheduled = false
            let term = self.view?.getTerminal()
            self.connect(cols: term?.cols ?? 80, rows: term?.rows ?? 24)
        }
    }

    private func feedText(_ text: String) {
        view?.feed(byteArray: ArraySlice(Array(text.utf8)))
    }

    func close() {
        manualClose = true
        conn?.cancel()
        conn = nil
        pending.removeAll()
    }

    /// Envía o encola según el handshake ya haya viajado.
    private func transmit(_ data: Data) {
        guard let conn else { return }
        if handshakeSent {
            conn.send(content: data, completion: .contentProcessed { _ in })
        } else {
            pending.append(data)
        }
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        // el 0x00 del usuario (Ctrl+Espacio) se duplica para no confundirse
        // con el prefijo de los frames de control
        var out = Data()
        for byte in data {
            out.append(byte)
            if byte == 0x00 { out.append(0x00) }
        }
        transmit(out)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        var frame = Data([0x00])
        frame.append(contentsOf: Array("R".utf8))
        frame.append(contentsOf: Array(String(format: "%04d", newCols).utf8))
        frame.append(contentsOf: Array(String(format: "%04d", newRows).utf8))
        transmit(frame)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        UIPasteboard.general.string = String(data: content, encoding: .utf8)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { UIApplication.shared.open(url) }
    }
    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// Paleta ANSI de Terminal.app de macOS (tema oscuro) — los mismos tonos que
/// ves en el Mac, para que zsh/powerlevel10k se vea idéntico.
enum MacTerminalTheme {
    /// Colores oscuros (los de siempre). Se conservan como estaban.
    static let background = UIColor(red: 0.086, green: 0.086, blue: 0.086, alpha: 1)
    static let foreground = UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
    static let cursor = UIColor(red: 0.898, green: 0.898, blue: 0.898, alpha: 1)
    static let selection = UIColor(red: 0.24, green: 0.35, blue: 0.55, alpha: 1)

    /// 16 colores ANSI (normales 0-7, brillantes 8-15) en componentes de 16 bits
    static let ansi: [SwiftTerm.Color] = [
        c(0x00, 0x00, 0x00), c(0xC9, 0x3C, 0x2F), c(0x25, 0xBC, 0x24), c(0xAD, 0xAD, 0x27),
        c(0x49, 0x2E, 0xE1), c(0xD3, 0x38, 0xD3), c(0x33, 0xBB, 0xC8), c(0xCB, 0xCC, 0xCD),
        c(0x81, 0x83, 0x83), c(0xFC, 0x39, 0x1F), c(0x31, 0xE7, 0x22), c(0xEA, 0xEC, 0x23),
        c(0x58, 0x33, 0xFF), c(0xF9, 0x35, 0xF7), c(0x14, 0xF0, 0xF0), c(0xE9, 0xEB, 0xEB),
    ]

    // MARK: - Paleta clara (perfil "Basic" del Terminal de macOS)

    static let lightBackground = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let lightForeground = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
    static let lightCursor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
    static let lightSelection = UIColor(red: 0.70, green: 0.80, blue: 0.98, alpha: 1)

    /// Los mismos 16 ANSI, oscurecidos donde harían falta sobre blanco: el
    /// amarillo y el cian del perfil oscuro son ilegibles sobre fondo claro.
    static let lightAnsi: [SwiftTerm.Color] = [
        c(0x00, 0x00, 0x00), c(0xC2, 0x1A, 0x1A), c(0x00, 0x7A, 0x1F), c(0x8A, 0x6D, 0x00),
        c(0x1B, 0x3D, 0xD6), c(0xA0, 0x1C, 0xA0), c(0x00, 0x77, 0x8A), c(0x4D, 0x4D, 0x4D),
        c(0x66, 0x66, 0x66), c(0xE0, 0x2A, 0x2A), c(0x00, 0x96, 0x27), c(0xA8, 0x86, 0x00),
        c(0x2C, 0x53, 0xF0), c(0xC4, 0x2A, 0xC4), c(0x00, 0x93, 0xAA), c(0x1A, 0x1A, 0x1A),
    ]

    /// Conjunto de colores para un tema concreto.
    struct Palette {
        let background: UIColor
        let foreground: UIColor
        let cursor: UIColor
        let selection: UIColor
        let ansi: [SwiftTerm.Color]
    }

    /// Paleta efectiva: la del tema elegido por el usuario, que solo mira el
    /// modo claro/oscuro cuando está en "Automático".
    static func palette(for scheme: ColorScheme) -> Palette {
        TerminalTheme.current.palette(for: scheme)
    }

    /// Aplica la paleta a una terminal **ya viva**, sin recrearla: el búfer,
    /// el historial y lo que el usuario esté escribiendo se conservan.
    static func apply(_ palette: Palette, to terminal: TerminalView) {
        terminal.nativeBackgroundColor = palette.background
        terminal.nativeForegroundColor = palette.foreground
        terminal.backgroundColor = palette.background
        terminal.caretColor = palette.cursor
        terminal.selectedTextBackgroundColor = palette.selection
        terminal.installColors(palette.ansi)
        terminal.setNeedsDisplay()
    }

    private static func c(_ r: Int, _ g: Int, _ b: Int) -> SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16(r * 257), green: UInt16(g * 257), blue: UInt16(b * 257))
    }

    /// Tipografía elegida por el usuario (por defecto MesloLGS NF, la de
    /// Powerlevel10k, que trae los glifos Nerd Font).
    static func font(size: CGFloat) -> UIFont {
        TerminalTypeface.current.font(size: size)
    }
}

/// SwiftTerm envuelto para SwiftUI con estética de Terminal de macOS.
struct SwiftTermView: UIViewRepresentable {
    let session: PTYConnection
    var fontSize: CGFloat = 13
    /// Tema del sistema. Al ser una propiedad del representable, cambiarlo
    /// dispara `updateUIView` sobre la MISMA vista, no `makeUIView`.
    var colorScheme: ColorScheme = .dark
    /// Identidad del aspecto elegido: cambiarla obliga a repintar, igual que
    /// el tema del sistema. Sin esto, elegir otra paleta no se notaba hasta
    /// cerrar y reabrir la ventana.
    var appearanceID: String = TerminalTheme.current.rawValue + TerminalTypeface.current.rawValue
    var onFontSizeChange: ((CGFloat) -> Void)? = nil

    func makeUIView(context: Context) -> TerminalView {
        let tv = MacTerminalView(frame: .zero)
        tv.font = MacTerminalTheme.font(size: fontSize)
        // barra de teclas colapsada en un botón (no tapa la última línea)
        tv.inputAccessoryView = CollapsibleAccessory(terminal: tv)
        // scroll del historial con dos dedos / trackpad
        tv.allowMouseReporting = true
        // el tamaño se lee de la vista, no de la copia capturada: si no, cada
        // pulsación partía del valor inicial y solo funcionaba una vez
        tv.onFontSizeDelta = { [weak tv] delta in
            guard let tv else { return }
            onFontSizeChange?(max(9, min(24, tv.font.pointSize + delta)))
        }
        tv.onFontSizeReset = { onFontSizeChange?(13) }
        MacTerminalTheme.apply(MacTerminalTheme.palette(for: colorScheme), to: tv)
        session.attach(tv)
        return tv
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        if uiView.font.pointSize != fontSize {
            uiView.font = MacTerminalTheme.font(size: fontSize)
        }
        // repintado en caliente al cambiar el tema del iPad
        if context.coordinator.scheme != colorScheme
            || context.coordinator.appearanceID != appearanceID {
            context.coordinator.scheme = colorScheme
            context.coordinator.appearanceID = appearanceID
            uiView.font = MacTerminalTheme.font(size: fontSize)
            MacTerminalTheme.apply(MacTerminalTheme.palette(for: colorScheme), to: uiView)
        }
        if let mac = uiView as? MacTerminalView {
            mac.onFontSizeDelta = { [weak mac] delta in
                guard let mac else { return }
                onFontSizeChange?(max(9, min(24, mac.font.pointSize + delta)))
            }
            mac.onFontSizeReset = { onFontSizeChange?(13) }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scheme: colorScheme, appearanceID: appearanceID)
    }

    /// Recuerda el último tema aplicado. Sin esta memoria, `updateUIView`
    /// reinstalaría la paleta en cada refresco (cambio de fuente, arrastre…),
    /// lo que provoca un parpadeo innecesario.
    final class Coordinator {
        var scheme: ColorScheme
        var appearanceID: String
        init(scheme: ColorScheme, appearanceID: String) {
            self.scheme = scheme
            self.appearanceID = appearanceID
        }
    }
}

/// Ventana flotante estilo picture-in-picture: arrastrable por la cabecera y
/// redimensionable por la esquina inferior derecha.
struct FloatingTerminal: View {
    let server: Server
    /// Sesión de tmux de ESTA ventana. Estable mientras la ventana viva, para
    /// que al reconectar se vuelva a enganchar al mismo shell.
    var sessionID: String = ""
    /// Si no está vacío, el equipo salta por SSH a esta máquina.
    var sshTarget: String = ""
    /// En Slide Over / ancho compacto la terminal llena toda la ventana
    var fullscreen: Bool = false
    var onClose: () -> Void

    @State private var session: PTYConnection?
    /// El host rechazó la contraseña (o no hay ninguna que ofrecerle)
    @State private var authFailed = false
    @State private var hostPasswordField = ""
    /// El servidor activo no ofrece terminal (vscode.dev, Codespaces…)
    @State private var unsupported = false
    @Environment(\.openWindow) private var openWindow
    /// Tema del iPad. Leerlo aquí NO recrea la terminal: solo hace que
    /// `updateUIView` reciba el valor nuevo sobre la vista que ya existe.
    @Environment(\.colorScheme) private var colorScheme
    @State private var center = CGPoint(x: 480, y: 340)
    @State private var size = CGSize(width: 600, height: 380)
    @AppStorage("terminalFontSize") private var fontSize: Double = 13
    // Observarlas aquí es lo que hace que un cambio de tema repinte el
    // terminal YA abierto: sin esto la vista no se recompone y el color nuevo
    // no llegaba hasta cerrar y volver a abrir la ventana.
    @AppStorage(TerminalTheme.storageKey) private var themeRaw = TerminalTheme.system.rawValue
    @AppStorage(TerminalTypeface.storageKey) private var faceRaw = TerminalTypeface.meslo.rawValue
    @State private var centered = false
    @State private var dropMessage: String?
    @State private var dropTargeted = false

    /// Mantiene el panel dentro de la ventana visible de la app.
    private func clamped(_ point: CGPoint, in container: CGSize) -> CGPoint {
        let halfW = min(size.width, container.width - 16) / 2
        let halfH = min(size.height, container.height - 16) / 2
        return CGPoint(
            x: min(max(point.x, halfW + 8), max(halfW + 8, container.width - halfW - 8)),
            y: min(max(point.y, halfH + 8), max(halfH + 8, container.height - halfH - 8))
        )
    }
    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGSize?

    var body: some View {
        Group {
            if fullscreen {
                panelContent
                    // el color del propio terminal: un gris fijo se veía como
                    // una franja ajena en modo claro
                    .background(
                        Color(uiColor: MacTerminalTheme.palette(for: colorScheme).background)
                            .ignoresSafeArea()
                    )
            } else {
                GeometryReader { geo in
                    panelContent
                        .frame(width: min(size.width, geo.size.width - 16),
                               height: min(size.height, geo.size.height - 16))
                        .background(Color(uiColor: MacTerminalTheme.background))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.18), lineWidth: 1)
                        )
                        .overlay(alignment: .bottomTrailing) { resizeGrip }
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
                        // la posición se mantiene DENTRO de la ventana de la
                        // app: si no, al usar la app en ventana el panel queda
                        // cortado y sus botones fuera de alcance
                        .position(clamped(center, in: geo.size))
                        .onAppear {
                            if !centered {
                                center = CGPoint(x: geo.size.width / 2,
                                                 y: geo.size.height / 2)
                                centered = true
                            }
                        }
                }
            }
        }
        .onAppear { openSession() }
        .onDisappear { session?.close() }
    }

    /// Sube los archivos soltados desde Archivos/Fotos a la sesión actual.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // Igual que en el editor: la subida la atiende el gestor del EQUIPO, y
        // ese valida la contraseña del equipo. Con la del contenedor, soltar un
        // archivo sobre la terminal de una máquina Docker se iba en 401.
        guard let mgrURL = server.managerURL,
              let pw = ServerStore.shared.hostPassword(for: server) else { return false }
        let client = ManagerClient(baseURL: mgrURL, password: pw)
        let machine = server.dockerMachineName
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, _ in
                guard let data else { return }
                let name = provider.suggestedName ?? "archivo"
                Task {
                    do {
                        let dest = try await client.upload(data: data, filename: name,
                                                           machine: machine, dest: "@cwd")
                        await MainActor.run {
                            dropMessage = "\(name) → \(dest)"
                            session?.terminalView?.feed(
                                byteArray: ArraySlice(Array("\r\n[recibido: \(name) en \(dest)]\r\n".utf8)))
                        }
                    } catch {
                        await MainActor.run {
                            dropMessage = "Error subiendo \(name): \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        return true
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            header
            if unsupported {
                unsupportedBanner
            } else if authFailed {
                authBanner
            } else if let session {
                SwiftTermView(session: session,
                              fontSize: CGFloat(fontSize),
                              colorScheme: colorScheme,
                              appearanceID: themeRaw + faceRaw) { newSize in
                    fontSize = Double(newSize)
                }
                .onDrop(of: ["public.data"], isTargeted: $dropTargeted) { providers in
                    handleDrop(providers)
                }
                .overlay(alignment: .center) {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 3, dash: [10]))
                            .background(Color.cyan.opacity(0.08))
                            .overlay(
                                Label("Soltar para subir", systemImage: "arrow.down.doc")
                                    .font(.headline)
                                    .foregroundStyle(.cyan))
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                Color(uiColor: MacTerminalTheme.background)
                    .overlay(Text("Sin conexión").foregroundStyle(.secondary))
            }
        }
    }

    /// Título como el de Terminal.app: "usuario — host — sesión — 80×24"
    private var titleText: String {
        // El destino SSH manda en el título: saber a qué máquina estás
        // escribiendo importa más que recordar por dónde saltaste.
        if !sshTarget.isEmpty {
            if let term = session?.terminalView?.getTerminal() {
                return "\(sshTarget) — ssh — \(term.cols)×\(term.rows)"
            }
            return "\(sshTarget) — ssh"
        }
        let name = server.dockerMachineName.isEmpty
            ? server.name
            : "\(server.dockerMachineName) — docker"
        if let term = session?.terminalView?.getTerminal() {
            return "\(name) — bash — \(term.cols)×\(term.rows)"
        }
        return "\(name) — bash"
    }

    /// Barra de título estilo Terminal.app: semáforos a la izquierda, título
    /// centrado, y controles discretos a la derecha.
    private var header: some View {
        ZStack {
            Text(titleText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                // recorta por el medio: el nombre del equipo y el tamaño son
                // lo informativo, y quedan a los extremos
                .truncationMode(.middle)
                .padding(.horizontal, 96)

            HStack(spacing: 8) {
                // en ventana propia los controles de ventana los dibuja iPadOS
                // en esta misma esquina: los nuestros solo estorbarían
                if fullscreen {
                    Color.clear.frame(width: 78, height: 1)
                } else {
                    trafficLights
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(barBackground)
        .contentShape(Rectangle())
        .gesture(
            fullscreen ? nil :
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if dragStart == nil { dragStart = center }
                    center = CGPoint(x: (dragStart?.x ?? 0) + value.translation.width,
                                     y: (dragStart?.y ?? 0) + value.translation.height)
                }
                .onEnded { _ in dragStart = nil }
        )
    }

    /// El fondo de la barra ES el del terminal, no un gris aparte: así la
    /// ventana se lee como una sola superficie. Encima, un realce mínimo
    /// arriba que insinúa volumen sin dibujar un degradado visible.
    private var barBackground: some View {
        let palette = MacTerminalTheme.palette(for: colorScheme)
        return SwiftUI.Color(uiColor: palette.background)
            .overlay(
                LinearGradient(
                    colors: [SwiftUI.Color.white.opacity(colorScheme == .dark ? 0.09 : 0.5),
                             SwiftUI.Color.white.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
            )
    }

    /// Gris medio en ambos temas: el blanco fijo desaparecía en modo claro.
    private var titleColor: SwiftUI.Color {
        colorScheme == .dark ? SwiftUI.Color.white.opacity(0.62)
                             : SwiftUI.Color.black.opacity(0.62)
    }

    private var trafficLights: some View {
        HStack(spacing: 8) {
            // rojo: cerrar
            trafficLight(color: SwiftUI.Color(red: 1.0, green: 0.37, blue: 0.35),
                         symbol: "xmark", enabled: !fullscreen) {
                session?.close()
                onClose()
            }
            // verde: abrir como ventana independiente
            trafficLight(color: SwiftUI.Color(red: 0.24, green: 0.79, blue: 0.25),
                         symbol: "arrow.up.left.and.arrow.down.right",
                         enabled: !fullscreen) {
                TerminalScene.open(serverID: server.id)
                onClose()
            }
        }
    }

    private func trafficLight(color: SwiftUI.Color, symbol: String,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(enabled ? color : SwiftUI.Color(white: 0.42))
                .frame(width: 12, height: 12)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(.black.opacity(enabled ? 0.5 : 0))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var resizeGrip: some View {
        Image(systemName: "line.3.horizontal.decrease")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
            .rotationEffect(.degrees(-45))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if resizeStart == nil { resizeStart = size }
                        // mínimo pequeño de verdad: 340×220 impedía dejar el
                        // panel como una tira estrecha junto al editor
                        size = CGSize(
                            width: max(240, (resizeStart?.width ?? 0) + value.translation.width),
                            height: max(160, (resizeStart?.height ?? 0) + value.translation.height)
                        )
                    }
                    .onEnded { _ in resizeStart = nil }
            )
    }

    private func openSession() {
        guard let comps = URLComponents(string: server.urlString),
              let host = comps.host else { return }
        // vscode.dev y compañía editan, pero no tienen canal PTY detrás
        guard server.isManagedHost else {
            unsupported = true
            return
        }
        // OJO: la del HOST, no la de la entrada activa. Un contenedor guarda la
        // suya propia y el canal PTY siempre lo atiende el host.
        guard let password = ServerStore.shared.hostPassword(for: server) else {
            authFailed = true
            return
        }
        let connection = PTYConnection(host: host,
                                       password: password,
                                       machine: server.dockerMachineName,
                                       session: sessionID,
                                       sshTarget: sshTarget)
        connection.onAuthFailure = { authFailed = true }
        session = connection
    }

    /// Vuelve a intentarlo con la contraseña que acaba de escribir el usuario.
    private func retryWithHostPassword() {
        let clean = hostPasswordField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        ServerStore.shared.saveHostPassword(clean, for: server)
        hostPasswordField = ""
        authFailed = false
        session?.close()
        session = nil
        openSession()
    }

    /// Este servidor edita, pero no da terminal.
    private var unsupportedBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal.slash")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Este servidor no ofrece terminal")
                .font(.headline)
            Text("vscode.dev y GitHub Codespaces solo sirven el editor. El terminal necesita un equipo con serve.sh en marcha.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    /// Aviso de contraseña rechazada, con la explicación y la salida.
    private var authBanner: some View {
        VStack(spacing: 12) {
            Label("El host rechazó la contraseña", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.headline)
            Text(server.isDockerMachine
                 ? "El terminal no habla con el contenedor, sino con el equipo que lo aloja, y ese usa su propia contraseña. Si el contenedor se creó antes de que la contraseña del equipo cambiara, las dos ya no coinciden."
                 : "La contraseña guardada ya no coincide con la del equipo. Se regenera al borrar ~/.ivscode.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("En el equipo:  cat ~/.ivscode/password")
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            SecureField("Contraseña del equipo", text: $hostPasswordField)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onSubmit { retryWithHostPassword() }
            Button("Conectar") { retryWithHostPassword() }
                .buttonStyle(.borderedProminent)
                .disabled(hostPasswordField.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
