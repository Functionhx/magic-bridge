import AppKit
import AuthenticationServices
import Foundation
import MagicBridgeCore

@MainActor
final class BridgeViewModel: NSObject, ObservableObject {
    enum MigrationState: Equatable {
        case idle
        case scanning
        case opening(AppleNotesScanSummary)
        case complete(AppleNotesScanSummary)
        case needsSourceSelection(String)
        case failed(String)
    }

    enum WebsiteState: Equatable {
        case disconnected
        case restoring
        case connecting
        case connected(WebsiteIdentity)
        case failed(String)
    }

    @Published private(set) var migrationState: MigrationState = .idle
    @Published private(set) var websiteState: WebsiteState = .disconnected

    private let websiteClient: WebsiteSessionClient
    private var authenticationSession: ASWebAuthenticationSession?
    private var didRestoreWebsiteSession = false
    private let appleNotesBookmarkKey = "apple-notes-container-bookmark-v1"

    override init() {
        websiteClient = WebsiteSessionClient(
            baseURL: URL(string: "https://functionhx-spark-vault.functionhx.workers.dev")!
        )
        super.init()
    }

    var isBusy: Bool {
        switch migrationState {
        case .scanning, .opening: true
        default: false
        }
    }

    func repairAppleNotesChecklists() {
        guard !isBusy else { return }
        let scopedSource = resolvedAppleNotesSource()
        let databaseURL = scopedSource?.url.appendingPathComponent("NoteStore.sqlite")
            ?? AppleNotesStoreReader.defaultDatabaseURL
        migrationState = .scanning
        Task {
            defer { scopedSource?.stopAccessing() }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try AppleNotesStoreReader().makePrecisionArchive(
                        from: databaseURL,
                        ephemeral: true
                    )
                }.value
                let url = try PrecisionArchiveWriter.makeEphemeralURL()
                try PrecisionArchiveWriter.write(result.archive, to: url)
                migrationState = .opening(result.summary)
                try await openInMagicNotes(url)
                migrationState = .complete(result.summary)
            } catch AppleNotesStoreError.permissionDenied,
                    AppleNotesStoreError.databaseUnavailable {
                migrationState = .needsSourceSelection(
                    "请选择 Apple 备忘录数据所在的 group.com.apple.notes 文件夹。授权只读，仅用于本机迁移。"
                )
            } catch {
                migrationState = .failed(error.localizedDescription)
            }
        }
    }

    func chooseAppleNotesSource() {
        let panel = NSOpenPanel()
        panel.title = "选择 Apple 备忘录数据文件夹"
        panel.message = "请选择 ~/Library/Group Containers/group.com.apple.notes。Magic Bridge 只会读取其中的 NoteStore.sqlite。"
        panel.prompt = "授予只读访问"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let databaseURL = url.appendingPathComponent("NoteStore.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            migrationState = .needsSourceSelection(
                "所选文件夹中没有 NoteStore.sqlite，请选择 group.com.apple.notes 文件夹。"
            )
            return
        }
        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: appleNotesBookmarkKey)
            repairAppleNotesChecklists()
        } catch {
            migrationState = .failed("无法保存只读授权：\(error.localizedDescription)")
        }
    }

    func resetMigrationStatus() {
        migrationState = .idle
    }

    func restoreWebsiteSessionIfNeeded() async {
        guard !didRestoreWebsiteSession else { return }
        didRestoreWebsiteSession = true
        websiteState = .restoring
        do {
            if let identity = try await websiteClient.restore() {
                websiteState = .connected(identity)
            } else {
                websiteState = .disconnected
            }
        } catch {
            websiteState = .failed(error.localizedDescription)
        }
    }

    func connectWebsite() {
        guard authenticationSession == nil else { return }
        do {
            let credentials = try WebsitePKCECredentials.make()
            let authorizationURL = try websiteClient.authorizationURL(
                credentials: credentials
            )
            websiteState = .connecting
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: "magicbridge"
            ) { [weak self] callbackURL, error in
                Task { @MainActor [weak self] in
                    await self?.finishWebsiteLogin(
                        callbackURL: callbackURL,
                        error: error,
                        credentials: credentials
                    )
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session
            if !session.start() {
                authenticationSession = nil
                websiteState = .failed("无法打开 GitHub 登录窗口，请稍后重试。")
            }
        } catch {
            websiteState = .failed(error.localizedDescription)
        }
    }

    func disconnectWebsite() {
        authenticationSession?.cancel()
        authenticationSession = nil
        Task {
            do {
                try await websiteClient.disconnect()
                websiteState = .disconnected
            } catch {
                websiteState = .failed(error.localizedDescription)
            }
        }
    }

    private func finishWebsiteLogin(
        callbackURL: URL?,
        error: Error?,
        credentials: WebsitePKCECredentials
    ) async {
        authenticationSession = nil
        if let authenticationError = error as? ASWebAuthenticationSessionError,
           authenticationError.code == .canceledLogin {
            websiteState = .disconnected
            return
        }
        if let error {
            websiteState = .failed(error.localizedDescription)
            return
        }
        guard let callbackURL,
              callbackURL.scheme == "magicbridge",
              callbackURL.host == "oauth",
              callbackURL.path == "/callback",
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.queryItems?.first(where: { $0.name == "state" })?.value == credentials.state,
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            websiteState = .failed(WebsiteSessionError.invalidCallback.localizedDescription)
            return
        }
        do {
            let identity = try await websiteClient.exchange(
                code: code,
                credentials: credentials
            )
            websiteState = .connected(identity)
        } catch {
            websiteState = .failed(error.localizedDescription)
        }
    }

    private func openInMagicNotes(_ archiveURL: URL) async throws {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "cn.com.fanyuchen.MagicNotes"
        ) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "没有找到 Magic Notes，请先安装或运行一次 Magic Notes。",
            ])
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let _: Void = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [archiveURL],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func resolvedAppleNotesSource() -> SecurityScopedAppleNotesSource? {
        guard let bookmark = UserDefaults.standard.data(forKey: appleNotesBookmarkKey) else {
            return nil
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                let refreshed = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(refreshed, forKey: appleNotesBookmarkKey)
            }
            let didStart = url.startAccessingSecurityScopedResource()
            return SecurityScopedAppleNotesSource(url: url, didStart: didStart)
        } catch {
            UserDefaults.standard.removeObject(forKey: appleNotesBookmarkKey)
            return nil
        }
    }
}

private struct SecurityScopedAppleNotesSource: @unchecked Sendable {
    var url: URL
    var didStart: Bool

    func stopAccessing() {
        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

extension BridgeViewModel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(
        for _: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
    }
}
