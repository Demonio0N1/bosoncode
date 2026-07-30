import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case auto, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .auto: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .auto: return "Automático"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var store = ServerStore.shared
    @State private var showLauncher = true
    @State private var loadError: String?
    @State private var reloadToken = UUID()
    @State private var downloadToast: String?
    @State private var toastToken = UUID()
    @State private var editorDropTargeted = false
    @State private var showFilePicker = false
    /// Selección propia de ESTA ventana. Al ser un @StateObject, cada escena
    /// crea la suya: es lo que hace que dos ventanas puedan mirar máquinas
    /// distintas sin pisarse.
    @StateObject private var session = WindowSession()
    @State private var showTerminal = false
    /// Último terminal abierto, para descartar disparos duplicados del atajo
    @State private var lastTerminalOpen = Date.distantPast
    @State private var showSSH = false
    /// Archivo que ZeroSpin pidió abrir (llega por bosoncode://)
    @State private var pendingFile: String?
    /// Segundos esperando, solo para ajustar el mensaje
    @State private var connectingSeconds = 0
    @State private var connecting = true
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.auto.rawValue
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openWindow) private var openWindow

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some View {
        ZStack {
            (systemScheme == .dark ? Color.black : Color(white: 0.96))
                .ignoresSafeArea()

            if let server = session.active, let url = editorURL(for: server) {
                CodeWebView(
                    url: url,
                    dataStoreID: server.id,
                    server: server,
                    interfaceStyle: appearance.interfaceStyle,
                    password: Keychain.password(for: server.id),
                    onOpenSettings: { withAnimation { showLauncher = true } },
                    onLoadError: { loadError = $0 },
                    onPasswordEntered: { pw in
                        Keychain.setPassword(pw, for: server.id)
                    },
                    onDownload: { filename in
                        showToast("Guardado en Archivos › iVsCode › Descargas: \(filename)")
                    },
                    onFileCopy: {
                        // el WebView ya disparó Copy Path; la ruta llega vía
                        // ClipboardBridge a UIPasteboard
                        let path = (UIPasteboard.general.string ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if path.hasPrefix("/"), !path.contains("\n") {
                            Task { await fileCopy(path: path, server: server) }
                        } else {
                            showToast("Selecciona el archivo en el explorador y pulsa ⌃⌥C de nuevo")
                        }
                    },
                    onFilePaste: {
                        Task { await filePaste(server: server) }
                    },
                    onTerminalToggle: {
                        // Este camino es el que funciona con el foco DENTRO del
                        // editor: ahí la página web se queda la tecla y el
                        // atajo de la ventana no llega a verla.
                        openTerminalWindow(for: server)
                    },
                    onLoading: { stillOnLogin in
                        withAnimation { connecting = stillOnLogin }
                        // El archivo que mandó ZeroSpin ya está abierto: se
                        // olvida. Si se quedara puesto, CUALQUIER recarga
                        // posterior —reconectar, cambiar de máquina— volvería a
                        // pedir esa misma ruta, en un equipo donde puede que ni
                        // exista.
                        if !stillOnLogin { pendingFile = nil }
                    }
                )
                // incluir la URL en la identidad: si una tarjeta se repara
                // (URL nueva), el WebView se recrea sí o sí
                .id("\(server.id.uuidString)-\(server.urlString)-\(reloadToken.uuidString)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // el teclado en pantalla no debe encoger el editor: VS Code
                // gestiona su propio desplazamiento
                .ignoresSafeArea(.all)
                // arrastrar archivos del iPad al editor: se suben a la carpeta
                // de trabajo de la sesión
                .onDrop(of: ["public.data"], isTargeted: $editorDropTargeted) { providers in
                    uploadDropped(providers, to: server)
                }
                .overlay(alignment: .center) {
                    if editorDropTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.cyan, style: StrokeStyle(lineWidth: 4, dash: [12]))
                            .background(Color.cyan.opacity(0.07))
                            .overlay(
                                Label("Soltar para subir a \(server.name)",
                                      systemImage: "arrow.down.doc.fill")
                                    .font(.title3.bold())
                                    .foregroundStyle(.cyan))
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }

                if !showLauncher {
                    // botón flotante: toque = lista de PCs; mantener pulsado =
                    // copiar/pegar archivos entre sesiones
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Menu {
                                Button {
                                    TerminalScene.open(serverID: server.id)
                                } label: {
                                    Label("Terminal en ventana propia (⌃⌥T)",
                                          systemImage: "macwindow.on.rectangle")
                                }
                                Button {
                                    withAnimation { showTerminal.toggle() }
                                } label: {
                                    Label(showTerminal ? "Cerrar panel dentro de la app"
                                                       : "Terminal dentro de la app",
                                          systemImage: "terminal")
                                }
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("Explorar archivos (copiar o arrastrar fuera)",
                                          systemImage: "folder")
                                }
                                Button {
                                    Task { await filePaste(server: server) }
                                } label: {
                                    Label("Pegar aquí (⌃⌥V)",
                                          systemImage: "doc.on.clipboard")
                                }
                            } label: {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 42, height: 42)
                                    .background(.black.opacity(0.45), in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.15)))
                            } primaryAction: {
                                withAnimation { showLauncher = true }
                            }
                            .padding(.trailing, 8)
                            .padding(.bottom, 12)

                            // Botón propio del terminal: un toque y listo. La
                            // entrada del menú seguía existiendo, pero estaba a
                            // dos toques y no se encontraba.
                            Button {
                                openTerminalWindow(for: server)
                            } label: {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .frame(width: 42, height: 42)
                                    .background(.black.opacity(0.45), in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.15)))
                            }
                            .contextMenu {
                                Button {
                                    withAnimation { showTerminal.toggle() }
                                } label: {
                                    Label(showTerminal ? "Cerrar panel dentro de la app"
                                                       : "Abrir dentro de la app",
                                          systemImage: "rectangle.inset.filled")
                                }
                                Button {
                                    showSSH = true
                                } label: {
                                    Label("Conectar por SSH…", systemImage: "network")
                                }
                                Divider()
                                Button {
                                    openWindow(id: MainScene.id)
                                } label: {
                                    Label("Nueva ventana", systemImage: "macwindow.badge.plus")
                                }
                            }
                            .padding(.trailing, 12)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }

            if showTerminal, let server = session.active {
                // en Slide Over (ancho compacto) la terminal ocupa todo:
                // la app se convierte en una terminal pura sobre otras apps
                FloatingTerminal(server: server,
                                 fullscreen: horizontalSizeClass == .compact) {
                    withAnimation { showTerminal = false }
                }
                .id("term-\(server.id.uuidString)")
                // al abrir "Mis PCs" solo se OCULTA: si se desmontara, moriría
                // la sesión del shell y se perdería el scrollback
                .opacity(showLauncher ? 0 : 1)
                .allowsHitTesting(!showLauncher)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            if connecting, !showLauncher, loadError == nil, let server = session.active {
                connectingOverlay(server.name)
            }

            if let error = loadError, !showLauncher {
                errorOverlay(error)
            }

            if let toast = downloadToast {
                VStack {
                    Label(toast, systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.green.opacity(0.85), in: Capsule())
                        .padding(.top, 18)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Sin equipo no hay nada que enseñar: si el que miraba esta ventana
            // se borró desde otra, se vuelve a la lista en vez de quedarse en
            // una pantalla vacía.
            if showLauncher || session.active == nil {
                LauncherView(
                    store: store,
                    session: session,
                    canClose: session.active != nil,
                    onConnect: { server in
                        let sameServer = session.activeID == server.id
                        // cambiar de equipo descarta el archivo pendiente: es
                        // una ruta del equipo anterior
                        if !sameServer { pendingFile = nil }
                        session.select(server.id)
                        // tocar el MISMO servidor tras un error también debe
                        // recargar (antes se quedaba con el overlay de error)
                        if !sameServer || loadError != nil {
                            loadError = nil
                            connecting = true      // pantalla "Conectando…"
                            reloadToken = UUID()
                        }
                        withAnimation { showLauncher = false }
                    }
                )
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showSSH) {
            if let server = session.active {
                SSHConnectView(server: server) { target in
                    TerminalScene.open(serverID: server.id, sshTarget: target)
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            if let server = session.active {
                FilePickerView(server: server) { path in
                    Task { await fileCopy(path: path, server: server) }
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        // ZeroSpin manda aquí los archivos que quiere ejecutar: sube el
        // archivo al equipo y nos pasa su ruta.
        .onOpenURL { incoming in
            guard incoming.scheme == "bosoncode",
                  let comps = URLComponents(url: incoming, resolvingAgainstBaseURL: false)
            else { return }
            let items = comps.queryItems ?? []
            if let raw = items.first(where: { $0.name == "server" })?.value,
               let id = UUID(uuidString: raw),
               store.servers.contains(where: { $0.id == id }) {
                session.select(id)
            }
            pendingFile = items.first(where: { $0.name == "file" })?.value
            withAnimation { showLauncher = false }
            reloadToken = UUID()          // recarga con ?file=
        }
        // ⌃⌥T a nivel de VENTANA, no del editor.
        //
        // Antes vivía como UIKeyCommand dentro del WKWebView, que solo los
        // recibe teniendo el foco: nada más entrar en una máquina, sin haber
        // tocado el editor, el atajo no hacía nada. Aquí responde desde el
        // primer instante, y comparte camino con el botón para que los dos
        // hagan exactamente lo mismo.
        .background(
            Button("") {
                if let server = session.active, !showLauncher {
                    openTerminalWindow(for: server)
                }
            }
            .keyboardShortcut("t", modifiers: [.control, .option])
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    /// Pantalla nativa mientras el auto-login trabaja: la página de login de
    /// code-server queda oculta y esto es lo único visible.
    private func connectingOverlay(_ name: String) -> some View {
        ZStack {
            LinearGradient(
                colors: systemScheme == .dark
                    ? [Color(red: 0.04, green: 0.05, blue: 0.10),
                       Color(red: 0.08, green: 0.10, blue: 0.20)]
                    : [Color(red: 0.93, green: 0.94, blue: 0.97),
                       Color(red: 0.85, green: 0.88, blue: 0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Conectando a \(name)…")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                // Barra continua, no un círculo: una línea que avanza deja
                // claro que la app sigue trabajando, y aquí la espera puede
                // ser larga si el equipo está por relé.
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.cyan)
                    .frame(maxWidth: 260)

                Text(elapsedHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)

                Button {
                    cancelConnection()
                } label: {
                    Label("Cancelar", systemImage: "xmark.circle")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .padding(.top, 4)
            }
        }
        .transition(.opacity)
        .task(id: reloadToken) {
            connectingSeconds = 0
            // El contador y la espera comparten bucle a propósito.
            //
            // Antes el contador vivía en un `Task { }` suelto dentro de este.
            // Una tarea así NO es hija de la que la crea: cancelar la vista no
            // la cancelaba, su `Task.isCancelled` nunca era cierto y el bucle
            // seguía despertando cada segundo para siempre. Cada intento de
            // conexión dejaba uno más vivo.
            //
            // Diez vueltas son también la red de seguridad: si en 10s no llegó
            // el workbench (contraseña mala, por ejemplo), se enseña lo que haya.
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // la vista se retiró: no tocar el estado, o la pantalla
                // "Conectando…" desaparecería antes de tiempo
                guard !Task.isCancelled else { return }
                connectingSeconds += 1
            }
            withAnimation { connecting = false }
        }
    }

    /// Aviso que aparece cuando la espera se alarga, para que el usuario sepa
    /// que puede irse en vez de quedarse mirando.
    private var elapsedHint: String {
        connectingSeconds < 8 ? "Autenticando…"
            : "Está tardando. Comprueba que el equipo esté encendido y en la red."
    }

    /// Corta el intento y vuelve a la lista de equipos.
    ///
    /// Se cambia la identidad de la vista web (`reloadToken`) para que SwiftUI
    /// la destruya: es lo que aborta de verdad la carga en curso, en lugar de
    /// dejarla trabajando detrás de la pantalla.
    private func cancelConnection() {
        connecting = false
        loadError = nil
        pendingFile = nil
        reloadToken = UUID()
        withAnimation { showLauncher = true }
    }

    /// URL del editor, con el archivo que se pidió abrir si lo hay.
    ///
    /// code-server acepta `?file=` para abrir un archivo concreto al cargar;
    /// así ZeroSpin puede mandar un notebook al equipo y que aparezca abierto,
    /// sin que el usuario tenga que buscarlo en el explorador.
    private func editorURL(for server: Server) -> URL? {
        guard let base = server.url else { return nil }
        guard let file = pendingFile, !file.isEmpty else { return base }

        // Cargar directamente `/?file=…` NO funciona: code-server redirige al
        // login y, tras autenticarse, vuelve a `/` perdiendo la consulta — el
        // archivo llegaba al equipo pero el editor abría vacío. La vía es
        // pasar por el login con `?to=`, que sí se respeta tras autenticar.
        var login = URLComponents(url: base.appendingPathComponent("login"),
                                  resolvingAgainstBaseURL: false)
        login?.queryItems = [URLQueryItem(name: "to", value: "/?file=" + file)]
        return login?.url ?? base
    }

    /// Abre el terminal como ventana propia de iPadOS.
    ///
    /// Hay tres caminos hasta aquí y los tres hacen falta:
    ///   · el botón flotante,
    ///   · el UIKeyCommand del editor —el único que ve la tecla cuando el foco
    ///     está dentro de la página web, que se la queda—,
    ///   · el atajo de la ventana, que responde cuando el editor NO tiene el
    ///     foco: nada más entrar en una máquina, por ejemplo.
    ///
    /// Con el foco en el editor pueden dispararse dos a la vez, así que se
    /// ignoran los disparos repetidos: si no, ⌃⌥T abriría dos terminales.
    private func openTerminalWindow(for server: Server) {
        let now = Date()
        guard now.timeIntervalSince(lastTerminalOpen) > 0.6 else { return }
        lastTerminalOpen = now
        TerminalScene.open(serverID: server.id)
    }

    private func showToast(_ message: String) {
        // token de generación: un toast nuevo no debe ser borrado por el
        // temporizador del anterior
        let token = UUID()
        toastToken = token
        withAnimation { downloadToast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            guard toastToken == token else { return }
            withAnimation { downloadToast = nil }
        }
    }

    /// Sube al servidor los archivos arrastrados desde Archivos/Fotos.
    private func uploadDropped(_ providers: [NSItemProvider], to server: Server) -> Bool {
        guard let client = manager(for: server) else {
            showToast("Este servidor no admite subir archivos")
            return false
        }
        let machine = server.dockerMachineName
        for provider in providers {
            provider.loadDataRepresentation(forTypeIdentifier: "public.data") { data, _ in
                guard let data else { return }
                let name = provider.suggestedName ?? "archivo"
                Task {
                    do {
                        let dest = try await client.upload(data: data, filename: name,
                                                           machine: machine, dest: "@cwd")
                        await MainActor.run { showToast("Subido: \(name) → \(dest)") }
                    } catch {
                        await MainActor.run {
                            showToast("Error subiendo \(name): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
        return true
    }

    private func manager(for server: Server) -> ManagerClient? {
        guard let mgrURL = server.managerURL,
              let pw = ServerStore.shared.hostPassword(for: server) else { return nil }
        return ManagerClient(baseURL: mgrURL, password: pw)
    }

    /// ⌃⌥C: el usuario eligió una ruta en el explorador nativo → se copia al
    /// portapapeles de archivos del PC (docker cp si la sesión es una máquina)
    private func fileCopy(path: String, server: Server) async {
        guard let client = manager(for: server) else {
            showToast("Este servidor no soporta copiar archivos entre sesiones")
            return
        }
        do {
            let (files, _) = try await client.clipboard(op: "copy", path: path,
                                                        machine: server.dockerMachineName)
            showToast("Copiado: \(files.joined(separator: ", ")) — usa ⌃⌥V en otra sesión")
        } catch {
            showToast("Error: \(error.localizedDescription)")
        }
    }

    /// ⌃⌥V: pega en la carpeta seleccionada de la sesión (el WebView ya capturó
    /// la selección al portapapeles); sin selección válida, en la de inicio
    private func filePaste(server: Server) async {
        guard let client = manager(for: server) else {
            showToast("Este servidor no soporta pegar archivos entre sesiones")
            return
        }
        let dest = (UIPasteboard.general.string ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let (files, target) = try await client.clipboard(
                op: "paste",
                dest: dest.hasPrefix("/") && !dest.contains("\n") ? dest : nil,
                machine: server.dockerMachineName
            )
            showToast("Pegado en \(target): \(files.joined(separator: ", "))")
        } catch {
            showToast("Error: \(error.localizedDescription)")
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Sin conexión con \(session.active?.name ?? "el backend")")
                .font(.title3.bold())
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Reintentar") {
                    loadError = nil
                    reloadToken = UUID()
                }
                .buttonStyle(.borderedProminent)
                Button("Mis PCs") { withAnimation { showLauncher = true } }
                    .buttonStyle(.bordered)
            }
            // Una máquina borrada en el equipo deja su tarjeta huérfana: la
            // ruta /m-<n>/ desaparece del proxy, la petición cae en el editor
            // raíz y responde 401. El mensaje no dice nada, así que se ofrece
            // la salida aquí mismo.
            if let active = session.active, active.isDockerMachine {
                Divider().frame(maxWidth: 260)
                Text("Si borraste esta máquina en el equipo, su tarjeta ya no lleva a ninguna parte.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(role: .destructive) {
                    store.delete(active)
                    loadError = nil
                    withAnimation { showLauncher = true }
                } label: {
                    Label("Quitar esta máquina", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
