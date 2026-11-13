import Foundation

/// One HTTP round-trip's result: the status code and the raw
/// body. Callers decide what a status means (401 = signed out,
/// 402 = subscription required, anything else per endpoint).
struct APIResponse {
    let status: Int
    let data: Data

    /// The body parsed as a JSON object, or nil if it is not one.
    var jsonObject: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The server's own error words, when it sent any. The
    /// tracker server answers failures with a JSON body whose
    /// "error" field carries the message (plain "message" is
    /// checked too, defensively).
    var serverMessage: String? {
        guard let json = jsonObject else { return nil }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        return nil
    }
}

enum APIClientError: Error {
    case badPath(String)
    case notHTTPResponse
}

/// The native layer's one door to the whatdimake.com server.
///
/// AUTH SHAPE: the server uses express-session cookies (the
/// session cookie is set by POST /auth/login and /auth/signup;
/// HttpOnly, SameSite=lax, Secure in production). There is no
/// token API and no CORS — neither matters here: this is native
/// URLSession, not a browser. The session's cookie jar is
/// HTTPCookieStorage.shared, which is per-app and persists on
/// disk across launches by itself.
///
/// USERDEFAULTS MIRROR: on top of that, after every response the
/// cookies for the server's host are mirrored into UserDefaults
/// (plain name/value/domain/path/expiry/secure records — the
/// session cookie is HttpOnly but that only restricts web-page
/// scripts, not this app), and on launch the mirror is loaded
/// back into the shared jar before the first request. That belt
/// and suspenders is what makes "still signed in after
/// relaunch" not depend on any one storage layer's habits.
/// Sign-out clears BOTH stores.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let mirrorKey = "whatdimake.cookieMirror.v1"

    /// The serializable form of one cookie for the mirror.
    private struct StoredCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expiresAt: TimeInterval?
        let isSecure: Bool
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
        restoreMirror()
    }

    // MARK: - Generic verbs

    func get(_ path: String) async throws -> APIResponse {
        try await send(path: path, method: "GET", jsonBody: nil)
    }

    func post(_ path: String, json: [String: Any]) async throws -> APIResponse {
        try await send(path: path, method: "POST", jsonBody: json)
    }

    func put(_ path: String, json: [String: Any]) async throws -> APIResponse {
        try await send(path: path, method: "PUT", jsonBody: json)
    }

    func delete(_ path: String) async throws -> APIResponse {
        try await send(path: path, method: "DELETE", jsonBody: nil)
    }

    /// POSTs raw bytes with an explicit content type — the
    /// vision reader's door (POST /api/vision/scan?kind=…): the
    /// server takes the photo itself as the request body, the
    /// same shape the website's scan sends. A longer timeout
    /// than the default: the reader can take a while.
    func postRaw(_ path: String, data: Data, contentType: String) async throws -> APIResponse {
        guard let url = URL(string: path, relativeTo: StoreConfig.baseURL) else {
            throw APIClientError.badPath(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.notHTTPResponse
        }
        saveMirror()
        return APIResponse(status: http.statusCode, data: responseData)
    }

    // MARK: - Auth endpoints (the server's own routes)

    func login(email: String, password: String) async throws -> APIResponse {
        try await post("/auth/login", json: ["email": email, "password": password])
    }

    func signup(email: String, password: String) async throws -> APIResponse {
        try await post("/auth/signup", json: ["email": email, "password": password])
    }

    func me() async throws -> APIResponse {
        try await get("/auth/me")
    }

    func logout() async throws -> APIResponse {
        try await post("/auth/logout", json: [:])
    }

    // MARK: - Cookie mirror

    /// Drops every cookie for the server's host from the shared
    /// jar and clears the UserDefaults mirror. Called on sign-out.
    func clearCookies() {
        let storage = HTTPCookieStorage.shared
        let host = StoreConfig.baseURL.host ?? "whatdimake.com"
        let cookies = storage.cookies ?? []
        for cookie in cookies where cookie.domain.hasSuffix(host) || host.hasSuffix(cookie.domain) {
            storage.deleteCookie(cookie)
        }
        UserDefaults.standard.removeObject(forKey: mirrorKey)
    }

    private func restoreMirror() {
        guard let data = UserDefaults.standard.data(forKey: mirrorKey),
              let stored = try? JSONDecoder().decode([StoredCookie].self, from: data) else {
            return
        }
        let storage = HTTPCookieStorage.shared
        for item in stored {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: item.name,
                .value: item.value,
                .domain: item.domain,
                .path: item.path,
            ]
            if let expiresAt = item.expiresAt {
                properties[.expires] = Date(timeIntervalSince1970: expiresAt)
            }
            if item.isSecure {
                properties[.secure] = "TRUE"
            }
            if let cookie = HTTPCookie(properties: properties) {
                storage.setCookie(cookie)
            }
        }
    }

    private func saveMirror() {
        guard let url = URL(string: "/", relativeTo: StoreConfig.baseURL),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return
        }
        let stored = cookies.map { cookie in
            StoredCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expiresAt: cookie.expiresDate.map { $0.timeIntervalSince1970 },
                isSecure: cookie.isSecure
            )
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: mirrorKey)
        }
    }

    // MARK: - Private

    private func send(path: String, method: String, jsonBody: [String: Any]?) async throws -> APIResponse {
        guard let url = URL(string: path, relativeTo: StoreConfig.baseURL) else {
            throw APIClientError.badPath(path)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.notHTTPResponse
        }
        // A login/signup (or any response) may carry a fresh
        // session cookie — mirror the jar after every round-trip.
        saveMirror()
        return APIResponse(status: http.statusCode, data: data)
    }
}
