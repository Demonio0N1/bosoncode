import SwiftUI

/// Sistema operativo del equipo, para elegir su icono.
///
/// El dato bueno viene del propio equipo: `serve.sh` publica `os=` en el TXT
/// del anuncio mDNS y ahí no hay nada que adivinar. La heurística sobre el
/// nombre del host queda solo para los casos en que no hay anuncio: equipos
/// añadidos a mano y equipos con una versión antigua del script.
enum HostPlatform {
    case linux, windows, mac

    private static let windowsMarks = ["windows", "win10", "win11", "win-", "-win", "msi"]
    private static let macMarks = ["mac", "imac", "macbook", "darwin", "mbp", "mini"]

    /// Valor exacto anunciado por serve.sh, si lo hay.
    static func from(advertised os: String?) -> HostPlatform? {
        switch os?.lowercased() {
        case "linux": return .linux
        case "macos", "darwin": return .mac
        case "windows": return .windows
        default: return nil
        }
    }

    /// Dato anunciado primero; si no lo hay, se cae a mirar el nombre.
    static func resolve(os: String?, name: String) -> HostPlatform {
        from(advertised: os) ?? detect(name)
    }

    static func detect(_ name: String) -> HostPlatform {
        let host = name.lowercased()
        if macMarks.contains(where: { host.contains($0) }) { return .mac }
        if windowsMarks.contains(where: { host.contains($0) }) { return .windows }
        return .linux
    }

    /// SF Symbols no tiene pingüino: para Linux se usa el símbolo de terminal,
    /// que es el que Apple emplea para entornos de línea de comandos.
    var symbol: String {
        let name: String
        switch self {
        case .linux: name = "terminal.fill"
        case .windows: name = "pc"
        case .mac: name = "apple.logo"
        }
        // si el símbolo no existe en esta versión de iOS, monitor genérico
        return UIImage(systemName: name) != nil ? name : "desktopcomputer"
    }

    var label: String {
        switch self {
        case .linux: return "Linux"
        case .windows: return "Windows"
        case .mac: return "macOS"
        }
    }
}

/// Datos de marca y enlaces externos, en un solo sitio.
enum BosonCodeInfo {
    /// Repositorio con la guía de Tailscale y `serve.sh`.
    static let setupGuideURL = URL(string: "https://github.com/Demonio0N1/bosoncode")!

    static let copyright = "© 2026 BosonCode. All rights reserved."

    /// VS Code público en la web. Deja probar el editor sin montar nada — y da
    /// al revisor de la App Store algo a lo que conectarse, que si no tendría
    /// que instalar Linux y ejecutar serve.sh para poder abrir la app.
    /// Debe estar también en WKAppBoundDomains o WebKit veta la navegación.
    static let webEditorName = "vscode.dev"
    static let webEditorURL = "https://vscode.dev"

    /// Atribución. Reconocer la marca y **negar la afiliación** de forma
    /// explícita es lo que evita el rechazo por la guía 5.2.1 de la App Store:
    /// decir solo "powered by Visual Studio Code" puede leerse como respaldo
    /// de Microsoft, que es justo lo que la revisión penaliza.
    static let attribution = """
    BosonCode is an independent client for code-server. \
    Visual Studio Code is a trademark of Microsoft Corporation. \
    Not affiliated with or endorsed by Microsoft.
    """
}

/// Marco de la tarjeta: fondo, borde y —si el equipo tiene contenedores— la
/// sección plegable debajo, ya fuera del área que conecta al tocar.
private struct CardChrome<Nested: View>: ViewModifier {
    let active: Bool
    let fill: Color
    let stroke: Color
    @ViewBuilder let nested: Nested

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content.padding(20)
            nested
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(active ? Color.green.opacity(0.4) : stroke, lineWidth: 1.5)
        )
    }
}

/// Pantalla de inicio: tarjetas con las computadoras guardadas y detectadas.
struct LauncherView: View {
    @ObservedObject var store: ServerStore
    @StateObject private var discovery = ServerDiscovery()
    var canClose: Bool
    var onConnect: (Server) -> Void

