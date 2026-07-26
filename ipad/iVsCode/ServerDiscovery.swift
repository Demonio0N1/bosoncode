import Foundation
import Network

struct DiscoveredServer: Identifiable, Equatable {
    let id: String
    let name: String
    let host: String
    let port: Int
    /// URL HTTPS canónica anunciada en el TXT (`url=`) — los notebooks/webviews
    /// de VS Code exigen contexto seguro, así que se prefiere siempre.
    let canonicalURL: String?

    var urlString: String { canonicalURL ?? "http://\(host):\(port)" }
}

/// Busca equipos anunciando _ivscode._tcp (los que corren serve.sh) y
/// resuelve cada servicio a host:puerto.
@MainActor
final class ServerDiscovery: ObservableObject {
    @Published var found: [DiscoveredServer] = []
    private var browser: NWBrowser?
    private var resolvers: [NWConnection] = []

    func start() {
        stop()
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_ivscode._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.resolve(results) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        resolvers.forEach { $0.cancel() }
        resolvers = []
        found = []
    }

    deinit {
        browser?.cancel()
        resolvers.forEach { $0.cancel() }
    }

    private func resolve(_ results: Set<NWBrowser.Result>) {
        // se reconcilia en vez de vaciar: antes las tarjetas desaparecían y
        // reaparecían con cada evento del navegador (parpadeo)
        let names = Set(results.compactMap { result -> String? in
            if case let .service(name, _, _, _) = result.endpoint { return name }
            return nil
        })
        found.removeAll { !names.contains($0.name) }
        resolvers.forEach { $0.cancel() }
        resolvers = []

        for result in results {
            guard case let .service(name, _, _, _) = result.endpoint else { continue }
            var canonical: String?
            if case let .bonjour(txt) = result.metadata,
               let url = txt.dictionary["url"], !url.isEmpty {
                canonical = url
            }
            // conexión efímera solo para resolver el endpoint a IP:puerto
            let conn = NWConnection(to: result.endpoint, using: .tcp)
            resolvers.append(conn)
            conn.stateUpdateHandler = { [weak self, weak conn] state in
                guard let conn else { return }
                // sin esto, un host apagado o una ruta IPv6 muerta dejaba el
                // socket colgado indefinidamente
                switch state {
                case .failed, .cancelled:
                    conn.cancel()
                    Task { @MainActor [weak self] in
                        self?.resolvers.removeAll { $0 === conn }
                    }
                    return
                case .waiting:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak conn] in
                        conn?.cancel()
                    }
                    return
                case .ready:
                    break
                default:
                    return
                }
                if let endpoint = conn.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = endpoint {
                    var hostString: String?
                    switch host {
                    case .ipv4(let addr):
                        hostString = "\(addr)"
                    case .name(let n, _):
                        hostString = n
                    default:
                        break   // IPv6 link-local: se ignora, llegará la IPv4
                    }
                    if let hostString {
                        // la interfaz puede venir pegada a la IP ("1.2.3.4%en0")
                        let clean = hostString.components(separatedBy: "%").first ?? hostString
                        let server = DiscoveredServer(
                            id: "\(name)|\(clean):\(port.rawValue)",
                            name: name,
                            host: clean,
                            port: Int(port.rawValue),
                            canonicalURL: canonical
                        )
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if !self.found.contains(server) {
                                self.found.append(server)
                            }
                        }
                    }
                }
                conn.cancel()
            }
            conn.start(queue: .main)
        }
    }
}
