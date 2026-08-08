import CryptoKit
import Foundation
import Security

public struct WebsiteIdentity: Codable, Equatable, Sendable {
    public var id: Int
    public var login: String

    public init(id: Int, login: String) {
        self.id = id
        self.login = login
    }
}

public struct WebsitePKCECredentials: Equatable, Sendable {
    public var verifier: String
    public var challenge: String
    public var state: String

    public init(verifier: String, challenge: String, state: String) {
        self.verifier = verifier
        self.challenge = challenge
        self.state = state
    }

    public static func make() throws -> WebsitePKCECredentials {
        let verifier = try randomBase64URL(byteCount: 48)
        let state = try randomBase64URL(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return WebsitePKCECredentials(
            verifier: verifier,
            challenge: Data(digest).base64URLEncodedString(),
            state: state
        )
    }

    private static func randomBase64URL(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw WebsiteSessionError.randomnessUnavailable
        }
        return Data(bytes).base64URLEncodedString()
    }
}

public enum WebsiteSessionError: LocalizedError, Equatable {
    case invalidCallback
    case invalidResponse
    case keychain(Int32)
    case randomnessUnavailable
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCallback:
            "网站登录回调不完整或已被替换，请重新连接。"
        case .invalidResponse:
            "网站返回了无法识别的连接结果。"
        case let .keychain(status):
            "无法访问钥匙串（\(status)）。"
        case .randomnessUnavailable:
            "系统无法生成安全随机数，请稍后重试。"
        case let .requestFailed(message):
            message
        }
    }
}

public protocol WebsiteSessionStoring: Sendable {
    func load() async throws -> String?
    func save(_ token: String) async throws
    func delete() async throws
}

public protocol WebsiteTransporting: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionWebsiteTransport: WebsiteTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WebsiteSessionError.invalidResponse
        }
        return (data, response)
    }
}

public struct KeychainWebsiteSessionStore: WebsiteSessionStoring {
    private let service: String
    private let account: String

    public init(
        service: String = "cn.com.fanyuchen.MagicBridge.website-session",
        account: String = "spark-vault"
    ) {
        self.service = service
        self.account = account
    }

    public func load() async throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw WebsiteSessionError.keychain(status)
        }
        return token
    }

    public func save(_ token: String) async throws {
        let data = Data(token.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw WebsiteSessionError.keychain(updateStatus)
        }
        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WebsiteSessionError.keychain(addStatus)
        }
    }

    public func delete() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WebsiteSessionError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public actor WebsiteSessionClient {
    private struct ExchangeRequest: Encodable {
        var code: String
        var codeVerifier: String

        enum CodingKeys: String, CodingKey {
            case code
            case codeVerifier = "code_verifier"
        }
    }

    private struct ExchangeResponse: Decodable {
        var authenticated: Bool
        var session: String
        var user: WebsiteIdentity
    }

    private struct SessionResponse: Decodable {
        var authenticated: Bool
        var user: WebsiteIdentity
    }

    private struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            var message: String
        }

        var error: Payload
    }

    private let baseURL: URL
    private let transport: any WebsiteTransporting
    private let store: any WebsiteSessionStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        transport: any WebsiteTransporting = URLSessionWebsiteTransport(),
        store: any WebsiteSessionStoring = KeychainWebsiteSessionStore()
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.store = store
    }

    public nonisolated func authorizationURL(credentials: WebsitePKCECredentials) throws -> URL {
        let endpoint = baseURL.appending(path: "auth/native/login")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw WebsiteSessionError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "code_challenge", value: credentials.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: credentials.state),
        ]
        guard let url = components.url else { throw WebsiteSessionError.invalidResponse }
        return url
    }

    public func exchange(
        code: String,
        credentials: WebsitePKCECredentials
    ) async throws -> WebsiteIdentity {
        var request = URLRequest(url: baseURL.appending(path: "auth/native/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            ExchangeRequest(code: code, codeVerifier: credentials.verifier)
        )
        let (data, response) = try await transport.data(for: request)
        try validate(response, data: data)
        let payload = try decoder.decode(ExchangeResponse.self, from: data)
        guard payload.authenticated, !payload.session.isEmpty else {
            throw WebsiteSessionError.invalidResponse
        }
        try await store.save(payload.session)
        return payload.user
    }

    public func restore() async throws -> WebsiteIdentity? {
        guard let token = try await store.load(), !token.isEmpty else { return nil }
        var request = URLRequest(url: baseURL.appending(path: "api/native/session"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 401 {
            try await store.delete()
            return nil
        }
        try validate(response, data: data)
        if let rotated = response.value(forHTTPHeaderField: "X-Magic-Bridge-Session"),
           !rotated.isEmpty {
            try await store.save(rotated)
        }
        let payload = try decoder.decode(SessionResponse.self, from: data)
        guard payload.authenticated else { throw WebsiteSessionError.invalidResponse }
        return payload.user
    }

    public func disconnect() async throws {
        try await store.delete()
    }

    private func validate(_ response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
               !envelope.error.message.isEmpty {
                throw WebsiteSessionError.requestFailed(envelope.error.message)
            }
            throw WebsiteSessionError.requestFailed("网站连接失败（HTTP \(response.statusCode)）。")
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
