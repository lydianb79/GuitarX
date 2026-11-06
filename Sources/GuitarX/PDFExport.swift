import AppKit
import UniformTypeIdentifiers

/// Builds PDF sheets of fretboard diagrams using the Metal renderer for the artwork.
enum PDFExporter {
    struct Item {
        let title: String
        let subtitle: String
        let detail: String
        let image: CGImage
    }

    // A4 landscape
    private static let pageSize = CGSize(width: 842, height: 595)
    private static let margin: CGFloat = 36

    // MARK: Entry points

    static func exportCurrentView(state: AppState) {
        guard let item = capture(state: state) else { return beep() }
        save(items: [item], perPage: 1, suggestedName: state.title, state: state)
    }

    static func exportAll(state: AppState) {
        let items = captureAll(state: state)
        guard !items.isEmpty else { return beep() }
        save(items: items, perPage: 2, suggestedName: "\(state.title) – \(state.exportAllLabel)", state: state)
    }

    // MARK: Capturing

    private static func capture(state: AppState) -> Item? {
        guard let renderer = state.renderer else { return nil }
        let width = 1400
        let height = Int(FretboardLayout.idealHeight(strings: state.tuning.notes.count))
        guard let image = renderer.renderImage(width: width, height: height) else { return nil }
        return Item(title: state.title, subtitle: state.subtitle, detail: detailLine(state), image: image)
    }

    private static func detailLine(_ state: AppState) -> String {
        let ivs = state.currentIntervals
        let names = state.spelledNotes
        var parts = zip(names, ivs).map { "\($0.text) (\($1.label))" }.joined(separator: "   ")
        if let v = state.displayedVoicing { parts += "      Grip: \(v.shorthand)" }
        return "\(parts)      Tuning: \(state.tuning.name)"
    }

    /// Steps through every position / shape / voicing / chord of the current mode, then restores the state.
    private static func captureAll(state: AppState) -> [Item] {
        var items: [Item] = []
        func grab() { if let i = capture(state: state) { items.append(i) } }

        switch state.mode {
        case .scale:
            let saved = state.scalePosition
            let count = state.positionSystem == .boxes ? state.scalePositions.count : state.scaleCAGEDShapes.count
            for p in 0...count { state.scalePosition = p; grab() }
            state.scalePosition = saved

        case .chord:
            switch state.chordDisplay {
            case .caged:
                let saved = state.cagedIndex
                for i in 0..<state.chordCAGEDShapes.count { state.cagedIndex = i; grab() }
                state.cagedIndex = saved
            case .voicings:
                let saved = state.voicingIndex
                for i in 0..<min(state.voicings.count, 30) { state.voicingIndex = i; grab() }
                state.voicingIndex = saved
            case .allTones:
                let saved = state.inversion
                for i in 0..<state.chord.intervals.count { state.inversion = i; grab() }
                state.inversion = saved
            }

        case .progression:
            if state.isPlaying { state.stopPlayback() }
            let saved = state.progressionStep
            for i in 0..<state.progression.count { state.progressionStep = i; grab() }
            state.progressionStep = saved
        }
        return items
    }

    // MARK: Writing

    private static func save(items: [Item], perPage: Int, suggestedName: String, state: AppState) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = sanitize(suggestedName) + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard write(items: items, perPage: perPage, to: url, state: state) else { return beep() }
        NSWorkspace.shared.open(url)
    }

    private static func write(items: [Item], perPage: Int, to url: URL, state: AppState) -> Bool {
        var box = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [kCGPDFContextCreator: "GuitarX", kCGPDFContextTitle: state.title]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return false }

        let pages = stride(from: 0, to: items.count, by: perPage).map { Array(items[$0..<min($0 + perPage, items.count)]) }
        for (pageIndex, pageItems) in pages.enumerated() {
            ctx.beginPDFPage(nil)
            let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc

            let contentTop = pageSize.height - margin
            let contentHeight = pageSize.height - margin * 2 - 18   // leave room for footer
            let slot = contentHeight / CGFloat(perPage)
            for (i, item) in pageItems.enumerated() {
                draw(item, in: CGRect(x: margin, y: contentTop - slot * CGFloat(i + 1),
                                      width: pageSize.width - margin * 2, height: slot), ctx: ctx)
            }
            drawFooter(page: pageIndex + 1, of: pages.count, state: state)

            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return true
    }

    private static func draw(_ item: Item, in rect: CGRect, ctx: CGContext) {
        var y = rect.maxY
        y = drawText(item.title, size: 18, weight: .bold, color: .black, x: rect.minX, top: y, width: rect.width)
        y = drawText(item.subtitle, size: 10.5, weight: .regular, color: .darkGray, x: rect.minX, top: y - 2, width: rect.width)
        y = drawText(item.detail, size: 10, weight: .medium, color: NSColor(white: 0.25, alpha: 1),
                     x: rect.minX, top: y - 3, width: rect.width)
        y -= 8

        let aspect = CGFloat(item.image.height) / CGFloat(item.image.width)
        var w = rect.width
        var h = w * aspect
        let available = y - rect.minY - 10
        if h > available { h = max(available, 40); w = h / aspect }
        let imageRect = CGRect(x: rect.minX + (rect.width - w) / 2, y: y - h, width: w, height: h)

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: imageRect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.clip()
        ctx.interpolationQuality = .high
        ctx.draw(item.image, in: imageRect)
        ctx.restoreGState()
    }

    /// Draws a single line of text whose top edge is at `top`; returns the new top for the next line.
    @discardableResult
    private static func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor,
                                 x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let h = ceil(str.size().height)
        str.draw(with: CGRect(x: x, y: top - h, width: width, height: h), options: [.usesLineFragmentOrigin])
        return top - h
    }

    private static func drawFooter(page: Int, of total: Int, state: AppState) {
        let df = DateFormatter()
        df.dateStyle = .medium
        let text = "GuitarX  ·  \(df.string(from: Date()))  ·  page \(page) of \(total)"
        drawText(text, size: 8.5, weight: .regular, color: .gray, x: margin, top: margin - 6,
                 width: pageSize.width - margin * 2)
    }

    private static func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return s.components(separatedBy: bad).joined(separator: "-")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func beep() { NSSound.beep() }
}
