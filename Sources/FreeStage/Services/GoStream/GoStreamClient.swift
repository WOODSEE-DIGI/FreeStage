//
//  GoStreamClient.swift
//  FreeStage
//
//  TCP transport for the OSEE GoStream GSP protocol (port 19010) plus
//  Bonjour discovery of `_oseectrl._tcp`.
//
//  An actor owns every Network-framework object; state crosses the boundary
//  only through AsyncStreams of Sendable values, which keeps the Swift 6
//  strict-concurrency checker happy without locks.
//
//  The Duet answers on whichever interface it is reachable: over the USB-C
//  cable to the Mac (CDC-ECM gadget, e.g. 172.28.53.130) or the LAN
//  (e.g. 192.168.1.x behind a router). Discovery via Bonjour covers both
//  without hardcoding addresses.
//

import Foundation
import Network

/// A GoStream discovered via Bonjour. Only the service name crosses actor
/// boundaries — the NWEndpoint stays cached inside the client, which avoids
/// any Network-framework Sendable edge cases under strict concurrency.
struct GoStreamDiscoveredDevice: Sendable, Equatable, Identifiable {
    let id: String       // Bonjour instance name, e.g. "GoStream_901395"
}

actor GoStreamClient {

    // MARK: - Streams

    private var frameContinuation: AsyncStream<GoStreamCommand>.Continuation?
    private var deviceContinuation: AsyncStream<GoStreamDiscoveredDevice>.Continuation?
    private var stateContinuation: AsyncStream<String>.Continuation?

    /// Held between priming and the consumer's take; nil once handed off.
    private var frameStreamStorage: AsyncStream<GoStreamCommand>?
    private var deviceStreamStorage: AsyncStream<GoStreamDiscoveredDevice>?
    private var stateStreamStorage: AsyncStream<String>?

    /// Install the continuation for the frame stream. Must be called once,
    /// synchronously, before any connection can go ready — otherwise frames the
    /// device sends in response to our first commands are yielded at a nil
    /// continuation and lost.
    func primeFrameStream() {
        let pair = AsyncStream<GoStreamCommand>.makeStream()
        frameContinuation = pair.continuation
        frameStreamStorage = pair.stream
    }

    func primeDeviceStream() {
        let pair = AsyncStream<GoStreamDiscoveredDevice>.makeStream()
        deviceContinuation = pair.continuation
        deviceStreamStorage = pair.stream
    }

    func primeStateStream() {
        let pair = AsyncStream<String>.makeStream()
        stateContinuation = pair.continuation
        stateStreamStorage = pair.stream
    }

    /// Consumer-side accessors. Each returns the stream primed above exactly
    /// once; the client keeps only the continuation for yielding.
    func takeFrameStream() -> AsyncStream<GoStreamCommand>? {
        defer { frameStreamStorage = nil }
        return frameStreamStorage
    }

    func takeDeviceStream() -> AsyncStream<GoStreamDiscoveredDevice>? {
        defer { deviceStreamStorage = nil }
        return deviceStreamStorage
    }

    func takeStateStream() -> AsyncStream<String>? {
        defer { stateStreamStorage = nil }
        return stateStreamStorage
    }

    // MARK: - State

    private var connection: NWConnection?
    private var browser: NWBrowser?
    private var reassembler = GoStreamFrameReassembler()
    private var knownEndpoints: [String: NWEndpoint] = [:]

    /// Set while a connection is desired; drives auto-reconnect.
    private var reconnectEnabled = false
    private var pendingHost: String?
    private var pendingServiceName: String?
    private let port: UInt16
    private var retryTask: Task<Void, Never>?

    /// Interfaces each Bonjour name was last seen on. The Duet is dual-homed
    /// (USB-C gadget + LAN) and the LAN address can be unreachable while still
    /// being announced — so we connect once per interface instead of trusting
    /// the system resolver, which silently prefers the dead address.
    private var knownInterfaces: [String: [NWInterface]] = [:]
    private var interfaceAttemptIndex = 0

    /// Watchdog for in-flight connection attempts: a stalled connect must
    /// surface as a failure, never hang the panel on "Connecting…".
    private var connectWatchdog: Task<Void, Never>?
    private var connectionIsReady = false
    private var activeConnectLabel: String = ""

    init(port: UInt16 = 19010) {
        self.port = port
    }

    // MARK: - Discovery

    func startBrowsing() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_oseectrl._tcp", domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            Task { await self?.browserState(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.browseResults(results) }
        }
        browser.start(queue: .global(qos: .userInitiated))
        self.browser = browser
        GoStreamLog.log("client: browsing _oseectrl._tcp")
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        knownEndpoints.removeAll()
    }

    private func browserState(_ state: NWBrowser.State) {
        switch state {
        case .failed(let error):
            GoStreamLog.log("client: browse failed: \(error)")
        case .waiting(let error):
            GoStreamLog.log("client: browse waiting: \(error)")
        default:
            break
        }
    }

    private func browseResults(_ results: Set<NWBrowser.Result>) {
        var fresh: [String] = []
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                knownEndpoints[name] = result.endpoint
                knownInterfaces[name] = result.interfaces
                fresh.append(name)
                GoStreamLog.log("client: '\(name)' on interfaces: \(result.interfaces.map(\.name).joined(separator: ", "))")
            }
        }
        GoStreamLog.log("client: discovered \(fresh.count) device(s): \(fresh.joined(separator: ", "))")
        for name in fresh {
            deviceContinuation?.yield(GoStreamDiscoveredDevice(id: name))
        }
    }

    // MARK: - Connect / disconnect

    /// Connect by direct address (e.g. "172.28.53.130").
    func connect(host: String) {
        GoStreamLog.log("client: connect host=\(host):\(port)")
        pendingHost = host
        pendingServiceName = nil
        reconnectEnabled = true
        interfaceAttemptIndex = 0
        activeConnectLabel = host
        openConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 19010)),
            watchdogSeconds: 6
        )
    }

    /// Connect via a Bonjour-discovered service name.
    ///
    /// The Duet is dual-homed (USB-C gadget + LAN). Its LAN address can be
    /// unreachable while still being advertised, and the system resolver
    /// silently hands Network.framework only that dead record — the connect
    /// then stalls forever with no state event. So instead of one
    /// service-endpoint connection we walk every interface the device was
    /// seen on, forcing the connection down each in turn with a hard timeout.
    func connect(serviceName: String) {
        guard let endpoint = knownEndpoints[serviceName] else {
            GoStreamLog.log("client: connect(serviceName=\(serviceName)) — not in cache; use startBrowsing first")
            stateContinuation?.yield("failed: unknown device \(serviceName)")
            return
        }
        GoStreamLog.log("client: connect service=\(serviceName)")
        pendingHost = nil
        pendingServiceName = serviceName
        reconnectEnabled = true
        interfaceAttemptIndex = 0
        activeConnectLabel = serviceName
        tryNextInterface(endpoint: endpoint, serviceName: serviceName)
    }

    /// Force a connection down interface #index for the service; advance on
    /// timeout. The last attempt (or the sole default-params attempt when the
    /// interface list is empty) carries the watchdog that fails the connect.
    private func tryNextInterface(endpoint: NWEndpoint, serviceName: String) {
        let interfaces = knownInterfaces[serviceName] ?? []
        let attempt = interfaceAttemptIndex
        interfaceAttemptIndex += 1

        if interfaces.isEmpty || attempt >= interfaces.count {
            stateContinuation?.yield("failed: \(serviceName) not reachable on any interface")
            return
        }

        let interface = interfaces[attempt]
        GoStreamLog.log("client: attempting \(serviceName) via \(interface.name) (\(attempt + 1)/\(interfaces.count))")
        activeConnectLabel = "\(serviceName)@\(interface.name)"

        let parameters = NWParameters.tcp
        parameters.requiredInterface = interface
        // Final attempt in the list gets a watchdog that reports failure;
        // earlier ones just get cancelled when the next attempt starts.
        let isLast = attempt == interfaces.count - 1
        openConnection(to: endpoint, parameters: parameters, watchdogSeconds: isLast ? 8 : 4)
    }

    /// Tear down and stop auto-reconnecting (user-initiated).
    func disconnect() {
        GoStreamLog.log("client: disconnect (user)")
        reconnectEnabled = false
        retryTask?.cancel()
        retryTask = nil
        connectWatchdog?.cancel()
        connectWatchdog = nil
        connection?.cancel()
        connection = nil
        connectionIsReady = false
        stateContinuation?.yield("idle")
    }

    private func openConnection(to endpoint: NWEndpoint, parameters: NWParameters = .tcp, watchdogSeconds: Double? = nil) {
        retryTask?.cancel()
        retryTask = nil
        connectWatchdog?.cancel()
        connectWatchdog = nil
        connection?.cancel()
        connectionIsReady = false
        reassembler = GoStreamFrameReassembler()

        let connection = NWConnection(to: endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.connectionState(state) }
        }
        connection.start(queue: .global(qos: .userInitiated))
        self.connection = connection
        stateContinuation?.yield("connecting")

        if let watchdogSeconds {
            let label = activeConnectLabel
            connectWatchdog = Task { [weak self] in
                let nanos = UInt64(watchdogSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled else { return }
                await self?.connectWatchdogFired(label: label)
            }
        }
    }

    /// A connect attempt did not reach .ready in time. For service connects
    /// this advances to the next interface; otherwise it fails visibly.
    private func connectWatchdogFired(label: String) async {
        guard !connectionIsReady else { return }
        GoStreamLog.log("client: connect attempt timed out: \(label)")
        connection?.cancel()
        connection = nil

        if let name = pendingServiceName, let endpoint = knownEndpoints[name], interfaceAttemptIndex > 0 {
            // More interfaces may remain to try.
            tryNextInterface(endpoint: endpoint, serviceName: name)
        } else {
            stateContinuation?.yield("failed: timeout connecting to \(label)")
        }
    }

    private func connectionState(_ state: NWConnection.State) {
        GoStreamLog.log("client: state \(state) (\(activeConnectLabel))")
        switch state {
        case .ready:
            GoStreamLog.log("client: connection ready (\(activeConnectLabel))")
            connectionIsReady = true
            connectWatchdog?.cancel()
            connectWatchdog = nil
            stateContinuation?.yield("ready")
            receiveLoop()
        case .failed(let error):
            GoStreamLog.log("client: connection failed: \(error)")
            connectionIsReady = false
            connectWatchdog?.cancel()
            connectWatchdog = nil
            stateContinuation?.yield("failed: \(error)")
            scheduleReconnect()
        case .cancelled:
            GoStreamLog.log("client: connection cancelled")
        case .waiting(let error):
            GoStreamLog.log("client: connection waiting: \(error)")
        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectEnabled else { return }
        retryTask?.cancel()
        GoStreamLog.log("client: reconnect in 2s")
        stateContinuation?.yield("reconnecting")
        retryTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self.performReconnect()
        }
    }

    private func performReconnect() {
        guard reconnectEnabled else { return }
        if let host = pendingHost {
            activeConnectLabel = host
            openConnection(
                to: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .init(integerLiteral: 19010)),
                watchdogSeconds: 6
            )
        } else if let name = pendingServiceName, let endpoint = knownEndpoints[name] {
            // Restart the interface walk from the top on reconnect.
            activeConnectLabel = name
            interfaceAttemptIndex = 0
            tryNextInterface(endpoint: endpoint, serviceName: name)
        } else {
            GoStreamLog.log("client: reconnect target lost")
            stateContinuation?.yield("failed: reconnect target lost")
        }
    }

    // MARK: - Receive

    private func receiveLoop() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                Task { await self?.handleReceive(data) }
            }
            if isComplete || error != nil {
                Task { await self?.handleReceiveEnd(error) }
            }
        }
    }

    private func handleReceive(_ data: Data) {
        let commands = reassembler.append(data)
        for command in commands {
            frameContinuation?.yield(command)
        }
        receiveLoop()
    }

    private func handleReceiveEnd(_ error: NWError?) {
        GoStreamLog.log("client: receive ended (\(error.map { "\($0)" } ?? "remote closed"))")
        connection?.cancel()
        connection = nil
        if reconnectEnabled {
            scheduleReconnect()
        } else {
            stateContinuation?.yield("idle")
        }
    }

    // MARK: - Send

    /// Send a command and await the socket's verdict. Returns false if there
    /// is no connection, or if Network-framework reports a send error, so the
    /// caller can retry instead of silently dropping the operator's intent.
    @discardableResult
    func send(id: String, type: String, value: [GoStreamValue]? = nil) async -> Bool {
        guard let connection else {
            GoStreamLog.log("client: send \(id) dropped — not connected")
            return false
        }
        let frame = GoStreamCodec.pack(id: id, type: type, value: value)
        guard !frame.isEmpty else { return false }

        return await withCheckedContinuation { continuation in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    GoStreamLog.log("client: send \(id) error: \(error)")
                    continuation.resume(returning: false)
                } else {
                    GoStreamLog.log("client: sent \(id)")
                    continuation.resume(returning: true)
                }
            })
        }
    }
}
