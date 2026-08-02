import SwiftUI
import WebKit

/// Qué sabe enseñar ZeroSpin por su cuenta, sin delegar en Quick Look.
enum DocumentKind {
    case notebook
    case code(String)      // extensión
    /// Documento que se EDITA en la app de su formato: Word, Excel, Pages…
    case office
    case other

    /// Formatos que existen para editarse, no para mirarse.
    ///
    /// Quick Look sabe dibujarlos, y por eso el doble clic caía en el visor
    /// propio: `canPreview` decía que sí. Pero de un .docx no se viene a ver una
    /// estampa de solo lectura, se viene a escribir — así que estos van a su
    /// app. La vista previa sigue a un espacio de distancia.
    private static let officeExtensions: Set<String> = [
        "doc", "docx", "rtf", "odt",
        "xls", "xlsx", "csvx", "ods",
        "ppt", "pptx", "odp",
        "pages", "numbers", "key",
    ]

    static func of(_ url: URL) -> DocumentKind {
        let ext = url.pathExtension.lowercased()
        if ext == "ipynb" { return .notebook }
        if officeExtensions.contains(ext) { return .office }
        if CodeHighlighter.isCode(url) { return .code(ext) }
        return .other
    }
}

/// Visor propio para notebooks y código.
///
/// Quick Look abre un `.ipynb` como texto plano —una pared de JSON con los
/// saltos de línea escapados— y un `.py` sin ningún color. Aquí se rinde la
/// página en local y se muestra en un `WKWebView`, que es lo que ya sabe
/// desplazar, ampliar y seleccionar texto largo sin escribirlo desde cero.
struct DocumentViewer: View {
    let url: URL

    @State private var html: String?
    @State private var failure: String?

    var body: some View {
        Group {
            if let html {
                HTMLView(html: html)
            } else if let failure {
                ContentUnavailableView("No se puede mostrar", systemImage: "doc.text.magnifyingglass",
                                       description: Text(failure))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: url) { await render() }
    }

    private func render() async {
        do {
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            switch DocumentKind.of(url) {
            case .notebook:
                html = try NotebookRenderer.html(from: data, title: name)
            case .code(let ext):
                // Los archivos enormes se recortan: pintar medio millón de
                // líneas bloquearía la vista sin que nadie las lea.
                let limit = 400_000
                var text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) ?? ""
                var note = ""
                if text.count > limit {
                    text = String(text.prefix(limit))
                    note = " · mostrando los primeros \(limit / 1000) mil caracteres"
                }
                let lines = text.components(separatedBy: "\n").count
                let body = "<pre class='code'>\(CodeHighlighter.html(text, extension: ext))</pre>"
                let language = CodeHighlighter.language(forExtension: ext)?.name ?? "texto"
                html = NotebookRenderer.page(title: name,
                                             subtitle: "\(lines) líneas · \(language)\(note)",
                                             body: body)
            case .office, .other:
                failure = "Formato no soportado por el visor propio."
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// `WKWebView` que muestra HTML generado en el propio dispositivo.
struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // La página es nuestra y no navega a ninguna parte: se bloquea
        // cualquier salto para que un enlace de un notebook ajeno no se lleve
        // la vista a Internet.
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if context.coordinator.html != html {
            context.coordinator.html = html
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(html: html) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String
        init(html: String) { self.html = html }

        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // la carga inicial sí; los enlaces se abren fuera, en Safari
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
