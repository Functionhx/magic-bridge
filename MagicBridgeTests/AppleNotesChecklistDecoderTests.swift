import Foundation
import XCTest
import zlib
@testable import MagicBridgeCore

final class AppleNotesChecklistDecoderTests: XCTestCase {
    func testDecodesChecklistStylesUsingUTF16Offsets() throws {
        let text = "标题😀\n待处理\n已完成\n"
        let titleLength = "标题😀\n".utf16.count
        let pendingLength = "待处理\n".utf16.count
        let completedLength = "已完成\n".utf16.count
        let payload = Fixture.noteStore(
            text: text,
            runs: [
                Fixture.run(length: titleLength),
                Fixture.run(length: pendingLength, style: .checklist(checked: false, indent: 1)),
                Fixture.run(length: completedLength, style: .checklist(checked: true, indent: 0)),
            ]
        )

        let decoded = try AppleNotesChecklistDecoder().decode(try gzip(payload))

        XCTAssertEqual(decoded.text, text)
        XCTAssertEqual(
            decoded.checklistParagraphs,
            [
                ChecklistParagraph(lineIndex: 1, isChecked: false, indentLevel: 1),
                ChecklistParagraph(lineIndex: 2, isChecked: true, indentLevel: 0),
            ]
        )
    }

    func testSplitFormattingRunsDoNotDuplicateChecklistParagraph() throws {
        let text = "标题\n加粗任务\n"
        let payload = Fixture.noteStore(
            text: text,
            runs: [
                Fixture.run(length: "标题\n".utf16.count),
                Fixture.run(length: 2, style: .checklist(checked: false, indent: 0)),
                Fixture.run(
                    length: "加粗任务\n".utf16.count - 2,
                    style: .checklist(checked: false, indent: 0)
                ),
            ]
        )

        let decoded = try AppleNotesChecklistDecoder().decode(payload)

        XCTAssertEqual(
            decoded.checklistParagraphs,
            [ChecklistParagraph(lineIndex: 1, isChecked: false, indentLevel: 0)]
        )
    }

    func testUnrelatedParagraphUUIDIsNotTreatedAsChecklist() throws {
        let text = "普通段落\n"
        let payload = Fixture.noteStore(
            text: text,
            runs: [
                Fixture.run(
                    length: text.utf16.count,
                    style: .paragraphIdentity
                ),
            ]
        )

        let decoded = try AppleNotesChecklistDecoder().decode(payload)

        XCTAssertTrue(decoded.checklistParagraphs.isEmpty)
    }

    func testRejectsMalformedGzip() {
        XCTAssertThrowsError(
            try AppleNotesChecklistDecoder().decode(Data([0x1f, 0x8b, 0x00]))
        )
    }

    private func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            15 + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            throw ProtobufError.malformed
        }
        defer { deflateEnd(&stream) }

        return try data.withUnsafeBytes { inputBuffer in
            guard let input = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw ProtobufError.malformed
            }
            stream.next_in = UnsafeMutablePointer(mutating: input)
            stream.avail_in = uInt(inputBuffer.count)
            var output = Data()
            var status = Z_OK
            repeat {
                var chunk = [UInt8](repeating: 0, count: 4_096)
                let produced = chunk.withUnsafeMutableBytes { buffer -> Int in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(buffer.count)
                    status = deflate(&stream, Z_FINISH)
                    return buffer.count - Int(stream.avail_out)
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw ProtobufError.malformed
                }
                output.append(contentsOf: chunk.prefix(produced))
            } while status != Z_STREAM_END
            return output
        }
    }
}

private enum Fixture {
    enum Style {
        case checklist(checked: Bool, indent: Int)
        case paragraphIdentity
    }

    static func noteStore(text: String, runs: [Data]) -> Data {
        var note = bytesField(2, Data(text.utf8))
        for run in runs { note.append(bytesField(5, run)) }
        let document = varintField(2, 1) + bytesField(3, note)
        return bytesField(2, document)
    }

    static func run(length: Int, style: Style? = nil) -> Data {
        var result = varintField(1, UInt64(length))
        if let style { result.append(bytesField(2, paragraphStyle(style))) }
        return result
    }

    private static func paragraphStyle(_ style: Style) -> Data {
        switch style {
        case let .checklist(checked, indent):
            let checklist = bytesField(1, Data(repeating: 0xa1, count: 16))
                + varintField(2, checked ? 1 : 0)
            return varintField(1, 103)
                + varintField(4, UInt64(indent))
                + bytesField(5, checklist)
        case .paragraphIdentity:
            // Current Notes stores also attach a 16-byte paragraph identity
            // at field 9. It is not a checklist marker.
            return varintField(3, 1)
                + bytesField(9, Data(repeating: 0xb2, count: 16))
        }
    }

    private static func varintField(_ field: UInt64, _ value: UInt64) -> Data {
        varint((field << 3) | 0) + varint(value)
    }

    private static func bytesField(_ field: UInt64, _ value: Data) -> Data {
        varint((field << 3) | 2) + varint(UInt64(value.count)) + value
    }

    private static func varint(_ value: UInt64) -> Data {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7f)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining != 0
        return Data(bytes)
    }
}
