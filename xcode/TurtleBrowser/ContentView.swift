//
//  ContentView.swift
//  Turtle Browser — prototype 0.12.1 (Swift)
//
//  The browser window: back / forward / reload / home, an address
//  bar, and a page view painted by our own Turtle Engine.
//  Links in the page are clickable and load in the same window.
//

import SwiftUI
import AppKit

@MainActor
final class BrowserModel: ObservableObject {
    @Published var pageText = NSAttributedString(string: "")
    @Published var addressText = "turtle://home"
    @Published var pageTitle = "Turtle Browser"
    @Published var statusLine = "Turtle Engine 0.12.1 (Swift) — background photos, no JavaScript yet"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageID = 0
    @Published var pageBackground: NSColor? = nil
    @Published var columnTextWidth: CGFloat? = nil

    private var currentURL = ""
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    init() {
        load("turtle://home", push: false)
    }

    func normalize(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("turtle://") { return t }
        if t.contains("://") { return t }
        if t.contains(" ") || !t.contains(".") {
            let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            return "https://html.duckduckgo.com/html/?q=\(q)"
        }
        return "https://" + t
    }

    func go() { load(addressText) }
    func reload() { if !currentURL.isEmpty { load(currentURL, push: false) } }
    func goHome() { load("turtle://home") }

    func goBack() {
        guard let target = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        load(target, push: false)
    }

    func goForward() {
        guard let target = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        load(target, push: false)
    }

    func load(_ raw: String, push: Bool = true) {
        let target = normalize(raw)
        if push && !currentURL.isEmpty {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }
        statusLine = "Loading \(target) …"
        Task {
            do {
                let (finalURL, html) = try await tbFetch(urlString: target)
                let (title, body, pageBG, columnW) = await tbRenderPage(html: html, base: finalURL)
                self.currentURL = finalURL
                self.addressText = finalURL
                self.pageTitle = title
                self.pageText = body
                self.pageBackground = pageBG
                self.columnTextWidth = columnW
                self.statusLine = "\(finalURL)  ·  Turtle Engine 0.12.1 (Swift) — background photos, no JavaScript yet"
            } catch {
                self.currentURL = target
                self.addressText = target
                self.pageTitle = "Could not load page"
                let msg = NSMutableAttributedString()
                msg.append(NSAttributedString(
                    string: "This page could not be loaded\n\n",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: 20)]))
                msg.append(NSAttributedString(
                    string: "\(target)\n\nReason: \(error.localizedDescription)",
                    attributes: [.font: NSFont.systemFont(ofSize: 14)]))
                self.pageText = msg
                self.pageBackground = nil
                self.columnTextWidth = nil
                self.statusLine = "Load failed"
            }
            self.canGoBack = !self.backStack.isEmpty
            self.canGoForward = !self.forwardStack.isEmpty
            self.pageID += 1
        }
    }
}

