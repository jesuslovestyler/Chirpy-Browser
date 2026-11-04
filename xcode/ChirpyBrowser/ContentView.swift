//
//  ContentView.swift
//  Chirpy Browser — prototype 0.25.0 (Swift)
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
    @Published var statusLine = "Chirpy Engine 0.25.0 (Swift) — first paint, positioned layout, floats, columns, flexbox, grid, color-mix, font shorthand, media queries, hover, forms, progress bar, parallel loading, no JavaScript yet"
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
    // no length, or the page is in and being walked. The
    // window then shows an indeterminate bar. Both clear
    // at first paint (0.20) — the moment the page is
    // readable — on success and on failure alike; pieces
    // still arriving after that are the status line's
    // business ("pictures still arriving"), not the bar's.
    @Published var isLoading = false
    @Published var loadProgress: Double? = nil
    // First paint (0.20): true from a page's first paint
    // until its pictures have all landed, so the view
    // knows to re-install the finished page when they do.
    @Published var pageArrivalsPending = false
    private var loadGeneration = 0
    private var activeFetch: TBProgressFetcher? = nil

    private var currentURL = ""
    private var backStack: [String] = []
    private var forwardStack: [String] = []

    // The finishing set (0.23): every URL this window has
    // landed on — the session :visited reads, handed to
    // the renderer with each load. Memory only: a new
    // launch starts with no visited links at all.
    private var sessionVisited: Set<String> = []
    // The finishing set (0.23): the text area's width as
    // the coordinator last measured it — @media's width
    // questions are answered against this render's width.
    // Nil until the window has laid out once; the
    // renderer then stands on its nominal width, as
    // pages did before the finishing set.
    var viewTextWidth: CGFloat? = nil

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
                // Fetched; rendering now. The walk has no
                // single honest fraction, so the bar goes
                // indeterminate until the first paint
                // settles it.
                if generation == self.loadGeneration {
                    self.loadProgress = nil
                }
                let settledStatus = "\(finalURL)  ·  Chirpy Engine 0.25.0 (Swift) — first paint, positioned layout, floats, columns, flexbox, grid, color-mix, font shorthand, media queries, hover, forms, progress bar, parallel loading, no JavaScript yet"
                // First paint (0.20): the render hands the
                // walked page over the moment it exists —
                // the install below runs then (the render
                // calls it on the main actor), settling the
                // bar while the page's pictures are still
                // fetching. The render's second stage, the
                // arrivals, may touch this page afterwards
                // only while this load is still the latest.
                let paint = await tbRenderPage(html: html, base: finalURL,
                                               visited: sessionVisited,
                                               mediaWidth: viewTextWidth) { first in
                    guard generation == self.loadGeneration else { return }
                    self.currentURL = first.landedURL
                    self.sessionVisited.insert(first.landedURL)
                    self.addressText = first.landedURL
                    self.pageTitle = first.title
                    self.pageText = first.body
                    self.pageBackground = first.pageBackground
                    self.columnTextWidth = first.columnWidth
                    self.pageForms = first.forms
                    self.pageFields = first.fields
                    self.pageLayoutEvents = first.layoutEvents
                    self.pageArrivalsPending = first.arrivalsPending
                    self.statusLine = first.arrivalsPending
                        ? settledStatus + "  ·  pictures still arriving"
                        : settledStatus
                    self.isLoading = false
                    self.loadProgress = nil
                    self.activeFetch = nil
                    self.canGoBack = !self.backStack.isEmpty
                    self.canGoForward = !self.forwardStack.isEmpty
                    self.pageID += 1
                }
                // The arrivals have landed (or a newer load
                // has superseded this one — then nothing
                // here may touch the window).
                if generation == self.loadGeneration, paint.arrivalsPending {
                    self.pageArrivalsPending = false
                    self.statusLine = settledStatus
                }
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
                self.pageArrivalsPending = false
                self.statusLine = "Load failed"
                self.isLoading = false
                self.loadProgress = nil
                self.activeFetch = nil
                self.canGoBack = !self.backStack.isEmpty
                self.canGoForward = !self.forwardStack.isEmpty
                self.pageID += 1
            }
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
        let textView = TBPageTextView()
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
            context.coordinator.clearFixedViews()
            (textView as? TBPageTextView)?.pageTextReplaced()
            textView.textStorage?.setAttributedString(model.pageText)
            textView.scrollToBeginningOfDocument(nil)
            context.coordinator.rebuildFormViews()
            context.coordinator.layoutEvents = model.pageLayoutEvents
            context.coordinator.floatLayoutDirty = true
            context.coordinator.settleFloatLayout()
            context.coordinator.awaitingArrivals = model.pageArrivalsPending
        }
        // First paint (0.20): this page's pictures have
        // all landed since it was installed — re-install
        // its finished text and resolve it again.
        if context.coordinator.awaitingArrivals && !model.pageArrivalsPending {
            context.coordinator.awaitingArrivals = false
            context.coordinator.refreshAfterArrivals()
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

        // Positioned layout (0.21): this page's fixed
        // boxes, living as real overlay views on the text
        // view, and the observer that keeps them glued to
        // the viewport while the page scrolls beneath.
        private var fixedViews: [(view: TBFixedOverlayView,
                                  spec: TBPositionedSpec)] = []
        private var scrollObserver: NSObjectProtocol? = nil

        // Positioned layout (0.17): the page's float and
        // clear events, and the container width they were
        // last resolved at — the exclusion paths are rebuilt
        // whenever either changes.
        var layoutEvents: [TBLayoutEvent] = []
        var floatLayoutDirty = false
        private var floatWidth: CGFloat = 0
        // First paint (0.20): this page was installed
        // before its pictures landed; when the model says
        // they have, the finished page is re-installed.
        var awaitingArrivals = false

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
                // refreshInsets lives on the main actor;
                // hop there, as the fetch progress does.
                Task { @MainActor in self?.refreshInsets() }
            }
            // Scrolling changes the clip view's bounds, not
            // its frame: watch both, so a fixed overlay is
            // reseated the moment the page moves under it.
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView, queue: .main) { [weak self] _ in
                self?.repositionFixedViews()
            }
        }

        @MainActor func refreshInsets() {
            guard let textView = textView, let clipView = clipView else { return }
            let available = clipView.frame.width
            // The finishing set (0.23): the model hands
            // this width — the window's text area, inside
            // its standing insets — to the renderer with
            // each load, so @media answers against the
            // window the reader actually has.
            if available > 32 { model.viewTextWidth = available - 32 }
            var insetX: CGFloat = 16
            if let column = columnWidth, available > 0 {
                insetX = max(16, (available - column) / 2)
            }
            let newInset = NSSize(width: insetX, height: 16)
            if textView.textContainerInset != newInset {
                textView.textContainerInset = newInset
            }
            settleFormViews()
            repositionFixedViews()
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
            if let scrollObserver = scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
            for view in formControlViews { view.removeFromSuperview() }
            formControlViews = []
            formAnchors = []
            fieldViews = [:]
            clearFixedViews()
        }

        // Remove every control and forget every anchor.
        func clearFormViews() {
            for view in formControlViews { view.removeFromSuperview() }
            formControlViews = []
            formAnchors = []
            fieldViews = [:]
        }

        // Remove every fixed overlay — the mirror of
        // clearFormViews: a page's overlays never outlive
        // the page.
        func clearFixedViews() {
            for entry in fixedViews { entry.view.removeFromSuperview() }
            fixedViews = []
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

        // First paint (0.20): the page's pictures have all
        // landed — the renderer's string is final now
        // (pictures seated at their true sizes, failures
        // wearing their labels). Re-install it so the
        // window matches the finished page exactly, rebuild
        // the form controls over it, and resolve the floats
        // against the final geometry. What the reader typed
        // into a field meanwhile is carried across; the
        // scroll stays where the reader left it — they may
        // be halfway down the article by now.
        @MainActor func refreshAfterArrivals() {
            guard let textView = textView,
                  let storage = textView.textStorage else { return }
            var typed: [Int: String] = [:]
            for (id, field) in fieldViews { typed[id] = field.stringValue }
            (textView as? TBPageTextView)?.pageTextReplaced()
            storage.setAttributedString(model.pageText)
            rebuildFormViews()
            for (id, value) in typed {
                fieldViews[id]?.stringValue = value
            }
            floatLayoutDirty = true
            settleFloatLayout()
        }

        // Positioned layout (0.21): build (or rebuild)
        // this page's fixed overlays — one view per fixed
        // box the layout events carry, added in stacking
        // order, so the higher z-index (document order
        // breaking ties) is added later and paints on top.
        // A box with no resolvable area yet — a dimension
        // still being measured that its insets don't
        // derive — waits for the arrivals rebuild.
        func rebuildFixedViews() {
            clearFixedViews()
            guard let textView = textView else { return }
            var fixed: [TBPositionedSpec] = []
            for event in layoutEvents {
                if case .positioned(let spec) = event, spec.kind == .fixed {
                    fixed.append(spec)
                }
            }
            let ordered = fixed.enumerated().sorted {
                ($0.element.zIndex, $0.offset) < ($1.element.zIndex, $1.offset)
            }
            for entry in ordered {
                let spec = entry.element
                guard let frame = fixedRect(spec: spec,
                                            visible: textView.visibleRect)
                else { continue }
                let view = TBFixedOverlayView()
                view.spec = spec
                view.frame = frame
                textView.addSubview(view)
                fixedViews.append((view: view, spec: spec))
            }
        }

        // Keep every fixed overlay glued to the viewport:
        // recompute its frame against the visible rect.
        // Called when the page scrolls, when the window
        // resizes, and whenever the overlays are rebuilt.
        func repositionFixedViews() {
            guard let textView = textView, !fixedViews.isEmpty else { return }
            let visible = textView.visibleRect
            for entry in fixedViews {
                if let frame = fixedRect(spec: entry.spec, visible: visible) {
                    entry.view.frame = frame
                    entry.view.needsDisplay = true
                }
            }
        }

        // Resolve one inset against an extent: a length
        // as it stands, a percentage of the extent.
        private func resolveInset(_ inset: TBInsetValue?,
                                  extent: CGFloat) -> CGFloat? {
            switch inset {
            case .points(let value): return value
            case .percent(let pct): return extent * pct / 100
            case nil: return nil
            }
        }

        // A fixed box's frame in text-view coordinates:
        // its insets resolve against the visible rect —
        // top:0 is the top of what the reader sees,
        // whatever the scroll has done. A dimension the
        // insets span is derived from them here, against
        // the viewport's true size. An inset left auto
        // falls back to the viewport's edge on that axis.
        // Nil when the box has no area to show yet.
        private func fixedRect(spec: TBPositionedSpec,
                               visible: NSRect) -> NSRect? {
            var width = spec.borderWidth
            var height = spec.borderHeight
            let left = resolveInset(spec.left, extent: visible.width)
            let right = resolveInset(spec.right, extent: visible.width)
            let top = resolveInset(spec.top, extent: visible.height)
            let bottom = resolveInset(spec.bottom, extent: visible.height)
            if spec.widthFromInsets, let l = left, let r = right {
                width = max(visible.width - l - r
                            - spec.marginLeft - spec.marginRight, 0)
            }
            if spec.heightFromInsets, let t = top, let b = bottom {
                height = max(visible.height - t - b
                             - spec.marginTop - spec.marginBottom, 0)
            }
            guard width > 0, height > 0 else { return nil }
            let x: CGFloat
            if let l = left {
                x = visible.minX + l + spec.marginLeft
            } else if let r = right {
                x = visible.maxX - r - spec.marginRight - width
            } else {
                x = visible.minX + spec.marginLeft
            }
            let y: CGFloat
            if let t = top {
                y = visible.minY + t + spec.marginTop
            } else if let b = bottom {
                y = visible.maxY - b - spec.marginBottom - height
            } else {
                y = visible.minY + spec.marginTop
            }
            return NSRect(x: x, y: y, width: width, height: height)
        }

        // The painted surface rect of a containing block,
        // in container coordinates: the full column width,
        // from its first paragraph's first line (less the
        // inside space its surface stamps above that line)
        // to its last paragraph's last line (plus the
        // stamped space below it), shifted by any relative
        // offset its paragraphs carry — the same numbers
        // paintContinuousSurfaces paints the ancestor's
        // own background from.
        private func containingRect(for block: TBContainingBlock,
                                    width: CGFloat) -> NSRect {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let storage = textView.textStorage,
                  storage.length > 0 else {
                return NSRect(x: 0, y: 0, width: width, height: 0)
            }
            let string = storage.string as NSString
            let start = min(max(block.startCharIndex, 0), storage.length - 1)
            var top = floatAnchorY(start)
            let extTop = (storage.attribute(TBExtTopKey, at: start,
                                            effectiveRange: nil) as? NSNumber)?
                .doubleValue ?? 0
            top -= CGFloat(extTop)
            var bottom = top
            let end = min(max(block.endCharIndex, 0), storage.length)
            if end > start {
                var last = end - 1
                while last > start && string.character(at: last) == 10 {
                    last -= 1
                }
                let paragraph = string.paragraphRange(
                    for: NSRange(location: last, length: 0))
                let glyphs = layoutManager.glyphRange(
                    forCharacterRange: paragraph, actualCharacterRange: nil)
                var maxY: CGFloat? = nil
                layoutManager.enumerateLineFragments(forGlyphRange: glyphs) {
                    rect, _, _, _, _ in
                    maxY = max(maxY ?? rect.maxY, rect.maxY)
                }
                if let maxY = maxY {
                    let extBottom = (storage.attribute(
                        TBExtBottomKey, at: paragraph.location,
                        effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
                    bottom = maxY + CGFloat(extBottom)
                }
            }
            var rect = NSRect(x: 0, y: top, width: width,
                              height: max(bottom - top, 0))
            if let offset = storage.attribute(TBRelOffsetKey, at: start,
                                              effectiveRange: nil) as? NSValue {
                rect = rect.offsetBy(dx: offset.pointValue.x,
                                     dy: offset.pointValue.y)
            }
            return rect
        }

        // An absolutely positioned box's border rect in
        // container coordinates, resolved against its
        // containing block: an inset positions the box's
        // margin edge, as it does for a float; percentages
        // take the block's width (left/right) or its
        // surface height (top/bottom); a dimension the
        // insets span is derived from them here, where the
        // true block is known. An inset left auto on an
        // axis falls back to where the flow would have put
        // the box — the block's edge horizontally, the
        // line it was met on vertically. Nil while a
        // dimension is still unmeasured and underivable:
        // the box takes its place at arrivals instead.
        private func resolveAbsolute(spec: TBPositionedSpec,
                                     in cb: NSRect) -> NSRect? {
            var width = spec.borderWidth
            var height = spec.borderHeight
            let left = resolveInset(spec.left, extent: cb.width)
            let right = resolveInset(spec.right, extent: cb.width)
            let top = resolveInset(spec.top, extent: cb.height)
            let bottom = resolveInset(spec.bottom, extent: cb.height)
            if spec.widthFromInsets, let l = left, let r = right {
                width = max(cb.width - l - r
                            - spec.marginLeft - spec.marginRight, 0)
            }
            if spec.heightFromInsets, let t = top, let b = bottom {
                height = max(cb.height - t - b
                             - spec.marginTop - spec.marginBottom, 0)
            }
            guard width > 0, height > 0 else { return nil }
            let x: CGFloat
            if let l = left {
                x = cb.minX + l + spec.marginLeft
            } else if let r = right {
                x = cb.maxX - r - spec.marginRight - width
            } else {
                x = cb.minX + spec.marginLeft
            }
            let y: CGFloat
            if let t = top {
                y = cb.minY + t + spec.marginTop
            } else if let b = bottom {
                y = cb.maxY - b - spec.marginBottom - height
            } else {
                y = floatAnchorY(spec.anchorCharIndex) + spec.marginTop
            }
            return NSRect(x: x, y: y, width: width, height: height)
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
        // The placements themselves are computed in
        // whole-page passes since 0.20 — see the batched
        // layout note inside.
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
            band?.positionedPaintsBelow = []
            band?.positionedPaints = []
            band?.columnPaints = []
            band?.flexPaints = []
            band?.gridPaints = []
            if !container.exclusionPaths.isEmpty {
                container.exclusionPaths = []
            }
            guard !layoutEvents.isEmpty, storage.length > 0 else {
                rebuildFixedViews()
                textView.needsDisplay = true
                return
            }
            layoutManager.ensureLayout(for: container)

            // Batched layout (0.20): placements for the
            // whole page are computed at once from the
            // layout as it currently stands, then every
            // exclusion is applied together, the text is
            // re-laid out, and the computation repeats
            // against the new layout until the placements
            // stop moving — at most three passes. 0.17
            // applied one exclusion at a time with a layout
            // between events, so a long, float-heavy page
            // (an article that floats every thumbnail)
            // paid a layout pass per float over the whole
            // text. The fixed point this converges to is
            // the same one 0.17 reached: a pass that moves
            // nothing proves every anchor was measured as
            // the text truly lies. A clear can alternate
            // between two passes (its own exclusion moves
            // its anchor), so the bound can end the loop —
            // the last pass still applies, measured with
            // the floats live, the measurement 0.17 took.
            func computePlacements() -> (exclusions: [NSBezierPath],
                                         paints: [(rect: NSRect, spec: TBFloatSpec)]) {
                var placed: [(rect: NSRect, side: TBFloatSide, anchor: Int)] = []
                var paints: [(rect: NSRect, spec: TBFloatSpec)] = []
                var exclusions: [NSBezierPath] = []

                func overlaps(_ a: NSRect, _ b: NSRect) -> Bool {
                    a.minX < b.maxX && b.minX < a.maxX
                        && a.minY < b.maxY && b.minY < a.maxY
                }

                for event in self.layoutEvents {
                    switch event {
                    case .float(let spec):
                        // A percentage width (0.25.0)
                        // resolves here, against the real
                        // column the view is placing in,
                        // less the containing block's
                        // horizontal padding the renderer
                        // recorded — never against the
                        // nominal thousand points the
                        // length parser once used, which
                        // is how two declared-44% columns
                        // came out at some 47% of their
                        // wrapper and squeezed everything
                        // after them into a crack. The
                        // height is re-measured at the
                        // resolved width: the box's words
                        // wrap narrower here than the
                        // renderer's provisional measure
                        // supposed.
                        var boxW = spec.borderWidth
                        var boxH = spec.borderHeight
                        if let pct = spec.widthPercent {
                            boxW = max(pct / 100
                                * max(width - spec.containingPaddingH, 10), 1)
                            if !spec.heightDeclared, let content = spec.content {
                                let contentW = max(
                                    boxW - spec.paddingLeft - spec.paddingRight, 10)
                                boxH = self.measureBoxText(content, width: contentW).height
                                    + spec.paddingTop + spec.paddingBottom
                            }
                        }
                        let marginW = boxW + spec.marginLeft + spec.marginRight
                        let marginH = boxH + spec.marginTop + spec.marginBottom
                        var top = self.floatAnchorY(spec.anchorCharIndex)
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
                                                    width: boxW,
                                                    height: boxH),
                                       spec: spec))
                        exclusions.append(NSBezierPath(rect: marginRect))
                    case .clear(let spec):
                        // A clear at the very end of the text has
                        // nothing after it to push — skip it, so a
                        // trailing float is never mistaken for a
                        // reason to move the last line.
                        guard spec.anchorCharIndex < storage.length else { continue }
                        let anchorTop = self.floatAnchorY(spec.anchorCharIndex)
                        var limit: CGFloat = 0
                        for other in placed {
                            if spec.side == .left && other.side != .left { continue }
                            if spec.side == .right && other.side != .right { continue }
                            // The bound is inclusive
                            // (0.25.0): a wrapper whose
                            // only children are floats
                            // appends no characters
                            // between its last float and
                            // its close, so its floats
                            // anchor AT the clear's own
                            // anchor index — the strict
                            // bound read them as outside
                            // the wrapper, and the
                            // containment contained
                            // nothing.
                            if let start = spec.rangeStart,
                               !(other.anchor >= start
                                 && other.anchor <= spec.anchorCharIndex) {
                                continue
                            }
                            limit = max(limit, other.rect.maxY)
                        }
                        if limit > anchorTop + 1 {
                            exclusions.append(NSBezierPath(rect: NSRect(
                                x: 0, y: anchorTop, width: width,
                                height: limit - anchorTop)))
                        }
                    case .positioned:
                        // Positioned boxes make no exclusions
                        // and move no text; they resolve after
                        // the float passes, at the end of
                        // settleFloatLayout.
                        continue
                    case .columns:
                        // Multicolumn blocks (0.22) make no
                        // exclusions either: their seat is
                        // ordinary flow text and already
                        // stands where it should. They
                        // resolve after the float passes,
                        // with the positioned boxes.
                        continue
                    case .flex:
                        // Flex containers (0.24) make no
                        // exclusions for the same reason:
                        // the seat is ordinary flow text.
                        // They resolve after the float
                        // passes too, with the columns.
                        continue
                    case .grid:
                        // Grid containers (0.25) make no
                        // exclusions for the same reason:
                        // the seat is ordinary flow text.
                        // They resolve after the float
                        // passes too, with the flex
                        // containers.
                        continue
                    }
                }
                return (exclusions, paints)
            }
            func samePaints(_ a: [(rect: NSRect, spec: TBFloatSpec)],
                            _ b: [(rect: NSRect, spec: TBFloatSpec)]) -> Bool {
                guard a.count == b.count else { return false }
                for i in a.indices {
                    if a[i].rect != b[i].rect || a[i].spec !== b[i].spec {
                        return false
                    }
                }
                return true
            }
            // No exclusion can move text above the first
            // event's anchor, so re-layout starts there.
            let firstAnchor = layoutEvents.map { event -> Int in
                switch event {
                case .float(let spec): return spec.anchorCharIndex
                case .clear(let spec): return spec.anchorCharIndex
                case .positioned(let spec): return spec.anchorCharIndex
                case .columns(let spec): return spec.anchorCharIndex
                case .flex(let spec): return spec.anchorCharIndex
                case .grid(let spec): return spec.anchorCharIndex
                }
            }.min() ?? 0
            var exclusions: [NSBezierPath] = []
            var paints: [(rect: NSRect, spec: TBFloatSpec)] = []
            var pass = 0
            while true {
                pass += 1
                let computed = computePlacements()
                let stable = pass > 1 && samePaints(computed.paints, paints)
                exclusions = computed.exclusions
                paints = computed.paints
                container.exclusionPaths = exclusions
                if stable || pass >= 3 { break }
                if firstAnchor < storage.length {
                    layoutManager.invalidateLayout(
                        forCharacterRange: NSRange(location: firstAnchor,
                                                   length: storage.length - firstAnchor),
                        actualCharacterRange: nil)
                }
                layoutManager.ensureLayout(for: container)
            }
            band?.floatPaints = paints

            // Positioned layout (0.21): with the floats
            // settled, resolve this page's absolutely
            // positioned boxes against the finished layout.
            // They make no exclusions and move no text, so
            // one resolution after the float passes is
            // enough — a containing block that holds floats
            // is read at its final extent. The boxes become
            // paint lists on the layout manager, split by
            // stacking: negative z-index paints in the
            // background pass, the rest above the glyphs,
            // each list ordered by z-index with document
            // order breaking ties. Fixed boxes are not
            // painted here at all — they are overlay views,
            // rebuilt and reseated below.
            var below: [(rect: NSRect, spec: TBPositionedSpec, order: Int)] = []
            var above: [(rect: NSRect, spec: TBPositionedSpec, order: Int)] = []
            let pageRect = NSRect(
                x: 0, y: 0, width: width,
                height: layoutManager.usedRect(for: container).size.height)
            var cbRects: [ObjectIdentifier: NSRect] = [:]
            for (order, event) in layoutEvents.enumerated() {
                guard case .positioned(let spec) = event,
                      spec.kind == .absolute else { continue }
                let cb: NSRect
                if let block = spec.containingBlock {
                    let key = ObjectIdentifier(block)
                    if let cached = cbRects[key] {
                        cb = cached
                    } else {
                        cb = containingRect(for: block, width: width)
                        cbRects[key] = cb
                    }
                } else {
                    cb = pageRect
                }
                guard let rect = resolveAbsolute(spec: spec, in: cb)
                else { continue }
                if spec.zIndex < 0 {
                    below.append((rect: rect, spec: spec, order: order))
                } else {
                    above.append((rect: rect, spec: spec, order: order))
                }
            }
            band?.positionedPaintsBelow = below
                .sorted { ($0.spec.zIndex, $0.order) < ($1.spec.zIndex, $1.order) }
                .map { (rect: $0.rect, spec: $0.spec) }
            band?.positionedPaints = above
                .sorted { ($0.spec.zIndex, $0.order) < ($1.spec.zIndex, $1.order) }
                .map { (rect: $0.rect, spec: $0.spec) }

            // Multi-column layout (0.22): a multicolumn
            // block's seat already stands in the flow at
            // its reserved height — the columns paint into
            // the seat's line, resolved here from the
            // seat's own line fragment, so a clear or a
            // float above the block that moved its line
            // moves the columns with it. The seat's glyph
            // is located the way a form control's seat is:
            // the fragment's start plus the glyph's own
            // advance within the line.
            var columnPaints: [(rect: NSRect, spec: TBMultiColumnSpec)] = []
            for event in layoutEvents {
                guard case .columns(let spec) = event,
                      spec.anchorCharIndex < storage.length else { continue }
                let glyph = layoutManager.glyphIndexForCharacter(
                    at: spec.anchorCharIndex)
                guard glyph < layoutManager.numberOfGlyphs else { continue }
                let fragment = layoutManager.lineFragmentRect(
                    forGlyphAt: glyph, effectiveRange: nil)
                let spot = layoutManager.location(forGlyphAt: glyph)
                columnPaints.append((rect: NSRect(
                    x: fragment.minX + spot.x, y: fragment.minY,
                    width: spec.totalWidth, height: spec.totalHeight),
                    spec: spec))
            }
            band?.columnPaints = columnPaints

            // Flexbox (0.24): a flex container's seat
            // stands in the flow at its reserved height,
            // exactly like a multicolumn block's — the
            // items paint into the seat's line, resolved
            // from the seat's own line fragment, so a
            // clear or a float above the container that
            // moved its line moves the items with it.
            var flexPaints: [(rect: NSRect, spec: TBFlexSpec)] = []
            for event in layoutEvents {
                guard case .flex(let spec) = event,
                      spec.anchorCharIndex < storage.length else { continue }
                let glyph = layoutManager.glyphIndexForCharacter(
                    at: spec.anchorCharIndex)
                guard glyph < layoutManager.numberOfGlyphs else { continue }
                let fragment = layoutManager.lineFragmentRect(
                    forGlyphAt: glyph, effectiveRange: nil)
                let spot = layoutManager.location(forGlyphAt: glyph)
                flexPaints.append((rect: NSRect(
                    x: fragment.minX + spot.x, y: fragment.minY,
                    width: spec.totalWidth, height: spec.totalHeight),
                    spec: spec))
            }
            band?.flexPaints = flexPaints

            // Grid (0.25): a grid container's seat
            // stands in the flow at its reserved height,
            // exactly like a flex container's — the
            // items paint into the seat's line, resolved
            // from the seat's own line fragment, so a
            // clear or a float above the container that
            // moved its line moves the items with it.
            var gridPaints: [(rect: NSRect, spec: TBGridSpec)] = []
            for event in layoutEvents {
                guard case .grid(let spec) = event,
                      spec.anchorCharIndex < storage.length else { continue }
                let glyph = layoutManager.glyphIndexForCharacter(
                    at: spec.anchorCharIndex)
                guard glyph < layoutManager.numberOfGlyphs else { continue }
                let fragment = layoutManager.lineFragmentRect(
                    forGlyphAt: glyph, effectiveRange: nil)
                let spot = layoutManager.location(forGlyphAt: glyph)
                gridPaints.append((rect: NSRect(
                    x: fragment.minX + spot.x, y: fragment.minY,
                    width: spec.totalWidth, height: spec.totalHeight),
                    spec: spec))
            }
            band?.gridPaints = gridPaints
            rebuildFixedViews()
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

        // Measure a painted box's text the way the
        // renderer measures it (0.25.0): its own storage,
        // manager and container at a given width. Used to
        // re-measure a percentage-width float's height
        // once its width has been resolved against the
        // real column, so the exclusion the text flows
        // around is the box that will actually paint.
        private func measureBoxText(_ string: NSAttributedString,
                                    width: CGFloat) -> CGSize {
            let storage = NSTextStorage(attributedString: string)
            let manager = NSLayoutManager()
            let container = NSTextContainer(
                size: NSSize(width: max(width, 10),
                             height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            return manager.usedRect(for: container).size
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

// The page's text view (0.21): after AppKit has drawn
// the text — backgrounds, surfaces, glyphs and all —
// the absolutely positioned boxes with z-index zero or
// above paint over it, in stacking order. A badge must
// be able to cover the card it hangs off; painting it
// in the background pass, under the glyphs, would let
// the card's own words show through it.
final class TBPageTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let band = layoutManager as? TBBandLayoutManager else { return }
        band.paintPositionedAbove(at: textContainerOrigin, dirtyRect: dirtyRect)
    }

    // Hover paint (0.23): the engine stamps each element's
    // hover traits onto its text — TBHoverAttrs on the
    // element's own run, TBHoverBlockAttrs on its block's
    // whole range. While the pointer rests on such text,
    // this view lifts those characters into the stamped
    // style — the element's traits over the block's, trait
    // by trait — and puts the original paint back exactly
    // when the pointer moves on. Paint only: the stamped
    // traits are colors and underline switches, none of
    // which can move a glyph, and layout is never re-run.
    private var hoverTrackingArea: NSTrackingArea? = nil
    private var hoverRange: NSRange? = nil
    private var hoverSaved: [(key: NSAttributedString.Key,
                              range: NSRange, value: Any?)] = []
    private var hoverTextLength = -1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited,
                      .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHover()
    }

    // The window replaced the page's text (a new load, or
    // the arrivals landing): any hover being worn belonged
    // to the old text. Forget it without restoring — the
    // new text never wore it.
    func pageTextReplaced() {
        hoverRange = nil
        hoverSaved = []
        hoverTextLength = -1
    }

    private func updateHover(with event: NSEvent) {
        guard let storage = textStorage, let layoutManager = layoutManager,
              let container = textContainer else { return }
        // The text changed length under a worn hover (a
        // re-install the coordinator did not announce):
        // the saved paint belongs to the old text — forget
        // it rather than write it onto the new.
        if hoverRange != nil && hoverTextLength != storage.length {
            pageTextReplaced()
        }
        guard storage.length > 0 else { clearHover(); return }
        let inView = convert(event.locationInWindow, from: nil)
        // The text view's own hit test (0.23 build fix):
        // the character under the point, the point given
        // in view coordinates. The guard is the old
        // container-space one restated against the
        // origin — nothing above or left of where the
        // text begins can be hovered.
        guard inView.x >= textContainerOrigin.x,
              inView.y >= textContainerOrigin.y
        else { clearHover(); return }
        let index = characterIndexForInsertion(at: inView)
        guard index < storage.length else { clearHover(); return }
        var elementRange = NSRange(location: 0, length: 0)
        var blockRange = NSRange(location: 0, length: 0)
        let element = storage.attribute(TBHoverAttrsKey, at: index,
                                        effectiveRange: &elementRange)
            as? TBHoverStyle
        let block = storage.attribute(TBHoverBlockAttrsKey, at: index,
                                      effectiveRange: &blockRange)
            as? TBHoverStyle
        guard element != nil || block != nil else { clearHover(); return }
        // Where the two stamps overlap, both are constant:
        // the element's run inside its block.
        let extent: NSRange
        if element != nil && block != nil {
            extent = NSIntersectionRange(elementRange, blockRange)
        } else if element != nil {
            extent = elementRange
        } else {
            extent = blockRange
        }
        guard extent.length > 0 else { clearHover(); return }
        if hoverRange == extent { return }   // already wearing it
        clearHover()
        applyHover(extent: extent, block: block, storage: storage)
    }

    private func applyHover(extent: NSRange, block: TBHoverStyle?,
                            storage: NSTextStorage) {
        let paintKeys: [NSAttributedString.Key] = [
            .foregroundColor, .backgroundColor,
            .underlineStyle, .strikethroughStyle]
        // Snapshot the paint this hover is about to cover,
        // run by run, so it can be put back exactly — a
        // hovered link's own color and underline included.
        var saved: [(key: NSAttributedString.Key,
                     range: NSRange, value: Any?)] = []
        for key in paintKeys {
            storage.enumerateAttribute(key, in: extent, options: []) {
                value, range, _ in
                saved.append((key: key, range: range, value: value))
            }
        }
        // Read the element stamp's runs before touching
        // anything — never mutate the text while an
        // enumeration is walking it. A plainer child inside
        // a hovered parent keeps its own stamp; the block's
        // traits fill whatever an element leaves unnamed.
        var runs: [(range: NSRange, style: TBHoverStyle?)] = []
        storage.enumerateAttribute(TBHoverAttrsKey, in: extent,
                                   options: []) { value, range, _ in
            runs.append((range: range, style: value as? TBHoverStyle))
        }
        for run in runs {
            let fg = run.style?.foregroundColor ?? block?.foregroundColor
            let bg = run.style?.backgroundColor ?? block?.backgroundColor
            let ul = run.style?.underlineStyle ?? block?.underlineStyle
            let st = run.style?.strikethroughStyle
                ?? block?.strikethroughStyle
            if let fg = fg {
                storage.addAttribute(.foregroundColor, value: fg,
                                     range: run.range)
            }
            if let bg = bg {
                storage.addAttribute(.backgroundColor, value: bg,
                                     range: run.range)
            }
            if let ul = ul {
                storage.addAttribute(.underlineStyle, value: ul,
                                     range: run.range)
            }
            if let st = st {
                storage.addAttribute(.strikethroughStyle, value: st,
                                     range: run.range)
            }
        }
        hoverSaved = saved
        hoverRange = extent
        hoverTextLength = storage.length
    }

    private func clearHover() {
        guard hoverRange != nil else { return }
        if let storage = textStorage {
            for entry in hoverSaved
            where NSMaxRange(entry.range) <= storage.length {
                if let value = entry.value {
                    storage.addAttribute(entry.key, value: value,
                                         range: entry.range)
                } else {
                    storage.removeAttribute(entry.key, range: entry.range)
                }
            }
        }
        pageTextReplaced()
    }
}

// What a painted out-of-flow box offers the one paint
// path (0.21): its backgrounds, its padding, and either
// its picture or its rendered contents. Floats have
// carried exactly these fields since 0.17; positioned
// boxes carry them now too, so a single painter serves
// both.
protocol TBBoxPaintSource: AnyObject {
    var backgroundColor: NSColor? { get }
    var backgroundBox: TBBackgroundBox? { get }
    var paddingTop: CGFloat { get }
    var paddingRight: CGFloat { get }
    var paddingBottom: CGFloat { get }
    var paddingLeft: CGFloat { get }
    var isImage: Bool { get }
    var image: NSImage? { get }
    var imageFailed: Bool { get }
    var alt: String { get }
    var content: NSAttributedString? { get }
}

extension TBFloatSpec: TBBoxPaintSource {}
extension TBPositionedSpec: TBBoxPaintSource {}

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
    // Painted layouts (0.25.0): the cache holds each
    // box's NSTextStorage alongside its layout manager
    // and container. A layout manager references its
    // text storage only weakly — the storage owns the
    // manager, never the reverse — so a cache that
    // kept only the manager and container left every
    // later repaint holding a manager with no text
    // behind it: no glyphs, and painted box and
    // column text simply never reached the screen.
    private var floatContentLayouts:
        [ObjectIdentifier: (NSTextStorage, NSLayoutManager, NSTextContainer)] = [:]

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
            var kept = 0
            for i in 0..<rectCount {
                var rect = rectArray[i]
                rect.origin.x = left
                rect.origin.y += offset.y
                rect.size.width = width
                // A rect with no area is dropped
                // (0.25.0): handed on, it would fill
                // as a zero-size draw — the kind
                // Metal's debug validation asserts
                // on — and it can paint no pixel
                // anyway. A run whose line fragment
                // measures no height (an empty
                // paragraph's) is the case in point.
                guard rect.width > 0, rect.height > 0 else { continue }
                widened[kept] = rect
                kept += 1
            }
            guard kept > 0 else { return }
            super.fillBackgroundRectArray(widened, count: kept,
                                          forCharacterRange: charRange, color: color)
            return
        }
        // Positioned layout (0.17): a relatively offset run
        // takes its background with it when it shifts.
        if offset != .zero {
            let shifted = UnsafeMutablePointer<NSRect>.allocate(capacity: rectCount)
            defer { shifted.deallocate() }
            var kept = 0
            for i in 0..<rectCount {
                let rect = NSRect(x: rectArray[i].origin.x + offset.x,
                                  y: rectArray[i].origin.y + offset.y,
                                  width: rectArray[i].width,
                                  height: rectArray[i].height)
                guard rect.width > 0, rect.height > 0 else { continue }
                shifted[kept] = rect
                kept += 1
            }
            guard kept > 0 else { return }
            super.fillBackgroundRectArray(shifted, count: kept,
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
        paintPositionedBelow(at: origin)
        paintFloats(at: origin)
        paintColumns(at: origin)
        paintFlex(at: origin)
        paintGrid(at: origin)
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
            // A band of no height — an empty
            // paragraph's surface can measure zero —
            // is never issued as a draw (0.25.0):
            // zero-size draws are what Metal's debug
            // validation asserts on (instanceCount 0),
            // and a rect with no area paints nothing
            // in any case.
            guard rect.width > 0, rect.height > 0 else { continue }
            if let color = band.color {
                color.setFill()
                rect.fill()
            }
            if let box = band.box {
                TBBandLayoutManager.paintBackgroundLayers(box, in: rect)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // Positioned layout (0.17): the page's floats, painted
    // over the surfaces at the positions the coordinator
    // resolved.
    private func paintFloats(at origin: NSPoint) {
        for paint in floatPaints {
            let rect = NSRect(x: origin.x + paint.rect.minX,
                              y: origin.y + paint.rect.minY,
                              width: paint.rect.width, height: paint.rect.height)
            paintBox(rect: rect, source: paint.spec)
        }
    }

    // Multi-column layout (0.22): the multicolumn blocks
    // the coordinator has resolved for this page — each
    // seat's rect in container coordinates, with the spec
    // carrying the block's contents and column geometry —
    // painted in drawBackground, after the floats: the
    // rules first (they stand under the columns' words),
    // then the columns themselves across their containers.
    var columnPaints: [(rect: NSRect, spec: TBMultiColumnSpec)] = [] {
        didSet { columnLayouts = [:] }
    }
    private var columnLayouts:
        [ObjectIdentifier: (NSTextStorage, NSLayoutManager, [NSTextContainer])] = [:]

    private func paintColumns(at origin: NSPoint) {
        for paint in columnPaints {
            let spec = paint.spec
            let rect = NSRect(x: origin.x + paint.rect.minX,
                              y: origin.y + paint.rect.minY,
                              width: paint.rect.width,
                              height: paint.rect.height)
            // One rule per gap, as tall as the columns,
            // centered in the gap. Of the border styles,
            // solid paints as a fill — and double, groove,
            // ridge, inset and outset paint solid too: a
            // rule a point or three wide has no bevel to
            // show. Dotted and dashed stroke a line with
            // a dash pattern instead. A rule of no height
            // is not drawn at all (0.25.0): a zero-height
            // fill, or a path from a point to itself, is
            // a zero-size draw.
            if spec.columnCount > 1, spec.ruleWidth > 0,
               spec.columnHeight > 0,
               spec.ruleStyle != "none", spec.ruleStyle != "hidden",
               let color = spec.ruleColor {
                for i in 1..<spec.columnCount {
                    let centerX = rect.minX + CGFloat(i) * spec.columnWidth
                        + CGFloat(i - 1) * spec.gap + spec.gap / 2
                    if spec.ruleStyle == "dotted"
                        || spec.ruleStyle == "dashed" {
                        let path = NSBezierPath()
                        path.move(to: NSPoint(x: centerX, y: rect.minY))
                        path.line(to: NSPoint(x: centerX,
                                              y: rect.minY + spec.columnHeight))
                        path.lineWidth = spec.ruleWidth
                        let dash: CGFloat = spec.ruleStyle == "dotted"
                            ? spec.ruleWidth : spec.ruleWidth * 3
                        path.setLineDash([dash, dash], count: 2, phase: 0)
                        color.setStroke()
                        path.stroke()
                    } else {
                        color.setFill()
                        NSRect(x: centerX - spec.ruleWidth / 2,
                               y: rect.minY, width: spec.ruleWidth,
                               height: spec.columnHeight).fill()
                    }
                }
            }
            drawColumnContent(spec, in: rect)
        }
    }

    // Lay a multicolumn block's contents out across its
    // containers — one per column, each the column's
    // width and the balanced height the renderer
    // measured — and paint them side by side: the text
    // flows down one column and continues at the top of
    // the next, the layout manager's own chaining. The
    // layout is cached per block until the page resolves
    // again, as a floated box's contents are.
    private func drawColumnContent(_ spec: TBMultiColumnSpec, in rect: NSRect) {
        guard let content = spec.content, content.length > 0,
              spec.columnCount > 0 else { return }
        let key = ObjectIdentifier(spec)
        let manager: NSLayoutManager
        let containers: [NSTextContainer]
        if let cached = columnLayouts[key],
           cached.2.count == spec.columnCount, !cached.2.isEmpty,
           cached.2[0].size == NSSize(width: spec.columnWidth,
                                      height: spec.columnHeight) {
            manager = cached.1
            containers = cached.2
        } else {
            // 0.25.0: the storage is built first and
            // attached to the manager before its
            // containers — the floated-box painter's
            // established order — and the cache keeps
            // the storage itself, not just the manager
            // and containers. A layout manager holds
            // its text storage weakly, so the old cache
            // outlived the very text it was meant to
            // paint: the columns' rules and backgrounds
            // (plain fills) showed, and their words
            // never did.
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            var built: [NSTextContainer] = []
            for _ in 0..<spec.columnCount {
                let container = NSTextContainer(
                    size: NSSize(width: spec.columnWidth,
                                 height: spec.columnHeight))
                manager.addTextContainer(container)
                built.append(container)
            }
            columnLayouts[key] = (storage, manager, built)
            containers = built
        }
        guard let last = containers.last else { return }
        manager.ensureLayout(for: last)
        for (index, container) in containers.enumerated() {
            let glyphs = manager.glyphRange(for: container)
            guard glyphs.length > 0 else { continue }
            let at = NSPoint(
                x: rect.minX + CGFloat(index) * (spec.columnWidth + spec.gap),
                y: rect.minY)
            manager.drawBackground(forGlyphRange: glyphs, at: at)
            manager.drawGlyphs(forGlyphRange: glyphs, at: at)
            // Flexbox (0.24): a flex container nested
            // in the columns paints at its seat in this
            // column, like one nested anywhere else.
            // Grid (0.25): a grid container nested in
            // the columns paints the same way.
            let chars = manager.characterRange(forGlyphRange: glyphs,
                                               actualGlyphRange: nil)
            paintFlexSeats(in: content, manager: manager, at: at,
                           charRange: chars)
            paintGridSeats(in: content, manager: manager, at: at,
                           charRange: chars)
        }
    }

    // Flexbox (0.24): the flex containers the
    // coordinator has resolved for this page — each
    // seat's rect in container coordinates, with the
    // spec carrying the items and their resolved
    // boxes — painted in drawBackground, after the
    // columns: each item's background first, then its
    // contents inside its padding.
    var flexPaints: [(rect: NSRect, spec: TBFlexSpec)] = [] {
        didSet { flexContentLayouts = [:] }
    }
    // Item contents are painted layouts, like a
    // floated box's: the cache holds each item's
    // NSTextStorage alongside its manager and
    // container, for the reason 0.25.0 recorded — a
    // layout manager holds its text storage only
    // weakly, and a cache that kept only the manager
    // left every repaint holding no text at all.
    private var flexContentLayouts:
        [ObjectIdentifier: (NSTextStorage, NSLayoutManager, NSTextContainer)] = [:]

    private func paintFlex(at origin: NSPoint) {
        for paint in flexPaints {
            paintFlexContainer(paint.spec, at: NSPoint(
                x: origin.x + paint.rect.minX,
                y: origin.y + paint.rect.minY))
        }
    }

    // Paint one flex container's items at a
    // content-box origin — the single flex paint
    // path: the main flow's seats arrive here from
    // paintFlex, and a container nested inside
    // painted contents arrives from paintFlexSeats,
    // at the seat's own place in its box. Each item
    // paints its background color and photo layers
    // over its whole border box (never for a rect
    // with no area — a zero-size fill is the draw
    // Metal's debug validation asserts on), then its
    // contents inside its padding.
    func paintFlexContainer(_ spec: TBFlexSpec, at origin: NSPoint) {
        for item in spec.items {
            let rect = NSRect(x: origin.x + item.rect.minX,
                              y: origin.y + item.rect.minY,
                              width: item.rect.width,
                              height: item.rect.height)
            if let color = item.backgroundColor,
               rect.width > 0, rect.height > 0 {
                color.setFill()
                rect.fill()
            }
            if let box = item.backgroundBox {
                TBBandLayoutManager.paintBackgroundLayers(box, in: rect)
            }
            let contentRect = NSRect(
                x: rect.minX + item.paddingLeft,
                y: rect.minY + item.paddingTop,
                width: max(0, rect.width - item.paddingLeft
                    - item.paddingRight),
                height: max(0, rect.height - item.paddingTop
                    - item.paddingBottom))
            if let content = item.content, content.length > 0,
               contentRect.width > 0, contentRect.height > 0 {
                drawFlexItemContent(item, in: contentRect)
            }
        }
    }

    // Lay a flex item's contents out in a private
    // layout manager at the item's content size and
    // paint them there — a floated box's content
    // painting, per item — then paint any flex
    // containers nested in those contents at their
    // seats. The layout is cached per item until the
    // page resolves again.
    private func drawFlexItemContent(_ item: TBFlexItem, in rect: NSRect) {
        guard let content = item.content, content.length > 0
        else { return }
        let key = ObjectIdentifier(item)
        let manager: NSLayoutManager
        let container: NSTextContainer
        if let cached = flexContentLayouts[key],
           cached.2.size == rect.size {
            manager = cached.1
            container = cached.2
        } else {
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            container = NSTextContainer(size: rect.size)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            flexContentLayouts[key] = (storage, manager, container)
        }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return }
        manager.drawBackground(forGlyphRange: glyphs, at: rect.origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: rect.origin)
        paintFlexSeats(in: content, manager: manager, at: rect.origin)
        // Grid (0.25): a grid container nested in a
        // flex item paints at its seat, as a flex
        // container nested in a grid item paints in
        // drawGridItemContent — the shared path.
        paintGridSeats(in: content, manager: manager, at: rect.origin)
    }

    // Paint the flex containers nested inside painted
    // contents: the renderer stamps each nested
    // container's spec on its seat character, so scan
    // the contents for the stamp, resolve each seat's
    // place from the layout that just painted the
    // contents — the fragment's start plus the glyph's
    // own advance within the line, the way a form
    // control's seat is found — and paint the
    // container's items there. A character range
    // limits the scan to one column of a multicolumn
    // block's chained containers.
    func paintFlexSeats(in content: NSAttributedString,
                        manager: NSLayoutManager, at origin: NSPoint,
                        charRange: NSRange? = nil) {
        let range = charRange
            ?? NSRange(location: 0, length: content.length)
        var seats: [(spec: TBFlexSpec, charIndex: Int)] = []
        content.enumerateAttribute(TBFlexSpecKey, in: range) {
            value, r, _ in
            if let spec = value as? TBFlexSpec {
                seats.append((spec: spec, charIndex: r.location))
            }
        }
        for seat in seats {
            let glyph = manager.glyphIndexForCharacter(at: seat.charIndex)
            guard glyph < manager.numberOfGlyphs else { continue }
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph,
                                                    effectiveRange: nil)
            let spot = manager.location(forGlyphAt: glyph)
            paintFlexContainer(seat.spec, at: NSPoint(
                x: origin.x + fragment.minX + spot.x,
                y: origin.y + fragment.minY))
        }
    }

    // Grid (0.25): the grid containers the
    // coordinator has resolved for this page — each
    // seat's rect in container coordinates, with the
    // spec carrying the items and their resolved
    // boxes — painted in drawBackground, after the
    // flex containers: each item's background first,
    // then its contents inside its padding, through
    // the one grid paint path the flex painters
    // established.
    var gridPaints: [(rect: NSRect, spec: TBGridSpec)] = [] {
        didSet { gridContentLayouts = [:] }
    }
    // Item contents are painted layouts, like a flex
    // item's: the cache holds each item's
    // NSTextStorage alongside its manager and
    // container — a layout manager holds its text
    // storage only weakly, and a cache that kept only
    // the manager left every repaint holding no text
    // at all (the 0.25.0 lesson, kept).
    private var gridContentLayouts:
        [ObjectIdentifier: (NSTextStorage, NSLayoutManager, NSTextContainer)] = [:]

    private func paintGrid(at origin: NSPoint) {
        for paint in gridPaints {
            paintGridContainer(paint.spec, at: NSPoint(
                x: origin.x + paint.rect.minX,
                y: origin.y + paint.rect.minY))
        }
    }

    // Paint one grid container's items at a
    // content-box origin — the single grid paint
    // path: the main flow's seats arrive here from
    // paintGrid, and a container nested inside
    // painted contents arrives from paintGridSeats,
    // at the seat's own place in its box. Each item
    // paints its background color and photo layers
    // over its whole border box (never for a rect
    // with no area — a zero-size fill is the draw
    // Metal's debug validation asserts on), then its
    // contents inside its padding.
    func paintGridContainer(_ spec: TBGridSpec, at origin: NSPoint) {
        for item in spec.items {
            let rect = NSRect(x: origin.x + item.rect.minX,
                              y: origin.y + item.rect.minY,
                              width: item.rect.width,
                              height: item.rect.height)
            if let color = item.backgroundColor,
               rect.width > 0, rect.height > 0 {
                color.setFill()
                rect.fill()
            }
            if let box = item.backgroundBox {
                TBBandLayoutManager.paintBackgroundLayers(box, in: rect)
            }
            let contentRect = NSRect(
                x: rect.minX + item.paddingLeft,
                y: rect.minY + item.paddingTop,
                width: max(0, rect.width - item.paddingLeft
                    - item.paddingRight),
                height: max(0, rect.height - item.paddingTop
                    - item.paddingBottom))
            if let content = item.content, content.length > 0,
               contentRect.width > 0, contentRect.height > 0 {
                drawGridItemContent(item, in: contentRect)
            }
        }
    }

    // Lay a grid item's contents out in a private
    // layout manager at the item's content size and
    // paint them there — a flex item's content
    // painting, per item — then paint any containers
    // nested in those contents at their seats, grid
    // and flex alike: one shared finalize path in the
    // renderer, one shared paint path here. The
    // layout is cached per item until the page
    // resolves again.
    private func drawGridItemContent(_ item: TBGridItem, in rect: NSRect) {
        guard let content = item.content, content.length > 0
        else { return }
        let key = ObjectIdentifier(item)
        let manager: NSLayoutManager
        let container: NSTextContainer
        if let cached = gridContentLayouts[key],
           cached.2.size == rect.size {
            manager = cached.1
            container = cached.2
        } else {
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            container = NSTextContainer(size: rect.size)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            gridContentLayouts[key] = (storage, manager, container)
        }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return }
        manager.drawBackground(forGlyphRange: glyphs, at: rect.origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: rect.origin)
        paintFlexSeats(in: content, manager: manager, at: rect.origin)
        paintGridSeats(in: content, manager: manager, at: rect.origin)
    }

    // Paint the grid containers nested inside painted
    // contents: the renderer stamps each nested
    // container's spec on its seat character, so scan
    // the contents for the stamp, resolve each seat's
    // place from the layout that just painted the
    // contents — the fragment's start plus the glyph's
    // own advance within the line, the way a form
    // control's seat is found — and paint the
    // container's items there. A character range
    // limits the scan to one column of a multicolumn
    // block's chained containers.
    func paintGridSeats(in content: NSAttributedString,
                        manager: NSLayoutManager, at origin: NSPoint,
                        charRange: NSRange? = nil) {
        let range = charRange
            ?? NSRange(location: 0, length: content.length)
        var seats: [(spec: TBGridSpec, charIndex: Int)] = []
        content.enumerateAttribute(TBGridSpecKey, in: range) {
            value, r, _ in
            if let spec = value as? TBGridSpec {
                seats.append((spec: spec, charIndex: r.location))
            }
        }
        for seat in seats {
            let glyph = manager.glyphIndexForCharacter(at: seat.charIndex)
            guard glyph < manager.numberOfGlyphs else { continue }
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph,
                                                    effectiveRange: nil)
            let spot = manager.location(forGlyphAt: glyph)
            paintGridContainer(seat.spec, at: NSPoint(
                x: origin.x + fragment.minX + spot.x,
                y: origin.y + fragment.minY))
        }
    }

    // One out-of-flow box, painted at a resolved rect —
    // the single paint path floats (0.17), absolutely
    // positioned boxes (0.21), and fixed overlays all
    // share: background color and photo layers first,
    // then the picture, or the box's own contents inside
    // its padding. A picture that never arrived leaves a
    // labelled frame, as a failed in-flow image does.
    func paintBox(rect: NSRect, source: TBBoxPaintSource) {
        // No fill for an empty rect (0.25.0): a box
        // resolved to no width or no height paints
        // nothing anyway, and a zero-size fill is
        // exactly the draw Metal's debug validation
        // asserts on.
        if let color = source.backgroundColor,
           rect.width > 0, rect.height > 0 {
            color.setFill()
            rect.fill()
        }
        if let box = source.backgroundBox {
            TBBandLayoutManager.paintBackgroundLayers(box, in: rect)
        }
        let contentRect = NSRect(
            x: rect.minX + source.paddingLeft, y: rect.minY + source.paddingTop,
            width: max(0, rect.width - source.paddingLeft - source.paddingRight),
            height: max(0, rect.height - source.paddingTop - source.paddingBottom))
        if source.isImage {
            if let image = source.image {
                TBBandLayoutManager.tbDrawPhoto(image, in: contentRect)
            } else if source.imageFailed,
                      contentRect.width > 1, contentRect.height > 1 {
                // The frame is inset half a point, so
                // a content rect of a point or less
                // would stroke an empty path (0.25.0).
                NSColor.separatorColor.setStroke()
                let frame = NSBezierPath(rect: contentRect.insetBy(dx: 0.5, dy: 0.5))
                frame.lineWidth = 1
                frame.stroke()
                let label = source.alt.isEmpty ? "image" : source.alt
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.secondaryLabelColor]
                let size = (label as NSString).size(withAttributes: attrs)
                (label as NSString).draw(
                    at: NSPoint(x: contentRect.midX - size.width / 2,
                                y: contentRect.midY - size.height / 2),
                    withAttributes: attrs)
            }
        } else if let content = source.content, content.length > 0 {
            drawBoxContent(content, key: ObjectIdentifier(source), in: contentRect)
        }
    }

    // Positioned layout (0.21): this page's absolutely
    // positioned boxes with negative z-index, in stacking
    // order — painted in drawBackground, over the
    // surfaces and under the floats: behind the page's
    // flow, as CSS stacks them, insofar as a text flow
    // can stack anything.
    var positionedPaintsBelow: [(rect: NSRect, spec: TBPositionedSpec)] = []
    // ...and those with z-index zero or above, painted
    // by the text view after the glyphs (TBPageTextView),
    // so a badge truly covers what it overlaps.
    var positionedPaints: [(rect: NSRect, spec: TBPositionedSpec)] = []

    private func paintPositionedBelow(at origin: NSPoint) {
        for paint in positionedPaintsBelow {
            let rect = NSRect(x: origin.x + paint.rect.minX,
                              y: origin.y + paint.rect.minY,
                              width: paint.rect.width, height: paint.rect.height)
            paintBox(rect: rect, source: paint.spec)
        }
    }

    // Called by the text view once its glyphs are on the
    // page: the z-index >= 0 positioned boxes, in
    // stacking order, at container rects offset into
    // view coordinates.
    func paintPositionedAbove(at origin: NSPoint, dirtyRect: NSRect) {
        for paint in positionedPaints {
            let rect = NSRect(x: origin.x + paint.rect.minX,
                              y: origin.y + paint.rect.minY,
                              width: paint.rect.width, height: paint.rect.height)
            if rect.intersects(dirtyRect) {
                paintBox(rect: rect, source: paint.spec)
            }
        }
    }

    // Lay a painted box's contents out in a private
    // layout manager at the box's content size and paint
    // them there. The layout is cached per box until the
    // page's floats are resolved again.
    private func drawBoxContent(_ content: NSAttributedString,
                                key: ObjectIdentifier, in rect: NSRect) {
        let manager: NSLayoutManager
        let container: NSTextContainer
        if let cached = floatContentLayouts[key], cached.2.size == rect.size {
            manager = cached.1
            container = cached.2
        } else {
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            container = NSTextContainer(size: rect.size)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            floatContentLayouts[key] = (storage, manager, container)
        }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return }
        manager.drawBackground(forGlyphRange: glyphs, at: rect.origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: rect.origin)
        // Flexbox (0.24): a flex container nested in
        // this box paints at its seat, recursively.
        paintFlexSeats(in: content, manager: manager, at: rect.origin)
        // Grid (0.25): a grid container nested in this
        // box paints at its seat the same way.
        paintGridSeats(in: content, manager: manager, at: rect.origin)
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
    // photos first, gradient veils over them. Static
    // since 0.21: the layer painters use no layout state,
    // and the fixed-position overlay views paint their
    // backgrounds through this same path.
    static func paintBackgroundLayers(_ box: TBBackgroundBox, in rect: NSRect) {
        // One guard for every caller — surfaces, the
        // box painter, the fixed overlays (0.25.0): no
        // layer of a box with no area is ever drawn,
        // since a gradient or photo issued into an
        // empty rect is a zero-size draw.
        guard rect.width > 0, rect.height > 0 else { return }
        for layer in box.layers.reversed() {
            switch layer.kind {
            case .gradient(let inner):
                TBBandLayoutManager.tbDrawLinearGradient(inner: inner, in: rect)
            case .image:
                if let image = layer.image {
                    TBBandLayoutManager.tbDrawBackgroundImage(
                        image, in: rect, sizeSpec: box.sizeSpec,
                        positionSpec: box.positionSpec,
                        repeatSpec: box.repeatSpec)
                }
            }
        }
    }

    // A linear gradient from its specification: an optional
    // direction (90deg, to right, …; default to bottom),
    // then color stops with optional % positions.
    static func tbDrawLinearGradient(inner: String, in rect: NSRect) {
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
            if part.contains("("), let open = part.firstIndex(of: "(") {
                // The color may be a function wearing
                // nested parentheses of its own — a
                // color-mix with another mix inside it
                // (0.22) — so its end is the paren that
                // BALANCES the first one, not the first
                // close that happens by. (For rgb() and
                // an unnested mix the two are the same
                // paren, so stops written before 0.22
                // parse exactly as they did.)
                var depth = 0
                var close: String.Index? = nil
                var j = open
                while j < part.endIndex {
                    if part[j] == "(" { depth += 1 }
                    else if part[j] == ")" {
                        depth -= 1
                        if depth == 0 { close = j; break }
                    }
                    j = part.index(after: j)
                }
                if let close = close {
                    colorText = String(part[...close])
                    let rest = part[part.index(after: close)...]
                        .trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { positionText = Substring(rest) }
                }
            }
            if colorText == part, let space = part.firstIndex(of: " ") {
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
    static func tbDrawPhoto(_ image: NSImage, in dest: NSRect) {
        guard dest.width > 0, dest.height > 0,
              let context = NSGraphicsContext.current?.cgContext,
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
    static func tbDrawBackgroundImage(_ image: NSImage, in rect: NSRect,
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
        let (fx, fy) = TBBandLayoutManager.tbBackgroundFractions(positionSpec)
        let originX = rect.minX + (rect.width - drawn.width) * fx
        let originY = rect.minY + (rect.height - drawn.height) * fy
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        if repeatSpec.lowercased().contains("no-repeat") {
            TBBandLayoutManager.tbDrawPhoto(image, in: NSRect(
                x: originX, y: originY, width: drawn.width, height: drawn.height))
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
                    TBBandLayoutManager.tbDrawPhoto(image, in: NSRect(
                        x: x, y: y, width: drawn.width, height: drawn.height))
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
    static func tbBackgroundFractions(_ spec: String) -> (fx: CGFloat, fy: CGFloat) {
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

// A fixed box's overlay (0.21): a real view the
// coordinator seats against the viewport and reseats
// on every scroll, so the box stays while the page
// moves beneath it — the way form controls are real
// views, one level up. It paints through the same box
// painter as floats and absolute boxes (its background
// layers via the layout manager's shared statics, its
// contents through a private layout of their own).
// Flipped, like the text view itself, so its contents
// lay out top-down the same way.
final class TBFixedOverlayView: NSView {
    var spec: TBPositionedSpec? = nil {
        didSet { contentLayout = nil }
    }
    // The storage rides in the cache for the same
    // reason as in the layout manager's painters
    // (0.25.0): the manager holds it only weakly, and
    // a fixed box's words must survive repaints.
    private var contentLayout: (NSTextStorage, NSLayoutManager, NSTextContainer)? = nil

    // Flexbox (0.24): the painter for any flex
    // containers nested in this box's contents — a
    // band layout manager kept for its item layout
    // caches and paint paths; it lays out nothing of
    // its own.
    private let flexPainter = TBBandLayoutManager()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let spec = spec else { return }
        if let color = spec.backgroundColor,
           bounds.width > 0, bounds.height > 0 {
            color.setFill()
            bounds.fill()
        }
        if let box = spec.backgroundBox {
            TBBandLayoutManager.paintBackgroundLayers(box, in: bounds)
        }
        let contentRect = NSRect(
            x: bounds.minX + spec.paddingLeft, y: bounds.minY + spec.paddingTop,
            width: max(0, bounds.width - spec.paddingLeft - spec.paddingRight),
            height: max(0, bounds.height - spec.paddingTop - spec.paddingBottom))
        if spec.isImage {
            if let image = spec.image {
                TBBandLayoutManager.tbDrawPhoto(image, in: contentRect)
            } else if spec.imageFailed,
                      contentRect.width > 1, contentRect.height > 1 {
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
            return
        }
        guard let content = spec.content, content.length > 0 else { return }
        let manager: NSLayoutManager
        let container: NSTextContainer
        if let cached = contentLayout, cached.2.size == contentRect.size {
            manager = cached.1
            container = cached.2
        } else {
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            container = NSTextContainer(size: contentRect.size)
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            contentLayout = (storage, manager, container)
        }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return }
        manager.drawBackground(forGlyphRange: glyphs, at: contentRect.origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: contentRect.origin)
        // Flexbox (0.24): a flex container nested in
        // this box paints at its seat, as in any
        // painted box.
        flexPainter.paintFlexSeats(in: content, manager: manager,
                                   at: contentRect.origin)
        // Grid (0.25): a grid container nested in this
        // box paints at its seat the same way.
        flexPainter.paintGridSeats(in: content, manager: manager,
                                   at: contentRect.origin)
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
