import Foundation
import MagicBridgeCore

struct ExportArguments {
    var databaseURL = AppleNotesStoreReader.defaultDatabaseURL
    var outputURL: URL?
    var ephemeral = false

    init(_ arguments: [String]) throws {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--database":
                guard let value = iterator.next() else { throw ArgumentError.missingValue(argument) }
                databaseURL = URL(fileURLWithPath: value)
            case "--output":
                guard let value = iterator.next() else { throw ArgumentError.missingValue(argument) }
                outputURL = URL(fileURLWithPath: value)
            case "--ephemeral":
                ephemeral = true
            default:
                throw ArgumentError.unknownArgument(argument)
            }
        }
    }
}

enum ArgumentError: LocalizedError {
    case missingValue(String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(argument): "\(argument) 缺少路径。"
        case let .unknownArgument(argument): "未知参数：\(argument)"
        }
    }
}

do {
    let arguments = try ExportArguments(CommandLine.arguments)
    let result = try AppleNotesStoreReader().makePrecisionArchive(
        from: arguments.databaseURL,
        ephemeral: arguments.ephemeral
    )
    let outputURL = try arguments.outputURL ?? PrecisionArchiveWriter.makeEphemeralURL()
    try PrecisionArchiveWriter.write(result.archive, to: outputURL)
    let summary = result.summary
    print("archive=\(outputURL.path)")
    print("inspected=\(summary.inspectedNotes) checklist_notes=\(summary.checklistNotes) checklist_items=\(summary.checklistItems) locked=\(summary.lockedNotes) unsupported=\(summary.unsupportedNotes)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
