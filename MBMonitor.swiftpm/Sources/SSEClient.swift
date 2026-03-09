import Foundation
import os

// MARK: - SSE Types

struct SSEEvent {
    let event: String
    let data: String
}

enum SSEError: Error {
    case nonRetryable(Int)
    case retryable(Int)
    case disconnected
}

// MARK: - SSEClient

/// Pure single-connection SSE parser. Opens one connection, yields events, throws on error/EOF.
/// Does NOT reconnect -- the caller owns retry policy.
///
///   +----------+  bytes(for:)  +-----------+  EOF/error  +----------+
///   |  IDLE    | ------------> | STREAMING | ----------> |  DONE    |
///   +----------+               | (yielding |             | (throws) |
///                              |  events)  |             +----------+
///                              +-----------+
final class SSEClient: Sendable {
    private let request: URLRequest
    private let session: URLSession
    private static let logger = Logger(subsystem: "com.keepit.MBMonitor", category: "SSE")

    init(request: URLRequest, session: URLSession = .shared) {
        self.request = request
        self.session = session
    }

    /// Stream SSE events from a single connection. Throws on HTTP errors or disconnect.
    func events() -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: SSEError.disconnected)
                        return
                    }

                    Self.logger.info("SSE connected: \(http.statusCode) \(self.request.url?.absoluteString ?? "?")")

                    switch http.statusCode {
                    case 200...299:
                        break
                    case 400...499:
                        continuation.finish(throwing: SSEError.nonRetryable(http.statusCode))
                        return
                    default:
                        continuation.finish(throwing: SSEError.retryable(http.statusCode))
                        return
                    }

                    var currentEvent = ""
                    var currentData: [String] = []

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        // Blank line = dispatch event
                        if line.isEmpty {
                            if !currentData.isEmpty {
                                let event = SSEEvent(
                                    event: currentEvent.isEmpty ? "message" : currentEvent,
                                    data: currentData.joined(separator: "\n")
                                )
                                Self.logger.debug("SSE event: \(event.event) data=\(event.data.prefix(100))")
                                continuation.yield(event)
                            }
                            currentEvent = ""
                            currentData = []
                            continue
                        }

                        // Comment lines (starting with :) are ignored per SSE spec
                        if line.hasPrefix(":") { continue }

                        // Parse "field: value" or "field:value"
                        let field: String
                        let value: String
                        if let colonIndex = line.firstIndex(of: ":") {
                            field = String(line[line.startIndex..<colonIndex])
                            let afterColon = line.index(after: colonIndex)
                            if afterColon < line.endIndex && line[afterColon] == " " {
                                value = String(line[line.index(after: afterColon)...])
                            } else {
                                value = String(line[afterColon...])
                            }
                        } else {
                            // Line with no colon -- skip per SSE spec
                            continue
                        }

                        switch field {
                        case "event": currentEvent = value
                        case "data": currentData.append(value)
                        case "id", "retry": break // recognized but not used
                        default: break // unknown fields ignored
                        }
                    }

                    // Stream ended (EOF)
                    Self.logger.info("SSE stream ended (EOF)")
                    continuation.finish(throwing: SSEError.disconnected)
                } catch is CancellationError {
                    Self.logger.info("SSE cancelled")
                    continuation.finish()
                } catch let error as SSEError {
                    continuation.finish(throwing: error)
                } catch {
                    Self.logger.error("SSE error: \(error.localizedDescription)")
                    continuation.finish(throwing: SSEError.disconnected)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
