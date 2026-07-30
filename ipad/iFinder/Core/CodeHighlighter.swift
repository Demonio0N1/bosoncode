import Foundation

/// Resaltado de sintaxis sin dependencias ni conexión.
///
/// Se hace en Swift, con un recorrido carácter a carácter, en vez de cargar
/// una librería JavaScript: una app que carga scripts de un CDN deja de
/// funcionar sin red —justo cuando estás mirando un archivo local— y además
/// complica la revisión de la App Store. El analizador no pretende entender
/// los lenguajes, solo distinguir las cuatro cosas que dan legibilidad:
/// comentarios, cadenas, números y palabras reservadas.
enum CodeHighlighter {

    struct Language {
        let name: String
        let keywords: Set<String>
        let lineComments: [String]
        let blockComment: (open: String, close: String)?
        /// Comillas que abren cadena en este lenguaje.
        let quotes: Set<Character>
    }

    // MARK: - Lenguajes

    static func language(forExtension ext: String) -> Language? {
        switch ext.lowercased() {
        case "py", "pyw":
            return Language(name: "Python",
                            keywords: ["def", "class", "return", "if", "elif", "else", "for",
                                       "while", "import", "from", "as", "with", "try", "except",
                                       "finally", "raise", "lambda", "yield", "async", "await",
                                       "pass", "break", "continue", "in", "is", "not", "and",
                                       "or", "None", "True", "False", "self", "global", "del"],
                            lineComments: ["#"], blockComment: nil, quotes: ["\"", "'"])
        case "swift":
            return Language(name: "Swift",
                            keywords: ["func", "var", "let", "class", "struct", "enum", "protocol",
                                       "extension", "if", "else", "guard", "for", "while", "return",
                                       "import", "init", "self", "nil", "true", "false", "switch",
                                       "case", "default", "async", "await", "throws", "try", "catch",
                                       "private", "public", "static", "some", "in", "where"],
                            lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""])
        case "js", "jsx", "ts", "tsx", "mjs":
            return Language(name: "JavaScript",
                            keywords: ["function", "const", "let", "var", "class", "return", "if",
                                       "else", "for", "while", "import", "export", "from", "new",
                                       "this", "null", "undefined", "true", "false", "async",
                                       "await", "try", "catch", "throw", "switch", "case", "of",
                                       "in", "typeof", "interface", "type", "extends"],
                            lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'", "`"])
        case "sh", "bash", "zsh":
            return Language(name: "Shell",
                            keywords: ["if", "then", "else", "elif", "fi", "for", "while", "do",
                                       "done", "case", "esac", "function", "return", "export",
                                       "local", "echo", "cd", "exit", "source", "set", "unset"],
                            lineComments: ["#"], blockComment: nil, quotes: ["\"", "'"])
        case "c", "h", "cpp", "hpp", "cc", "m", "mm":
            return Language(name: "C",
                            keywords: ["int", "char", "float", "double", "void", "return", "if",
                                       "else", "for", "while", "struct", "class", "public",
                                       "private", "const", "static", "include", "define", "new",
                                       "delete", "namespace", "using", "template", "typename"],
                            lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"])
        case "jl":
            return Language(name: "Julia",
                            keywords: ["function", "end", "if", "elseif", "else", "for", "while",
                                       "return", "using", "import", "module", "struct", "mutable",
                                       "const", "local", "global", "begin", "let", "do", "true",
                                       "false", "nothing", "in", "where"],
                            lineComments: ["#"], blockComment: ("#=", "=#"), quotes: ["\"", "'"])
        case "go":
            return Language(name: "Go",
                            keywords: ["func", "package", "import", "var", "const", "type",
                                       "struct", "interface", "return", "if", "else", "for",
                                       "range", "go", "defer", "chan", "map", "nil", "true",
                                       "false", "switch", "case", "default"],
                            lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "`"])
        case "rs":
            return Language(name: "Rust",
                            keywords: ["fn", "let", "mut", "struct", "enum", "impl", "trait",
                                       "pub", "use", "mod", "match", "if", "else", "for", "while",
                                       "loop", "return", "self", "Some", "None", "Ok", "Err",
                                       "true", "false", "async", "await", "where"],
                            lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\""])
        case "json":
            return Language(name: "JSON", keywords: ["true", "false", "null"],
                            lineComments: [], blockComment: nil, quotes: ["\""])
        case "yml", "yaml", "toml", "ini", "conf", "cfg":
            return Language(name: "Config", keywords: ["true", "false", "null", "yes", "no"],
                            lineComments: ["#"], blockComment: nil, quotes: ["\"", "'"])
        case "java", "kt", "scala", "cs":
            return Language(name: "Java",
                            keywords: ["public", "private", "protected", "class", "interface",
                                       "void", "int", "return", "if", "else", "for", "while",
                                       "new", "static", "final", "import", "package", "this",
                                       "null", "true", "false", "extends", "implements", "fun", "val"],
                            lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"])
        case "txt", "log", "md", "markdown":
            return nil          // sin resaltado: texto plano
        default:
            return nil
        }
    }