struct PageTextView: NSViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = context.coordinator
        // The engine paints link appearance itself — CSS colors,
        // its own [n] markers. The text view's built-in styling
        // for anything carrying a link (blue, underlined) would
        // repaint whole cards, so it is switched off here; the
        // link attribute itself still makes text clickable.
        textView.linkTextAttributes = [:]
        // Layout step two: a layout manager that paints block
        // backgrounds as full-width bands across the column.
        textView.textContainer?.replaceLayoutManager(TBBandLayoutManager())
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticLinkDetectionEnabled = false
        scrollView.documentView = textView
        context.coordinator.attach(to: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.backgroundColor = model.pageBackground ?? NSColor.textBackgroundColor
        if context.coordinator.lastPageID != model.pageID {
            context.coordinator.lastPageID = model.pageID
            textView.textStorage?.setAttributedString(model.pageText)
            textView.scrollToBeginningOfDocument(nil)
        }
        context.coordinator.columnWidth = model.columnTextWidth
        context.coordinator.refreshInsets()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: BrowserModel
        var lastPageID = -1
        var columnWidth: CGFloat? = nil
        private weak var textView: NSTextView?
        private weak var clipView: NSClipView?
        private var frameObserver: NSObjectProtocol? = nil

        init(model: BrowserModel) {
            self.model = model
        }

        // Layout step two: keep the text centered in the column
        // the page itself declares, following the window as it
        // resizes — the insets do the centering.
        func attach(to scrollView: NSScrollView, textView: NSTextView) {
            self.textView = textView
            self.clipView = scrollView.contentView
            scrollView.contentView.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView, queue: .main) { [weak self] _ in
                self?.refreshInsets()
            }
        }

        func refreshInsets() {
            guard let textView = textView, let clipView = clipView else { return }
            let available = clipView.frame.width
            var insetX: CGFloat = 16
            if let column = columnWidth, available > 0 {
                insetX = max(16, (available - column) / 2)
            }
            let newInset = NSSize(width: insetX, height: 16)
            if textView.textContainerInset != newInset {
                textView.textContainerInset = newInset
            }
        }

        func detach() {
            if let frameObserver = frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
                self.frameObserver = nil
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let s = link as? String {
                model.load(s)
                return true
            }
            if let u = link as? URL {
                model.load(u.absoluteString)
                return true
            }
            return false
        }
    }
}

