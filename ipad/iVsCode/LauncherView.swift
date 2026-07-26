import SwiftUI

/// Pantalla de inicio: tarjetas con las computadoras guardadas y detectadas.
struct LauncherView: View {
    @ObservedObject var store: ServerStore
    @StateObject private var discovery = ServerDiscovery()
    var canClose: Bool
    var onConnect: (Server) -> Void

    @State private var editorTarget: EditorTarget?
    @State private var machinesTarget: Server?
    @State private var reachable: [UUID: Bool] = [:]
    @AppStorage("appearance") private var appearanceRaw = AppearanceMode.auto.rawValue
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
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.04, green: 0.05, blue: 0.10),
                       Color(red: 0.08, green: 0.10, blue: 0.20)]
                    : [Color(red: 0.93, green: 0.94, blue: 0.97),
                       Color(red: 0.85, green: 0.88, blue: 0.95)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 36) {
                    header
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(store.servers) { server in
                            savedCard(server)
                        }
                        ForEach(newDiscoveries) { d in
                            discoveredCard(d)
                        }
                        addCard
                    }
                    .padding(.horizontal, 40)

                    if newDiscoveries.isEmpty {
                        Label("Buscando equipos con serve.sh en tu red…",
                              systemImage: "wifi")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            Text("iVsCode")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Elige una computadora")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func savedCard(_ server: Server) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue],
                                       startPoint: .top, endPoint: .bottom)
                    )
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
                    Text("CONECTADO")
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
                        Label("Máquinas", systemImage: "shippingbox")
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
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(server.id == store.activeID
                        ? Color.green.opacity(0.4)
                        : cardStroke, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { onConnect(server) }
        .contextMenu {
            Button { editorTarget = .edit(server) } label: {
                Label("Editar", systemImage: "pencil")
            }
            if server.managerURL != nil {
                Button { machinesTarget = server } label: {
                    Label("Máquinas Docker", systemImage: "shippingbox")
                }
            }
            Button(role: .destructive) { store.delete(server) } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
    }

    private func discoveredCard(_ d: DiscoveredServer) -> some View {
        Button {
            editorTarget = .prefilled(Server(name: d.name, urlString: d.urlString))
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
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
                    Text("Detectado en tu red — toca para añadir")
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

    private var addCard: some View {
        Button {
            editorTarget = .new
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Añadir manualmente")
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
