import Foundation

/// AVFoundation does not consistently expose Vorbis comments or FLAC pictures.
/// Read only metadata blocks, with strict bounds; audio decoding stays native.
struct FLACMetadata: Sendable {
    var tags: [String: String] = [:]
    var artwork: Data?

    enum ParseError: Error { case malformed, tooLarge }

    static func read(from url: URL) throws -> FLACMetadata {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func read(_ count: Int) throws -> Data {
            let data = try handle.read(upToCount: count) ?? Data()
            guard data.count == count else { throw ParseError.malformed }
            return data
        }
        guard try read(4) == Data("fLaC".utf8) else { throw ParseError.malformed }
        var result = FLACMetadata()
        var total = 0
        for _ in 0..<256 {
            try Task.checkCancellation()
            let header = try read(4)
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            total += length
            guard total <= 64 * 1_024 * 1_024 else { throw ParseError.tooLarge }
            let kind = header[0] & 0x7f
            if kind == 4 || kind == 6 {
                let block = try read(length)
                if kind == 4 { result.tags = try comments(block) }
                else if result.artwork == nil { result.artwork = try picture(block) }
            } else {
                try handle.seek(toOffset: handle.offset() + UInt64(length))
            }
            if header[0] & 0x80 != 0 { return result }
        }
        throw ParseError.tooLarge
    }

    static func comments(_ data: Data) throws -> [String: String] {
        var reader = ByteReader(data: data)
        _ = try reader.bytes(Int(reader.uint32(littleEndian: true))) // vendor
        let count = try reader.uint32(littleEndian: true)
        guard count <= 10_000 else { throw ParseError.tooLarge }
        var result: [String: String] = [:]
        for _ in 0..<count {
            let length = try reader.uint32(littleEndian: true)
            let bytes = try reader.bytes(Int(length))
            guard let string = String(data: bytes, encoding: .utf8), let equal = string.firstIndex(of: "=") else { continue }
            let key = string[..<equal].uppercased()
            let value = String(string[string.index(after: equal)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if result[key] == nil && !value.isEmpty { result[key] = value }
        }
        return result
    }

    static func picture(_ data: Data) throws -> Data? {
        var reader = ByteReader(data: data)
        let type = try reader.uint32()
        let mimeLength = try reader.uint32()
        let mime = try reader.bytes(Int(mimeLength))
        let descriptionLength = try reader.uint32()
        _ = try reader.bytes(Int(descriptionLength))
        _ = try reader.bytes(16) // dimensions, depth, palette
        let imageLength = try reader.uint32()
        let image = try reader.bytes(Int(imageLength))
        // Linked pictures are URLs, not artwork. Prefer front cover / unspecified.
        guard mime != Data("-->".utf8), type == 3 || type == 0 else { return nil }
        return image
    }
}

private struct ByteReader {
    let data: Data
    var offset = 0

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= data.count - offset else { throw FLACMetadata.ParseError.malformed }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func uint32(littleEndian: Bool = false) throws -> UInt32 {
        let bytes = try bytes(4)
        let ordered = littleEndian ? Array(bytes.reversed()) : Array(bytes)
        return ordered.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
