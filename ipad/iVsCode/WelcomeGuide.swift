import SwiftUI

/// Guía de bienvenida: solo la primera vez que se abre BosonCode.
///
/// Cubre las dos cosas que nadie adivina por su cuenta: que hace falta un
/// equipo con `serve.sh` en marcha, y que el terminal nativo vive tras un
/// atajo de teclado. El resto de la app se explica sola.
struct WelcomeGuide: View {
    var onFinish: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    step(number: 1,
                         icon: "desktopcomputer",
                         title: "Run the server on your computer",
                         detail: "Linux or macOS, with Tailscale signed in. No root, no Docker.") {
                        CommandBlock(lines: ["git clone https://github.com/Demonio0N1/bosoncode.git",
                                             "cd bosoncode",
                                             "./serve.sh"])
                        Text("Add `--install-service` and it starts on every boot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    step(number: 2,
                         icon: "wifi",
                         title: "Your machine appears on its own",
                         detail: "It announces itself on the network — no address to type. Tap its card and enter the password once.") {
                        CommandBlock(lines: ["cat ~/.ivscode/password"])
                        Text("That command prints it on the computer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    step(number: 3,
                         icon: "terminal",
                         title: "Open a terminal with ⌃⌥T",
                         detail: "A real terminal in its own window, not the web one. Press it again to hide it.") {
                        HStack(spacing: 8) {
                            KeyCap("control"); KeyCap("option"); KeyCap("T")
                        }
                        Text("The green button on its title bar opens another, independent terminal.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(28)
            }

            footer
        }
        .frame(maxWidth: 560)
        .background(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Text("Welcome to BosonCode")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Three things and you are set up.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
            HStack {
                Link(destination: BosonCodeInfo.setupGuideURL) {
                    Label("Full guide", systemImage: "arrow.up.forward.square")
                        .font(.callout)
                }
                Spacer()
                Button("Get started", action: onFinish)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
        }
    }

    /// Un paso: número, icono, texto y el contenido propio de cada uno.
    private func step<Content: View>(number: Int,
                                     icon: String,
                                     title: String,
                                     detail: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.cyan)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("\(number). \(title)")
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
    }
}

/// Bloque de comandos, seleccionable para poder copiarlo.
private struct CommandBlock: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)      // se puede copiar de verdad
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Tecla dibujada como en un teclado físico.
private struct KeyCap: View {
    let symbol: String
    init(_ symbol: String) { self.symbol = symbol }

    private var label: String {
        switch symbol {
        case "control": return "⌃"
        case "option": return "⌥"
        default: return symbol
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .frame(minWidth: 34, minHeight: 32)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
    }
}
