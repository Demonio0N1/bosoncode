import SwiftUI

/// Conectar por SSH a otra máquina de la red.
///
/// Quien ejecuta `ssh` es el equipo al que ya estás conectado, no el iPad.
/// Eso da gratis lo que un cliente SSH propio costaría meses: claves, agente,
/// `known_hosts`, teclado-interactivo y `~/.ssh/config` con sus alias y saltos.
/// Y la contraseña, si hace falta, la pide `ssh` dentro del terminal — la app
/// nunca la ve ni la guarda.
struct SSHConnectView: View {
    let server: Server
    var onConnect: (String) -> Void

    @AppStorage("sshRecentTargets") private var recentRaw = ""
    @State private var target = ""
    @Environment(\.dismiss) private var dismiss

    private var recents: [String] {
        recentRaw.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private var clean: String {
        target.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("usuario@servidor", text: $target)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { connect() }
                } header: {
                    Text("Destino")
                } footer: {
                    Text("Añade `:puerto` si no es el 22 — por ejemplo `itachi@10.0.0.5:2222`. También valen los alias de tu `~/.ssh/config`.")
                }

                if !recents.isEmpty {
                    Section {
                        ForEach(recents, id: \.self) { recent in
                            Button {
                                target = recent
                                connect()
                            } label: {
                                Label(recent, systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(.primary)
                            }
                        }
                        .onDelete { offsets in
                            var list = recents
                            list.remove(atOffsets: offsets)
                            recentRaw = list.joined(separator: "\n")
                        }
                    } header: {
                        Text("Recientes")
                    }
                }

                Section {
                    Label("Salta desde \(server.name)", systemImage: "arrow.turn.down.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Ese equipo debe alcanzar al destino y tener permiso: si usa clave, la clave vive allí, no en el iPad. Si pide contraseña, te la pedirá el propio terminal.")
                }
            }
            .navigationTitle("Conectar por SSH")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conectar") { connect() }
                        .disabled(clean.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func connect() {
        guard !clean.isEmpty else { return }
        // el más reciente primero, sin repetidos y con tope de ocho
        var list = recents.filter { $0 != clean }
        list.insert(clean, at: 0)
        recentRaw = list.prefix(8).joined(separator: "\n")

        onConnect(clean)
        dismiss()
    }
}