    /// ¿Merece la pena abrir este archivo como código?
    static func isCode(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if language(forExtension: ext) != nil { return true }
        return ["txt", "log", "md", "markdown", "csv", "xml", "html", "css",
                "gitignore", "env"].contains(ext)
    }

    // MARK: - Análisis

    /// Convierte el código en HTML con etiquetas de color.
    static func html(_ source: String, extension ext: String) -> String {
        guard let language = language(forExtension: ext) else {
            return escape(source)          // texto plano, pero seguro
        }

        var out = ""
        var buffer = ""                    // identificador o número en curso
        let chars = Array(source)
        var i = 0

        /// Vuelca lo acumulado decidiendo si era palabra reservada o número.
        func flush() {
            guard !buffer.isEmpty else { return }
            if language.keywords.contains(buffer) {
                out += "<span class='kw'>\(escape(buffer))</span>"
            } else if buffer.first?.isNumber == true {
                out += "<span class='num'>\(escape(buffer))</span>"
            } else {
                out += escape(buffer)
            }
            buffer = ""
        }

        while i < chars.count {
            let rest = String(chars[i...].prefix(3))

            // comentario de bloque
            if let block = language.blockComment, rest.hasPrefix(block.open) {
                flush()
                var comment = ""
                while i < chars.count {
                    comment.append(chars[i]); i += 1
                    if comment.hasSuffix(block.close) { break }
                }
                out += "<span class='com'>\(escape(comment))</span>"
                continue
            }

            // comentario de línea
            if let marker = language.lineComments.first(where: { rest.hasPrefix($0) }) {
                flush()
                _ = marker
                var comment = ""
                while i < chars.count, chars[i] != "\n" { comment.append(chars[i]); i += 1 }
                out += "<span class='com'>\(escape(comment))</span>"
                continue
            }

            // cadena, respetando el escape con barra invertida
            if language.quotes.contains(chars[i]) {
                flush()
                let quote = chars[i]
                var text = String(quote)
                i += 1
                while i < chars.count {
                    if chars[i] == "\\", i + 1 < chars.count {
                        text.append(chars[i]); text.append(chars[i + 1]); i += 2
                        continue
                    }
                    text.append(chars[i])
                    let closed = chars[i] == quote
                    i += 1
                    if closed { break }
                }
                out += "<span class='str'>\(escape(text))</span>"
                continue
            }

            if chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                buffer.append(chars[i])
            } else {
                flush()
                out += escape(String(chars[i]))
            }
            i += 1
        }
        flush()
        return out
    }

    /// Escapa lo que en HTML tiene otro significado. Va SIEMPRE antes de
    /// insertar en la página: un archivo de código puede contener `<script>`.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