    @State private var editorTarget: EditorTarget?
    @State private var machinesTarget: Server?
    @State private var reachable: [UUID: Bool] = [:]
    /// Ventana inicial en la que el aviso de búsqueda tiene sentido
    @State private var scanning = true
    /// Equipos con sus contenedores desplegados
    @State private var expanded: Set<UUID> = []
    /// Equipo que se está renombrando
    @State private var renaming: Server?
    @State private var renameText = ""
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.auto.rawValue
    /// La guía se enseña una sola vez; luego queda en el pie por si acaso
    @AppStorage("bosonWelcomeSeen") private var welcomeSeen = false
    @State private var showWelcome = false
    @State private var showTerminalSettings = false
    @Environment(\.colorScheme) private var scheme

    private var isDark: Bool { scheme == .dark }
    private var cardFill: Color { isDark ? .white.opacity(0.06) : .black.opacity(0.04) }
    private var cardStroke: Color { isDark ? .white.opacity(0.10) : .black.opacity(0.08) }

    private enum EditorTarget: Identifiable {
        case new
        case prefilled(Server)
        case edit(Server)
        var id: String {
            switch self {
            case .new: return "new"
            case .prefilled(let s): return "pre-\(s.id.uuidString)"
            case .edit(let s): return s.id.uuidString
            }
        }
    }

