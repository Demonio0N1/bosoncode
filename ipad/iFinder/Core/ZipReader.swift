import Foundation
import Compression

/// Lector de archivos ZIP.
///
/// ## Por qué hay que escribirlo
///
/// iOS sabe CREAR zips —`NSFileCoordinator` con `.forUploading` es lo que usa
/// «Comprimir»— pero no sabe abrirlos: Foundation no expone ninguna API de
/// descompresión, y `AppleArchive` habla su propio formato, no ZIP.
///
/// Lo que sí hay es `Compression`, que trae el DEFLATE en bruto. Y eso es justo
/// lo que un ZIP guarda dentro: el resto del formato es el sobre —dónde empieza
/// cada archivo y cuánto mide—, que se lee con unos cuantos enteros.
///
/// La alternativa era añadir una dependencia externa solo para esto. Para un
/// formato estable desde 1989 no compensa el riesgo de arrastrar código ajeno.
enum ZipReader {

    enum Failure: LocalizedError {
        case notAZip
        case unsupported(String)
        case corrupt

        var errorDescription: String? {
            switch self {
            case .notAZip:
                return "Este archivo no es un ZIP válido."
            case .unsupported(let what):
                return "Este ZIP usa \(what), que aún no se puede abrir aquí."
            case .corrupt:
                return "El ZIP está dañado o incompleto."
            }
        }
    }

    /// Una entrada del índice del ZIP.
    private struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    // MARK: - API

