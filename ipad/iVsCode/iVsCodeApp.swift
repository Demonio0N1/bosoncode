import SwiftUI

@main
struct BosonCodeApp: App {
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.auto.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some Scene {
        // Con id, `openWindow` puede pedir otra ventana igual. Cada una crea su
        // propio WindowSession, así que miran máquinas distintas sin pisarse.
        WindowGroup(id: MainScene.id) {
            ContentView()
                .ignoresSafeArea()
                .background(MainWindowUnrestrictor())
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)   // oculta el indicador de Home
                .defersSystemGestures(on: .all)      // el primer swipe de borde va a la app
        }

        // Ventana independiente: una ventana MÁS de iPadOS (aparece por separado
        // en el conmutador de apps), no un panel dentro de la ventana principal.
        WindowGroup(id: "terminal", for: UUID.self) { $serverID in
            TerminalWindowView(serverID: serverID)
                .preferredColorScheme(appearance.colorScheme)
        }
        .defaultSize(width: 620, height: 400)
        .handlesExternalEvents(matching: [TerminalScene.activityType])
    }
}

/// Crea la ventana-terminal como una ESCENA nueva de iPadOS: aparece como una
/// ventana independiente de la app (igual que arrastrar el icono para abrir una
/// segunda ventana), no como un panel dentro de la ventana actual.
enum MainScene {
    static let id = "editor"
}

enum TerminalScene {
    static let activityType = "com.garyguaman.ivscode.terminal"

    /// Abre una terminal nueva. Cada llamada genera su propio identificador de
    /// sesión, que es lo que hace que dos ventanas del MISMO equipo tengan
    /// shells independientes en lugar de compartir uno espejado.
    static func open(serverID: UUID,
                     sessionID: String = String(UUID().uuidString.prefix(8)).lowercased(),
                     sshTarget: String = "") {
        let activity = NSUserActivity(activityType: activityType)
        activity.targetContentIdentifier = activityType
        activity.userInfo = ["serverID": serverID.uuidString, "sessionID": sessionID,
                             "sshTarget": sshTarget]
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        // session: nil ⇒ SIEMPRE una ventana nueva
        UIApplication.shared.requestSceneSessionActivation(
            nil, userActivity: activity, options: options, errorHandler: nil)
    }

    /// Si no hay ninguna ventana principal (VS Code) conectada, la abre.
    static func ensureMainWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let hasMain = UIApplication.shared.connectedScenes.contains { scene in
                (scene.session.userInfo?["ivscodeRole"] as? String) == "main"
            }
            guard !hasMain else { return }
            // userActivity nil ⇒ la escena por defecto: la ventana de VS Code
            UIApplication.shared.requestSceneSessionActivation(
                nil, userActivity: nil, options: nil, errorHandler: nil)
        }
    }
}

/// Fuerza el tamaño inicial de la ventana (iPadOS abre las escenas nuevas a
/// pantalla completa si no se le dice otra cosa). Se aprieta la restricción un
/// instante para que el sistema encoja la ventana y luego se relaja, de modo
/// que puedas redimensionarla libremente después.
struct WindowSizer: UIViewRepresentable {
    let size: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard let scene = view.window?.windowScene else { return }
            // marca la escena como "terminal": la ventana principal usa esto
            // para NO heredar el tamaño pequeño
            if scene.session.userInfo == nil { scene.session.userInfo = [:] }
            scene.session.userInfo?["ivscodeRole"] = "terminal"
            guard let restrictions = scene.sizeRestrictions else { return }
            // Truco para fijar el tamaño INICIAL: iPadOS solo lo respeta si
            // mínimo y máximo coinciden. Se suelta enseguida — mientras dure,
            // la ventana no se puede redimensionar.
            restrictions.minimumSize = size
            restrictions.maximumSize = size
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                // A partir de aquí, libertad total: mínimo pequeño de verdad,
                // sin techo práctico y con pantalla completa permitida (sin
                // esto último la ventana se niega a ocupar todo).
                restrictions.minimumSize = CGSize(width: 240, height: 160)
                restrictions.maximumSize = CGSize(width: 10000, height: 10000)
                restrictions.allowsFullScreen = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// La ventana principal debe poder ocupar toda la pantalla: si una escena
/// heredó las restricciones pequeñas de una ventana-terminal, se relajan.
struct MainWindowUnrestrictor: UIViewRepresentable {
    /// Tamaño de partida del editor: amplio, como en un escritorio.
    static let standardSize = CGSize(width: 1180, height: 820)

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        for delay in [0.2, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let scene = view.window?.windowScene,
                      let restrictions = scene.sizeRestrictions else { return }
                if (scene.session.userInfo?["ivscodeRole"] as? String) == "terminal" { return }
                // marca la escena como principal para que la ventana-terminal
                // sepa que ya existe VS Code y no abra otra
                if scene.session.userInfo == nil { scene.session.userInfo = [:] }
                scene.session.userInfo?["ivscodeRole"] = "main"

                // iPadOS restaura el tamaño de la sesión anterior: si cerraste
                // la app con la ventana encogida, reabría diminuta. La ventana
                // principal debe nacer siempre cómoda, así que la primera
                // pasada la fija (mínimo == máximo, único modo de que iPadOS
                // respete un tamaño) y la segunda suelta las restricciones.
                if delay < 0.5 {
                    restrictions.minimumSize = Self.standardSize
                    restrictions.maximumSize = Self.standardSize
                } else {
                    restrictions.minimumSize = CGSize(width: 480, height: 400)
                    restrictions.maximumSize = CGSize(width: 10000, height: 10000)
                    restrictions.allowsFullScreen = true
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Contenido de la ventana-terminal independiente.
struct TerminalWindowView: View {
    let serverID: UUID?
    @StateObject private var store = ServerStore.shared
    @State private var activityServerID: UUID?
    /// Sesión propia de esta ventana. Se fija una vez y no cambia, así que al
    /// reconectar (o al volver de segundo plano) se reengancha a su shell.
    @State private var sessionID = String(UUID().uuidString.prefix(8)).lowercased()
    @State private var sshTarget = ""

    private var server: Server? {
        let id = activityServerID ?? serverID
        guard let id else { return store.active }
        return store.servers.first { $0.id == id } ?? store.active
    }

    var body: some View {
        Group {
            if let server {
                FloatingTerminal(server: server, sessionID: sessionID,
                                 sshTarget: sshTarget, fullscreen: true) {}
            } else {
                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                    Text("Sin servidor seleccionado")
                        .foregroundStyle(.secondary)
                }
            }
        }
        // antes solo se ignoraba abajo: arriba quedaba una banda del fondo de
        // la escena, que es la "línea gris" del borde superior
        .ignoresSafeArea()
        .background(WindowSizer(size: CGSize(width: 640, height: 420)))
        .onAppear {
            // iPadOS restaura la última ventana usada: si la app arranca
            // directamente en una terminal, se abre además la ventana
            // principal para no quedarse sin VS Code
            TerminalScene.ensureMainWindow()
        }
        .onContinueUserActivity(TerminalScene.activityType) { activity in
            if let raw = activity.userInfo?["serverID"] as? String,
               let id = UUID(uuidString: raw) {
                activityServerID = id
            }
            // la sesión viaja con la actividad: así la ventana restaurada por
            // iPadOS vuelve a su shell y no al de otra ventana
            if let incoming = activity.userInfo?["sessionID"] as? String, !incoming.isEmpty {
                sessionID = incoming
            }
            if let target = activity.userInfo?["sshTarget"] as? String {
                sshTarget = target
            }
        }
    }
}
