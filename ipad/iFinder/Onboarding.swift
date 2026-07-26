import SwiftUI

/// Permite que la ventana se reduzca todo lo que iPadOS admita (por defecto
/// impone un mínimo grande).
struct WindowFreeResize: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        for delay in [0.2, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let r = view.window?.windowScene?.sizeRestrictions else { return }
                r.minimumSize = CGSize(width: 320, height: 320)
                r.maximumSize = CGSize(width: 10000, height: 10000)
                r.allowsFullScreen = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Pantalla inicial: iOS aísla las apps, así que hay que pedirle al usuario
/// que conceda sus carpetas una vez. Después quedan guardadas.
struct OnboardingView: View {
    var onPick: (LocalRoot) -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 54))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .blue],
                                   startPoint: .top, endPoint: .bottom))
            Text("Da acceso a tus archivos")
                .font(.title2.bold())
            Text("iPadOS protege tus datos: elige una vez cada carpeta y iFinder la recordará para siempre.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Label("En el selector, abre la barra lateral y elige la ubicación completa (En mi iPad, iCloud Drive…), luego pulsa Abrir.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 30)

            VStack(spacing: 12) {
                ForEach(LocalRoot.allCases) { root in
                    Button {
                        onPick(root)
                    } label: {
                        HStack {
                            Image(systemName: root.icon)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(root.title).font(.body.weight(.medium))
                                Text(root.hint)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 26)

            Button("Ahora no", action: onSkip)
                .font(.callout)
                .padding(.top, 4)
        }
        .padding(.vertical, 34)
        .frame(maxWidth: 460)
    }
}

/// Carpetas típicas del iPad que se ofrecen al arrancar.
enum LocalRoot: String, CaseIterable, Identifiable {
    case onMyIPad, iCloud, downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onMyIPad: return "En mi iPad"
        case .iCloud: return "iCloud Drive"
        case .downloads: return "Descargas"
        }
    }

    var hint: String {
        switch self {
        case .onMyIPad: return "Documentos guardados en el dispositivo"
        case .iCloud: return "Tu unidad de iCloud completa"
        case .downloads: return "La carpeta de descargas de Safari y Archivos"
        }
    }

    var icon: String {
        switch self {
        case .onMyIPad: return "ipad"
        case .iCloud: return "icloud.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }

    /// iPadOS no expone rutas para "En mi iPad" ni "iCloud Drive": el selector
    /// debe abrirse en su ubicación por defecto y el usuario elige ahí.
    var suggestedURL: URL? { nil }
}
