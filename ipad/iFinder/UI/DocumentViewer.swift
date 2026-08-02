import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Qué sabe enseñar ZeroSpin por su cuenta, sin delegar en Quick Look.
enum DocumentKind {
    case notebook
    case code(String)      // extensión
    /// Documento que se EDITA en la app de su formato: Word, Excel, Pages…
    case office
    case other

    /// Familia ofimática, para saber qué app le corresponde.
    enum OfficeFamily {
        case word, excel, powerPoint, appleIWork

        var appName: String {
            switch self {
            case .word: return "Word"
            case .excel: return "Excel"
            case .powerPoint: return "PowerPoint"
            case .appleIWork: return "Pages, Numbers o Keynote"
            }
        }
    }

    /// Tipos uniformes de cada familia.
    ///
    /// Se pregunta por el UTType antes que por la extensión porque es más
    /// fiable: un archivo que llega de un proveedor de nube puede traer un
    /// nombre sin extensión útil y, en cambio, su tipo declarado correcto.
    /// `conforms(to:)` acierta además con variantes —una plantilla .dotx
    /// desciende del documento de Word— que una lista de extensiones no cubre
    /// salvo que se enumeren todas a mano.
    private static let officeTypes: [(OfficeFamily, [String])] = [
        (.word, ["org.openxmlformats.wordprocessingml.document",
                 "com.microsoft.word.doc",
                 "org.oasis-open.opendocument.text"]),
        (.excel, ["org.openxmlformats.spreadsheetml.sheet",
                  "com.microsoft.excel.xls",
                  "org.oasis-open.opendocument.spreadsheet"]),
        (.powerPoint, ["org.openxmlformats.presentationml.presentation",
                       "com.microsoft.powerpoint.ppt",
                       "org.oasis-open.opendocument.presentation"]),
        (.appleIWork, ["com.apple.iwork.pages.pages",
                       "com.apple.iwork.numbers.numbers",
                       "com.apple.iwork.keynote.key"]),
    ]

    /// Respaldo por extensión, para cuando el tipo no viene declarado.
    private static let officeExtensions: [String: OfficeFamily] = [
        "doc": .word, "docx": .word, "dotx": .word, "rtf": .word, "odt": .word,
        "xls": .excel, "xlsx": .excel, "xltx": .excel, "ods": .excel,
        "ppt": .powerPoint, "pptx": .powerPoint, "potx": .powerPoint, "odp": .powerPoint,
        "pages": .appleIWork, "numbers": .appleIWork, "key": .appleIWork,
    ]

    /// A qué familia pertenece, si es que a alguna.
    static func officeFamily(of url: URL) -> OfficeFamily? {
        if let declared = UTType(filenameExtension: url.pathExtension) {
            for (family, identifiers) in officeTypes {
                for identifier in identifiers {
                    if let type = UTType(identifier), declared.conforms(to: type) {
                        return family
                    }
                }
            }
        }
        return officeExtensions[url.pathExtension.lowercased()]
    }

    static func of(_ url: URL) -> DocumentKind {
        let ext = url.pathExtension.lowercased()
        if ext == "ipynb" { return .notebook }
        if officeFamily(of: url) != nil { return .office }
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
