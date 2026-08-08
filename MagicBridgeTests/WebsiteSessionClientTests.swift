import Foundation
import XCTest
@testable import MagicBridgeCore

final class WebsiteSessionClientTests: XCTestCase {
    func testPKCECredentialsAndAuthorizationURLUseS256() async throws {
        let credentials = try WebsitePKCECredentials.make()
        XCTAssertTrue((43...128).contains(credentials.verifier.count))
        XCTAssertTrue((43...128).contains(credentials.challenge.count))
        XCTAssertTrue((24...128).contains(credentials.state.count))

        let client = WebsiteSessionClient(
            baseURL: try XCTUnwrap(URL(string: "https://vault.example")),
            transport: StubWebsiteTransport(responses: []),
            store: MemoryWebsiteSessionStore()
        )
        let url = try client.authorizationURL(credentials: credentials)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.path, "/auth/native/login")
        XCTAssertEqual(query["code_challenge"], credentials.challenge)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["state"], credentials.state)
    }

    func testExchangeStoresOnlySealedSessionAndRestoreUsesBearerToken() async throws {
        let exchange = #"{"authenticated":true,"session":"sealed-native-session","user":{"id":172989722,"login":"Functionhx"}}"#
        let restored = #"{"authenticated":true,"user":{"id":172989722,"login":"Functionhx"}}"#
        let transport = StubWebsiteTransport(
            responses: [
                .json(exchange, status: 200),
                .json(restored, status: 200, headers: ["X-Magic-Bridge-Session": "rotated-native-session"]),
            ]
        )
        let store = MemoryWebsiteSessionStore()
        let client = WebsiteSessionClient(
            baseURL: try XCTUnwrap(URL(string: "https://vault.example")),
            transport: transport,
            store: store
        )
        let credentials = WebsitePKCECredentials(
            verifier: String(repeating: "v", count: 64),
            challenge: String(repeating: "c", count: 43),
            state: String(repeating: "s", count: 32)
        )

        let identity = try await client.exchange(code: String(repeating: "a", count: 43), credentials: credentials)
        XCTAssertEqual(identity, WebsiteIdentity(id: 172989722, login: "Functionhx"))
        let exchangedToken = await store.currentToken()
        XCTAssertEqual(exchangedToken, "sealed-native-session")

        let restoredIdentity = try await client.restore()
        XCTAssertEqual(restoredIdentity, identity)
        let rotatedToken = await store.currentToken()
        XCTAssertEqual(rotatedToken, "rotated-native-session")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/auth/native/session")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Origin"))
        let exchangeBody = try XCTUnwrap(requests[0].httpBody)
        let exchangeJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: exchangeBody) as? [String: String])
        XCTAssertEqual(exchangeJSON["code_verifier"], credentials.verifier)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer sealed-native-session")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Origin"))
    }

    func testExpiredSessionIsRemovedFromStore() async throws {
        let transport = StubWebsiteTransport(responses: [.json(#"{"error":{"message":"expired"}}"#, status: 401)])
        let store = MemoryWebsiteSessionStore(token: "expired-session")
        let client = WebsiteSessionClient(
            baseURL: try XCTUnwrap(URL(string: "https://vault.example")),
            transport: transport,
            store: store
        )

        let restored = try await client.restore()
        let storedToken = await store.currentToken()
        XCTAssertNil(restored)
        XCTAssertNil(storedToken)
    }
}

private actor MemoryWebsiteSessionStore: WebsiteSessionStoring {
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func load() async throws -> String? {
        token
    }

    func save(_ token: String) async throws {
        self.token = token
    }

    func delete() async throws {
        token = nil
    }

    func currentToken() -> String? {
        token
    }
}

private actor StubWebsiteTransport: WebsiteTransporting {
    struct Response: Sendable {
        var data: Data
        var status: Int
        var headers: [String: String]

        static func json(
            _ string: String,
            status: Int,
            headers: [String: String] = [:]
        ) -> Response {
            Response(data: Data(string.utf8), status: status, headers: headers)
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw WebsiteSessionError.invalidResponse }
        let response = responses.removeFirst()
        let http = try XCTUnwrap(
            HTTPURLResponse(
                url: request.url ?? URL(fileURLWithPath: "/"),
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
            )
        )
        return (response.data, http)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
