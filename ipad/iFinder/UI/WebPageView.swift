import SwiftUI
import WebKit

/// Una página HTML local, renderizada.
///
/// ## Por qué no es "abrir en Safari"
///
/// Safari no puede recibir un archivo local de otra app: `UIApplication.open`
/// rechaza las URL `file://`, y Safari tampoco se declara capaz de abrir HTML
/// local, así que no aparece en "Abrir con…". No hay forma de entregárselo.
///
/// Lo que sí se puede es usar **su mismo motor**: `WKWebView` es WebKit, el
/// mismo que dibuja Safari. La página se ve igual; lo que cambia es el marco
/// que la rodea.
///
/// El detalle que hace que funcione de verdad es `allowingReadAccessTo`: sin
/// darle permiso sobre la CARPETA, la página carga pero sus hojas de estilo,
/// sus imágenes y sus scripts —que se referencian con rutas relativas— no, y el
/// resultado es un documento sin formato que parece roto.
struct WebPageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        load(into: view)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func load(into view: WKWebView) {
        // Un archivo de una nube o de una carpeta concedida necesita su ámbito
        // abierto mientras WebKit lee, igual que para cualquier otra lectura.
        let folder = url.deletingLastPathComponent()
        let scoped = url.startAccessingSecurityScopedResource()
        let root = CloudFileHandler.root(containing: url)
        let rootScoped = (root != nil && root != url)
            ? root!.startAccessingSecurityScopedResource() : false
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            if rootScoped, let root { root.stopAccessingSecurityScopedResource() }
        }
        view.loadFileURL(url, allowingReadAccessTo: folder)
    }
}

/// Ventana de página web, con lo justo alrededor.
struct WebPageWindow: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            WebPageView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        // El botón de acciones del sistema, que sí lista las
                        // apps capaces de abrir el archivo. Si algún día Safari
                        // se declara entre ellas, aparecerá aquí sin tocar nada.
                        DocumentActionsButton(url: url)
                            .frame(width: 30, height: 30)
                    }
                }
        }
    }
}
