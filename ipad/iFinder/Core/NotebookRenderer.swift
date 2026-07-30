import Foundation

/// Convierte un `.ipynb` en una página legible.
///
/// Un notebook es JSON: celdas con su fuente y, si se ejecutaron, sus salidas
/// guardadas. Quick Look lo enseña como texto plano —una pared de JSON con los
/// `\n` escapados— que no hay quien lea. Aquí se reconstruye lo que se vería en
/// Jupyter: markdown formateado, código resaltado y las salidas, incluidas las
/// imágenes, que viajan en base64 dentro del propio archivo.
enum NotebookRenderer {

    enum Failure: LocalizedError {
        case notANotebook
        var errorDescription: String? { "Este archivo no tiene el formato de un notebook." }
    }

    static func html(from data: Data, title: String) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = root["cells"] as? [[String: Any]] else {
            throw Failure.notANotebook
        }

        let language = ((root["metadata"] as? [String: Any])?["kernelspec"]
            as? [String: Any])?["language"] as? String ?? "python"
        let ext = language.lowercased().hasPrefix("jul") ? "jl"
                : language.lowercased().hasPrefix("py") ? "py" : language

        var body = ""
        var executionCount = 0
        for cell in cells {
            let source = joined(cell["source"])
            switch cell["cell_type"] as? String {
            case "markdown":
                body += "<div class='md'>\(Markdown.html(source))</div>"
            case "code":
                executionCount += 1
                let number = cell["execution_count"] as? Int
                body += codeCell(source, extension: ext, number: number ?? executionCount,
                                 outputs: cell["outputs"] as? [[String: Any]] ?? [])
            case "raw":
                body += "<pre class='raw'>\(CodeHighlighter.escape(source))</pre>"
            default:
                break
            }
        }

