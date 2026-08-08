import Foundation
import SQLite3

public struct AppleNotesScanSummary: Equatable, Sendable {
    public var inspectedNotes: Int
    public var checklistNotes: Int
    public var checklistItems: Int
    public var lockedNotes: Int
    public var unsupportedNotes: Int

    public init(
        inspectedNotes: Int = 0,
        checklistNotes: Int = 0,
        checklistItems: Int = 0,
        lockedNotes: Int = 0,
        unsupportedNotes: Int = 0
    ) {
        self.inspectedNotes = inspectedNotes
        self.checklistNotes = checklistNotes
        self.checklistItems = checklistItems
        self.lockedNotes = lockedNotes
        self.unsupportedNotes = unsupportedNotes
    }
}

public struct AppleNotesScanResult: Equatable, Sendable {
    public var archive: PrecisionArchive
    public var summary: AppleNotesScanSummary
}

public enum AppleNotesStoreError: LocalizedError, Equatable {
    case permissionDenied
    case databaseUnavailable
    case snapshotFailed
    case metadataQueryFailed
    case metadataMissing
    case metadataInvalid
    case invalidNoteQuery

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Magic Bridge 尚无权读取 Apple 备忘录。请在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中开启 Magic Bridge。"
        case .databaseUnavailable:
            "没有找到 Apple 备忘录数据库。"
        case .snapshotFailed:
            "无法建立 Apple 备忘录的一致只读快照。"
        case .metadataQueryFailed:
            "Apple 备忘录快照无法查询存储标识。"
        case .metadataMissing:
            "Apple 备忘录快照没有存储标识。"
        case .metadataInvalid:
            "Apple 备忘录快照的存储标识格式无效。"
        case .invalidNoteQuery:
            "Apple 备忘录数据库缺少可读取的笔记表。"
        }
    }
}

public struct AppleNotesStoreReader: Sendable {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
    }

    private let decoder = AppleNotesChecklistDecoder()

    public init() {}

    public func makePrecisionArchive(
        from databaseURL: URL = Self.defaultDatabaseURL,
        ephemeral: Bool
    ) throws -> AppleNotesScanResult {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw AppleNotesStoreError.databaseUnavailable
        }
        let snapshot = try makeSnapshot(of: databaseURL)
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }

        var database: OpaquePointer?
        guard sqlite3_open_v2(snapshot.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            throw AppleNotesStoreError.snapshotFailed
        }
        defer { sqlite3_close(database) }

        let storeUUID = try readStoreUUID(database)
        var statement: OpaquePointer?
        let query = """
        SELECT n.Z_PK, COALESCE(n.ZISPASSWORDPROTECTED, 0), d.ZDATA
        FROM ZICNOTEDATA d
        JOIN ZICCLOUDSYNCINGOBJECT n ON n.Z_PK = d.ZNOTE
        WHERE d.ZDATA IS NOT NULL
          AND COALESCE(n.ZMARKEDFORDELETION, 0) = 0
        ORDER BY n.Z_PK
        """
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw AppleNotesStoreError.invalidNoteQuery
        }
        defer { sqlite3_finalize(statement) }

        var records: [PrecisionRecord] = []
        var summary = AppleNotesScanSummary()
        while sqlite3_step(statement) == SQLITE_ROW {
            summary.inspectedNotes += 1
            let primaryKey = sqlite3_column_int64(statement, 0)
            if sqlite3_column_int(statement, 1) != 0 {
                summary.lockedNotes += 1
                continue
            }
            guard let blob = sqlite3_column_blob(statement, 2) else {
                summary.unsupportedNotes += 1
                continue
            }
            let size = Int(sqlite3_column_bytes(statement, 2))
            guard size > 0 else {
                summary.unsupportedNotes += 1
                continue
            }

            do {
                let decoded = try decoder.decode(Data(bytes: blob, count: size))
                guard !decoded.checklistParagraphs.isEmpty else { continue }
                let identifier = "x-coredata://\(storeUUID)/ICNote/p\(primaryKey)"
                records.append(
                    PrecisionRecord(
                        identifier: identifier,
                        text: decoded.text,
                        checklistParagraphs: decoded.checklistParagraphs
                    )
                )
                summary.checklistNotes += 1
                summary.checklistItems += decoded.checklistParagraphs.count
            } catch {
                summary.unsupportedNotes += 1
            }
        }

        return AppleNotesScanResult(
            archive: PrecisionArchive(ephemeral: ephemeral, records: records),
            summary: summary
        )
    }

    private func makeSnapshot(of sourceURL: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MagicBridge-Snapshot", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destinationURL = directory.appendingPathComponent("NoteStore.sqlite")

        var source: OpaquePointer?
        let sourceResult = sqlite3_open_v2(
            sourceURL.path,
            &source,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard sourceResult == SQLITE_OK, let source else {
            try? FileManager.default.removeItem(at: directory)
            if sourceResult == SQLITE_AUTH || sourceResult == SQLITE_CANTOPEN {
                throw AppleNotesStoreError.permissionDenied
            }
            throw AppleNotesStoreError.snapshotFailed
        }
        defer { sqlite3_close(source) }
        sqlite3_busy_timeout(source, 5_000)

        var destination: OpaquePointer?
        guard sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let destination else {
            try? FileManager.default.removeItem(at: directory)
            throw AppleNotesStoreError.snapshotFailed
        }
        defer { sqlite3_close(destination) }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            try? FileManager.default.removeItem(at: directory)
            throw AppleNotesStoreError.snapshotFailed
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            try? FileManager.default.removeItem(at: directory)
            throw AppleNotesStoreError.snapshotFailed
        }

        // Notes keeps its live store in WAL mode. sqlite3_backup copies that
        // header flag, but the private snapshot has no matching -wal/-shm
        // sidecars. Normalize only the disposable destination to a standalone
        // database before reopening it read-only. The original store is never
        // modified.
        guard sqlite3_exec(
            destination,
            "PRAGMA journal_mode=DELETE",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            try? FileManager.default.removeItem(at: directory)
            throw AppleNotesStoreError.snapshotFailed
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destinationURL.path
        )
        return destinationURL
    }

    private func readStoreUUID(_ database: OpaquePointer) throws -> String {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT Z_UUID FROM Z_METADATA LIMIT 1",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw AppleNotesStoreError.metadataQueryFailed
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            throw AppleNotesStoreError.metadataMissing
        }
        let uuid = String(cString: value)
        guard UUID(uuidString: uuid) != nil else {
            throw AppleNotesStoreError.metadataInvalid
        }
        return uuid.uppercased()
    }
}
