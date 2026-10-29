import Testing
import SwiftUI
@testable import CrystalDiskInfoMacCore

@MainActor
@Test func mainViewRendersAtExpectedSize() {
    let renderer = ImageRenderer(content: MainView(model: .preview))
    renderer.proposedSize = .init(width: 960, height: 640)

    let image = renderer.nsImage
    #expect(image != nil)
    #expect(image?.size == CGSize(width: 960, height: 640))
}

