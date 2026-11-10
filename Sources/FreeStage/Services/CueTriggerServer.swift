//
//  CueTriggerServer.swift
//  FreeStage
//
//  Minimal TCP/HTTP server that lets external controllers (e.g., Stream Deck)
//  trigger cues by UUID over the local network. Also exposes a JSON discovery
//  endpoint so controllers can list available cues.
//

import Foundation
import Network
import OSLog

private let triggerLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "CueTriggerServer")

/// A tiny HTTP server that accepts POST /cue/<uuid> and triggers the matching cue,
/// plus POST /gimbal/... to move the selected camera gimbal from external controllers.
@Observable
final class CueTriggerServer: @unchecked Sendable {
    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var port: UInt16 = 0

    private var listener: NWListener?
    private var triggerHandler: ((UUID) -> Void)?
    private var gimbalHandler: ((GimbalHTTPAction) -> Void)?
    private var cuesSnapshot: () -> [CueSnapshot]
    private var localhostOnly = false
    private let lock = NSLock()

    init(cuesSnapshot: @escaping () -> [CueSnapshot] = { [] }) {
        self.cuesSnapshot = cuesSnapshot
    }

    /// Start listening on the given port. Set `localhostOnly` to reject non-local connections.
    /// `trigger` is called on the main actor when a valid cue UUID is received.
    /// `gimbal` is called on the main actor for `/gimbal/...` requests.
    func start(
        port: UInt16,
        localhostOnly: Bool = false,
        trigger: @escaping (UUID) -> Void,
        gimbal: @escaping (GimbalHTTPAction) -> Void
    ) throws {
        stop()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

        lock.withLock {
            self.triggerHandler = trigger
            self.gimbalHandler = gimbal
            self.localhostOnly = localhostOnly
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.lock.withLock { self?.isRunning = true }
                triggerLogger.info("Cue trigger server listening on port \(port)")
            case .failed(let error):
                self?.lock.withLock {
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                }
                triggerLogger.error("Cue trigger server failed: \(error.localizedDescription)")
            case .cancelled:
                self?.lock.withLock { self?.isRunning = false }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: .global(qos: .utility))

        lock.withLock {
            self.listener = listener
            self.port = port
        }
    }

    func stop() {
        lock.withLock {
            listener?.cancel()
            listener = nil
            triggerHandler = nil
            gimbalHandler = nil
            isRunning = false
            port = 0
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        let shouldReject = lock.withLock { localhostOnly } && !connection.endpoint.isLocalHost
        guard !shouldReject else {
            triggerLogger.debug("Rejecting non-local connection from \(connection.endpoint.debugDescription)")
            connection.cancel()
            return
        }
        connection.start(queue: .global(qos: .utility))
        receiveNext(on: connection, buffer: Data())
    }

    private func receiveNext(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var nextBuffer = buffer
            if let data { nextBuffer.append(data) }

            if let error {
                triggerLogger.warning("Cue trigger connection error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            // Try to parse a complete HTTP request once we see the header terminator.
            if let response = self.processRequestIfComplete(nextBuffer) {
                self.sendResponse(response, on: connection)
                return
            }

            if isComplete {
                let response = self.processRequestIfComplete(nextBuffer) ?? httpResponse(status: 400, body: "Bad Request")
                self.sendResponse(response, on: connection)
            } else {
                self.receiveNext(on: connection, buffer: nextBuffer)
            }
        }
    }

    /// Parse the buffer if it contains a complete HTTP request line and headers.
    private func processRequestIfComplete(_ buffer: Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.prefix(upTo: headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return httpResponse(status: 400, body: "Bad Request") }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return httpResponse(status: 400, body: "Bad Request") }

        let method = parts[0].uppercased()
        let path = String(parts[1])

        if method == "GET" && path == "/health" {
            return httpResponse(status: 200, body: "OK", contentType: "text/plain")
        }

        if method == "GET" && path == "/cues" {
            return jsonResponse(cuesSnapshot())
        }

        if method == "GET" && path.hasPrefix("/cue/") {
            let uuidString = String(path.dropFirst("/cue/".count))
                .components(separatedBy: "?")
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard let cueID = UUID(uuidString: uuidString) else {
                return httpResponse(status: 400, body: "Invalid UUID")
            }
            guard let cue = cuesSnapshot().first(where: { $0.id == cueID }) else {
                return httpResponse(status: 404, body: "Cue not found")
            }
            return jsonResponse(cue)
        }

        if method == "POST" && path.hasPrefix("/cue/") {
            let uuidString = String(path.dropFirst("/cue/".count))
                .components(separatedBy: "?")
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard let cueID = UUID(uuidString: uuidString) else {
                return httpResponse(status: 400, body: "Invalid UUID")
            }
            DispatchQueue.main.async { [weak self] in
                self?.triggerHandler?(cueID)
            }
            return httpResponse(status: 200, body: "OK")
        }

        if method == "POST" && path.hasPrefix("/gimbal/") {
            return handleGimbalRequest(path: path)
        }

        return httpResponse(status: 404, body: "Not Found")
    }

    private func handleGimbalRequest(path: String) -> Data {
        let query = URLComponents(string: "http://localhost\(path)")?.queryItems ?? []
        let params = Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })

