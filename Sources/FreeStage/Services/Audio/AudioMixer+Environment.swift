//
//  AudioMixer+Environment.swift
//  FreeStage
//
//  Environment key for AudioMixer.
//

import SwiftUI

private struct AudioMixerKey: EnvironmentKey {
    static let defaultValue: AudioMixer? = nil
}

extension EnvironmentValues {
    var audioMixer: AudioMixer? {
        get { self[AudioMixerKey.self] }
        set { self[AudioMixerKey.self] = newValue }
    }
}
