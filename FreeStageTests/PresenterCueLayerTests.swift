//
//  PresenterCueLayerTests.swift
//  FreeStageTests
//
//  Tests for per-cue (per-segment) presenter layers: model compatibility,
//  scene composition order, and store mutations.
//

import Foundation
import Testing
@testable import FreeStage

@MainActor
struct PresenterCueLayerTests {

    private func makeStore(
        segmentLayers: [Layer] = [],
        globalLayers: [Layer] = []
    ) -> (ShowStore, PresenterSegment) {
        let segment = PresenterSegment(
            name: "Screen Share Cue",
            type: .cameraGraphic,
            cameraAngle: .primary,
            layers: segmentLayers
        )
        let rundown = PresenterRundown(
            segments: [segment],
            globalLayers: globalLayers
        )
        let show = Show(kind: .presenter, presenterRundown: rundown)
        return (ShowStore(show: show), segment)
    }

    // MARK: - Codable backwards compatibility

    @Test("Legacy segment JSON without layers decodes with an empty layer list")
    func legacySegmentDecodesWithoutLayers() throws {
        let json = """
        {
          "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "name": "Opening",
          "type": "cameraGraphic",
          "cameraAngle": "primary",
          "autoFollow": false,
          "notes": ""
        }
        """.data(using: .utf8)!

        let segment = try JSONDecoder().decode(PresenterSegment.self, from: json)

        #expect(segment.name == "Opening")
        #expect(segment.layers.isEmpty)
    }

    @Test("Segments round-trip their cue layers through Codable")
    func segmentRoundTripsLayers() throws {
        let layer = Layer(
            name: "Screen 1",
            source: .screen(displayID: 1),
            placement: .foreground
        )
        let segment = PresenterSegment(name: "Cue", layers: [layer])

        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(PresenterSegment.self, from: data)

        #expect(decoded.layers.count == 1)
        #expect(decoded.layers.first?.name == "Screen 1")
        #expect(decoded.layers.first?.placement == .foreground)
    }

    // MARK: - Scene composition

    @Test("Cue background layers render behind content and foreground layers on top")
    func sceneCompositionOrder() {
        let background = Layer(
            name: "Cue BG",
            source: .color(CGColorComponents(r: 0, g: 0, b: 1, a: 1)),
            placement: .background
        )
        let foreground = Layer(
            name: "Cue FG",
            source: .color(CGColorComponents(r: 1, g: 0, b: 0, a: 1)),
            placement: .foreground
        )
        let globalFG = Layer(
            name: "Global Bug",
            source: .color(CGColorComponents(r: 0, g: 1, b: 0, a: 1)),
            placement: .foreground
        )
        let globalBG = Layer(
            name: "Global Set",
            source: .color(CGColorComponents(r: 0.5, g: 0.5, b: 0.5, a: 1)),
            placement: .background
        )
        let (store, segment) = makeStore(
            segmentLayers: [foreground, background],
            globalLayers: [globalFG, globalBG]
        )

        let scene = store.scene(for: segment)
        let names = scene.layers.map(\.name)

        let globalBGIndex = names.firstIndex(of: "Global Set")
        let cueBGIndex = names.firstIndex(of: "Cue BG")
        let cueFGIndex = names.firstIndex(of: "Cue FG")
        let globalFGIndex = names.firstIndex(of: "Global Bug")

        guard let globalBGIndex, let cueBGIndex, let cueFGIndex, let globalFGIndex else {
            Issue.record("Expected all cue and global layers in the scene: \(names)")
            return
        }

        #expect(globalBGIndex < cueBGIndex)
        #expect(cueBGIndex < cueFGIndex)
        #expect(cueFGIndex < globalFGIndex)
    }