        let subtitle = "\(cells.count) celdas · \(language)"
        return page(title: title, subtitle: subtitle, body: body)
    }

    // MARK: - Piezas

    private static func codeCell(_ source: String, extension ext: String,
                                 number: Int, outputs: [[String: Any]]) -> String {
        var html = """
        <div class='cell'>
          <div class='gutter'>[\(number)]</div>
          <pre class='code'>\(CodeHighlighter.html(source, extension: ext))</pre>
        """
        for output in outputs {
            html += render(output: output)
        }
        return html + "</div>"
    }

    private static func render(output: [String: Any]) -> String {
        let data = output["data"] as? [String: Any] ?? [:]

        // Las imágenes vienen en base64 DENTRO del notebook, así que las
        // gráficas se ven sin ejecutar nada ni salir a la red.
        if let png = data["image/png"] as? String {
            let clean = png.replacingOccurrences(of: "\n", with: "")
            return "<img class='out-img' src='data:image/png;base64,\(clean)'>"
        }
        if let svg = data["image/svg+xml"] {
            return "<div class='out-img'>\(joined(svg))</div>"
        }
        if let html = data["text/html"] {
            // ya es HTML del propio notebook (tablas de pandas, por ejemplo)
            return "<div class='out-html'>\(joined(html))</div>"
        }
        if let text = data["text/plain"] {
            return "<pre class='out'>\(CodeHighlighter.escape(joined(text)))</pre>"
        }
        if let text = output["text"] {           // salidas de stream (print)
            return "<pre class='out'>\(CodeHighlighter.escape(joined(text)))</pre>"
        }
        if output["output_type"] as? String == "error" {
            let name = output["ename"] as? String ?? "Error"
            let value = output["evalue"] as? String ?? ""
            return "<pre class='out err'>\(CodeHighlighter.escape("\(name): \(value)"))</pre>"
        }
        return ""
    }

    /// En el formato .ipynb, `source` y `text` pueden ser una cadena o una
    /// lista de líneas; ambos casos son válidos y hay que aceptar los dos.
    private static func joined(_ value: Any?) -> String {
        if let text = value as? String { return text }
        if let lines = value as? [String] { return lines.joined() }
        return ""
    }

    // MARK: - Página

    static func page(title: String, subtitle: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset='utf-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <style>\(css)</style></head>
        <body>
          <header><h1>\(CodeHighlighter.escape(title))</h1><p>\(subtitle)</p></header>
          \(body)
        </body></html>
        """
    }

    /// Un solo bloque de estilo para notebooks y código, con las dos
    /// variantes de tema para que siga al iPad sin recargar.
    static let css = """
    :root {
      --bg: #ffffff; --fg: #1d1d1f; --muted: #6e6e73; --line: #e3e3e6;
      --cell: #f6f6f8; --kw: #9b2393; --str: #c41a16; --num: #1c00cf; --com: #6e7781;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #1c1c1e; --fg: #f2f2f7; --muted: #98989d; --line: #38383a;
        --cell: #262629; --kw: #ff7ab2; --str: #ff8170; --num: #d9c97c; --com: #7f8c98;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; padding: 18px 20px 60px;
      background: var(--bg); color: var(--fg);
      font: 15px/1.55 -apple-system, system-ui, sans-serif;
      -webkit-text-size-adjust: 100%;
    }
    header { border-bottom: 1px solid var(--line); padding-bottom: 10px; margin-bottom: 18px; }
    header h1 { font-size: 19px; margin: 0 0 2px; }
    header p { margin: 0; color: var(--muted); font-size: 12px; }
    .cell { margin: 0 0 18px; }
    .gutter { color: var(--muted); font: 11px ui-monospace, Menlo, monospace; margin-bottom: 4px; }
    pre {
      margin: 0; padding: 12px 14px; overflow-x: auto;
      background: var(--cell); border-radius: 9px;
      font: 13px/1.5 ui-monospace, "SF Mono", Menlo, monospace;
      white-space: pre; -webkit-overflow-scrolling: touch;
    }
    pre.out { background: transparent; border-left: 3px solid var(--line);
              border-radius: 0; margin-top: 6px; color: var(--muted); }
    pre.out.err { border-left-color: #ff453a; color: #ff453a; }
    .out-img { max-width: 100%; margin-top: 8px; border-radius: 6px; }
    .out-html { margin-top: 8px; overflow-x: auto; font-size: 13px; }
    .out-html table { border-collapse: collapse; }
    .out-html th, .out-html td { border: 1px solid var(--line); padding: 4px 8px; }
    .md { margin-bottom: 18px; }
    .md h1, .md h2, .md h3 { margin: 14px 0 6px; }
    .md code { background: var(--cell); padding: 1px 5px; border-radius: 4px;
               font: 13px ui-monospace, Menlo, monospace; }
    .md pre code { background: none; padding: 0; }
    .md a { color: #0a84ff; }
    .kw { color: var(--kw); } .str { color: var(--str); }
    .num { color: var(--num); } .com { color: var(--com); font-style: italic; }
    """
}

/// Markdown mínimo: lo que de verdad aparece en las celdas de un notebook.
///
/// No es un intérprete completo a propósito — encabezados, énfasis, código,
/// listas y enlaces cubren casi todo, y cada regla añadida es una forma más de
/// equivocarse con el texto del usuario.
enum Markdown {
    static func html(_ source: String) -> String {
        var out: [String] = []
        var inFence = false
        var listOpen = false

        for rawLine in source.components(separatedBy: "\n") {
            let line = rawLine

            if line.hasPrefix("```") {
                if inFence { out.append("</code></pre>") } else { out.append("<pre><code>") }
                inFence.toggle()
                continue
            }
            if inFence {
                out.append(CodeHighlighter.escape(line))
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if listOpen { out.append("</ul>"); listOpen = false }
                continue
            }

            // encabezados
            if let hashes = trimmed.range(of: "^#{1,6} ", options: .regularExpression) {
                let level = trimmed.distance(from: trimmed.startIndex, to: hashes.upperBound) - 1
                let text = String(trimmed[hashes.upperBound...])
                if listOpen { out.append("</ul>"); listOpen = false }
                out.append("<h\(level)>\(inline(text))</h\(level)>")
                continue
            }

            // listas
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !listOpen { out.append("<ul>"); listOpen = true }
                out.append("<li>\(inline(String(trimmed.dropFirst(2))))</li>")
                continue
            }

            if listOpen { out.append("</ul>"); listOpen = false }
            out.append("<p>\(inline(trimmed))</p>")
        }
        if listOpen { out.append("</ul>") }
        if inFence { out.append("</code></pre>") }
        return out.joined(separator: "\n")
    }

    /// Énfasis, código y enlaces dentro de una línea, ya escapada.
    private static func inline(_ text: String) -> String {
        var html = CodeHighlighter.escape(text)
        html = replace(html, #"`([^`]+)`"#, "<code>$1</code>")
        html = replace(html, #"\*\*([^*]+)\*\*"#, "<strong>$1</strong>")
        html = replace(html, #"\*([^*]+)\*"#, "<em>$1</em>")
        html = replace(html, #"\[([^\]]+)\]\(([^)]+)\)"#, "<a href='$2'>$1</a>")
        return html
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
