import Foundation
import zlib

public final class FlareMessageDecoder: PhoenixChannelClient.MessageDecoder {
    public init() {}

    public func decode(text: String) throws -> String? {
        return text
    }

    public func decode(data: Data) throws -> String? {
        guard !data.isEmpty else { return nil }

        let start = data.startIndex
        if data[start] == 1 {
            var offset = 1

            guard data.count >= offset + 4 else { return nil }
            let headerLen = Int(readUInt32BE(data: data, offset: offset))
            offset += 4

            guard data.count >= offset + headerLen else { return nil }
            let headerData = data.subdata(in: (start + offset)..<(start + offset + headerLen))
            offset += headerLen

            guard let headerJson = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else { return nil }

            guard data.count >= offset + 4 else { return nil }
            let layoutLen = Int(readUInt32BE(data: data, offset: offset))
            offset += 4

            guard data.count >= offset + layoutLen else { return nil }
            let layoutGz = data.subdata(in: (start + offset)..<(start + offset + layoutLen))
            offset += layoutLen

            guard data.count >= offset + 4 else { return nil }
            let varsLen = Int(readUInt32BE(data: data, offset: offset))
            offset += 4

            guard data.count >= offset + varsLen else { return nil }
            let varsGz = data.subdata(in: (start + offset)..<(start + offset + varsLen))

            let layoutData = decompressGzip(data: layoutGz) ?? Data()
            let varsData = decompressGzip(data: varsGz) ?? Data()

            let layoutObj = (try? JSONSerialization.jsonObject(with: layoutData)) as? [String: Any] ?? [:]
            let varsArr = (try? JSONSerialization.jsonObject(with: varsData)) as? [Any] ?? []

            var payload = headerJson["payload"] as? [String: Any] ?? [:]
            payload["layout"] = layoutObj
            payload["variables"] = varsArr

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

    private func readUInt32BE(data: Data, offset: Int) -> UInt32 {
        let idx = data.startIndex + offset
        let b0 = UInt32(data[idx])
        let b1 = UInt32(data[idx + 1])
        let b2 = UInt32(data[idx + 2])
        let b3 = UInt32(data[idx + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private func decompressGzip(data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        var status: Int32 = inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
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