    @Test("Hidden cue layers are excluded from the scene")
    func hiddenCueLayerExcluded() {
        let hidden = Layer(
            name: "Hidden",
            source: .color(CGColorComponents(r: 1, g: 1, b: 1, a: 1)),
            isVisible: false,
            placement: .foreground
        )
        let (store, segment) = makeStore(segmentLayers: [hidden])

        let names = store.scene(for: segment).layers.map(\.name)
        #expect(!names.contains("Hidden"))
    }

    // MARK: - Store mutations

    @Test("Adding a cue layer appends it to the owning segment only")
    func addCueLayer() {
        let (store, segment) = makeStore()

        let id = store.addPresenterSegmentLayer(
            segmentID: segment.id,
            source: .screen(displayID: 2),
            name: "Screen 2"
        )

        let layers = store.presenterSegment(id: segment.id)?.layers ?? []
        #expect(layers.count == 1)
        #expect(layers.first?.id == id)
        #expect(layers.first?.name == "Screen 2")
    }

    @Test("Updating then deleting a cue layer mutates the segment")
    func updateAndDeleteCueLayer() {
        let (store, segment) = makeStore()
        let id = store.addPresenterSegmentLayer(segmentID: segment.id, source: .color(CGColorComponents(r: 1, g: 0, b: 0, a: 1)))

        store.updatePresenterSegmentLayer(segmentID: segment.id, id: id) { layer in
            layer.opacity = 0.25
            layer.placement = .background
        }

        let updated = store.presenterSegment(id: segment.id)?.layers.first
        #expect(updated?.opacity == 0.25)
        #expect(updated?.placement == .background)

        store.deletePresenterSegmentLayer(segmentID: segment.id, id: id)
        #expect(store.presenterSegment(id: segment.id)?.layers.isEmpty == true)
    }

    @Test("Moving a cue layer reorders it within the segment")
    func moveCueLayer() {
        let (store, segment) = makeStore()
        let first = store.addPresenterSegmentLayer(segmentID: segment.id, source: .color(CGColorComponents(r: 1, g: 0, b: 0, a: 1)), name: "First")
        let second = store.addPresenterSegmentLayer(segmentID: segment.id, source: .color(CGColorComponents(r: 0, g: 1, b: 0, a: 1)), name: "Second")

        store.movePresenterSegmentLayer(segmentID: segment.id, id: second, by: -1)

        let names = store.presenterSegment(id: segment.id)?.layers.map(\.name)
        #expect(names == ["Second", "First"])

        // Moving past the bounds is a no-op rather than a crash.
        store.movePresenterSegmentLayer(segmentID: segment.id, id: first, by: 5)
        #expect(store.presenterSegment(id: segment.id)?.layers.map(\.name).count == 2)
    }

    @Test("Copying a cue layer produces an independent copy with a new ID")
    func copyCueLayer() {
        let source = PresenterSegment(name: "Source")
        let target = PresenterSegment(name: "Target")
        let rundown = PresenterRundown(segments: [source, target])
        let store = ShowStore(show: Show(kind: .presenter, presenterRundown: rundown))

        let id = store.addPresenterSegmentLayer(segmentID: source.id, source: .screen(displayID: 3), name: "Screen 3")
        store.copyPresenterSegmentLayer(from: source.id, layerID: id, to: target.id)

        let copies = store.presenterSegment(id: target.id)?.layers ?? []
        #expect(copies.count == 1)
        #expect(copies.first?.name == "Screen 3")
        #expect(copies.first?.id != id)
    }

    @Test("Cue layer mutations leave other segments untouched")
    func mutationsAreSegmentScoped() {
        let first = PresenterSegment(name: "First")
        let second = PresenterSegment(name: "Second")
        let store = ShowStore(show: Show(
            kind: .presenter,
            presenterRundown: PresenterRundown(segments: [first, second])
        ))

        store.addPresenterSegmentLayer(segmentID: first.id, source: .color(CGColorComponents(r: 0, g: 0, b: 0, a: 1)))

        #expect(store.presenterSegment(id: first.id)?.layers.count == 1)
        #expect(store.presenterSegment(id: second.id)?.layers.isEmpty == true)
    }
}
