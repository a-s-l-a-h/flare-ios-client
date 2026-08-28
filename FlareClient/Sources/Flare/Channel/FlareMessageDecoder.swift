import Foundation
import zlib

/// Optimized binary frame decoder matching Flare.Serializer (vsn 1).
/// Uses RFC 1952 Zlib streams with MAX_WBITS + 32 window bits for hardware-accelerated gzip decompression.
public final class FlareMessageDecoder: PhoenixChannelClient.MessageDecoder {
    public init() {}

    public func decode(text: String) throws -> String? {
        return text
    }

    public func decode(data: Data) throws -> String? {
        guard !data.isEmpty else { return nil }

        // Flare Binary Frame v1 identifier check
        if data[0] == 1 {
            var offset = 1

            // 1. Unpack Header Length & Payload
            guard data.count >= offset + 4 else { return nil }
            let headerLen = Int(data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            offset += 4

            guard data.count >= offset + headerLen else { return nil }
            let headerData = data.subdata(in: offset..<offset+headerLen)
            offset += headerLen

            guard var headerJson = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else { return nil }

            // 2. Unpack GZIP Layout Block
            guard data.count >= offset + 4 else { return nil }
            let layoutLen = Int(data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            offset += 4

            guard data.count >= offset + layoutLen else { return nil }
            let layoutGz = data.subdata(in: offset..<offset+layoutLen)
            offset += layoutLen

            // 3. Unpack GZIP Variables Block
            guard data.count >= offset + 4 else { return nil }
            let varsLen = Int(data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
            offset += 4

            guard data.count >= offset + varsLen else { return nil }
            let varsGz = data.subdata(in: offset..<offset+varsLen)

            // 4. Stream Decompress
            let layoutData = decompressGzip(data: layoutGz) ?? Data()
            let varsData = decompressGzip(data: varsGz) ?? Data()

            let layoutObj = (try? JSONSerialization.jsonObject(with: layoutData)) as? [String: Any] ?? [:]
            let varsArr = (try? JSONSerialization.jsonObject(with: varsData)) as? [Any] ?? []

            // 5. Reconstruct Wire Payload
            var payload = headerJson["payload"] as? [String: Any] ?? [:]
            payload["layout"] = layoutObj
            payload["variables"] = varsArr

            // 6. Output Phoenix Standard Message Array [join_ref, ref, topic, event, payload]
            let phxMessage: [Any] = [
                headerJson["join_ref"] ?? NSNull(),
                headerJson["ref"] ?? NSNull(),
                headerJson["topic"] ?? "",
                headerJson["event"] ?? "",
                payload
            ]

            let finalData = try JSONSerialization.data(withJSONObject: phxMessage)
            return String(data: finalData, encoding: .utf8)
        }

        return String(data: data, encoding: .utf8)
    }

    private func decompressGzip(data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        // MAX_WBITS + 32 tells zlib to seek and validate standard RFC 1952 gzip stream headers automatically
        var status: Int32 = inflateInit2_(&stream, MAX_WBITS + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var decompressed = Data(capacity: data.count * 3)
        let bufferSize = 65536
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: rawBuffer.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)

            repeat {
                stream.next_out = buffer
                stream.avail_out = uInt(bufferSize)

                status = inflate(&stream, Z_NO_FLUSH)
                let bytesRead = bufferSize - Int(stream.avail_out)
                if bytesRead > 0 {
                    decompressed.append(buffer, count: bytesRead)
                }
            } while status == Z_OK
        }

        return (status == Z_STREAM_END || status == Z_OK) ? decompressed : nil
    }
}