// Layout step two: background bands. AppKit fills a text
// background only behind its glyphs, so a banner hugs its
// words like a highlighter. When a background run belongs to
// a paragraph whose own terminating newline carries the same
// color, the run is a block's band — widen its rects to the
// full width of the text container (the column). An inline
// pill (a button inside the banner) never reaches its
// paragraph's newline in its own color, so it keeps its
// shape; a run that itself reaches a newline is a band too.
final class TBBandLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        if rectCount > 0, let storage = textStorage, storage.length > 0,
           let container = textContainers.first, let textView = container.textView,
           isBandRun(storage: storage, charRange: charRange, color: color) {
            let widened = UnsafeMutablePointer<NSRect>.allocate(capacity: rectCount)
            defer { widened.deallocate() }
            let left = textView.textContainerOrigin.x
            let width = container.size.width
            for i in 0..<rectCount {
                var rect = rectArray[i]
                rect.origin.x = left
                rect.size.width = width
                widened[i] = rect
            }
            super.fillBackgroundRectArray(widened, count: rectCount,
                                          forCharacterRange: charRange, color: color)
            return
        }
        super.fillBackgroundRectArray(rectArray, count: rectCount,
                                      forCharacterRange: charRange, color: color)
    }

    // Layout step three: continuous surfaces. A colored
    // container's paragraphs paint as separate bands (above),
    // but the spacing between them belongs to no line of
    // text, so it shows as dark seams — while a real box
    // paints its whole surface, gaps and all. Here, before
    // the ordinary background pass, consecutive paragraphs
    // that share one surface color are bridged: one fill
    // runs from the first paragraph's first line to the last
    // one's last line, seams included. A paragraph with no
    // surface color, or a different one, breaks the run;
    // the page's own background color is never bridged
    // (it is already the canvas).
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // AppKit's own background pass FIRST: it paints the
        // runs' background colors — including, in 0.10, right
        // over the photos and gradients this class had just
        // painted. Our surfaces and layers paint after it,
        // so they stay visible; the glyphs draw later still.
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        paintContinuousSurfaces(forGlyphRange: glyphsToShow, at: origin)
    }

    private func paintContinuousSurfaces(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0,
              let container = textContainers.first,
              let textView = container.textView else { return }
        let string = storage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let canvas = textView.backgroundColor

        // A surface: a run of consecutive paragraphs sharing
        // a background — its fill color and/or its layer box
        // (photos and gradients, 0.10).
        var bands: [(color: NSColor?, box: TBBackgroundBox?,
                     boxID: ObjectIdentifier?, top: CGFloat, bottom: CGFloat)] = []
        var index = charRange.location
        let end = min(NSMaxRange(charRange), string.length)
        while index < end {
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            if paragraph.length == 0 { break }
            let lastIndex = paragraph.location + paragraph.length - 1
            let box = storage.attribute(TBBackgroundKey, at: lastIndex,
                                        effectiveRange: nil) as? TBBackgroundBox
            let surface = surfaceColor(storage: storage, paragraph: paragraph)
            let fill = (surface != nil && !surface!.isEqual(canvas)) ? surface : nil
            if fill != nil || box != nil {
                var top: CGFloat? = nil
                var bottom: CGFloat = 0
                let pGlyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
                enumerateLineFragments(forGlyphRange: pGlyphs) { rect, _, _, _, _ in
                    if top == nil { top = rect.minY }
                    bottom = rect.maxY
                }
                if let top = top {
                    let boxID = box.map { ObjectIdentifier($0) }
                    bands.append((color: fill, box: box, boxID: boxID,
                                  top: top, bottom: bottom))
                }
            }
            index = NSMaxRange(paragraph)
        }

        if bands.isEmpty { return }
        // Coalesce neighbouring bands that share a surface
        // (same color, same layer box) across the ordinary
        // spacing between paragraphs, so one element's
        // background reads as one continuous surface.
        var surfaces: [(color: NSColor?, box: TBBackgroundBox?,
                        boxID: ObjectIdentifier?, top: CGFloat, bottom: CGFloat)] = []
        for band in bands {
            if let last = surfaces.last, last.boxID == band.boxID,
               (last.color == nil && band.color == nil)
                || (last.color != nil && band.color != nil
                    && last.color!.isEqual(band.color!)),
               band.top - last.bottom <= 64 {
                surfaces[surfaces.count - 1].bottom = band.bottom
            } else {
                surfaces.append(band)
            }
        }
        NSGraphicsContext.saveGraphicsState()
        for band in surfaces {
            let rect = NSRect(x: origin.x, y: origin.y + band.top,
                              width: container.size.width,
                              height: band.bottom - band.top)
            if let color = band.color {
                color.setFill()
                rect.fill()
            }
            if let box = band.box {
                paintBackgroundLayers(box, in: rect)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // Paint a surface's background layers: CSS lists the
    // top layer first, so the list paints back to front —
    // photos first, gradient veils over them.
    private func paintBackgroundLayers(_ box: TBBackgroundBox, in rect: NSRect) {
        for layer in box.layers.reversed() {
            switch layer.kind {
            case .gradient(let inner):
                tbDrawLinearGradient(inner: inner, in: rect)
            case .image:
                if let image = layer.image {
                    tbDrawBackgroundImage(image, in: rect, sizeSpec: box.sizeSpec,
                                          positionSpec: box.positionSpec,
                                          repeatSpec: box.repeatSpec)
                }
            }
        }
    }

    // A linear gradient from its specification: an optional
    // direction (90deg, to right, …; default to bottom),
    // then color stops with optional % positions.
    private func tbDrawLinearGradient(inner: String, in rect: NSRect) {
        let parts = tbSplitLayers(inner).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count >= 2 else { return }
        var angle: Double = 180
        var stopParts = parts
        let head = parts[0].lowercased()
        if head.hasSuffix("deg"), let value = Double(head.dropLast(3)) {
            angle = value
            stopParts = Array(parts.dropFirst())
        } else if head.hasPrefix("to ") {
            var x = 0.0
            var y = 0.0
            for word in head.dropFirst(3).split(separator: " ") {
                switch word {
                case "top": y = -1
                case "bottom": y = 1
                case "left": x = -1
                case "right": x = 1
                default: break
                }
            }
            angle = atan2(x, -y) * 180 / .pi
            stopParts = Array(parts.dropFirst())
        }
        var colors: [NSColor] = []
        var locations: [CGFloat] = []
        var specified: [Bool] = []
        for part in stopParts {
            var colorText = part
            var positionText: Substring? = nil
            if part.contains("("), let close = part.firstIndex(of: ")") {
                colorText = String(part[...close])
                let rest = part[part.index(after: close)...]
                    .trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { positionText = Substring(rest) }
            } else if let space = part.firstIndex(of: " ") {
                colorText = String(part[..<space])
                positionText = part[part.index(after: space)...]
            }
            guard let color = tbParseColor(colorText) else { continue }
            colors.append(color)
            if let positionText = positionText, positionText.hasSuffix("%"),
               let pct = Double(positionText.dropLast()) {
                locations.append(CGFloat(pct / 100))
                specified.append(true)
            } else {
                locations.append(0)
                specified.append(false)
            }
        }
        guard colors.count >= 2 else { return }
        // Unspecified stops: the first sits at 0, the last
        // at 1, and middles spread evenly between their
        // specified neighbours (the CSS rule).
        if !specified.first! { locations[0] = 0; specified[0] = true }
        if !specified.last! {
            locations[locations.count - 1] = 1
            specified[locations.count - 1] = true
        }
        var i = 0
        while i < locations.count {
            if specified[i] { i += 1; continue }
            var j = i
            while j < locations.count && !specified[j] { j += 1 }
            let from = locations[i - 1], to = locations[j]
            for k in i..<j {
                locations[k] = from + (to - from) * CGFloat(k - i + 1) / CGFloat(j - i + 1)
            }
            i = j
        }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors.map { $0.cgColor } as CFArray,
            locations: locations) else { return }
        let radians = angle * .pi / 180
        let dx = CGFloat(sin(radians))
        let dy = CGFloat(-cos(radians))
        let length = abs(rect.width * dx) + abs(rect.height * dy)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let start = NSPoint(x: center.x - dx * length / 2,
                            y: center.y - dy * length / 2)
        let end = NSPoint(x: center.x + dx * length / 2,
                          y: center.y + dy * length / 2)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation,
                                             .drawsAfterEndLocation])
        context.restoreGState()
    }

    // Draw a photo right side up. In the layout manager's
    // drawing space, NSImage's own drawing lands upside
    // down (the 0.11 banner wore its sunset inverted), so
    // the picture goes through Quartz with an explicit
    // vertical flip about the destination rect — specified
    // behavior, no heuristics.
    private func tbDrawPhoto(_ image: NSImage, in dest: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let cg = image.cgImage(forProposedRect: nil,
                                     context: NSGraphicsContext.current,
                                     hints: nil) else { return }
        context.saveGState()
        context.translateBy(x: 0, y: dest.minY + dest.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(cg, in: dest)
        context.restoreGState()
    }

    // A background photo, sized (cover / contain / auto /
    // lengths), positioned (keywords or % — the % point of
    // the photo aligns with the % point of the surface),
    // and tiled unless no-repeat.
    private func tbDrawBackgroundImage(_ image: NSImage, in rect: NSRect,
                                       sizeSpec: String, positionSpec: String,
                                       repeatSpec: String) {
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return }
        var drawn = natural
        let size = sizeSpec.trimmingCharacters(in: .whitespaces).lowercased()
        if size == "cover" {
            let scale = max(rect.width / natural.width, rect.height / natural.height)
            drawn = NSSize(width: natural.width * scale, height: natural.height * scale)
        } else if size == "contain" {
            let scale = min(rect.width / natural.width, rect.height / natural.height)
            drawn = NSSize(width: natural.width * scale, height: natural.height * scale)
        } else if !size.isEmpty && size != "auto" {
            let tokens = size.split(separator: " ").map(String.init)
            func dimension(_ token: String?, extent: CGFloat, natural: CGFloat) -> CGFloat {
                guard let token = token, token != "auto" else { return natural }
                if token.hasSuffix("%"), let pct = Double(token.dropLast()) {
                    return extent * CGFloat(pct) / 100
                }
                return tbLengthValue(token, fontSize: 16) ?? natural
            }
            let w = dimension(tokens.first, extent: rect.width, natural: natural.width)
            var h = dimension(tokens.count > 1 ? tokens[1] : nil,
                              extent: rect.height, natural: natural.height)
            if tokens.count < 2 || tokens[1] == "auto" {
                h = natural.height * (w / natural.width)
            }
            drawn = NSSize(width: w, height: h)
        }
        guard drawn.width > 0, drawn.height > 0 else { return }
        let (fx, fy) = tbBackgroundFractions(positionSpec)
        let originX = rect.minX + (rect.width - drawn.width) * fx
        let originY = rect.minY + (rect.height - drawn.height) * fy
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        if repeatSpec.lowercased().contains("no-repeat") {
            tbDrawPhoto(image, in: NSRect(x: originX, y: originY,
                                          width: drawn.width, height: drawn.height))
        } else {
            var startX = originX
            while startX > rect.minX { startX -= drawn.width }
            var startY = originY
            while startY > rect.minY { startY -= drawn.height }
            let repeatX = repeatSpec.lowercased() != "repeat-y"
            let repeatY = repeatSpec.lowercased() != "repeat-x"
            var x = startX
            while x < rect.maxX {
                var y = startY
                while y < rect.maxY {
                    tbDrawPhoto(image, in: NSRect(x: x, y: y,
                                                  width: drawn.width, height: drawn.height))
                    if !repeatY { break }
                    y += drawn.height
                }
                if !repeatX { break }
                x += drawn.width
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // background-position as fractions along each axis:
    // left/top 0, center 0.5, right/bottom 1, or a %.
    private func tbBackgroundFractions(_ spec: String) -> (fx: CGFloat, fy: CGFloat) {
        var fx: CGFloat? = nil
        var fy: CGFloat? = nil
        let tokens = spec.lowercased().split(separator: " ").map(String.init)
        if tokens == ["center"] { return (0.5, 0.5) }
        func setNext(_ value: CGFloat) {
            if fx == nil { fx = value }
            else if fy == nil { fy = value }
        }
        for token in tokens {
            switch token {
            case "left": fx = 0
            case "right": fx = 1
            case "top": fy = 0
            case "bottom": fy = 1
            case "center": setNext(0.5)
            default:
                if token.hasSuffix("%"), let pct = Double(token.dropLast()) {
                    setNext(CGFloat(pct) / 100)
                }
            }
        }
        return (fx ?? 0, fy ?? 0)
    }

    private func surfaceColor(storage: NSTextStorage, paragraph: NSRange) -> NSColor? {
        let lastIndex = paragraph.location + paragraph.length - 1
        if lastIndex < 0 { return nil }
        return storage.attribute(.backgroundColor, at: lastIndex,
                                 effectiveRange: nil) as? NSColor
    }

    private func isBandRun(storage: NSTextStorage, charRange: NSRange, color: NSColor) -> Bool {
        let string = storage.string as NSString
        let location = min(charRange.location, string.length - 1)
        if location < 0 { return false }
        let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
        let lastIndex = min(paragraph.location + paragraph.length - 1, string.length - 1)
        if lastIndex >= 0,
           let endColor = storage.attribute(.backgroundColor, at: lastIndex,
                                            effectiveRange: nil) as? NSColor,
           endColor.isEqual(color) {
            return true
        }
        let end = min(charRange.location + charRange.length, string.length)
        if end > charRange.location {
            return string.substring(with: NSRange(location: charRange.location,
                                                  length: end - charRange.location))
                .contains("\n")
        }
        return false
    }
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("\u{25C0}") { model.goBack() }
                    .disabled(!model.canGoBack)
                    .help("Back")
                Button("\u{25B6}") { model.goForward() }
                    .disabled(!model.canGoForward)
                    .help("Forward")
                Button("\u{27F3}") { model.reload() }
                    .help("Reload")
                Button("\u{2302}") { model.goHome() }
                    .help("Turtle Home")
                TextField("Address", text: $model.addressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.go() }
                Button("Go") { model.go() }
            }
            PageTextView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(model.statusLine)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(minWidth: 720, minHeight: 520)
    }
}
