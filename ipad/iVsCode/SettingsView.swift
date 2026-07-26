import SwiftUI

struct ServerEditorView: View {
    @ObservedObject var store: ServerStore
    let server: Server?
    var onSaved: ((Server) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var urlString = ""
    @State private var password = ""
    @State private var showPassword = false

    /// `URL(string:)` acepta casi cualquier cosa ("hola" incluido): hay que
    /// exigir esquema y host o se guardan servidores que nunca cargarán.
    private var urlIsValid: Bool {
        guard let comps = URLComponents(string: urlString.trimmingCharacters(in: .whitespaces)),
              let scheme = comps.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = comps.host, !host.isEmpty else { return false }
        return true
    }

    private var isNew: Bool {
        guard let server else { return true }
        return !store.servers.contains { $0.id == server.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("PC RTX 4090", text: $name)
                }
                Section {
                    TextField("https://mi-pc.mi-tailnet.ts.net", text: $urlString)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("URL")
                } footer: {
                    Text("La que imprime `serve.sh` al arrancar (o la de `tailscale serve`).")
                }
                Section {
                    HStack {
                        if showPassword {
                            TextField("Contraseña de code-server", text: $password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Contraseña de code-server", text: $password)
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Contraseña")
                } footer: {
                    Text("Se guarda en el Llavero: la app inicia sesión sola y nunca verás la pantalla de login.")
                }
            }
            .navigationTitle(isNew ? "Nuevo servidor" : "Editar servidor")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Guardar y conectar" : "Guardar") {
                        var updated = server ?? Server(name: "", urlString: "")
                        updated.name = name.trimmingCharacters(in: .whitespaces)
                        updated.urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                        store.upsert(updated, password: password)
                        dismiss()
                        onSaved?(updated)
                    }
                    .disabled(name.isEmpty || !urlIsValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear {
                if let server {
                    name = server.name
                    urlString = server.urlString
                    password = Keychain.password(for: server.id) ?? ""
                }
                // Herencia de contraseña SOLO dentro del mismo host (las
                // máquinas Docker de un PC comparten su clave). Nunca se
                // prefila hacia un host distinto: un equipo desconocido
                // anunciándose por Bonjour recibiría tu contraseña.
                if password.isEmpty, let activeID = store.activeID,
                   let active = store.servers.first(where: { $0.id == activeID }),
                   let activeHost = URLComponents(string: active.urlString)?.host,
                   let newHost = URLComponents(string: urlString)?.host,
                   activeHost == newHost,
                   let inherited = Keychain.password(for: activeID) {
                    password = inherited
                }
            }
        }
    }
}