    private var newDiscoveries: [DiscoveredServer] {
        discovery.found.filter { d in
            !store.servers.contains { $0.urlString == d.urlString }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 20)]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Grafito neutro, sin tinte de color. `systemGray6` es el gris de
            // fondo del propio sistema, así que se adapta solo a claro/oscuro
            // y encaja con los materiales nativos.
            Color(uiColor: .systemGray6)
                .ignoresSafeArea()
            // velo muy tenue arriba: da profundidad de ventana sin ensuciar
            // el gris con un color
            LinearGradient(
                colors: [Color.white.opacity(isDark ? 0.045 : 0.55), .clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 36) {
                    header
                    LazyVGrid(columns: columns, spacing: 20) {
                        // Solo equipos: sus contenedores van DENTRO de la
                        // tarjeta, no sueltos como si fueran otro ordenador.
                        ForEach(store.hosts) { host in
                            savedCard(host)
                        }
                        // contenedores cuyo equipo no está guardado: sin esto
                        // desaparecerían de la pantalla
                        ForEach(store.orphanMachines) { machine in
                            savedCard(machine)
                        }
                        ForEach(newDiscoveries) { d in
                            discoveredCard(d)
                        }
                        addCard
                        webEditorCard
                    }
                    .padding(.horizontal, 40)

                    // Solo mientras la búsqueda tiene sentido. Antes se
                    // mostraba siempre que no hubiera equipos NUEVOS, es decir,
                    // de forma permanente en cuanto guardabas el tuyo: parecía
                    // atascado en "buscando" con todo ya encontrado.
                    if newDiscoveries.isEmpty, scanning {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Scanning for devices…")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                    }

                    footer
                }
                .padding(.vertical, 60)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }

            if canClose {
                Button {
                    onConnectActive()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(.primary.opacity(0.08), in: Circle())
                }
                .padding(20)
            }
        }
        .overlay(alignment: .topLeading) {
            // selector de modo claro / oscuro / automático
            Menu {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    Button {
                        appearanceRaw = mode.rawValue
                    } label: {
                        if mode.rawValue == appearanceRaw {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Label(mode.label, systemImage: mode.icon)
                        }
                    }
                }
                Divider()
                Button {
                    showTerminalSettings = true
                } label: {
                    Label("Aspecto del terminal…", systemImage: "paintpalette")
                }
            } label: {
                Image(systemName: (AppearanceMode(rawValue: appearanceRaw) ?? .auto).icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(.primary.opacity(0.08), in: Circle())
            }
            .padding(20)
        }
        .onAppear {
            discovery.start()
            checkReachability()
            if !welcomeSeen { showWelcome = true }
        }
        .alert("Nombre del equipo",
               isPresented: Binding(get: { renaming != nil },
                                    set: { if !$0 { renaming = nil } })) {
            TextField("Ej.: Portátil del laboratorio", text: $renameText)
            Button("Guardar") {
                if let server = renaming { store.rename(server, to: renameText) }
                renaming = nil
            }
            Button("Cancelar", role: .cancel) { renaming = nil }
        } message: {
            Text("Solo cambia cómo lo ves aquí; el equipo sigue anunciándose con su nombre.")
        }
        .sheet(isPresented: $showTerminalSettings) { TerminalSettingsView() }
        .sheet(isPresented: $showWelcome) {
            WelcomeGuide {
                welcomeSeen = true
                showWelcome = false
            }
            .presentationDetents([.large])
        }
        // La búsqueda sigue viva mientras esta pantalla esté abierta —los
        // equipos que se enciendan después aparecen solos—, pero el aviso solo
        // acompaña a los primeros segundos, que es cuando informa de algo.
        .task(id: store.servers.count) {
            scanning = true
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation { scanning = false }
        }
        .onDisappear { discovery.stop() }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new:
                ServerEditorView(store: store, server: nil) { onConnect($0) }
            case .prefilled(let s), .edit(let s):
                ServerEditorView(store: store, server: s) { onConnect($0) }
            }
        }
        .sheet(item: $machinesTarget) { server in
            DockerMachinesView(server: server, store: store) { onConnect($0) }
        }
    }

    private func onConnectActive() {
        if let active = store.active { onConnect(active) }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("BosonCode")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    /// Pie de página: guía de instalación, atribución y copyright.
    private var footer: some View {
        VStack(spacing: 18) {
            // `Link` abre Safari sin pasar por UIApplication.open, así que no
            // toca ninguna lógica de la vista
            HStack(spacing: 10) {
                Button {
                    showWelcome = true
                } label: {
                    Label("How it works", systemImage: "sparkles")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)

            Link(destination: BosonCodeInfo.setupGuideURL) {
                Label("Host Setup Guide", systemImage: "arrow.up.forward.square")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.cyan.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(.cyan.opacity(0.25), lineWidth: 1))
            }
            .accessibilityHint("Opens the setup instructions for Tailscale and serve.sh")
            }

            Divider()
                .frame(maxWidth: 420)
                .opacity(0.5)

            VStack(spacing: 6) {
                Text(BosonCodeInfo.attribution)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                Text(BosonCodeInfo.copyright)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 40)
    }

    /// Contenedores de este equipo, plegables dentro de su propia tarjeta.
    @ViewBuilder
    private func nestedMachines(_ host: Server) -> some View {
        let machines = store.machines(of: host)
        if !machines.isEmpty {
            let open = expanded.contains(host.id)
            VStack(spacing: 0) {
                Divider().opacity(0.4)
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if open { expanded.remove(host.id) } else { expanded.insert(host.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                            .rotationEffect(.degrees(open ? 90 : 0))
                        Text(machines.count == 1 ? "1 container" : "\(machines.count) containers")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if open {
                    VStack(spacing: 6) {
                        ForEach(machines) { machine in
                            machineRow(machine, host: host)
                        }
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// Fila de un contenedor: nombre corto, sin repetir el del equipo.
    private func machineRow(_ machine: Server, host: Server) -> some View {
        let short = machine.name.components(separatedBy: " · ").first ?? machine.name
        return Button { onConnect(machine) } label: {
            HStack(spacing: 9) {
                Image(systemName: "shippingbox.fill")
                    .font(.caption)
                    .foregroundStyle(.cyan)
                Text(short)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if machine.id == store.activeID {
                    Circle().fill(.green).frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(machine.id == store.activeID ? Color.green.opacity(0.12)
                                                     : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { renaming = machine; renameText = machine.name } label: {
                Label("Rename…", systemImage: "character.cursor.ibeam")
            }
            Button { machinesTarget = host } label: {
                Label("Manage…", systemImage: "shippingbox")
            }
            Button(role: .destructive) { store.delete(machine) } label: {
                Label("Remove card", systemImage: "minus.circle")
            }
        }
    }

    private func savedCard(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                let platform = HostPlatform.resolve(os: server.os, name: server.name)
                Image(systemName: platform.symbol)
                    .font(.system(size: 34))
                    .frame(width: 40, height: 40)          // ancho fijo: los símbolos
                    .foregroundStyle(                       // no miden lo mismo
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .accessibilityLabel(platform.label)
                Spacer()
                statusDot(for: server)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(server.urlString
                        .replacingOccurrences(of: "https://", with: "")
                        .replacingOccurrences(of: "http://", with: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                if server.id == store.activeID {
                    Text("CONNECTED")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.green.opacity(0.15), in: Capsule())
                }
                Spacer()
                if server.managerURL != nil {
                    Button {
                        machinesTarget = server
                    } label: {
                        Label("Machines", systemImage: "shippingbox")
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.cyan.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // El toque de conectar cubre la cabecera, NO la tarjeta entera: si no,
        // pulsar un contenedor anidado conectaría con el equipo.
        .contentShape(Rectangle())
        .onTapGesture { onConnect(server) }
        .overlay(alignment: .bottom) { EmptyView() }
        .modifier(CardChrome(active: server.id == store.activeID,
                             fill: cardFill, stroke: cardStroke) {
            nestedMachines(server)
        })
        .contextMenu {
            Button { renaming = server; renameText = server.name } label: {
                Label("Rename…", systemImage: "character.cursor.ibeam")
            }
            Button { editorTarget = .edit(server) } label: {
                Label("Edit", systemImage: "pencil")
            }
            // misma pantalla, pero visible para quien busca "cambiar la clave"
            Button { editorTarget = .edit(server) } label: {
                Label("Change password…", systemImage: "key.horizontal")
            }
            if server.managerURL != nil {
                Button { machinesTarget = server } label: {
                    Label("Docker machines", systemImage: "shippingbox")
                }
            }
            Button(role: .destructive) { store.delete(server) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func discoveredCard(_ d: DiscoveredServer) -> some View {
        Button {
            editorTarget = .prefilled(Server(name: d.name, urlString: d.urlString, os: d.os))
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    let platform = HostPlatform.resolve(os: d.os, name: d.name)
                    Image(systemName: platform.symbol)
                        .font(.system(size: 34))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(platform.label)
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.cyan)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(d.name)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Found on your network — tap to add")
                        .font(.caption)
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.cyan.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.cyan.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7]))
            )
        }
        .buttonStyle(.plain)
    }

    /// Atajo a vscode.dev: editar sin equipo propio. Sin terminal ni máquinas,
    /// porque detrás no hay ningún serve.sh.
    private var webEditorCard: some View {
        Button {
            let existing = store.servers.first { $0.urlString == BosonCodeInfo.webEditorURL }
            let target = existing ?? Server(name: BosonCodeInfo.webEditorName,
                                            urlString: BosonCodeInfo.webEditorURL)
            if existing == nil { store.upsert(target, password: "") }
            onConnect(target)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: "globe")
                        .font(.system(size: 34))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try vscode.dev")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Text("No machine needed — editor only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(cardFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(cardStroke, style: StrokeStyle(lineWidth: 1.5, dash: [7]))
            )
        }
        .buttonStyle(.plain)
    }

    private var addCard: some View {
        Button {
            editorTarget = .new
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Add manually")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(cardFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(cardStroke,
                            style: StrokeStyle(lineWidth: 1.5, dash: [7]))
            )
        }
        .buttonStyle(.plain)
    }

    private func statusDot(for server: Server) -> some View {
        Circle()
            .fill(reachable[server.id] == true ? Color.green
                  : reachable[server.id] == false ? Color.orange
                  : Color.gray.opacity(0.5))
            .frame(width: 10, height: 10)
    }

    private func checkReachability() {
        for server in store.servers {
            guard let url = server.url else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 4
            URLSession.shared.dataTask(with: request) { _, response, _ in
                // antes cualquier respuesta pintaba verde, incluido el 502 de
                // un proxy sin backend detrás
                let ok = (response as? HTTPURLResponse).map { (200..<400).contains($0.statusCode) } ?? false
                DispatchQueue.main.async {
                    reachable[server.id] = ok
                }
            }.resume()
        }
    }
}
