import Foundation

public struct PrecisionArchive: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var ephemeral: Bool
    public var records: [PrecisionRecord]

    public init(
        version: Int = currentVersion,
        generatedAt: Date = .now,
        ephemeral: Bool,
        records: [PrecisionRecord]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.ephemeral = ephemeral
        self.records = records
    }
}

public struct PrecisionRecord: Codable, Equatable, Sendable {
    public var identifier: String
    public var text: String
    public var checklistParagraphs: [ChecklistParagraph]

    public init(
        identifier: String,
        text: String,
        checklistParagraphs: [ChecklistParagraph]
    ) {
        self.identifier = identifier
        self.text = text
        self.checklistParagraphs = checklistParagraphs
    }
}

public struct ChecklistParagraph: Codable, Equatable, Sendable {
    public var lineIndex: Int
    public var isChecked: Bool
    public var indentLevel: Int

    public init(lineIndex: Int, isChecked: Bool, indentLevel: Int) {
        self.lineIndex = lineIndex
        self.isChecked = isChecked
        self.indentLevel = indentLevel
    }
}

public enum PrecisionArchiveWriter {
    public static func write(_ archive: PrecisionArchive, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    public static func makeEphemeralURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MagicBridge", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
            .appendingPathComponent("Apple-Notes-Checklists")
            .appendingPathExtension("magicnoteschecklists")
    }
}
