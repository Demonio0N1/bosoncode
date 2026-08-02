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
        // Sin extensión conocida pero claramente texto: datos sueltos, listas,
        // configuraciones. Son justo los archivos que se editan al vuelo.
        return ["txt", "log", "md", "markdown", "csv", "tsv", "xml", "html", "css",
                "gitignore", "env", "dat", "list", "properties", "cnf", "conf",
                "in", "out", "tex", "bib", "srt", "gitconfig", "editorconfig",
                "dockerfile", "makefile", "gradle", "plist"].contains(ext)
    }

    // MARK: - Análisis

    /// Qué es cada trozo de código.
    enum Token { case plain, keyword, string, number, comment }

    /// Tramos del código con su tipo, en orden.
    ///
    /// El analizador produce esto y no HTML directamente: así el mismo
    /// recorrido sirve para pintar la vista previa (HTML) y el editor nativo
    /// (texto con atributos), sin dos analizadores que se desincronicen.
    static func spans(_ source: String, extension ext: String) -> [(text: String, token: Token)] {
        guard let language = language(forExtension: ext) else {
            return [(source, .plain)]
        }
        var spans: [(String, Token)] = []
        var buffer = ""
        let chars = Array(source)
        var i = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            if language.keywords.contains(buffer) {
                spans.append((buffer, .keyword))
            } else if buffer.first?.isNumber == true {
                spans.append((buffer, .number))
            } else {
                spans.append((buffer, .plain))
            }
            buffer = ""
        }

        while i < chars.count {
            let rest = String(chars[i...].prefix(3))

            if let block = language.blockComment, rest.hasPrefix(block.open) {
                flush()
                var comment = ""
                while i < chars.count {
                    comment.append(chars[i]); i += 1
                    if comment.hasSuffix(block.close) { break }
                }
                spans.append((comment, .comment))
                continue
            }
            if language.lineComments.contains(where: { rest.hasPrefix($0) }) {
                flush()
                var comment = ""
                while i < chars.count, chars[i] != "\n" { comment.append(chars[i]); i += 1 }
                spans.append((comment, .comment))
                continue
            }
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
                spans.append((text, .string))
                continue
            }
            if chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                buffer.append(chars[i])
            } else {
                flush()
                spans.append((String(chars[i]), .plain))
            }
            i += 1
        }
        flush()
        return spans
    }

    /// Convierte el código en HTML con etiquetas de color.
    static func html(_ source: String, extension ext: String) -> String {
        guard language(forExtension: ext) != nil else {
            return escape(source)          // texto plano, pero seguro
        }
        return spans(source, extension: ext).map { span in
            switch span.token {
            case .plain: return escape(span.text)
            case .keyword: return "<span class='kw'>\(escape(span.text))</span>"
            case .string: return "<span class='str'>\(escape(span.text))</span>"
            case .number: return "<span class='num'>\(escape(span.text))</span>"
            case .comment: return "<span class='com'>\(escape(span.text))</span>"
            }
        }.joined()
    }


    /// Escapa lo que en HTML tiene otro significado. Va SIEMPRE antes de
    /// insertar en la página: un archivo de código puede contener `<script>`.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
