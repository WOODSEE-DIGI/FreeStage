//
//  SyphonSourceRenderer.swift
//  FreeStage
//
//  Renders a Syphon input source into a Metal texture. Servers are discovered
//  via SyphonServerDirectory and matched by stored UUID (preferred) or by
//  name + app name for reconnection across launches.
//

import Metal
import Syphon

/// Renders a `Source.syphon` into a `MTLTexture`.
final class SyphonSourceRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [String: SyphonMetalClient] = [:]

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .syphon(let name, let appName, let uuid) = source else { return nil }
        let key = source.id

        lock.lock()
        let existingClient = clients[key]
        lock.unlock()

        if let client = existingClient {
            guard client.isValid else {
                lock.lock()
                clients.removeValue(forKey: key)
                lock.unlock()
                return nil
            }
            return client.newFrameImage()
        }

        guard let description = Self.matchingServerDescription(
            name: name,
            appName: appName,
            uuid: uuid
        ) else {
            return nil
        }

        let client = SyphonMetalClient(
            serverDescription: description,
            device: device,
            options: nil,
            newFrameHandler: nil
        )
        guard client.isValid else { return nil }

        lock.lock()
        clients[key] = client
        lock.unlock()

        return client.newFrameImage()
    }

    private static func matchingServerDescription(
        name: String,
        appName: String?,
        uuid: String?
    ) -> [String: Any]? {
        let directory = SyphonServerDirectory.shared()
        let servers = directory.servers as [[String: Any]]

        // Prefer a UUID match so a renamed server still reconnects.
        if let uuid = uuid, !uuid.isEmpty {
            if let match = servers.first(where: {
                ($0[SyphonServerDescriptionUUIDKey] as? String) == uuid
            }) {
                return match
            }
        }

        // Fall back to name + optional app name.
        return servers.first { server in
            let serverName = server[SyphonServerDescriptionNameKey] as? String ?? ""
            let serverAppName = server[SyphonServerDescriptionAppNameKey] as? String ?? ""
            let nameMatches = serverName == name
            let appNameMatches = appName == nil || serverAppName == appName
            return nameMatches && appNameMatches
        }
    }
}
