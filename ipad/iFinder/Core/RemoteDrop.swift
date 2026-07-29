import Foundation

/// Arrastres que vienen del editor remoto.
///
/// VS Code no entrega un archivo cuando arrastras desde su explorador: entrega
/// una URL con esquema `vscode-remote://<autoridad>/<ruta>`. No es un archivo
/// local, así que `FileManager` la rechaza con
/// "URL type vscode-remote isn't supported" — el error que veía el usuario.
///
/// La solución es traerse el contenido por la misma API que ya usa la app para
/// descargar archivos del equipo, dejarlo en el directorio temporal y seguir
/// trabajando con esa ruta local.
enum RemoteDrop {
    enum Failure: LocalizedError {
        case unsupported(String)
        case noServer

        var errorDescription: String? {
            switch self {
            case .unsupported(let scheme):
                return "No sé traer archivos de tipo \(scheme)."
            case .noServer:
                return "No hay ningún equipo conectado del que descargar el archivo. Abre BosonCode y conéctate primero."
            }
        }
    }

    /// Descarga el archivo remoto y devuelve su copia local.
    static func materialize(_ url: URL) async throws -> URL {
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "vscode-remote" || scheme == "vscode" else {
            throw Failure.unsupported(scheme.isEmpty ? "desconocido" : scheme)
        }

        // vscode-remote://<autoridad>/home/itachi/1.ipynb → /home/itachi/1.ipynb
        let path = url.path.removingPercentEncoding ?? url.path
        guard !path.isEmpty, path != "/" else { throw Failure.unsupported("vscode-remote") }

        let (client, machine) = try await MainActor.run { try Self.clientForDrop() }
        let data = try await client.download(path: path, machine: machine)

        let name = (path as NSString).lastPathComponent
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("remoto-\(UUID().uuidString.prefix(6))-\(name)")
        try data.write(to: copy, options: .atomic)
        return copy
    }

    /// Equipo del que descargar: el activo en BosonCode, que ZeroSpin comparte.
    @MainActor
    private static func clientForDrop() throws -> (ManagerClient, String) {
        let store = ServerStore.shared
        let candidates = [store.active].compactMap { $0 } + store.servers
        for server in candidates {
            if let url = server.managerURL,
               let password = store.hostPassword(for: server) {
                return (ManagerClient(baseURL: url, password: password),
                        server.dockerMachineName)
            }
        }
        throw Failure.noServer
    }
}
