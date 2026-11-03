//
//  ContentView.swift
//  Turtle Browser — prototype 0.8.1 (Swift)
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
    @Published var statusLine = "Turtle Engine 0.8.1 (Swift) — layout step three, no JavaScript yet"
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
                self.statusLine = "\(finalURL)  ·  Turtle Engine 0.8.1 (Swift) — layout step three, no JavaScript yet"
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
        paintContinuousSurfaces(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func paintContinuousSurfaces(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0,
              let container = textContainers.first,
              let textView = container.textView else { return }
        let string = storage.string as NSString
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let canvas = textView.backgroundColor

        var bands: [(color: NSColor, top: CGFloat, bottom: CGFloat)] = []
        var previousWasBand = false
        var index = charRange.location
        let end = min(NSMaxRange(charRange), string.length)
        while index < end {
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            if paragraph.length == 0 { break }
            var merged = false
            if let color = surfaceColor(storage: storage, paragraph: paragraph),
               !color.isEqual(canvas) {
                var top: CGFloat? = nil
                var bottom: CGFloat = 0
                let pGlyphs = glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
                enumerateLineFragments(forGlyphRange: pGlyphs) { rect, _, _, _, _ in
                    if top == nil { top = rect.minY }
                    bottom = rect.maxY
                }
                if let top = top {
                    if previousWasBand, let last = bands.last, last.color.isEqual(color) {
                        bands[bands.count - 1].bottom = bottom
                    } else {
                        bands.append((color: color, top: top, bottom: bottom))
                    }
                    merged = true
                }
            }
            previousWasBand = merged
            index = NSMaxRange(paragraph)
        }

        if bands.isEmpty { return }
        NSGraphicsContext.saveGraphicsState()
        for band in bands {
            band.color.setFill()
            NSRect(x: origin.x, y: origin.y + band.top,
                   width: container.size.width,
                   height: band.bottom - band.top).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // A paragraph's surface color: the background carried by
    // its last character — for every paragraph but the final
    // one that is its terminating newline, which the renderer
    // paints with the block's own effective background.
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