        let action: GimbalHTTPAction?
        if path.hasPrefix("/gimbal/moveTo") {
            guard let pan = Double(params["pan"] ?? ""),
                  let tilt = Double(params["tilt"] ?? "") else {
                return httpResponse(status: 400, body: "Missing or invalid pan/tilt")
            }
            action = .moveTo(pan: pan, tilt: tilt)
        } else if path.hasPrefix("/gimbal/nudge") {
            guard let pan = Double(params["pan"] ?? ""),
                  let tilt = Double(params["tilt"] ?? "") else {
                return httpResponse(status: 400, body: "Missing or invalid pan/tilt")
            }
            action = .nudge(pan: pan, tilt: tilt)
        } else if path.hasPrefix("/gimbal/recenter") {
            action = .recenter
        } else {
            return httpResponse(status: 404, body: "Unknown gimbal command")
        }

        DispatchQueue.main.async { [weak self] in
            self?.gimbalHandler?(action!)
        }
        return httpResponse(status: 200, body: "OK")
    }

    private func sendResponse(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// Actions that can be requested over HTTP by external controllers such as Stream Deck.
enum GimbalHTTPAction: Sendable {
    case moveTo(pan: Double, tilt: Double)
    case nudge(pan: Double, tilt: Double)
    case recenter
}

/// A JSON-serializable snapshot of a cue for external controllers.
struct CueSnapshot: Codable, Sendable, Identifiable {
    let id: UUID
    let number: String
    let name: String
    let sceneID: UUID
    let sceneName: String
    let isArmed: Bool

    init(cue: Cue, sceneName: String) {
        self.id = cue.id
        self.number = cue.number
        self.name = cue.name
        self.sceneID = cue.sceneID
        self.sceneName = sceneName
        self.isArmed = cue.isArmed
    }
}

private func httpResponse(status: Int, body: String, contentType: String = "text/plain") -> Data {
    let statusText: String
    switch status {
    case 200: statusText = "OK"
    case 400: statusText = "Bad Request"
    case 404: statusText = "Not Found"
    default: statusText = ""
    }
    let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
    return Data(header.utf8) + Data(body.utf8)
}

extension NWEndpoint {
    var isLocalHost: Bool {
        switch self {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return address == .loopback
            case .ipv6(let address):
                return address == .loopback
            case .name(let hostname, _):
                let lower = hostname.lowercased()
                return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
            @unknown default:
                return false
            }
        default:
            return false
        }
    }
}

private func jsonResponse<T: Encodable>(_ value: T) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value),
          let json = String(data: data, encoding: .utf8) else {
        return httpResponse(status: 500, body: "JSON encoding failed")
    }
    return httpResponse(status: 200, body: json, contentType: "application/json")
}
