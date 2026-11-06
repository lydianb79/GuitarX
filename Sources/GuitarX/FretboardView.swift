import SwiftUI
import MetalKit

/// SwiftUI wrapper around the Metal-rendered fretboard.
struct FretboardView: NSViewRepresentable {
    let state: AppState

    func makeNSView(context: Context) -> FretboardMTKView {
        let view = FretboardMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0.055, green: 0.055, blue: 0.065, alpha: 1)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.state = state
        if let renderer = FretboardRenderer(view: view, state: state) {
            view.renderer = renderer
            view.delegate = renderer
            state.renderer = renderer
        }
        return view
    }

    func updateNSView(_ nsView: FretboardMTKView, context: Context) {}
}

final class FretboardMTKView: MTKView {
    var renderer: FretboardRenderer?
    weak var state: AppState?
    private var hoverArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = hoverArea { removeTrackingArea(old) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    private func fretPos(for event: NSEvent) -> FretPos? {
        let p = convert(event.locationInWindow, from: nil)
        return renderer?.hitTest(x: Float(p.x), y: Float(bounds.height - p.y))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = fretPos(for: event)
        if state?.hover != p { state?.hover = p }
    }

    override func mouseExited(with event: NSEvent) {
        if state?.hover != nil { state?.hover = nil }
    }

    override func mouseDown(with event: NSEvent) {
        if let p = fretPos(for: event) { state?.playNote(at: p) }
    }
}
