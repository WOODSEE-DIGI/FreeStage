//
//  AudioRingBuffer.swift
//  FreeStage
//
//  Thread-safe ring buffer for interleaved Float32 audio samples.
//

import Foundation

/// Fixed-size ring buffer for interleaved audio samples (e.g. LRLR…).
/// One slot is left unused so full and empty states are distinguishable.
final class AudioRingBuffer: @unchecked Sendable {
    private let buffer: UnsafeMutablePointer<Float>
    private let capacity: Int
    private let lock = NSLock()
    private var readIndex = 0
    private var writeIndex = 0

    init(capacity: Int) {
        self.capacity = max(capacity, 2)
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: self.capacity)
    }

    deinit {
        buffer.deallocate()
    }

    /// Write interleaved samples. Returns the number of samples actually written.
    @discardableResult
    func write(_ samples: UnsafePointer<Float>, count: Int) -> Int {
        lock.withLock {
            var written = 0
            for i in 0..<count {
                let next = (writeIndex + 1) % capacity
                guard next != readIndex else { break }
                buffer[writeIndex] = samples[i]
                writeIndex = next
                written += 1
            }
            return written
        }
    }

    /// Read up to `count` interleaved samples into `output`. Returns samples read.
    @discardableResult
    func read(into output: UnsafeMutablePointer<Float>, count: Int) -> Int {
        lock.withLock {
            let available = (writeIndex - readIndex + capacity) % capacity
            let toRead = min(count, available)
            for i in 0..<toRead {
                output[i] = buffer[readIndex]
                readIndex = (readIndex + 1) % capacity
            }
            return toRead
        }
    }

    /// Discard all contents.
    func clear() {
        lock.withLock {
            readIndex = 0
            writeIndex = 0
        }
    }

    /// Current number of interleaved samples available to read.
    var count: Int {
        lock.withLock { (writeIndex - readIndex + capacity) % capacity }
    }
}
