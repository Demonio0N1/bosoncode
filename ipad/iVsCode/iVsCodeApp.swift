import SwiftUI

@main
struct iVsCodeApp: App {
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.auto.rawValue

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .auto
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea()
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
enum TerminalScene {
    static let activityType = "com.garyguaman.ivscode.terminal"

    static func open(serverID: UUID) {
        let activity = NSUserActivity(activityType: activityType)
        activity.targetContentIdentifier = activityType
        activity.userInfo = ["serverID": serverID.uuidString]
        let options = UIScene.ActivationRequestOptions()
        options.requestingScene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        // session: nil ⇒ SIEMPRE una ventana nueva
        UIApplication.shared.requestSceneSessionActivation(
            nil, userActivity: activity, options: options, errorHandler: nil)
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
            guard let restrictions = view.window?.windowScene?.sizeRestrictions else { return }
            restrictions.minimumSize = size
            restrictions.maximumSize = size
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                restrictions.minimumSize = CGSize(width: 320, height: 220)
                restrictions.maximumSize = CGSize(width: 4000, height: 4000)
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

    private var server: Server? {
        let id = activityServerID ?? serverID
        guard let id else { return store.active }
        return store.servers.first { $0.id == id } ?? store.active
    }

    var body: some View {
        Group {
            if let server {
                FloatingTerminal(server: server, fullscreen: true) {}
            } else {
                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                    Text("Sin servidor seleccionado")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(WindowSizer(size: CGSize(width: 640, height: 420)))
        .onContinueUserActivity(TerminalScene.activityType) { activity in
            if let raw = activity.userInfo?["serverID"] as? String,
               let id = UUID(uuidString: raw) {
                activityServerID = id
            }
        }
    }
}
