//
//  ContentView.swift
//  Chirpy Browser — prototype 0.18.0 (Swift)
//
//  The browser window: back / forward / reload / home, an address
//  bar, and a page view painted by our own Chirpy Engine.
//  Links in the page are clickable and load in the same window.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class BrowserModel: ObservableObject {
    @Published var pageText = NSAttributedString(string: "")
    @Published var addressText = "chirpy://home"
    @Published var pageTitle = "Chirpy Browser"
    @Published var statusLine = "Chirpy Engine 0.18.0 (Swift) — floats, forms, progress bar, no JavaScript yet"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageID = 0
    @Published var pageBackground: NSColor? = nil
    @Published var columnTextWidth: CGFloat? = nil
    @Published var pageForms: [TBFormSpec] = []
    @Published var pageFields: [TBFormField] = []
    @Published var pageLayoutEvents: [TBLayoutEvent] = []

    // Load progress (0.18): the bar under the address bar.
    // isLoading says a load is in flight; loadProgress is
    // the document fetch's fraction of the bar (the fetch
    // fills its first 70%) — nil while loading means there
    // is no honest fraction to show: the server declared
    // no length, or the page is in and now rendering its
    // styles and pictures. The window then shows an
    // indeterminate bar. Both clear when the page settles,
    // on success and on failure alike.
    @Published var isLoading = false
    @Published var loadProgress: Double? = nil
    private var loadGeneration = 0
    private var activeFetch: TBProgressFetcher? = nil

    private var currentURL = ""
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    init() {
        load("chirpy://home", push: false)
    }

    func normalize(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("chirpy://") { return t }
        if t.contains("://") { return t }
        if t.contains(" ") || !t.contains(".") {
            let q = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t
            return "https://html.duckduckgo.com/html/?q=\(q)"
        }
        return "https://" + t
    }

    // Forms (0.13): submit a GET form the way a browser
    // does — the action's own query items first, then the
    // hidden inputs, the fields' current values, and the
    // first named submit control — and navigate there.
    func submitForm(_ form: TBFormSpec, values: [Int: String]) {
        guard form.method == "get" || form.method == "post" else {
            statusLine = "That form sends with \(form.method.uppercased()) — Chirpy submits GET and POST forms for now"
            return
        }
        var items: [URLQueryItem] = []
        for hidden in form.hidden {
            items.append(URLQueryItem(name: hidden.name, value: hidden.value))
        }
        for field in pageFields where field.formID == form.id && !field.name.isEmpty {
            items.append(URLQueryItem(name: field.name,
                                      value: values[field.id] ?? field.defaultValue))
        }
        if let name = form.submitName {
            items.append(URLQueryItem(name: name, value: form.submitValue ?? ""))
        }
        if form.method == "post" {
            // The values travel in the body; the action
            // keeps only its own query, as a browser sends it.
            var encoder = URLComponents()
            encoder.queryItems = items
            load(form.action, postBody: encoder.percentEncodedQuery ?? "")
            return
        }
        var all = URLComponents(string: form.action)?.queryItems ?? []
        all.append(contentsOf: items)
        guard var components = URLComponents(string: form.action) else { return }
        components.queryItems = all.isEmpty ? nil : all
        if let url = components.url { load(url.absoluteString) }
    }

    func noteUnsubmittableField() {
        statusLine = "That box answers to the page's JavaScript — Chirpy doesn't speak it yet (a form with an action, like Google's, submits)"
    }

    func go() { load(addressText) }
    func reload() { if !currentURL.isEmpty { load(currentURL, push: false) } }
    func goHome() { load("chirpy://home") }

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

    func load(_ raw: String, push: Bool = true, postBody: String? = nil) {
        let target = normalize(raw)
        if push && !currentURL.isEmpty {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }
        statusLine = "Loading \(target) …"
        // Load progress (0.18): a new load supersedes any
        // in flight — stop its fetch, and let the generation
        // checks below silence its late arrival, so it can
        // neither paint over this page nor clear this bar.
        loadGeneration += 1
        let generation = loadGeneration
        activeFetch?.cancel()
        activeFetch = nil
        isLoading = true
        loadProgress = nil
        Task {
            guard generation == self.loadGeneration else { return }
            do {
                let fetched: (finalURL: String, html: String)
                if target.hasPrefix("http://") || target.hasPrefix("https://") {
                    // The document fetch reports its bytes:
                    // they fill the bar's first 70%.
                    let fetcher = TBProgressFetcher()
                    self.activeFetch = fetcher
                    fetched = try await fetcher.fetch(
                        urlString: target, postBody: postBody) { [weak self] fraction in
                        Task { @MainActor in
                            guard let self = self,
                                  generation == self.loadGeneration else { return }
                            self.loadProgress = fraction.map { 0.7 * $0 }
                        }
                    }
                } else if let postBody = postBody {
                    fetched = try await tbFetchPOST(urlString: target, body: postBody)
                } else {
                    fetched = try await tbFetch(urlString: target)
                }
                let (finalURL, html) = fetched
                // Fetched; rendering now. The render's own
                // fetches (styles, pictures, floats) have no
                // single honest fraction across their
                // passes, so the bar goes indeterminate
                // until the page settles.
                if generation == self.loadGeneration {
                    self.loadProgress = nil
                }
                let (title, body, pageBG, columnW, forms, fields, landedURL, layoutEvents) =
                    await tbRenderPage(html: html, base: finalURL)
                guard generation == self.loadGeneration else { return }
                self.currentURL = landedURL
                self.addressText = landedURL
                self.pageTitle = title
                self.pageText = body
                self.pageBackground = pageBG
                self.columnTextWidth = columnW
                self.pageForms = forms
                self.pageFields = fields
                self.pageLayoutEvents = layoutEvents
                self.statusLine = "\(finalURL)  ·  Chirpy Engine 0.18.0 (Swift) — floats, forms, progress bar, no JavaScript yet"
            } catch {
                guard generation == self.loadGeneration else { return }
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
                self.pageForms = []
                self.pageFields = []
                self.pageLayoutEvents = []
                self.statusLine = "Load failed"
            }
            self.isLoading = false
            self.loadProgress = nil
            self.activeFetch = nil
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
        textView.layoutManager?.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isAutomaticLinkDetectionEnabled = false
        // Drag-and-drop (0.18): the page view is read-only
        // and takes no drops of its own — unregister its
        // dragged types, so a file dropped on the page
        // falls through to the window's own drop handler
        // (the onDrop on the root view) instead of being
        // swallowed by the text view.
        textView.unregisterDraggedTypes()
        scrollView.documentView = textView
        context.coordinator.attach(to: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.backgroundColor = model.pageBackground ?? NSColor.textBackgroundColor
        if context.coordinator.lastPageID != model.pageID {
            context.coordinator.lastPageID = model.pageID
            context.coordinator.clearFormViews()
            textView.textStorage?.setAttributedString(model.pageText)
            textView.scrollToBeginningOfDocument(nil)
            context.coordinator.rebuildFormViews()
            context.coordinator.layoutEvents = model.pageLayoutEvents
            context.coordinator.floatLayoutDirty = true
            context.coordinator.settleFloatLayout()
        }
        context.coordinator.columnWidth = model.columnTextWidth
        context.coordinator.refreshInsets()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        let model: BrowserModel
        var lastPageID = -1
        var columnWidth: CGFloat? = nil
        private weak var textView: NSTextView?
        private weak var clipView: NSClipView?
        private var frameObserver: NSObjectProtocol? = nil

        // Forms (0.13): the real controls laid over the
        // engine's field and button attachments, and where
        // each one is anchored in the text.
        private var fieldViews: [Int: NSTextField] = [:]
        private var formControlViews: [NSView] = []
        private var formAnchors: [(view: NSView, charIndex: Int,
                                   attachment: NSTextAttachment)] = []
        private var formIDByFieldID: [Int: Int] = [:]

        // Positioned layout (0.17): the page's float and
        // clear events, and the container width they were
        // last resolved at — the exclusion paths are rebuilt
        // whenever either changes.
        var layoutEvents: [TBLayoutEvent] = []
        var floatLayoutDirty = false
        private var floatWidth: CGFloat = 0

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
            settleFormViews()
            // A new column width can land mid-cycle; resolve
            // the floats once it has settled, the same way
            // the form seating settles.
            DispatchQueue.main.async { [weak self] in
                self?.settleFloatLayout()
            }
        }

        func detach() {
            if let frameObserver = frameObserver {
                NotificationCenter.default.removeObserver(frameObserver)
                self.frameObserver = nil
            }
            for view in formControlViews { view.removeFromSuperview() }
            formControlViews = []
            formAnchors = []
            fieldViews = [:]
        }

        // Remove every control and forget every anchor.
        func clearFormViews() {
            for view in formControlViews { view.removeFromSuperview() }
            formControlViews = []
            formAnchors = []
            fieldViews = [:]
        }

        // Build this page's controls over their attachments:
        // an NSTextField for every typable input, an NSButton
        // for every submit. The attachments reserved the
        // space in the text; these are the live controls.
        @MainActor func rebuildFormViews() {
            guard let textView = textView,
                  let storage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            for view in formControlViews { view.removeFromSuperview() }
            formControlViews = []
            formAnchors = []
            fieldViews = [:]
            formIDByFieldID = Dictionary(
                uniqueKeysWithValues: model.pageFields.map { ($0.id, $0.formID) })
            guard storage.length > 0 else { return }
            layoutManager.ensureLayout(for: container)
            storage.enumerateAttribute(
                .attachment, in: NSRange(location: 0, length: storage.length)
            ) { value, range, _ in
                if let fieldAtt = value as? TBFieldAttachment,
                   let spec = self.model.pageFields.first(where: { $0.id == fieldAtt.fieldID }) {
                    let field = NSTextField()
                    field.stringValue = spec.defaultValue
                    field.placeholderString = spec.placeholder
                    field.font = NSFont.systemFont(ofSize: 13)
                    field.isBezeled = true
                    field.bezelStyle = .roundedBezel
                    field.tag = spec.id
                    field.target = self
                    field.action = #selector(Coordinator.fieldSubmitted(_:))
                    textView.addSubview(field)
                    self.fieldViews[spec.id] = field
                    self.formControlViews.append(field)
                    self.formAnchors.append((view: field, charIndex: range.location,
                                             attachment: fieldAtt))
                } else if let submitAtt = value as? TBSubmitAttachment {
                    let button = NSButton(title: submitAtt.label, target: self,
                                          action: #selector(Coordinator.submitClicked(_:)))
                    button.bezelStyle = .rounded
                    button.bezelColor = .controlColor
                    button.tag = submitAtt.formID
                    textView.addSubview(button)
                    self.formControlViews.append(button)
                    self.formAnchors.append((view: button, charIndex: range.location,
                                             attachment: submitAtt))
                }
            }
            repositionFormViews()
            // The seating is measured again once this update
            // cycle has fully settled — window size, insets,
            // and layout all final — because a measurement
            // taken mid-update seats every control at the
            // line's start (0.13.1's overlapping pile).
            DispatchQueue.main.async { [weak self] in
                self?.settleFormViews()
            }
        }

        // Force the layout complete, then seat the controls.
        func settleFormViews() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            repositionFormViews()
        }

        // Positioned layout (0.17): resolve the page's float
        // and clear events against the column's real width.
        // Each float packs at the highest band it fits —
        // against its side's edge or beside the floats
        // already there, dropping below the shallowest
        // blocker when the band is full — and becomes an
        // exclusion path the remaining text wraps around;
        // each clear becomes a full-width exclusion running
        // from its paragraph's top to the deepest float it
        // must pass. Exclusions apply one event at a time,
        // with layout re-run between them, so every later
        // anchor measures the text as it will truly lie.
        // A non-floated block beside a float needs nothing
        // special: the exclusion narrows its lines for as
        // long as the float lasts, and full width resumes
        // below it — the sidebar pattern falls out of this.
        func settleFloatLayout() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let storage = textView.textStorage else { return }
            let width = container.size.width
            if !floatLayoutDirty && width == floatWidth { return }
            if width < 40 { return }   // no real frame yet; stay dirty
            floatLayoutDirty = false
            floatWidth = width
            let band = layoutManager as? TBBandLayoutManager
            band?.floatPaints = []
            if !container.exclusionPaths.isEmpty {
                container.exclusionPaths = []
            }
            guard !layoutEvents.isEmpty, storage.length > 0 else {
                textView.needsDisplay = true
                return
            }
            layoutManager.ensureLayout(for: container)
            var placed: [(rect: NSRect, side: TBFloatSide, anchor: Int)] = []
            var paints: [(rect: NSRect, spec: TBFloatSpec)] = []
            var exclusions: [NSBezierPath] = []

            func overlaps(_ a: NSRect, _ b: NSRect) -> Bool {
                a.minX < b.maxX && b.minX < a.maxX
                    && a.minY < b.maxY && b.minY < a.maxY
            }
            func applyExclusions(from charIndex: Int) {
                container.exclusionPaths = exclusions
                if charIndex < storage.length {
                    layoutManager.invalidateLayout(
                        forCharacterRange: NSRange(location: charIndex,
                                                   length: storage.length - charIndex),
                        actualCharacterRange: nil)
                }
                layoutManager.ensureLayout(for: container)
            }

            for event in layoutEvents {
                switch event {
                case .float(let spec):
                    let marginW = spec.borderWidth + spec.marginLeft + spec.marginRight
                    let marginH = spec.borderHeight + spec.marginTop + spec.marginBottom
                    var top = floatAnchorY(spec.anchorCharIndex)
                    // A float never rises above an earlier one.
                    for other in placed { top = max(top, other.rect.minY) }
                    var y = top
                    var marginX: CGFloat? = nil
                    var tries = 0
                    while marginX == nil && tries < 80 {
                        tries += 1
                        let blockers = placed.filter {
                            $0.rect.minY < y + marginH && y < $0.rect.maxY
                        }
                        var candidates: [CGFloat] = [
                            spec.side == .left ? 0 : width - marginW
                        ]
                        for blocker in blockers {
                            candidates.append(spec.side == .left
                                ? blocker.rect.maxX
                                : blocker.rect.minX - marginW)
                        }
                        candidates.sort { spec.side == .left ? $0 < $1 : $0 > $1 }
                        for x in candidates {
                            if x < -0.5 || x + marginW > width + 0.5 { continue }
                            let rect = NSRect(x: x, y: y,
                                              width: marginW, height: marginH)
                            if blockers.allSatisfy({ !overlaps($0.rect, rect) }) {
                                marginX = x
                                break
                            }
                        }
                        if marginX == nil {
                            // The band is full: drop below the
                            // shallowest blocker and try again.
                            // With nothing in the way but a box
                            // wider than the column, take the
                            // edge and let it overflow.
                            let bottoms = blockers.map { $0.rect.maxY }
                                .filter { $0 > y }
                            if let next = bottoms.min() {
                                y = next
                            } else {
                                marginX = spec.side == .left
                                    ? 0 : max(0, width - marginW)
                            }
                        }
                    }
                    let placedX = marginX ?? 0
                    let marginRect = NSRect(x: placedX, y: y,
                                            width: marginW, height: marginH)
                    placed.append((rect: marginRect, side: spec.side,
                                   anchor: spec.anchorCharIndex))
                    paints.append((rect: NSRect(x: placedX + spec.marginLeft,
                                                y: y + spec.marginTop,
                                                width: spec.borderWidth,
                                                height: spec.borderHeight),
                                   spec: spec))
                    exclusions.append(NSBezierPath(rect: marginRect))
                    applyExclusions(from: spec.anchorCharIndex)
                case .clear(let spec):
                    // A clear at the very end of the text has
                    // nothing after it to push — skip it, so a
                    // trailing float is never mistaken for a
                    // reason to move the last line.
                    guard spec.anchorCharIndex < storage.length else { continue }
                    let anchorTop = floatAnchorY(spec.anchorCharIndex)
                    var limit: CGFloat = 0
                    for other in placed {
                        if spec.side == .left && other.side != .left { continue }
                        if spec.side == .right && other.side != .right { continue }
                        if let start = spec.rangeStart,
                           !(other.anchor >= start
                             && other.anchor < spec.anchorCharIndex) {
                            continue
                        }
                        limit = max(limit, other.rect.maxY)
                    }
                    if limit > anchorTop + 1 {
                        exclusions.append(NSBezierPath(rect: NSRect(
                            x: 0, y: anchorTop, width: width,
                            height: limit - anchorTop)))
                        applyExclusions(from: spec.anchorCharIndex)
                    }
                }
            }
            band?.floatPaints = paints
            textView.needsDisplay = true
            repositionFormViews()
        }

        // The top of the line holding a character, in text
        // container coordinates — where a float hangs from,
        // and where a clear's exclusion begins.
        private func floatAnchorY(_ charIndex: Int) -> CGFloat {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let storage = textView.textStorage,
                  storage.length > 0 else { return 0 }
            let clamped = min(max(charIndex, 0), storage.length - 1)
            let glyph = layoutManager.glyphIndexForCharacter(at: clamped)
            // NSLayoutManager ensures layout by container or
            // glyph range — there is no forGlyphAt variant
            // (first-build compile fix, Nov 4).
            layoutManager.ensureLayout(for: container)
            return layoutManager.lineFragmentRect(forGlyphAt: glyph,
                                                  effectiveRange: nil).minY
        }

        // Set each control over its attachment: the glyph's
        // line rect, with the control's own height centered
        // in the line. This pass only reads finished layout,
        // so the layout-completion callback may use it.
        func repositionFormViews() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  !formAnchors.isEmpty else { return }
            let origin = textView.textContainerOrigin
            let charCount = textView.textStorage?.length ?? 0
            // Controls seat in text order. A field seats by
            // its glyph; a submit seats immediately after
            // the previous control of its own form — the
            // field's frame is known-good (it has landed
            // correctly in every build), so the buttons
            // chain off it instead of trusting a second
            // glyph measurement that has twice mis-seated
            // them.
            var lastInForm: [Int: NSRect] = [:]
            for anchor in formAnchors {
                guard anchor.charIndex < charCount else { continue }
                let glyph = layoutManager.glyphIndexForCharacter(at: anchor.charIndex)
                guard glyph < layoutManager.numberOfGlyphs else { continue }
                let fragment = layoutManager.lineFragmentRect(
                    forGlyphAt: glyph, effectiveRange: nil)
                let spot = layoutManager.location(forGlyphAt: glyph)
                let size = anchor.attachment.bounds.size
                var frame = NSRect(
                    x: origin.x + fragment.minX + spot.x,
                    y: origin.y + fragment.minY + (fragment.height - size.height) / 2,
                    width: size.width, height: size.height)
                var formID = -2
                if let fieldAtt = anchor.attachment as? TBFieldAttachment {
                    formID = formIDByFieldID[fieldAtt.fieldID] ?? -1
                } else if let submitAtt = anchor.attachment as? TBSubmitAttachment {
                    formID = submitAtt.formID
                    if let prev = lastInForm[formID] {
                        frame.origin.x = prev.maxX + 8
                        frame.origin.y = prev.minY + (prev.height - size.height) / 2
                    }
                }
                anchor.view.frame = frame
                if formID != -2 { lastInForm[formID] = frame }
            }
        }

        func layoutManager(_ layoutManager: NSLayoutManager,
                           didCompleteLayoutFor textContainer: NSTextContainer?,
                           atEnd layoutFinishedFlag: Bool) {
            if layoutFinishedFlag { repositionFormViews() }
        }

        @MainActor @objc func fieldSubmitted(_ sender: NSTextField) {
            guard let spec = model.pageFields.first(where: { $0.id == sender.tag })
            else { return }
            if spec.formID >= 0,
               let form = model.pageForms.first(where: { $0.id == spec.formID }) {
                submit(form)
            } else {
                model.noteUnsubmittableField()
            }
        }

        @MainActor @objc func submitClicked(_ sender: NSButton) {
            if let form = model.pageForms.first(where: { $0.id == sender.tag }) {
                submit(form)
            }
        }

        @MainActor private func submit(_ form: TBFormSpec) {
            var values: [Int: String] = [:]
            for (id, field) in fieldViews {
                if model.pageFields.first(where: { $0.id == id })?.formID == form.id {
                    values[id] = field.stringValue
                }
            }
            model.submitForm(form, values: values)
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
    // Positioned layout (0.17): the floats the coordinator
    // has placed for this page — border rects in container
    // coordinates, with the spec describing each box —
    // painted last in drawBackground, over the surfaces.
    var floatPaints: [(rect: NSRect, spec: TBFloatSpec)] = [] {
        didSet { floatContentLayouts = [:] }
    }
    private var floatContentLayouts:
        [ObjectIdentifier: (NSLayoutManager, NSTextContainer)] = [:]

    // A character's relative-position offset (0.17), read
    // from the stamp the renderer left on the text.
    private func paintOffset(at charIndex: Int, in storage: NSTextStorage) -> NSPoint {
        guard storage.length > 0 else { return .zero }
        let clamped = min(max(charIndex, 0), storage.length - 1)
        if let value = storage.attribute(TBRelOffsetKey, at: clamped,
                                         effectiveRange: nil) as? NSValue {
            return value.pointValue
        }
        return .zero
    }

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        guard rectCount > 0, let storage = textStorage, storage.length > 0 else {
            super.fillBackgroundRectArray(rectArray, count: rectCount,
                                          forCharacterRange: charRange, color: color)
            return
        }
        let offset = paintOffset(at: charRange.location, in: storage)
        if let container = textContainers.first, let textView = container.textView,
           isBandRun(storage: storage, charRange: charRange, color: color) {
            let widened = UnsafeMutablePointer<NSRect>.allocate(capacity: rectCount)
            defer { widened.deallocate() }
            let left = textView.textContainerOrigin.x + offset.x
            let width = container.size.width
            for i in 0..<rectCount {
                var rect = rectArray[i]
                rect.origin.x = left
                rect.origin.y += offset.y
                rect.size.width = width
                widened[i] = rect
            }
            super.fillBackgroundRectArray(widened, count: rectCount,
                                          forCharacterRange: charRange, color: color)
            return
        }
        // Positioned layout (0.17): a relatively offset run
        // takes its background with it when it shifts.
        if offset != .zero {
            let shifted = UnsafeMutablePointer<NSRect>.allocate(capacity: rectCount)
            defer { shifted.deallocate() }
            for i in 0..<rectCount {
                shifted[i] = NSRect(x: rectArray[i].origin.x + offset.x,
                                    y: rectArray[i].origin.y + offset.y,
                                    width: rectArray[i].width,
                                    height: rectArray[i].height)
            }
            super.fillBackgroundRectArray(shifted, count: rectCount,
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
        paintFloats(at: origin)
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
                     boxID: ObjectIdentifier?, top: CGFloat, bottom: CGFloat,
                     dx: CGFloat, dy: CGFloat)] = []
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
                    // Surface edges (0.15): the surface's
                    // first paragraph carries the inside
                    // space above it, its last the space
                    // below — extend the band through both,
                    // so a padded container's color and
                    // photo reach their true edges.
                    let extTop = (storage.attribute(TBExtTopKey, at: paragraph.location,
                                                    effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
                    let extBottom = (storage.attribute(TBExtBottomKey, at: paragraph.location,
                                                       effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
                    let boxID = box.map { ObjectIdentifier($0) }
                    // Positioned layout (0.17): a relatively
                    // offset surface paints shifted, as one
                    // band of its own.
                    let offset = paintOffset(at: paragraph.location, in: storage)
                    bands.append((color: fill, box: box, boxID: boxID,
                                  top: top - CGFloat(extTop),
                                  bottom: bottom + CGFloat(extBottom),
                                  dx: offset.x, dy: offset.y))
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
                        boxID: ObjectIdentifier?, top: CGFloat, bottom: CGFloat,
                        dx: CGFloat, dy: CGFloat)] = []
        for band in bands {
            if let last = surfaces.last, last.boxID == band.boxID,
               last.dx == band.dx, last.dy == band.dy,
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
            let rect = NSRect(x: origin.x + band.dx, y: origin.y + band.top + band.dy,
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

    // Positioned layout (0.17): the page's floats, painted
    // over the surfaces at the positions the coordinator
    // resolved — background color and photo layers first,
    // then the picture, or the box's own contents inside
    // its padding. A picture that never arrived leaves a
    // labelled frame, as a failed in-flow image does.
    private func paintFloats(at origin: NSPoint) {
        for paint in floatPaints {
            let spec = paint.spec
            let rect = NSRect(x: origin.x + paint.rect.minX,
                              y: origin.y + paint.rect.minY,
                              width: paint.rect.width, height: paint.rect.height)
            if let color = spec.backgroundColor {
                color.setFill()
                rect.fill()
            }
            if let box = spec.backgroundBox {
                paintBackgroundLayers(box, in: rect)
            }
            let contentRect = NSRect(
                x: rect.minX + spec.paddingLeft, y: rect.minY + spec.paddingTop,
                width: max(0, rect.width - spec.paddingLeft - spec.paddingRight),
                height: max(0, rect.height - spec.paddingTop - spec.paddingBottom))
            if spec.isImage {
                if let image = spec.image {
                    tbDrawPhoto(image, in: contentRect)
                } else if spec.imageFailed {
                    NSColor.separatorColor.setStroke()
                    let frame = NSBezierPath(rect: contentRect.insetBy(dx: 0.5, dy: 0.5))
                    frame.lineWidth = 1
                    frame.stroke()
                    let label = spec.alt.isEmpty ? "image" : spec.alt
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor]
                    let size = (label as NSString).size(withAttributes: attrs)
                    (label as NSString).draw(
                        at: NSPoint(x: contentRect.midX - size.width / 2,
                                    y: contentRect.midY - size.height / 2),
                        withAttributes: attrs)
                }
            } else if let content = spec.content, content.length > 0 {
                drawFloatContent(content, spec: spec, in: contentRect)
            }
        }
    }

    // Lay a block float's contents out in a private layout
    // manager at the box's content size and paint them
    // there. The layout is cached per float until the
    // page's floats are resolved again.
    private func drawFloatContent(_ content: NSAttributedString,
                                  spec: TBFloatSpec, in rect: NSRect) {
        let key = ObjectIdentifier(spec)
        let manager: NSLayoutManager
        let container: NSTextContainer
        if let cached = floatContentLayouts[key], cached.1.size == rect.size {
            manager = cached.0
            container = cached.1
        } else {
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            container = NSTextContainer(size: rect.size)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            floatContentLayouts[key] = (manager, container)
        }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return }
        manager.drawBackground(forGlyphRange: glyphs, at: rect.origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: rect.origin)
    }

    // Positioned layout (0.17): glyphs under a relative
    // offset paint shifted by it, run by run, while the
    // layout itself — selection, carets, form seats —
    // stays at the flow position.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0 else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let charRange = characterRange(forGlyphRange: glyphsToShow,
                                       actualGlyphRange: nil)
        var segments: [(range: NSRange, offset: NSPoint)] = []
        var hasOffset = false
        storage.enumerateAttribute(TBRelOffsetKey, in: charRange) { value, range, _ in
            let offset = (value as? NSValue)?.pointValue ?? .zero
            if offset != .zero { hasOffset = true }
            segments.append((range: range, offset: offset))
        }
        guard hasOffset else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        for entry in segments {
            let segment = glyphRange(forCharacterRange: entry.range,
                                     actualCharacterRange: nil)
            guard segment.length > 0 else { continue }
            if entry.offset == .zero {
                super.drawGlyphs(forGlyphRange: segment, at: origin)
            } else {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext
                    .translateBy(x: entry.offset.x, y: entry.offset.y)
                super.drawGlyphs(forGlyphRange: segment, at: origin)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
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
                    .help("Chirpy Home")
                TextField("Address", text: $model.addressText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.go() }
                Button("Go") { model.go() }
            }
            // Load progress (0.18): a thin bar directly
            // under the address bar while a page is coming
            // in — filled to the fetched fraction when the
            // server declared the page's length,
            // indeterminate when there is no honest
            // fraction (no length declared, or the page is
            // in and rendering). Gone when the page settles.
            if model.isLoading {
                if let progress = model.loadProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
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
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            // Drag-and-drop (0.18): an HTML file dropped
            // anywhere on the window opens here, the way
            // Chrome opens one — through the ordinary load
            // path, progress bar and all. Only the first
            // file counts, and only .html/.htm: the engine
            // cannot render anything else honestly, so
            // other files are ignored.
            guard let provider = providers.first,
                  provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            else { return false }
            _ = provider.loadObject(ofClass: URL.self) { reading, _ in
                guard let url = reading as? URL else { return }
                let ext = url.pathExtension.lowercased()
                guard ext == "html" || ext == "htm" else { return }
                DispatchQueue.main.async {
                    model.load(url.absoluteString)
                }
            }
            return true
        }
    }
}
