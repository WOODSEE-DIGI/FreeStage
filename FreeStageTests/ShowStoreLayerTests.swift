//
//  ShowStoreLayerTests.swift
//  FreeStageTests
//
//  Tests for ShowStore layer helpers used by the Assemble workspace.
//

import Foundation
import Testing
@testable import FreeStage

@MainActor
struct ShowStoreLayerTests {

    @Test("addLayerToActiveCue appends a rectangle layer to a theatre scene")
    func addLayerToTheatreScene() {
        let scene = Scene(name: "Opening")
        let show = Show(kind: .theatre, scenes: [scene])
        let store = ShowStore(show: show)
        store.selectedSceneID = scene.id

        let layerID = store.addLayerToActiveCue(
            source: .color(.red),
            name: "Rectangle",
            transform: ItemTransform(x: 0.5, y: 0.5, scaleX: 0.3, scaleY: 0.3, rotation: 0, crop: .zero)
        )

        #expect(layerID != nil)
        #expect(store.show.scenes.first?.layers.count == 1)
        #expect(store.show.scenes.first?.layers.first?.name == "Rectangle")
        #expect(store.show.scenes.first?.layers.first?.source == .color(.red))
        #expect(store.show.scenes.first?.layers.first?.transform.scaleX == 0.3)
    }

    @Test("addLayerToActiveCue appends a text layer to a presenter segment")
    func addLayerToPresenterSegment() {
        let segment = PresenterSegment(name: "Opening", type: .cameraGraphic)
        let rundown = PresenterRundown(segments: [segment])
        let show = Show(kind: .presenter, presenterRundown: rundown)
        let store = ShowStore(show: show)
        store.selectSegment(id: segment.id)

        let layerID = store.addLayerToActiveCue(
            source: .text(TextSource(content: "New Text")),
            name: "Text"
        )

        #expect(layerID != nil)
        #expect(store.presenterSegment(id: segment.id)?.layers.count == 1)
        #expect(store.presenterSegment(id: segment.id)?.layers.first?.name == "Text")
        if case .text(let textSource) = store.presenterSegment(id: segment.id)?.layers.first?.source {
            #expect(textSource.content == "New Text")
        } else {
            Issue.record("Expected text source")
        }
    }

    @Test("addLayerToActiveCue selects the new layer")
    func addLayerSelectsIt() {
        let scene = Scene(name: "Opening")
        let show = Show(kind: .theatre, scenes: [scene])
        let store = ShowStore(show: show)
        store.selectedSceneID = scene.id

        let layerID = store.addLayerToActiveCue(source: .color(.white), name: "Box")

        #expect(store.selectedLayerID == layerID)
    }
}
