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
    private var manualClose = false
    private var reconnectScheduled = false
    /// Datos (teclas/resize) producidos antes de que el handshake viaje: se
    /// encolan aquí para que el JSON de login sea SIEMPRE lo primero que lee
    /// el servidor (si no, un resize temprano rompía el login).
    private var handshakeSent = false
    private var pending: [Data] = []

    var terminalView: TerminalView? { view }

    init(host: String, password: String, machine: String) {
        self.host = host
        self.password = password
        self.machine = machine
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

    private static func c(_ r: Int, _ g: Int, _ b: Int) -> SwiftTerm.Color {
        SwiftTerm.Color(red: UInt16(r * 257), green: UInt16(g * 257), blue: UInt16(b * 257))
    }

    /// MesloLGS NF: la fuente de Powerlevel10k (incluye los glifos Nerd Font).
    static func font(size: CGFloat) -> UIFont {
        UIFont(name: "MesloLGSNF-Regular", size: size)
            ?? UIFont(name: "MesloLGS NF", size: size)
            ?? UIFont(name: "Menlo", size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// SwiftTerm envuelto para SwiftUI con estética de Terminal de macOS.
struct SwiftTermView: UIViewRepresentable {
    let session: PTYConnection
    var fontSize: CGFloat = 13
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
        tv.nativeBackgroundColor = MacTerminalTheme.background
        tv.nativeForegroundColor = MacTerminalTheme.foreground
        tv.backgroundColor = MacTerminalTheme.background
        tv.caretColor = MacTerminalTheme.cursor
        tv.selectedTextBackgroundColor = MacTerminalTheme.selection
        tv.installColors(MacTerminalTheme.ansi)
        session.attach(tv)
        return tv
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        if uiView.font.pointSize != fontSize {
            uiView.font = MacTerminalTheme.font(size: fontSize)
        }
        if let mac = uiView as? MacTerminalView {
            mac.onFontSizeDelta = { [weak mac] delta in
                guard let mac else { return }
                onFontSizeChange?(max(9, min(24, mac.font.pointSize + delta)))
            }
            mac.onFontSizeReset = { onFontSizeChange?(13) }
        }
    }
}

/// Ventana flotante estilo picture-in-picture: arrastrable por la cabecera y
/// redimensionable por la esquina inferior derecha.
struct FloatingTerminal: View {
    let server: Server
    /// En Slide Over / ancho compacto la terminal llena toda la ventana
    var fullscreen: Bool = false
    var onClose: () -> Void

    @State private var session: PTYConnection?
    @Environment(\.openWindow) private var openWindow
    @State private var center = CGPoint(x: 480, y: 340)
    @State private var size = CGSize(width: 600, height: 380)
    @AppStorage("terminalFontSize") private var fontSize: Double = 13
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
                    .background(Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea())
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
        guard let mgrURL = server.managerURL,
              let pw = Keychain.password(for: server.id) else { return false }
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
            if let session {
                SwiftTermView(session: session, fontSize: CGFloat(fontSize)) { newSize in
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .padding(.horizontal, 120)

            HStack(spacing: 8) {
                // en ventana propia los controles de ventana los dibuja iPadOS
                // en esta misma esquina: los nuestros solo estorbarían
                if fullscreen {
                    Color.clear.frame(width: 78, height: 1)
                } else {
                    trafficLights
                }
                Spacer()
                rightControls
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            LinearGradient(colors: [SwiftUI.Color(white: 0.27), SwiftUI.Color(white: 0.20)],
                           startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.4)).frame(height: 0.5)
        }
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

    private var rightControls: some View {
        HStack(spacing: 8) {
            Button { fontSize = max(9, fontSize - 1) } label: {
                Image(systemName: "textformat.size.smaller")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Button { fontSize = min(22, fontSize + 1) } label: {
                Image(systemName: "textformat.size.larger")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
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
                        size = CGSize(
                            width: max(340, (resizeStart?.width ?? 0) + value.translation.width),
                            height: max(220, (resizeStart?.height ?? 0) + value.translation.height)
                        )
                    }
                    .onEnded { _ in resizeStart = nil }
            )
    }

    private func openSession() {
        guard let comps = URLComponents(string: server.urlString),
              let host = comps.host,
              let password = Keychain.password(for: server.id) else { return }
        session = PTYConnection(host: host,
                                password: password,
                                machine: server.dockerMachineName)
    }
}
