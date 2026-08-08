import Foundation
import zlib

enum GzipDecoder {
    private static let maximumOutputSize = 64 * 1_024 * 1_024

    static func decode(_ data: Data) throws -> Data {
        guard data.count >= 2, data[data.startIndex] == 0x1f,
              data[data.index(after: data.startIndex)] == 0x8b else {
            return data
        }

        var stream = z_stream()
        let initialization = inflateInit2_(
            &stream,
            15 + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initialization == Z_OK else { throw ProtobufError.malformed }
        defer { inflateEnd(&stream) }

        return try data.withUnsafeBytes { inputBuffer in
            guard let input = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw ProtobufError.malformed
            }
            stream.next_in = UnsafeMutablePointer(mutating: input)
            stream.avail_in = uInt(inputBuffer.count)

            var output = Data()
            var status = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 64 * 1_024)
                let produced = chunk.withUnsafeMutableBytes { outputBuffer -> Int in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(outputBuffer.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return outputBuffer.count - Int(stream.avail_out)
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw ProtobufError.malformed
                }
                if produced > 0 {
                    output.append(contentsOf: chunk.prefix(produced))
                }
                guard output.count <= maximumOutputSize else {
                    throw ProtobufError.decompressedPayloadTooLarge
                }
            } while status != Z_STREAM_END
            return output
        }
    }
}
