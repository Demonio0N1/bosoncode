import SwiftUI

/// Aspecto del terminal: tema y tipografía, con muestra en vivo.
///
/// La muestra no es decorativa: elegir una paleta por su nombre es adivinar, y
/// aquí se ve el resultado —incluidos los colores del prompt— antes de cerrar.
struct TerminalSettingsView: View {
    @AppStorage(TerminalTheme.storageKey) private var themeRaw = TerminalTheme.system.rawValue
    @AppStorage(TerminalTypeface.storageKey) private var faceRaw = TerminalTypeface.meslo.rawValue
    @AppStorage("terminalFontSize") private var fontSize: Double = 13
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    private var theme: TerminalTheme { TerminalTheme(rawValue: themeRaw) ?? .system }
    private var face: TerminalTypeface { TerminalTypeface(rawValue: faceRaw) ?? .meslo }

    var body: some View {
        NavigationStack {
            Form {
                Section("Muestra") { preview }

                Section {
                    Picker("Tema", selection: $themeRaw) {
                        ForEach(TerminalTheme.allCases) { t in
                            Text(t.label).tag(t.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Tema")
                } footer: {
                    if let hint = theme.hint { Text(hint) }
                }

                Section {
                    Picker("Fuente", selection: $faceRaw) {
                        ForEach(TerminalTypeface.allCases) { f in
                            Text(f.label).tag(f.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Tipografía")
                } footer: {
                    Text(face.hint ?? "Solo se ofrecen fuentes monoespaciadas: con una proporcional, las tablas y el prompt se desalinean.")
                }

                Section {
                    HStack {
                        Text("Tamaño")
                        Spacer()
                        Text("\(Int(fontSize)) pt").foregroundStyle(.secondary)
                    }
                    Slider(value: $fontSize, in: 9...24, step: 1)
                } footer: {
                    Text("También con ⌃+ y ⌃− dentro del terminal.")
                }
            }
            .navigationTitle("Aspecto del terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    /// Bloque de terminal falso con los colores y la fuente elegidos.
    private var preview: some View {
        let palette = theme.palette(for: scheme)
        let font = Font(face.font(size: fontSize))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text("itachi@boson").foregroundStyle(SwiftUI.Color(uiColor: palette.ansiColor(2)))
                Text(":").foregroundStyle(SwiftUI.Color(uiColor: palette.foreground))
                Text("~/proyectos").foregroundStyle(SwiftUI.Color(uiColor: palette.ansiColor(4)))
                Text("$ ls").foregroundStyle(SwiftUI.Color(uiColor: palette.foreground))
            }
            HStack(spacing: 12) {
                Text("Documentos").foregroundStyle(SwiftUI.Color(uiColor: palette.ansiColor(4)))
                Text("informe.pdf").foregroundStyle(SwiftUI.Color(uiColor: palette.foreground))
                Text("script.sh").foregroundStyle(SwiftUI.Color(uiColor: palette.ansiColor(2)))
            }
            HStack(spacing: 0) {
                Text("error:").foregroundStyle(SwiftUI.Color(uiColor: palette.ansiColor(1)))
                Text(" archivo no encontrado").foregroundStyle(SwiftUI.Color(uiColor: palette.foreground))
            }
        }
        .font(font)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SwiftUI.Color(uiColor: palette.background), in: RoundedRectangle(cornerRadius: 8))
    }

}
