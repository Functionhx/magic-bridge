import Foundation

enum ProtobufError: LocalizedError, Equatable {
    case malformed
    case unsupportedWireType(Int)
    case decompressedPayloadTooLarge

    var errorDescription: String? {
        switch self {
        case .malformed:
            "Apple 备忘录数据结构不完整。"
        case let .unsupportedWireType(type):
            "Apple 备忘录包含暂不支持的 protobuf wire type：\(type)。"
        case .decompressedPayloadTooLarge:
            "单条 Apple 备忘录解压后超过安全上限。"
        }
    }
}

struct ProtobufField: Equatable {
    enum Value: Equatable {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
    }

    var number: Int
    var value: Value
}

struct ProtobufMessage: Equatable {
    var fields: [ProtobufField]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        var cursor = 0
        var result: [ProtobufField] = []
        while cursor < bytes.count {
            let key = try Self.readVarint(bytes, cursor: &cursor)
            let number = Int(key >> 3)
            let wireType = Int(key & 0x07)
            guard number > 0 else { throw ProtobufError.malformed }

            let value: ProtobufField.Value
            switch wireType {
            case 0:
                value = .varint(try Self.readVarint(bytes, cursor: &cursor))
            case 1:
                guard cursor <= bytes.count - 8 else { throw ProtobufError.malformed }
                var number: UInt64 = 0
                for shift in 0..<8 {
                    number |= UInt64(bytes[cursor + shift]) << UInt64(shift * 8)
                }
                cursor += 8
                value = .fixed64(number)
            case 2:
                let length = try Self.readVarint(bytes, cursor: &cursor)
                guard length <= UInt64(Int.max) else { throw ProtobufError.malformed }
                let count = Int(length)
                guard count >= 0, cursor <= bytes.count - count else {
                    throw ProtobufError.malformed
                }
                value = .bytes(Data(bytes[cursor..<(cursor + count)]))
                cursor += count
            case 5:
                guard cursor <= bytes.count - 4 else { throw ProtobufError.malformed }
                var number: UInt32 = 0
                for shift in 0..<4 {
                    number |= UInt32(bytes[cursor + shift]) << UInt32(shift * 8)
                }
                cursor += 4
                value = .fixed32(number)
            default:
                throw ProtobufError.unsupportedWireType(wireType)
            }
            result.append(ProtobufField(number: number, value: value))
        }
        fields = result
    }

    func firstBytes(_ number: Int) -> Data? {
        fields.lazy.compactMap { field -> Data? in
            guard field.number == number, case let .bytes(value) = field.value else {
                return nil
            }
            return value
        }.first
    }

    func allBytes(_ number: Int) -> [Data] {
        fields.compactMap { field in
            guard field.number == number, case let .bytes(value) = field.value else {
                return nil
            }
            return value
        }
    }

    func firstVarint(_ number: Int) -> UInt64? {
        fields.lazy.compactMap { field -> UInt64? in
            guard field.number == number, case let .varint(value) = field.value else {
                return nil
            }
            return value
        }.first
    }

    private static func readVarint(_ bytes: [UInt8], cursor: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard cursor < bytes.count else { throw ProtobufError.malformed }
            let byte = bytes[cursor]
            cursor += 1
            result |= UInt64(byte & 0x7f) << UInt64(shift)
            if byte & 0x80 == 0 {
                return result
            }
        }
        throw ProtobufError.malformed
    }
}
