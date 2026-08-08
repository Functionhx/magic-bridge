import Foundation

public struct DecodedAppleNote: Equatable, Sendable {
    public var text: String
    public var checklistParagraphs: [ChecklistParagraph]

    public init(text: String, checklistParagraphs: [ChecklistParagraph]) {
        self.text = text
        self.checklistParagraphs = checklistParagraphs
    }
}

public struct AppleNotesChecklistDecoder: Sendable {
    public init() {}

    public func decode(_ compressedData: Data) throws -> DecodedAppleNote {
        let root = try ProtobufMessage(data: GzipDecoder.decode(compressedData))
        guard let documentData = root.firstBytes(2),
              let noteData = try ProtobufMessage(data: documentData).firstBytes(3) else {
            throw ProtobufError.malformed
        }
        let note = try ProtobufMessage(data: noteData)
        guard let textData = note.firstBytes(2),
              let text = String(data: textData, encoding: .utf8) else {
            throw ProtobufError.malformed
        }

        var utf16Offset = 0
        var checklistByLine: [Int: ChecklistParagraph] = [:]
        for runData in note.allBytes(5) {
            let run = try ProtobufMessage(data: runData)
            let length = Int(run.firstVarint(1) ?? 0)
            guard length >= 0 else { throw ProtobufError.malformed }

            if let styleData = run.firstBytes(2),
               let state = try checklistState(from: styleData) {
                let line = Self.lineIndex(in: text, atUTF16Offset: utf16Offset)
                let item = ChecklistParagraph(
                    lineIndex: line,
                    isChecked: state.isChecked,
                    indentLevel: state.indentLevel
                )
                if let existing = checklistByLine[line], existing != item {
                    throw ProtobufError.malformed
                }
                checklistByLine[line] = item
            }
            guard utf16Offset <= Int.max - length else { throw ProtobufError.malformed }
            utf16Offset += length
        }

        return DecodedAppleNote(
            text: text,
            checklistParagraphs: checklistByLine.values.sorted {
                $0.lineIndex < $1.lineIndex
            }
        )
    }

    private func checklistState(
        from paragraphStyleData: Data
    ) throws -> (isChecked: Bool, indentLevel: Int)? {
        let style = try ProtobufMessage(data: paragraphStyleData)
        let indentLevel = Int(style.firstVarint(4) ?? 0)

        // Across the current Apple Notes stores (including macOS 26), a real
        // checklist is represented by ParagraphStyle.checklist (field 5),
        // containing a UUID (field 1) and completion state (field 2).
        if let checklistData = style.firstBytes(5) {
            let checklist = try ProtobufMessage(data: checklistData)
            guard let identifier = checklist.firstBytes(1), identifier.count == 16 else {
                return nil
            }
            return (checklist.firstVarint(2) != 0, max(0, indentLevel))
        }
        return nil
    }

    private static func lineIndex(in text: String, atUTF16Offset offset: Int) -> Int {
        let utf16 = Array(text.utf16)
        let upperBound = min(max(0, offset), utf16.count)
        return utf16[..<upperBound].reduce(into: 0) { count, value in
            if value == 0x000a { count += 1 }
        }
    }
}
