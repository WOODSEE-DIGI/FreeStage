//
//  OSCCueServer.swift
//  FreeStage
//
//  UDP OSC input server that lets external controllers trigger cues
//  and control the selected camera gimbal. Supports messages like:
//    /freestage/cue/<uuid>
//    /freestage/cue/go
//    /freestage/cue/next
//    /freestage/cue/prev
//    /freestage/cue/number/<number>
//    /freestage/gimbal/moveTo <pan> <tilt>
//    /freestage/gimbal/nudge <panDelta> <tiltDelta>
//    /freestage/gimbal/recenter
//

import Foundation
import Network
import OSLog

private let oscLogger = Logger(subsystem: "com.woodseedigi.FreeStage", category: "OSCCueServer")

/// Receives OSC packets and translates them to ShowStore actions.
@Observable
final class OSCCueServer: @unchecked Sendable {
    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var port: UInt16 = 0

    private var listener: NWListener?
    private var actionHandler: ((OSCAction) -> Void)?
    private var localhostOnly = false
    private let lock = NSLock()

    /// Start listening on the given UDP port. Set `localhostOnly` to reject non-local packets.
    func start(
        port: UInt16,
        localhostOnly: Bool = false,
        action: @escaping (OSCAction) -> Void
    ) throws {
        stop()

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

        lock.withLock {
            self.actionHandler = action
            self.localhostOnly = localhostOnly
        }

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.lock.withLock { self?.isRunning = true }
                oscLogger.info("OSC cue server listening on port \(port)")
            case .failed(let error):
                self?.lock.withLock {
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                }
                oscLogger.error("OSC cue server failed: \(error.localizedDescription)")
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
            actionHandler = nil
            isRunning = false
            port = 0
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        let shouldReject = lock.withLock { localhostOnly } && !connection.endpoint.isLocalHost
        guard !shouldReject else {
            oscLogger.debug("Rejecting non-local OSC packet from \(connection.endpoint.debugDescription)")
            connection.cancel()
            return
        }
        connection.start(queue: .global(qos: .utility))
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let error {
                oscLogger.warning("OSC receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            if let data {
                self.handlePacket(data)
                self.receiveNext(on: connection)
            } else {
                connection.cancel()
            }
        }
    }

    private func handlePacket(_ data: Data) {
        guard let message = OSCMessage.decode(data) else {
            oscLogger.debug("Ignoring non-OSC or malformed packet")
            return
        }

        let address = message.address
        let action: OSCAction?

        if address.hasPrefix("/freestage/cue/") {
            let suffix = String(address.dropFirst("/freestage/cue/".count))
            switch suffix {
            case "go":
                action = .go
            case "next":
                action = .next
            case "prev", "previous":
                action = .previous
            default:
                if let uuid = UUID(uuidString: suffix) {
                    action = .trigger(uuid)
                } else if suffix.hasPrefix("number/"),
                          let number = suffix.dropFirst("number/".count)
                    .split(separator: "/")
                    .first
                    .map(String.init) {
                    action = .triggerNumber(number)
                } else {
                    action = nil
                }
            }
        } else if address.hasPrefix("/cue/") {
            let suffix = String(address.dropFirst("/cue/".count))
            if let uuid = UUID(uuidString: suffix) {
                action = .trigger(uuid)
            } else {
                action = nil
            }
        } else if address == "/freestage/gimbal/moveTo" {
            action = parseGimbalMove(message: message)
        } else if address == "/freestage/gimbal/nudge" {
            action = parseGimbalNudge(message: message)
        } else if address == "/freestage/gimbal/recenter" {
            action = .gimbalRecenter
        } else {
            action = nil
        }

        guard let action else {
            oscLogger.debug("Unhandled OSC address: \(address)")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.actionHandler?(action)
        }
    }

    private func parseGimbalMove(message: OSCMessage) -> OSCAction? {
        guard message.arguments.count >= 2,
              let pan = message.arguments[0].doubleValue,
              let tilt = message.arguments[1].doubleValue
        else { return nil }
        return .gimbalMoveTo(pan: pan, tilt: tilt)
    }

    private func parseGimbalNudge(message: OSCMessage) -> OSCAction? {
        guard message.arguments.count >= 2,
              let pan = message.arguments[0].doubleValue,
              let tilt = message.arguments[1].doubleValue
        else { return nil }
        return .gimbalNudge(pan: pan, tilt: tilt)
    }
}

private extension OSCArgument {
    var doubleValue: Double? {
        switch self {
        case .int32(let value):
            return Double(value)
        case .float32(let value):
            return Double(value)
        case .string:
            return nil
        }
    }
}

enum OSCAction: Sendable {
    case trigger(UUID)
    case triggerNumber(String)
    case go
    case next
    case previous

    // Gimbal control via external OSC (e.g., Stream Deck Companion plugin).
    case gimbalMoveTo(pan: Double, tilt: Double)
    case gimbalNudge(pan: Double, tilt: Double)
    case gimbalRecenter
}
