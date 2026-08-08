import Foundation
import Compression

/// Escritor de archivos ZIP.
///
/// ## Por qué también hay que escribirlo
///
/// «Comprimir» usaba `NSFileCoordinator` con `.forUploading`, que parece la
/// solución sin dependencias… pero solo empaqueta CARPETAS. Con un archivo
/// suelto entrega el archivo tal cual, y lo que se guardaba con extensión
/// `.zip` era el original sin comprimir: `Léeme.zip` contenía el texto de
/// `Léeme.txt` en claro. Nadie lo notó porque nada volvía a abrirlos, y al
/// añadir «Descomprimir» salieron todos a la vez.
///
/// Como `ZipReader` ya conoce el formato, escribirlo es el mismo sobre al
/// revés, y a cambio el resultado es predecible: se sabe exactamente qué
/// nombres quedan dentro y con qué estructura.
enum ZipWriter {

    /// Comprime lo indicado en un ZIP dentro de `directory`.
    ///
    /// La estructura imita a Finder: un solo elemento queda en la raíz del ZIP
    /// con su propio nombre; varios quedan todos en la raíz, uno al lado del
    /// otro. Nunca se añade una carpeta envolvente que no existía.
    static func write(_ urls: [URL], to destination: URL) throws {
        var entries: [Entry] = []
        for url in urls {
            try collect(url, base: url.deletingLastPathComponent(), into: &entries)
        }
        // El ZIP clásico cuenta las entradas en 16 bits. Pasarse no daba un
        // error: `UInt16(entries.count)` ABORTA el proceso, y comprimir una
        // carpeta con muchos archivos cerraba la app de golpe.
        guard entries.count <= 0xFFFF else {
            throw Failure.tooMany(entries.count)
        }
        try assemble(entries, to: destination)
    }

    enum Failure: LocalizedError {
        case tooMany(Int)
        case tooBig(String)

        var errorDescription: String? {
            switch self {
            case .tooMany(let n):
                return "Son \(n) archivos y un ZIP admite 65 535. Comprime menos elementos a la vez."
            case .tooBig(let name):
                return "«\(name)» pasa de 4 GB, que es el máximo de un ZIP normal."
            }
        }
    }

    // MARK: - Recorrido

    private struct Entry {
        let name: String            // ruta dentro del ZIP
        let url: URL?               // nil para carpetas
        let modified: Date
    }

    private static func collect(_ url: URL, base: URL, into entries: inout [Entry]) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        let attributes = try? fm.attributesOfItem(atPath: url.path)
        let modified = (attributes?[.modificationDate] as? Date) ?? Date()
        let relative = relativeName(of: url, from: base)

