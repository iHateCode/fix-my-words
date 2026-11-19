import Foundation
import Network

/// A fake OpenRouter on 127.0.0.1 for the UI tests. It answers `POST …/chat/completions`
/// with scripted server-sent events or error statuses, and records each request's model,
/// `reasoning.effort` and instruction so tests can check which model was called.
final class StubOpenRouter: @unchecked Sendable {       // state is only touched on `queue`, or through `lock`
    struct Request: Equatable {
        let model: String
        let effort: String?
        let instruction: String?     // from the user message's "Instruction: …" line
        let text: String?            // what sat between <text> and </text>
    }

    enum Finish { case stop, error(code: Int, message: String) }

    enum Response {
        /// A 200 stream: waits `delay`, then sends each chunk as a `delta.content`, then the finish.
        /// With a `chunkDelay`, the chunks arrive that far apart instead of all at once.
        case stream([String], delay: Duration = .zero, chunkDelay: Duration = .zero, finish: Finish = .stop)
        /// A plain HTTP error with OpenRouter's error body.
        case status(Int, message: String = "Stub error")
        /// A 200 stream that only ever sends `: OPENROUTER PROCESSING` keep-alives.
        case keepAliveForever(every: Duration = .seconds(1))
    }

    /// Picks the reply for the nth request (0-based). Set before the app sends anything.
    var script: @Sendable (_ request: Request, _ index: Int) -> Response = { _, _ in .status(500) }
    /// Served at `GET …/models` when set, as OpenRouter's `data` array. Nil answers 404, so Settings falls back to typed ids.
    var models: [[String: Any]]?
    /// The only key `GET …/key` accepts.
    static let validKey = "sk-or-uitest"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "StubOpenRouter")
    private let lock = NSLock()
    private var recorded: [Request] = []

    var requests: [Request] { lock.withLock { recorded } }
    var port: UInt16 { listener.port?.rawValue ?? 0 }
    var baseURL: String { "http://127.0.0.1:\(port)/api/v1" }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and waits until the port is known.
    func start() throws {
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else { throw URLError(.cannotConnectToHost) }
    }

    func stop() { listener.cancel() }

    // MARK: HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    /// Reads until the headers and `Content-Length` bytes of body have arrived.
    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let (head, body) = Self.split(buffer) {
                let length = Self.contentLength(head)
                if body.count >= length {
                    self.respond(on: connection, head: head, body: body.prefix(length))
                    return
                }
            }
            if isComplete || error != nil { connection.cancel(); return }
            self.receiveRequest(on: connection, buffer: buffer)
        }
    }

    private func respond(on connection: NWConnection, head: String, body: Data) {
        let requestLine = head.split(separator: "\r\n").first.map(String.init) ?? ""
        if requestLine.hasPrefix("GET "), requestLine.contains("/models"), let models {
            let body = (try? JSONSerialization.data(withJSONObject: ["data": models])) ?? Data()
            send(on: connection, status: 200, body: body)
            return
        }
        if requestLine.hasPrefix("GET "), requestLine.contains("/key ") {
            let ok = head.lowercased().contains("authorization: bearer \(Self.validKey)")
            send(on: connection, status: ok ? 200 : 401, body: ok ? Data(#"{"data":{}}"#.utf8) : Self.errorBody(401, "No auth"))
            return
        }
        guard requestLine.hasPrefix("POST "), requestLine.contains("/chat/completions") else {
            send(on: connection, status: 404, body: Self.errorBody(404, "Not found"))
            return
        }
        let request = Self.parse(body)
        let index = lock.withLock { () -> Int in recorded.append(request); return recorded.count - 1 }

        switch script(request, index) {
        case .status(let code, let message):
            send(on: connection, status: code, body: Self.errorBody(code, message))
        case .stream(let chunks, let delay, let chunkDelay, let finish):
            startStream(on: connection)
            queue.asyncAfter(deadline: .now() + delay.timeInterval) { [weak self] in
                guard let self else { return }
                var events = chunks.map { Self.event(["choices": [["delta": ["content": $0], "finish_reason": NSNull()]]]) }
                switch finish {
                case .stop:
                    events.append(Self.event(["choices": [["delta": [:], "finish_reason": "stop"]]]))
                case .error(let code, let message):
                    events.append(Self.event(["error": ["code": code, "message": message],
                                              "choices": [["delta": [:], "finish_reason": "error"]]]))
                }
                events.append("data: [DONE]\n\n")
                if chunkDelay == .zero {
                    connection.send(content: Data(events.joined().utf8), completion: .contentProcessed { _ in connection.cancel() })
                } else {
                    self.sendSpaced(events, every: chunkDelay, on: connection)
                }
            }
        case .keepAliveForever(let every):
            startStream(on: connection)
            keepAlive(on: connection, every: every)
        }
    }

    /// Sends one event, waits `every`, then the next, and closes after the last.
    private func sendSpaced(_ events: [String], every: Duration, on connection: NWConnection) {
        guard let first = events.first else { connection.cancel(); return }
        connection.send(content: Data(first.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil, let self else { connection.cancel(); return }
            self.queue.asyncAfter(deadline: .now() + every.timeInterval) { self.sendSpaced(Array(events.dropFirst()), every: every, on: connection) }
        })
    }

    private func keepAlive(on connection: NWConnection, every: Duration) {
        connection.send(content: Data(": OPENROUTER PROCESSING\n\n".utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil, let self else { connection.cancel(); return }
            self.queue.asyncAfter(deadline: .now() + every.timeInterval) { self.keepAlive(on: connection, every: every) }
        })
    }

    private func startStream(on connection: NWConnection) {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .idempotent)
    }

    private func send(on connection: NWConnection, status: Int, body: Data) {
        let head = "HTTP/1.1 \(status) Stub\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: Parsing and encoding

    private static func split(_ buffer: Data) -> (String, Data)? {
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        return (String(decoding: buffer[..<range.lowerBound], as: UTF8.self), buffer[range.upperBound...])
    }

    private static func contentLength(_ head: String) -> Int {
        for line in head.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    private static func parse(_ body: Data) -> Request {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let reasoning = json["reasoning"] as? [String: Any]
        let messages = json["messages"] as? [[String: Any]] ?? []
        let user = messages.last { $0["role"] as? String == "user" }?["content"] as? String ?? ""
        return Request(model: json["model"] as? String ?? "",
                       effort: reasoning?["effort"] as? String,
                       instruction: between(user, "Instruction: ", "\n\n<text>"),
                       text: between(user, "<text>\n", "\n</text>"))
    }

    private static func between(_ s: String, _ start: String, _ end: String) -> String? {
        guard let a = s.range(of: start), let b = s.range(of: end, range: a.upperBound..<s.endIndex) else { return nil }
        return String(s[a.upperBound..<b.lowerBound])
    }

    private static func event(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return "data: \(String(decoding: data, as: UTF8.self))\n\n"
    }

    private static func errorBody(_ code: Int, _ message: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["error": ["code": code, "message": message]])) ?? Data()
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
