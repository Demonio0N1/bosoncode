import SwiftUI

/// Dónde ejecutar el archivo.
///
/// Se pregunta en lugar de suponer: con dos equipos y varios contenedores, "el
/// activo" rara vez es el que quieres — y el que tiene GPU no siempre es el que
/// estabas mirando.
struct RunTargetView: View {
    let name: String
    /// Qué hacer con la máquina elegida.
    ///
    /// Recibe una acción en vez del modelo del explorador para que la ventana
    /// del notebook —que es otra escena y no lo tiene— pueda usar el mismo
    /// selector. Duplicarlo habría significado dos listas de equipos que
    /// acabarían divergiendo.
    let onPick: (Server) -> Void

    @Environment(\.dismiss) private var dismiss

    private var destinations: [Server] { RunInBosonCode.destinations }
    private var hosts: [Server] { destinations.filter { !$0.isDockerMachine } }

    var body: some View {
        NavigationStack {
            Group {
                if destinations.isEmpty {
                    ContentUnavailableView(
                        "Ningún equipo disponible",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text("Abre BosonCode, conéctate a un equipo y vuelve a intentarlo."))
                } else {
                    List {
                        ForEach(hosts) { host in
                            Section {
                                row(host, label: host.name, icon: "desktopcomputer")
                                ForEach(machines(of: host)) { machine in
                                    row(machine,
                                        label: machine.name.components(separatedBy: " · ").first
                                            ?? machine.name,
                                        icon: "shippingbox.fill",
                                        indented: true)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ejecutar \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func machines(of host: Server) -> [Server] {
        destinations.filter { $0.isDockerMachine && $0.sharesHost(with: host) }
    }

    private func row(_ server: Server, label: String, icon: String,
                     indented: Bool = false) -> some View {
        Button {
            dismiss()
            onPick(server)
        } label: {
            HStack(spacing: 10) {
                if indented { Spacer().frame(width: 14) }
                Image(systemName: icon).foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).foregroundStyle(.primary)
                    // Dónde va a acabar el archivo, dicho sin rodeos.
                    Text(server.isDockerMachine ? "/root/ZeroSpin" : "~/ZeroSpin")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
