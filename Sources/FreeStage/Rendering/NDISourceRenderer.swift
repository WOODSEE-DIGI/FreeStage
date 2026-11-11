//
//  NDISourceRenderer.swift
//  FreeStage
//
//  Renders an NDI input source into a Metal texture. Uses the NDI SDK via the
//  bridging header and links against the system libndi.dylib.
//

import Metal

/// Renders a `Source.ndi` into a `MTLTexture`.
final class NDISourceRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var receivers: [String: NDIlib_recv_instance_t] = [:]
    private var textures: [String: MTLTexture] = [:]
    private static let initLock = NSLock()
    nonisolated(unsafe) private static var isLibraryInitialized = false

    deinit {
        lock.lock()
        let receiversCopy = receivers
        receivers.removeAll()
        lock.unlock()
        for (_, receiver) in receiversCopy {
            NDIlib_recv_destroy(receiver)
        }
    }

    func render(
        source: Source,
        device: MTLDevice,
        commandQueue: MTLCommandQueue
    ) throws -> MTLTexture? {
        guard case .ndi(let name) = source else { return nil }
        ensureLibraryInitialized()

        let key = source.id
        let receiver = receiver(forKey: key, name: name)
        guard let receiver = receiver else { return nil }

        var videoFrame = NDIlib_video_frame_v2_t()
        let frameType = NDIlib_recv_capture_v2(receiver, &videoFrame, nil, nil, 0)
        defer { NDIlib_recv_free_video_v2(receiver, &videoFrame) }

        guard frameType == NDIlib_frame_type_video,
              videoFrame.p_data != nil,
              videoFrame.xres > 0,
              videoFrame.yres > 0 else {
            // No new frame yet; return the previous texture if we have one.
            lock.lock()
            let cached = textures[key]
            lock.unlock()
            return cached
        }

        guard let texture = texture(
            forKey: key,
            width: videoFrame.xres,
            height: videoFrame.yres,
            device: device
        ) else {
            return nil
        }

        let region = MTLRegionMake2D(0, 0, Int(videoFrame.xres), Int(videoFrame.yres))
        texture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: videoFrame.p_data,
            bytesPerRow: Int(videoFrame.line_stride_in_bytes)
        )

        return texture
    }

    // MARK: - Setup

    private func ensureLibraryInitialized() {
        Self.initLock.lock()
        defer { Self.initLock.unlock() }
        guard !Self.isLibraryInitialized else { return }
        if NDIlib_initialize() {
            Self.isLibraryInitialized = true
        }
    }

    private func receiver(forKey key: String, name: String) -> NDIlib_recv_instance_t? {
        lock.lock()
        let existing = receivers[key]
        lock.unlock()

        if let receiver = existing {
            return receiver
        }

        guard let ndiSourceName = Self.findSourceName(named: name) else { return nil }

        let receiver = ndiSourceName.withCString { namePtr in
            var source = NDIlib_source_t()
            source.p_ndi_name = namePtr

            var create = NDIlib_recv_create_v3_t()
            create.source_to_connect_to = source
            create.color_format = NDIlib_recv_color_format_BGRX_BGRA
            create.bandwidth = NDIlib_recv_bandwidth_highest
            create.allow_video_fields = false

            return NDIlib_recv_create_v3(&create)
        }

        guard let receiver = receiver else { return nil }

        lock.lock()
        receivers[key] = receiver
        lock.unlock()
        return receiver
    }

    private func texture(forKey key: String, width: Int32, height: Int32, device: MTLDevice) -> MTLTexture? {
        let w = Int(width)
        let h = Int(height)

        lock.lock()
        if let existing = textures[key], existing.width == w, existing.height == h {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let descriptor = MTLTextureDescriptor()
        descriptor.width = w
        descriptor.height = h
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        lock.lock()
        textures[key] = texture
        lock.unlock()
        return texture
    }

    // MARK: - Discovery

    static func discoverSources() -> [NDISourceInfo] {
        guard NDIlib_initialize() else { return [] }

        var create = NDIlib_find_create_t()
        create.show_local_sources = true
        guard let finder = NDIlib_find_create_v2(&create) else { return [] }
        defer { NDIlib_find_destroy(finder) }

        var count: UInt32 = 0
        guard let sources = NDIlib_find_get_current_sources(finder, &count) else { return [] }

        var result: [NDISourceInfo] = []
        for i in 0..<Int(count) {
            let source = sources[i]
            guard let namePtr = source.p_ndi_name else { continue }
            let name = String(cString: namePtr)
            result.append(NDISourceInfo(name: name))
        }
        return result
    }

    private static func findSourceName(named name: String) -> String? {
        var create = NDIlib_find_create_t()
        create.show_local_sources = true
        guard let finder = NDIlib_find_create_v2(&create) else { return nil }
        defer { NDIlib_find_destroy(finder) }

        var count: UInt32 = 0
        guard let sources = NDIlib_find_get_current_sources(finder, &count) else { return nil }

        for i in 0..<Int(count) {
            let source = sources[i]
            guard let namePtr = source.p_ndi_name else { continue }
            if String(cString: namePtr) == name {
                return name
            }
        }
        return nil
    }
}

/// Displayable summary of a discovered NDI source.
struct NDISourceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    init(name: String) {
        self.name = name
        self.id = name
    }
}