    /// Extrae el ZIP dentro de `directory`, en una carpeta con su nombre.
    /// - Returns: la carpeta creada.
    static func extract(_ zip: URL, into directory: URL, named folderName: String) throws -> URL {
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        let entries = try index(of: data)

        let root = directory.appendingPathComponent(folderName)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        for entry in entries {
            // Un nombre dentro del ZIP puede contener «../» y apuntar fuera de
            // la carpeta de destino: es el ataque conocido como zip slip, y
            // permitiría sobrescribir archivos de la app abriendo un ZIP
            // cualquiera. Se resuelve la ruta y se comprueba que siga dentro.
            guard let target = safeURL(for: entry.name, under: root) else {
                throw Failure.unsupported("rutas fuera de la carpeta de destino")
            }
            if entry.name.hasSuffix("/") {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            let contents = try payload(of: entry, in: data)
            try contents.write(to: target, options: .atomic)
        }
        return root
    }

    // MARK: - El sobre

    /// Lee el índice central, que es donde el ZIP dice qué contiene.
    ///
    /// Se lee ESE y no la cadena de cabeceras locales porque es el único sitio
    /// fiable: las locales pueden traer los tamaños a cero cuando el zip se
    /// escribió en streaming, remitiendo a un descriptor que va detrás.
    private static func index(of data: Data) throws -> [Entry] {
        guard let eocd = locateEndOfCentralDirectory(data) else { throw Failure.notAZip }

        let count = Int(data.u16(eocd + 10))
        let start = Int(data.u32(eocd + 16))
        // 0xFFFFFFFF es la marca de «mira en el registro Zip64»
        guard start != 0xFFFF_FFFF, data.u16(eocd + 8) != 0xFFFF else {
            throw Failure.unsupported("el formato Zip64")
        }
        guard start < data.count else { throw Failure.corrupt }

        var entries: [Entry] = []
        var p = start
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(p) == 0x0201_4b50 else { throw Failure.corrupt }
            let nameLength = Int(data.u16(p + 28))
            let extraLength = Int(data.u16(p + 30))
            let commentLength = Int(data.u16(p + 32))
            guard p + 46 + nameLength <= data.count else { throw Failure.corrupt }

            let name = String(decoding: data[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            let compressed = Int(data.u32(p + 20))
            let uncompressed = Int(data.u32(p + 24))
            guard compressed != 0xFFFF_FFFF, uncompressed != 0xFFFF_FFFF else {
                throw Failure.unsupported("el formato Zip64")
            }
            // bit 0 de las banderas: contenido cifrado
            guard data.u16(p + 8) & 1 == 0 else {
                throw Failure.unsupported("contraseña")
            }
            entries.append(Entry(name: name,
                                 method: data.u16(p + 10),
                                 compressedSize: compressed,
                                 uncompressedSize: uncompressed,
                                 localHeaderOffset: Int(data.u32(p + 42))))
            p += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// El índice va al final, detrás de un comentario de longitud variable, así
    /// que su firma se busca hacia atrás. El comentario cabe en 64 KB, y ese es
    /// todo lo que hay que mirar.
    private static func locateEndOfCentralDirectory(_ data: Data) -> Int? {
        let minimum = 22
        guard data.count >= minimum else { return nil }
        let floor = max(0, data.count - minimum - 0xFFFF)
        var p = data.count - minimum
        while p >= floor {
            if data.u32(p) == 0x0605_4b50 { return p }
            p -= 1
        }
        return nil
    }

    /// Salta la cabecera local —cuyos campos de longitud NO tienen por qué
    /// coincidir con los del índice— y devuelve el contenido ya expandido.
    private static func payload(of entry: Entry, in data: Data) throws -> Data {
        let h = entry.localHeaderOffset
        guard h + 30 <= data.count, data.u32(h) == 0x0403_4b50 else { throw Failure.corrupt }
        let start = h + 30 + Int(data.u16(h + 26)) + Int(data.u16(h + 28))
        let end = start + entry.compressedSize
        guard end <= data.count else { throw Failure.corrupt }
        let raw = data[start..<end]

        switch entry.method {
        case 0:                             // guardado tal cual
            return Data(raw)
        case 8:                             // deflate
            return try inflate(Data(raw), expected: entry.uncompressedSize)
        default:
            throw Failure.unsupported("un método de compresión poco común")
        }
    }

    // MARK: - DEFLATE

    /// `COMPRESSION_ZLIB` en el framework de Apple es DEFLATE **en bruto**, sin
    /// la cabecera de zlib. Es exactamente lo que el ZIP guarda, así que los
    /// bytes entran sin tocarlos.
    private static func inflate(_ source: Data, expected: Int) throws -> Data {
        guard !source.isEmpty else { return Data() }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE,
                                      COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.corrupt
        }
        defer { compression_stream_destroy(stream) }

        let chunk = 128 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { destination.deallocate() }

        var output = Data()
        output.reserveCapacity(max(expected, chunk))

        try source.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                throw Failure.corrupt
            }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count

            while true {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = chunk
                // FINALIZE porque todo el origen está ya en memoria: no va a
                // llegar más entrada después de esta.
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunk - stream.pointee.dst_size
                if produced > 0 { output.append(destination, count: produced) }

                switch status {
                case COMPRESSION_STATUS_END: return
                case COMPRESSION_STATUS_OK: continue
                default: throw Failure.corrupt
                }
            }
        }
        return output
    }

    // MARK: - Rutas

    /// Devuelve el destino solo si queda DENTRO de la carpeta de extracción.
    private static func safeURL(for name: String, under root: URL) -> URL? {
        // rutas absolutas y componentes vacíos fuera desde el principio
        let parts = name.split(separator: "/").map(String.init)
        guard !name.hasPrefix("/"), !parts.isEmpty else { return nil }
        guard !parts.contains("..") else { return nil }
        var url = root
        for part in parts { url.appendPathComponent(part) }
        // Cinturón y tirantes, comparando rutas normalizadas.
        //
        // `standardized` y NO `standardizedFileURL`: el segundo además resuelve
        // enlaces simbólicos, y solo puede hacerlo si la ruta YA existe. La
        // carpeta de destino existe y el archivo que va a escribirse todavía
        // no, así que se comparaba una ruta resuelta contra otra sin resolver y
        // no coincidían nunca. En iOS eso es la norma, no un caso raro: el
        // contenedor de la app cuelga de /var, que es un enlace a /private/var,
        // de modo que la comprobación habría rechazado TODOS los archivos.
        let base = root.standardized.path
        guard url.standardized.path.hasPrefix(base + "/") else { return nil }
        return url
    }
}

// MARK: - Enteros del formato

/// El ZIP guarda sus números en little-endian y sin alinear, así que se leen
/// byte a byte: `load(as:)` sobre un desplazamiento cualquiera es
/// comportamiento indefinido en arquitecturas que exigen alineación.
private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let i = startIndex + offset
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let i = startIndex + offset
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8
            | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
}
