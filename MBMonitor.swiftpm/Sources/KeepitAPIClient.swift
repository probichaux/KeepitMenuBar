import Foundation

/// Talks to the Keepit REST API. All responses are XML; we parse them with XMLParser-based helpers.
final class KeepitAPIClient: @unchecked Sendable {
    private var baseURL: URL?
    private var authHeader: String?
    var userId: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    func configure(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
        self.authHeader = "Basic \(encoded)"
    }

    // MARK: - Authentication

    /// Returns the user/account ID. Response XML: `<user><id>...</id></user>`
    func authenticate() async throws -> String {
        let data = try await request(path: "/users/", accept: "application/vnd.keepit.v1+xml")
        guard let id = XMLSimpleParser.firstElementText(named: "id", in: data) else {
            let body = String(data: data, encoding: .utf8) ?? "(non-utf8)"
            throw APIError.parseError("Could not find <id> in response: \(body.prefix(200))")
        }
        return id
    }

    // MARK: - Connectors

    func fetchConnectors() async throws -> [Connector] {
        guard let userId else { throw APIError.notAuthenticated }
        let data = try await request(
            path: "/users/\(userId)/devices",
            accept: "application/vnd.keepit.v4+xml"
        )
        return ConnectorParser.parse(data: data)
    }

    func fetchConnectorHealth(connectorId: String) async throws -> (HealthStatus, String?) {
        guard let userId else { throw APIError.notAuthenticated }
        let data = try await request(
            path: "/users/\(userId)/devices/\(connectorId)/health?reason=true",
            accept: "application/xml"
        )
        return HealthParser.parse(data: data)
    }

    /// Returns the timestamp of the latest snapshot for a connector.
    /// Response XML: `<history><backup><tstamp>...</tstamp></backup></history>`
    func fetchLatestSnapshot(connectorId: String) async throws -> Date? {
        guard let userId else { throw APIError.notAuthenticated }
        let data = try await request(
            path: "/users/\(userId)/devices/\(connectorId)/history/latest",
            accept: "application/vnd.keepit.v1+xml"
        )
        guard let tstamp = XMLSimpleParser.firstElementText(named: "tstamp", in: data) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: tstamp)
    }

    /// Returns true if the connector has any anomalies in the last 7 days.
    /// `GET /users/{userId}/devices/{connectorId}/anomalies?from=...&to=...`
    func fetchHasAnomalies(connectorId: String) async throws -> Bool {
        guard let userId else { throw APIError.notAuthenticated }
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let fmt = ISO8601DateFormatter()
        let from = fmt.string(from: weekAgo)
        let to = fmt.string(from: now)
        let data = try await request(
            path: "/users/\(userId)/devices/\(connectorId)/anomalies?from=\(from)&to=\(to)",
            accept: "application/vnd.keepit.v4+xml"
        )
        // If there's any <anomaly> element, there are anomalies
        return XMLSimpleParser.firstElementText(named: "guid", in: data) != nil
    }

    func fetchBackupSummary() async throws -> Data {
        guard let userId else { throw APIError.notAuthenticated }
        return try await request(
            path: "/users/\(userId)/monitoring/backup/summary",
            accept: "application/vnd.keepit.v4+xml"
        )
    }

    // MARK: - SSE / vqueues

    /// Build an authenticated URLRequest for the vqueues multiqueue SSE endpoint.
    func vqueueRequest(sources: [String]) throws -> URLRequest {
        guard let baseURL, let authHeader else { throw APIError.notConfigured }
        let joined = sources.joined(separator: ",")
        guard let url = URL(string: "/vqueues/multiqueue?sources=\(joined)", relativeTo: baseURL) else {
            throw APIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        // No timeout for SSE — connection stays open indefinitely
        req.timeoutInterval = 0
        return req
    }

    /// The SSE queue sources to subscribe to for real-time connector updates.
    func vqueueSources() throws -> [String] {
        guard let userId else { throw APIError.notAuthenticated }
        return ["devices-\(userId)", "job-\(userId)"]
    }

    // MARK: - Private

    private func request(path: String, accept: String, method: String = "GET") async throws -> Data {
        guard let baseURL, let authHeader else { throw APIError.notConfigured }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200...299: return data
        case 401: throw APIError.authenticationFailed
        case 404: throw APIError.notFound
        default: throw APIError.httpError(http.statusCode)
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case notConfigured
    case notAuthenticated
    case authenticationFailed
    case notFound
    case invalidResponse
    case httpError(Int)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "API not configured"
        case .notAuthenticated: return "Not authenticated"
        case .authenticationFailed: return "Authentication failed"
        case .notFound: return "Resource not found"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code): return "HTTP error \(code)"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
