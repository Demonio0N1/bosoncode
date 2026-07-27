import SwiftUI

/// Buscador de la barra de herramientas, como el del Finder.
///
/// En reposo es solo una lupa; al pulsarla el campo crece hacia la izquierda y
/// recibe el foco. Se pliega solo al vaciarse y perder el foco, así que no hay
/// que cerrarlo a mano.
///
/// Se hace a mano en vez de con `.searchable` porque ese modificador siempre
/// reserva una fila completa bajo la barra de navegación: rompe el diseño
/// compacto de escritorio y no admite el plegado.
struct SearchField: View {
    @Binding var text: String
    /// Ancho del campo desplegado.
    var width: CGFloat = 200

    @State private var expanded = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .onTapGesture { toggle() }

            if expanded {
                TextField("Buscar", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    // Esc cierra el buscador, como en macOS
                    .onKeyPress(.escape) { close(); return .handled }
                    .frame(width: width)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, expanded ? 7 : 0)
        .padding(.vertical, expanded ? 4 : 0)
        .background {
            if expanded {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
        // se pliega solo cuando queda vacío y sin foco
        .onChange(of: focused) { _, hasFocus in
            if !hasFocus, text.isEmpty { expanded = false }
        }
    }

    private func toggle() {
        if expanded {
            close()
        } else {
            expanded = true
            // el campo no existe hasta que la animación lo inserta: pedirle el
            // foco en el mismo ciclo no tendría efecto
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private func close() {
        text = ""
        focused = false
        expanded = false
    }
}