        if isDirectory.boolValue {
            entries.append(Entry(name: relative + "/", url: nil, modified: modified))
            let children = try fm.contentsOfDirectory(at: url,
                                                      includingPropertiesForKeys: nil,
                                                      options: [])
            // orden estable: comprimir dos veces lo mismo da el mismo archivo
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try collect(child, base: base, into: &entries)
            }
        } else {
            entries.append(Entry(name: relative, url: url, modified: modified))
        }
    }

    private static func relativeName(of url: URL, from base: URL) -> String {
        let full = url.standardized.pathComponents
        let root = base.standardized.pathComponents
        guard full.count > root.count, Array(full.prefix(root.count)) == root else {
            return url.lastPathComponent
        }
        return full.dropFirst(root.count).joined(separator: "/")
    }

    // MARK: - Montaje

    private static func assemble(_ entries: [Entry], to destination: URL) throws {
        var payload = Data()        // cabeceras locales + contenido
        var central = Data()        // índice final

        for entry in entries {
            let offset = payload.count
            let isDirectory = entry.url == nil
            let raw = try isDirectory ? Data() : Data(contentsOf: entry.url!, options: .mappedIfSafe)

            // Igual que arriba: los tamaños van en 32 bits y `UInt32(...)`
            // aborta al desbordar. Un vídeo de más de 4 GB cerraba la app.
            guard raw.count <= 0xFFFF_FFFF, offset <= 0xFFFF_FFFF else {
                throw Failure.tooBig(entry.name)
            }

            let crc = crc32(raw)
            var method: UInt16 = 0
            var body = raw
            if !isDirectory, !raw.isEmpty, let squeezed = deflate(raw), squeezed.count < raw.count {
                // solo si de verdad sale más pequeño: en un JPEG o un MP4 el
                // deflate crece, y guardar eso sería pagar CPU por ocupar más
                method = 8
                body = squeezed
            }

            let name = Array(entry.name.utf8)
            guard name.count <= 0xFFFF else { throw Failure.tooBig(entry.name) }
            let (time, date) = dosTimestamp(entry.modified)
            // bit 11: los nombres van en UTF-8. Sin esta marca, un archivo con
            // tildes o eñes se abre con el nombre roto en otros sistemas.
            let flags: UInt16 = 0x0800

            var local = Data()
            local.u32(0x0403_4b50)
            local.u16(20); local.u16(flags); local.u16(method)
            local.u16(time); local.u16(date)
            local.u32(crc); local.u32(UInt32(body.count)); local.u32(UInt32(raw.count))
            local.u16(UInt16(name.count)); local.u16(0)
            local.append(contentsOf: name)
            local.append(body)
            payload.append(local)

            central.u32(0x0201_4b50)
            central.u16(0x031E)                 // creado en Unix, ZIP 3.0
            central.u16(20); central.u16(flags); central.u16(method)
            central.u16(time); central.u16(date)
            central.u32(crc); central.u32(UInt32(body.count)); central.u32(UInt32(raw.count))
            central.u16(UInt16(name.count)); central.u16(0); central.u16(0)
            central.u16(0); central.u16(0)
            // permisos en los 16 bits altos; el bit 0x10 marca carpeta
            central.u32(isDirectory ? (0o40755 << 16) | 0x10 : (0o100644 << 16))
            central.u32(UInt32(offset))
            central.append(contentsOf: name)
        }

        var out = payload
        let centralOffset = out.count
        // El total también se anota en 32 bits. Cada entrada cabía por
        // separado, pero la suma puede no caber.
        guard centralOffset <= 0xFFFF_FFFF, central.count <= 0xFFFF_FFFF else {
            throw Failure.tooBig(destination.lastPathComponent)
        }
        out.append(central)
        out.u32(0x0605_4b50)
        out.u16(0); out.u16(0)
        out.u16(UInt16(entries.count)); out.u16(UInt16(entries.count))
        out.u32(UInt32(central.count)); out.u32(UInt32(centralOffset))
        out.u16(0)

        try out.write(to: destination, options: .atomic)
    }

    // MARK: - DEFLATE

    /// Devuelve nil si no se puede comprimir; el llamante guarda entonces el
    /// original tal cual, que es un ZIP igual de válido.
    private static func deflate(_ source: Data) -> Data? {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE,
                                      COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(stream) }

        let chunk = 128 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { destination.deallocate() }

        var output = Data()
        var failed = false
        source.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
                failed = true; return
            }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count
            while true {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = chunk
                let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunk - stream.pointee.dst_size
                if produced > 0 { output.append(destination, count: produced) }
                if status == COMPRESSION_STATUS_END { return }
                if status != COMPRESSION_STATUS_OK { failed = true; return }
            }
        }
        return failed ? nil : output
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1 == 1) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    /// El ZIP guarda un CRC32 por entrada, y las herramientas lo comprueban:
    /// sin él, `unzip -t` da el archivo por dañado aunque el contenido esté bien.
    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    // MARK: - Fecha

    /// El ZIP guarda la fecha en el formato de MS-DOS: segundos en pasos de dos
    /// y los años contados desde 1980.
    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar(identifier: .gregorian)
        let p = c.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        // El formato solo llega hasta 2107, y por arriba TAMBIÉN hay que
        // acotar: con una fecha corrupta —que las hay, y basta una— el
        // desplazamiento se salía de 16 bits y la conversión abortaba la app.
        // Una fecha rara dentro de un ZIP no es motivo para no comprimirlo.
        let year = min(2107, max(1980, p.year ?? 1980))
        let time = UInt16((p.hour ?? 0) << 11 | (p.minute ?? 0) << 5 | ((p.second ?? 0) / 2))
        let day = UInt16((year - 1980) << 9 | (p.month ?? 1) << 5 | (p.day ?? 1))
        return (time, day)
    }
}

// MARK: - Enteros del formato

private extension Data {
    mutating func u16(_ value: UInt16) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
    }

    mutating func u32(_ value: UInt32) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF)); append(UInt8((value >> 24) & 0xFF))
    }
}
