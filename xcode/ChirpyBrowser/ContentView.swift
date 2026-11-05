//
//  ContentView.swift
//  Chirpy Browser — prototype 0.29.0 (Swift)
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
    @Published var statusLine = "Chirpy Engine 0.29.0 (Swift) — first paint, positioned layout, floats, columns, flexbox, grid, sticky, focus, active, styled forms, color-mix, font shorthand, media queries, hover, shadows, transforms, transitions, animations, the shield, the banding repair, progress bar, parallel loading, no JavaScript yet"
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
                let settledStatus = "\(finalURL)  ·  Chirpy Engine 0.29.0 (Swift) — first paint, positioned layout, floats, columns, flexbox, grid, sticky, focus, active, styled forms, color-mix, font shorthand, media queries, hover, shadows, transforms, transitions, animations, the shield, the banding repair, progress bar, parallel loading, no JavaScript yet"
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
            (textView as? TBPageTextView)?.pageTextInstalled()
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
                self?.repositionStickyElements()
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
            repositionStickyElements()
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
                    let field = TBStyledTextField()
                    field.stringValue = spec.defaultValue
                    field.placeholderString = spec.placeholder
                    field.font = NSFont.systemFont(ofSize: 13)
                    field.isBezeled = true
                    field.bezelStyle = .roundedBezel
                    field.tag = spec.id
                    field.target = self
                    field.action = #selector(Coordinator.fieldSubmitted(_:))
                    // The interaction set (0.26): the page
                    // dresses its control — the style its
                    // element resolved to — and a control
                    // taking focus releases the text's
                    // focused link, one focus at a time.
                    field.controlStyle = fieldAtt.style
                    field.applyControlStyle()
                    field.onFocusChange = { [weak self] focused in
                        if focused {
                            (self?.textView as? TBPageTextView)?
                                .noteControlFocus()
                        }
                    }
                    textView.addSubview(field)
                    self.fieldViews[spec.id] = field
                    self.formControlViews.append(field)
                    self.formAnchors.append((view: field, charIndex: range.location,
                                             attachment: fieldAtt))
                } else if let submitAtt = value as? TBSubmitAttachment {
                    let button = TBStyledButton(title: submitAtt.label, target: self,
                                                action: #selector(Coordinator.submitClicked(_:)))
                    button.bezelStyle = .rounded
                    button.bezelColor = .controlColor
                    button.tag = submitAtt.formID
                    // The interaction set (0.26): the
                    // button's page dress, as the field's.
                    button.controlStyle = submitAtt.style
                    button.applyControlStyle()
                    button.onFocusChange = { [weak self] focused in
                        if focused {
                            (self?.textView as? TBPageTextView)?
                                .noteControlFocus()
                        }
                    }
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
            (textView as? TBPageTextView)?.pageTextInstalled()
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

        // The interaction set (0.26): resolve every sticky
        // element's paint shift against the scroll, in the
        // fixed overlays' update discipline — recomputed
        // when the page scrolls, resizes, or re-settles,
        // never in the flow. The element's natural rect
        // and its containing block's rect are the painted
        // surface rects containingRect measures; the
        // element holds at its inset inside the visible
        // band until its containing block's edge pushes
        // it off, and it never shifts past the room its
        // containing block leaves it. A shift is paint
        // only: the layout manager adds it where the
        // relative offsets are added, so surfaces and
        // glyphs move together and the flow never does.
        // Coordinates here are the container's, y down;
        // the visible band's top is the scroll position.
        func repositionStickyElements() {
            guard let textView = textView,
                  let band = textView.layoutManager as? TBBandLayoutManager,
                  let container = textView.textContainer else { return }
            var specs: [TBStickySpec] = []
            for event in layoutEvents {
                if case .sticky(let spec) = event { specs.append(spec) }
            }
            var shifts: [ObjectIdentifier: CGFloat] = [:]
            if !specs.isEmpty {
                let width = container.size.width
                let scrollTop = textView.visibleRect.minY
                    - textView.textContainerOrigin.y
                let visibleHeight = textView.visibleRect.height
                for spec in specs {
                    let natural = containingRect(for: spec.rangeBlock,
                                                 width: width)
                    guard natural.height > 0 else { continue }
                    let containing: NSRect
                    if let block = spec.containingBlock {
                        containing = containingRect(for: block, width: width)
                    } else {
                        containing = NSRect(x: 0, y: 0, width: width,
                                            height: container.size.height)
                    }
                    var dy: CGFloat = 0
                    if let top = resolveInset(spec.top,
                                              extent: containing.height) {
                        dy = min(max(0, scrollTop + top - natural.minY),
                                 max(0, containing.maxY - natural.maxY))
                    } else if let bottom = resolveInset(
                        spec.bottom, extent: containing.height) {
                        dy = min(0, (scrollTop + visibleHeight - bottom)
                                 - natural.maxY)
                        dy = max(dy, min(0, containing.minY - natural.minY))
                    }
                    if dy != 0 { shifts[ObjectIdentifier(spec)] = dy }
                }
            }
            if shifts != band.stickyShifts {
                band.stickyShifts = shifts
                textView.needsDisplay = true
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
            band?.stickyShifts = [:]
            if !container.exclusionPaths.isEmpty {
                container.exclusionPaths = []
            }
            guard !layoutEvents.isEmpty, storage.length > 0 else {
                rebuildFixedViews()
                repositionStickyElements()
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
                    case .sticky:
                        // Sticky blocks (0.26) make no
                        // exclusions either: the element
                        // is ordinary flow text, and only
                        // its paint shifts, as the page
                        // scrolls — resolved by
                        // repositionStickyElements.
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
                case .sticky(let spec): return spec.rangeBlock.startCharIndex
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
            repositionStickyElements()
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

// The interaction set (0.26): the live form controls,
// dressed by the page. The coordinator builds these
// subclasses instead of plain NSTextField / NSButton
// and hands each the TBControlStyle its element's
// declarations resolved to. A control whose style
// declares nothing keeps the native look exactly as
// it stood before 0.26. Focus presentation is
// computed from the style alone — the resting values
// below — never read back off the control, whose
// property shapes are AppKit's to vary.
final class TBStyledTextField: NSTextField {
    var controlStyle: TBControlStyle? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    // Dress the field in its resting style. The native
    // bezel stands down only when the page paints the
    // field itself — a background, a border or a corner
    // radius declared; a field the page leaves alone
    // keeps the classic bezel it always had.
    func applyControlStyle() {
        guard let style = controlStyle else { return }
        if let font = style.font { self.font = font }
        if let color = style.textColor { textColor = color }
        if style.backgroundColor != nil || style.borderColor != nil
            || style.cornerRadius > 0 {
            isBezeled = false
            // A background paints only when the page
            // declares one — a border alone leaves the
            // page showing through, as CSS has it.
            if let bg = style.backgroundColor {
                drawsBackground = true
                backgroundColor = bg
            }
            wantsLayer = true
            if let layer = layer {
                if let border = style.borderColor {
                    layer.borderColor = border.cgColor
                }
                layer.borderWidth = style.borderWidth
                layer.cornerRadius = style.cornerRadius
            }
        }
    }

    // The focus's dress: a declared outline rides as
    // the border ring while the focus lasts; else a
    // :focus border color takes the ring's place, and
    // :focus background and text colors swap in. The
    // resign puts the resting values back — all read
    // from the style, as above.
    private func applyFocusPresentation(_ focused: Bool) {
        guard let style = controlStyle else { return }
        if focused {
            if let focusText = style.focusTextColor {
                textColor = focusText
            }
            if style.backgroundColor != nil || style.borderColor != nil
                || style.cornerRadius > 0 || style.outlineColor != nil {
                isBezeled = false
                wantsLayer = true
                // The background swaps only when the
                // focus declares one — an outline alone
                // must not flash the default field
                // background under the page's text.
                if let bg = style.focusBackgroundColor {
                    drawsBackground = true
                    backgroundColor = bg
                }
                if let layer = layer {
                    if let outline = style.outlineColor {
                        layer.borderColor = outline.cgColor
                        layer.borderWidth = style.outlineWidth
                    } else if let focusBorder = style.focusBorderColor {
                        layer.borderColor = focusBorder.cgColor
                    }
                }
            }
        } else {
            // The resting dress, in full: the focus may
            // have stood the bezel down for an outline
            // alone, so a field the page paints nothing
            // on gets its native bezel back explicitly.
            if style.backgroundColor == nil && style.borderColor == nil
                && style.cornerRadius <= 0 {
                if let color = style.textColor { textColor = color }
                isBezeled = true
                drawsBackground = false
                if let layer = layer {
                    layer.borderWidth = 0
                    layer.cornerRadius = 0
                }
            } else {
                applyControlStyle()
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            applyFocusPresentation(true)
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            applyFocusPresentation(false)
            onFocusChange?(false)
        }
        return accepted
    }
}

// A submit or form button (0.26): its background rides
// as the bezel tint, its color as the title's color,
// its font as the button's. While pressed it wears
// its :active colors; while focused, its :focus
// background — or, lacking one, its :focus border
// color — stands in for the tint, the closest honest
// dress a native button has for a focus ring.
final class TBStyledButton: NSButton {
    var controlStyle: TBControlStyle? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    func applyControlStyle() {
        guard let style = controlStyle else { return }
        if let font = style.font { self.font = font }
        if let bg = style.backgroundColor { bezelColor = bg }
        if let color = style.textColor {
            attributedTitle = NSAttributedString(
                string: title, attributes: [.foregroundColor: color])
        }
    }

    private func applyTitleColor(_ color: NSColor?) {
        guard let color = color else { return }
        attributedTitle = NSAttributedString(
            string: title, attributes: [.foregroundColor: color])
    }

    // NSButton's mouseDown runs the whole press —
    // tracking, highlighting, the action on release —
    // inside the super call, so the :active dress is
    // put on before it and taken off after it returns.
    override func mouseDown(with event: NSEvent) {
        if let style = controlStyle {
            if let activeBG = style.activeBackgroundColor {
                bezelColor = activeBG
            }
            applyTitleColor(style.activeTextColor)
        }
        super.mouseDown(with: event)
        applyControlStyle()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            if let style = controlStyle,
               let focusBG = style.focusBackgroundColor
                ?? style.focusBorderColor {
                bezelColor = focusBG
            }
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            applyControlStyle()
            onFocusChange?(false)
        }
        return accepted
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
        // The interaction set (0.26): a held sticky
        // element paints above the words scrolling under
        // it, after the positioned boxes.
        band.paintStickyAbove(at: textContainerOrigin, dirtyRect: dirtyRect)
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
    // The interaction set (0.26): :focus and :active are
    // stamped the same way under their own keys and worn
    // as layers with the hover — see the slots below.
    private var hoverTrackingArea: NSTrackingArea? = nil
    private var hoverRange: NSRange? = nil
    // The interaction set (0.26): the hover layer is one
    // of three state layers now — hover under focus
    // under active — each worn in its own extent, all
    // three applied by repaintStatePaint in that order
    // over ONE snapshot stack, so any layer lifting
    // restores everything beneath it exactly.
    // focusRange is the focused link's extent: a press
    // on a link gives it focus, as in a real browser,
    // and a live control taking focus releases it (the
    // coordinator calls noteControlFocus). activeRange
    // is the extent being pressed; mouseUp lifts it.
    private var focusRange: NSRange? = nil
    private var activeRange: NSRange? = nil
    private var stateSaved: [(key: NSAttributedString.Key,
                              range: NSRange, value: Any?)] = []
    private var stateTextLength = -1

    // The paint & motion set (0.27): transitions and
    // @keyframes animations of paint traits, driven by
    // ONE timer that exists only while something is
    // actually animating — started when a transition
    // or a keyframe run begins, stopped the moment
    // none remain, and never ticking an idle page.
    // Transitions run between the trait sets the state
    // layers wear (wornTargets); keyframe runs are
    // discovered from the text's animation stamps.
    // Colors are written as attributes frame by frame;
    // opacity and transforms ride the layout manager's
    // effects table, recomposed by rebuildFXOverrides.
    private struct TBTransition {
        var key: String
        var range: NSRange
        var property: String
        var fromColor: NSColor? = nil
        var toColor: NSColor? = nil
        var fromOpacity: CGFloat? = nil
        var toOpacity: CGFloat? = nil
        var fromTransform: TBTransformSpec? = nil
        var toTransform: TBTransformSpec? = nil
        var start: Date
        var duration: Double
        var delay: Double
        var timing: TBTimingFunction

        func progress(at now: Date) -> Double {
            let t = now.timeIntervalSince(start) - delay
            if t <= 0 { return 0 }
            if duration <= 0 { return 1 }
            return min(t / duration, 1)
        }

        func currentColor(at now: Date) -> NSColor? {
            guard let from = fromColor, let to = toColor
            else { return fromColor }
            return tbLerpColor(
                from, to, CGFloat(timing.evaluate(progress(at: now))))
        }

        func currentOpacity(at now: Date) -> CGFloat? {
            guard fromOpacity != nil || toOpacity != nil else { return nil }
            let from = fromOpacity ?? 1
            let to = toOpacity ?? 1
            return from + (to - from)
                * CGFloat(timing.evaluate(progress(at: now)))
        }
    }

    private struct TBKeyframeAnim {
        var range: NSRange
        var spec: TBAnimationSpec
        var start: Date
        var resting: [(range: NSRange, fg: NSColor?, bg: NSColor?)]
        var restingOpacity: CGFloat?
        var restingTransform: TBTransformSpec?
    }

    private struct TBWornTraits {
        var fg: NSColor? = nil
        var bg: NSColor? = nil
        var opacity: CGFloat? = nil
        var transform: TBTransformSpec? = nil
    }

    private var fxTimer: Timer? = nil
    private var transitions: [TBTransition] = []
    private var transitionFX: [String: (opacity: CGFloat?,
                                        transform: TBTransformSpec?)] = [:]
    private var keyframeAnims: [TBKeyframeAnim] = []
    private var keyframeFX: [(range: NSRange, opacity: CGFloat?,
                              transform: TBTransformSpec?)] = []
    private var wornTargets: [String: TBWornTraits] = [:]

    deinit {
        fxTimer?.invalidate()
    }

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
        // The pointer left the text: hover lifts, and a
        // press cannot outlive the pointer leaving.
        if hoverRange != nil || activeRange != nil {
            hoverRange = nil
            activeRange = nil
            repaintStatePaint()
        }
    }

    // State paint (0.26): while the pointer is pressed,
    // the pressed element wears its :active layer, and a
    // press on a link gives that link the focus — its
    // :focus layer — as in a real browser; a press
    // anywhere else releases the text's focus. The
    // hit test is the hover one, at the pressed
    // character. Live controls are subviews and never
    // reach this — their own presses are theirs.
    override func mouseDown(with event: NSEvent) {
        if let storage = textStorage, storage.length > 0 {
            let inView = convert(event.locationInWindow, from: nil)
            if inView.x >= textContainerOrigin.x,
               inView.y >= textContainerOrigin.y {
                let index = characterIndexForInsertion(at: inView)
                if index < storage.length {
                    var changed = false
                    let isLink = storage.attribute(
                        .link, at: index, effectiveRange: nil) != nil
                    let newFocus = isLink
                        ? stateExtent(at: index,
                                      elementKey: TBFocusAttrsKey,
                                      blockKey: TBFocusBlockAttrsKey,
                                      storage: storage)
                        : nil
                    if newFocus != focusRange {
                        focusRange = newFocus
                        changed = true
                    }
                    let newActive = stateExtent(
                        at: index, elementKey: TBActiveAttrsKey,
                        blockKey: TBActiveBlockAttrsKey, storage: storage)
                    if newActive != activeRange {
                        activeRange = newActive
                        changed = true
                    }
                    if changed { repaintStatePaint() }
                }
            }
        }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if activeRange != nil {
            activeRange = nil
            repaintStatePaint()
        }
        super.mouseUp(with: event)
    }

    // A live form control took the keyboard focus: the
    // text's focused link releases its :focus layer —
    // one focus at a time, as in a real browser.
    func noteControlFocus() {
        if focusRange != nil {
            focusRange = nil
            repaintStatePaint()
        }
    }

    // The window replaced the page's text (a new load, or
    // the arrivals landing): any state being worn belonged
    // to the old text. Forget it without restoring — the
    // new text never wore it.
    func pageTextReplaced() {
        hoverRange = nil
        focusRange = nil
        activeRange = nil
        stateSaved = []
        stateTextLength = -1
        // The paint & motion set (0.27): the old text's
        // motion dies with it — its transitions, its
        // keyframe runs, the timer — and the layout
        // manager's registrations are cleared; the new
        // text's keyframe animations are then
        // discovered fresh from its stamps.
        transitions = []
        transitionFX = [:]
        wornTargets = [:]
        keyframeFX = []
        fxTimer?.invalidate()
        fxTimer = nil
        if let band = layoutManager as? TBBandLayoutManager {
            band.fxOverrides = []
            band.stateLayerPaints = []
            band.transformPivots = [:]
        }
    }

    // The counterpart the window calls once the new
    // text is actually in: pageTextReplaced runs
    // BEFORE the install at both call sites (nothing
    // of the old page may touch the new text), so the
    // new page's keyframe animations are discovered
    // here, from the text as installed.
    func pageTextInstalled() {
        discoverAnimations()
    }

    // The hover layer's extent at a character (0.23's
    // computation, shared by all three state layers since
    // 0.26): where the element stamp and the block stamp
    // overlap, both are constant — the element's run
    // inside its block. Nil when the character carries
    // neither stamp for this state.
    private func stateExtent(at index: Int,
                             elementKey: NSAttributedString.Key,
                             blockKey: NSAttributedString.Key,
                             storage: NSTextStorage) -> NSRange? {
        var elementRange = NSRange(location: 0, length: 0)
        var blockRange = NSRange(location: 0, length: 0)
        let element = storage.attribute(elementKey, at: index,
                                        effectiveRange: &elementRange)
            as? TBHoverStyle
        let block = storage.attribute(blockKey, at: index,
                                      effectiveRange: &blockRange)
            as? TBHoverStyle
        guard element != nil || block != nil else { return nil }
        let extent: NSRange
        if element != nil && block != nil {
            extent = NSIntersectionRange(elementRange, blockRange)
        } else if element != nil {
            extent = elementRange
        } else {
            extent = blockRange
        }
        return extent.length > 0 ? extent : nil
    }

    private func updateHover(with event: NSEvent) {
        guard let storage = textStorage else { return }
        // The text changed length under a worn state (a
        // re-install the coordinator did not announce):
        // the saved paint belongs to the old text — forget
        // it rather than write it onto the new.
        if (hoverRange != nil || focusRange != nil || activeRange != nil)
            && stateTextLength != storage.length {
            pageTextReplaced()
        }
        var extent: NSRange? = nil
        if storage.length > 0 {
            let inView = convert(event.locationInWindow, from: nil)
            // The text view's own hit test (0.23 build fix):
            // the character under the point, the point given
            // in view coordinates. The guard is the old
            // container-space one restated against the
            // origin — nothing above or left of where the
            // text begins can be hovered.
            if inView.x >= textContainerOrigin.x,
               inView.y >= textContainerOrigin.y {
                let index = characterIndexForInsertion(at: inView)
                if index < storage.length {
                    extent = stateExtent(at: index,
                                         elementKey: TBHoverAttrsKey,
                                         blockKey: TBHoverBlockAttrsKey,
                                         storage: storage)
                }
            }
        }
        if extent == hoverRange { return }   // already wearing it
        hoverRange = extent
        repaintStatePaint()
    }

    // Wear the three state layers (0.26): put the covered
    // paint back, then lay hover, focus and active down
    // in that order over one fresh snapshot, so the top
    // layer wins where they overlap and any change of
    // the set restores the page exactly.
    private func repaintStatePaint() {
        guard let storage = textStorage else { return }
        for entry in stateSaved
        where NSMaxRange(entry.range) <= storage.length {
            if let value = entry.value {
                storage.addAttribute(entry.key, value: value,
                                     range: entry.range)
            } else {
                storage.removeAttribute(entry.key, range: entry.range)
            }
        }
        stateSaved = []
        // The paint & motion set (0.27): the worn
        // layers' full traits — colors, background
        // layers, opacity, transforms — are collected
        // BEFORE anything is applied, so transitions
        // can start from what the page currently shows
        // (the restore above has just put the resting
        // paint back, which is the honest "from" for a
        // trait no state wore before), and the layout
        // manager can be handed the layers to paint.
        var targets: [String: TBWornTraits] = [:]
        var layerPaints: [(range: NSRange, box: TBBackgroundBox,
                           widen: Bool)] = []
        let layers: [(extent: NSRange?,
                      element: NSAttributedString.Key,
                      block: NSAttributedString.Key)] = [
            (hoverRange, TBHoverAttrsKey, TBHoverBlockAttrsKey),
            (focusRange, TBFocusAttrsKey, TBFocusBlockAttrsKey),
            (activeRange, TBActiveAttrsKey, TBActiveBlockAttrsKey)]
        for layer in layers {
            guard let extent = layer.extent else { continue }
            collectStateTraits(extent: extent, elementKey: layer.element,
                               blockKey: layer.block, storage: storage,
                               into: &targets, layerPaints: &layerPaints)
        }
        startTransitions(old: wornTargets, new: targets, storage: storage)
        wornTargets = targets
        let skips = transitionColorSkips()
        if let extent = hoverRange {
            stateSaved += applyStatePaint(
                extent: extent, elementKey: TBHoverAttrsKey,
                blockKey: TBHoverBlockAttrsKey, storage: storage,
                skips: skips)
        }
        if let extent = focusRange {
            stateSaved += applyStatePaint(
                extent: extent, elementKey: TBFocusAttrsKey,
                blockKey: TBFocusBlockAttrsKey, storage: storage,
                skips: skips)
        }
        if let extent = activeRange {
            stateSaved += applyStatePaint(
                extent: extent, elementKey: TBActiveAttrsKey,
                blockKey: TBActiveBlockAttrsKey, storage: storage,
                skips: skips)
        }
        if let band = layoutManager as? TBBandLayoutManager {
            band.stateLayerPaints = layerPaints
        }
        rebuildFXOverrides()
        stateTextLength = storage.length
        // A change that moves no attribute — a
        // transform arriving with no color trait —
        // damages nothing through the storage; ask for
        // the worn extents' repaint directly.
        for layer in layers {
            if let extent = layer.extent {
                invalidateTextRange(extent)
            }
        }
    }

    private func rangeKey(_ range: NSRange) -> String {
        "\(range.location):\(range.length)"
    }

    private func rangeFromKey(_ key: String) -> NSRange? {
        let parts = key.split(separator: ":")
        guard parts.count == 2, let location = Int(parts[0]),
              let length = Int(parts[1]) else { return nil }
        return NSRange(location: location, length: length)
    }

    // One worn layer's traits, run by run, in the same
    // shape applyStatePaint paints them: the element
    // stamp's traits over the block's, trait by trait.
    // Later layers override earlier ones property by
    // property, as their paint does.
    private func collectStateTraits(
        extent: NSRange, elementKey: NSAttributedString.Key,
        blockKey: NSAttributedString.Key, storage: NSTextStorage,
        into targets: inout [String: TBWornTraits],
        layerPaints: inout [(range: NSRange, box: TBBackgroundBox,
                             widen: Bool)]
    ) {
        let block = storage.attribute(blockKey, at: extent.location,
                                      effectiveRange: nil) as? TBHoverStyle
        storage.enumerateAttribute(elementKey, in: extent,
                                   options: []) { value, range, _ in
            let style = value as? TBHoverStyle
            var traits = targets[rangeKey(range)] ?? TBWornTraits()
            if let fg = style?.foregroundColor ?? block?.foregroundColor {
                traits.fg = fg
            }
            if let bg = style?.backgroundColor ?? block?.backgroundColor {
                traits.bg = bg
            }
            if let opacity = style?.opacityValue ?? block?.opacityValue {
                traits.opacity = opacity
            }
            if let transform = style?.transformSpec ?? block?.transformSpec {
                traits.transform = transform
            }
            targets[rangeKey(range)] = traits
            if let box = style?.backgroundBox ?? block?.backgroundBox {
                layerPaints.append((
                    range: range, box: box,
                    widen: style?.backgroundBox == nil
                        && block?.backgroundBox != nil))
            }
        }
    }

    // One layer's paint (0.23's applyHover, keyed since
    // 0.26): the traits reduced onto the extent's runs,
    // the element stamp's traits over the block's, trait
    // by trait. Returns the paint it covered, to be put
    // back by the next repaint.
    private func applyStatePaint(
        extent: NSRange, elementKey: NSAttributedString.Key,
        blockKey: NSAttributedString.Key, storage: NSTextStorage,
        skips: Set<String> = []
    ) -> [(key: NSAttributedString.Key, range: NSRange, value: Any?)] {
        let block = storage.attribute(blockKey, at: extent.location,
                                      effectiveRange: nil) as? TBHoverStyle
        let paintKeys: [NSAttributedString.Key] = [
            .foregroundColor, .backgroundColor,
            .underlineStyle, .strikethroughStyle]
        // Snapshot the paint this layer is about to cover,
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
        storage.enumerateAttribute(elementKey, in: extent,
                                   options: []) { value, range, _ in
            runs.append((range: range, style: value as? TBHoverStyle))
        }
        for run in runs {
            let fg = run.style?.foregroundColor ?? block?.foregroundColor
            let bg = run.style?.backgroundColor ?? block?.backgroundColor
            let ul = run.style?.underlineStyle ?? block?.underlineStyle
            let st = run.style?.strikethroughStyle
                ?? block?.strikethroughStyle
            // The paint & motion set (0.27): a color
            // property a running transition owns is not
            // applied here — the timer is writing it,
            // frame by frame, and will land it exactly.
            let runKey = "\(run.range.location):\(run.range.length)|"
            if let fg = fg, !skips.contains(runKey + "color") {
                storage.addAttribute(.foregroundColor, value: fg,
                                     range: run.range)
            }
            if let bg = bg, !skips.contains(runKey + "background-color") {
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
        return saved
    }

    // MARK: - Paint & motion (0.27)

    // The "range|property" keys of the color
    // transitions currently running — applyStatePaint
    // leaves those properties to the timer.
    private func transitionColorSkips() -> Set<String> {
        Set(transitions
            .filter { $0.property == "color"
                || $0.property == "background-color" }
            .map { "\($0.key)|\($0.property)" })
    }

    // Hand one property's transition over: build the
    // new run from the value currently shown (the
    // build closure reads the in-flight run before it
    // is replaced), then let it replace the old. No
    // spec entry for the property, or reduced motion,
    // and the change simply lands at once.
    private func replaceTransition(
        key: String, range: NSRange, property: String,
        spec: TBTransitionSpec?, reduced: Bool,
        build: (TBTransitionEntry) -> TBTransition
    ) {
        let built = (!reduced ? spec?.entry(for: property) : nil)
            .map(build)
        transitions.removeAll { $0.key == key && $0.property == property }
        if let built = built {
            transitions.append(built)
            ensureFXTimer()
        }
    }

    // Start (or hand off) the transitions a change of
    // worn traits calls for: for every run whose
    // traits changed, property by property, from what
    // the page currently shows to the new target —
    // the resting paint when a state has lifted.
    private func startTransitions(old: [String: TBWornTraits],
                                  new: [String: TBWornTraits],
                                  storage: NSTextStorage) {
        let reduced = NSWorkspace.shared
            .accessibilityDisplayShouldReduceMotion
        var keys = Set(old.keys)
        keys.formUnion(new.keys)
        for key in keys {
            guard let range = rangeFromKey(key),
                  NSMaxRange(range) <= storage.length else { continue }
            let oldT = old[key]
            let newT = new[key]
            let spec = storage.attribute(TBTransitionKey,
                                         at: range.location,
                                         effectiveRange: nil)
                as? TBTransitionSpec
            func restingColor(_ attr: NSAttributedString.Key) -> NSColor? {
                storage.attribute(attr, at: range.location,
                                  effectiveRange: nil) as? NSColor
            }
            func restingOpacity() -> CGFloat? {
                (storage.attribute(TBOpacityKey, at: range.location,
                                   effectiveRange: nil)
                    as? TBOpacitySpec)?.value
            }
            func restingTransform() -> TBTransformSpec? {
                storage.attribute(TBTransformKey, at: range.location,
                                  effectiveRange: nil) as? TBTransformSpec
            }
            if !tbColorsEqual(oldT?.fg, newT?.fg) {
                replaceTransition(key: key, range: range, property: "color",
                                  spec: spec, reduced: reduced) { entry in
                    TBTransition(
                        key: key, range: range, property: "color",
                        fromColor: transitions.first {
                            $0.key == key && $0.property == "color"
                        }?.currentColor(at: Date())
                            ?? oldT?.fg ?? restingColor(.foregroundColor),
                        toColor: newT?.fg ?? restingColor(.foregroundColor),
                        start: Date(), duration: entry.duration,
                        delay: entry.delay, timing: entry.timing)
                }
            }
            if !tbColorsEqual(oldT?.bg, newT?.bg) {
                replaceTransition(key: key, range: range,
                                  property: "background-color",
                                  spec: spec, reduced: reduced) { entry in
                    TBTransition(
                        key: key, range: range,
                        property: "background-color",
                        fromColor: transitions.first {
                            $0.key == key
                                && $0.property == "background-color"
                        }?.currentColor(at: Date())
                            ?? oldT?.bg ?? restingColor(.backgroundColor),
                        toColor: newT?.bg
                            ?? restingColor(.backgroundColor),
                        start: Date(), duration: entry.duration,
                        delay: entry.delay, timing: entry.timing)
                }
            }
            if oldT?.opacity != newT?.opacity {
                replaceTransition(key: key, range: range, property: "opacity",
                                  spec: spec, reduced: reduced) { entry in
                    TBTransition(
                        key: key, range: range, property: "opacity",
                        fromOpacity: transitions.first {
                            $0.key == key && $0.property == "opacity"
                        }?.currentOpacity(at: Date())
                            ?? oldT?.opacity ?? restingOpacity(),
                        toOpacity: newT?.opacity ?? restingOpacity(),
                        start: Date(), duration: entry.duration,
                        delay: entry.delay, timing: entry.timing)
                }
            }
            if oldT?.transform !== newT?.transform {
                replaceTransition(key: key, range: range,
                                  property: "transform",
                                  spec: spec, reduced: reduced) { entry in
                    TBTransition(
                        key: key, range: range, property: "transform",
                        fromTransform: transitionFX[key]?.transform
                            ?? oldT?.transform ?? restingTransform(),
                        toTransform: newT?.transform ?? restingTransform(),
                        start: Date(), duration: entry.duration,
                        delay: entry.delay, timing: entry.timing)
                }
            }
        }
    }

    // Recompose the layout manager's effects table
    // from its three sources, in paint order: keyframe
    // runs at the bottom, the worn states' traits over
    // them, and running transitions on top — a
    // property a transition owns is the transition's
    // current value, never the state's resting target.
    private func rebuildFXOverrides() {
        guard let band = layoutManager as? TBBandLayoutManager
        else { return }
        var list: [(range: NSRange, opacity: CGFloat?,
                    transform: TBTransformSpec?)] = []
        list += keyframeFX
        for (key, traits) in wornTargets {
            guard let range = rangeFromKey(key) else { continue }
            let opacityOwned = transitions.contains {
                $0.key == key && $0.property == "opacity"
            }
            let transformOwned = transitions.contains {
                $0.key == key && $0.property == "transform"
            }
            let opacity = opacityOwned ? nil : traits.opacity
            let transform = transformOwned ? nil : traits.transform
            if opacity != nil || transform != nil {
                list.append((range: range, opacity: opacity,
                             transform: transform))
            }
        }
        for (key, fx) in transitionFX {
            guard let range = rangeFromKey(key) else { continue }
            if fx.opacity != nil || fx.transform != nil {
                list.append((range: range, opacity: fx.opacity,
                             transform: fx.transform))
            }
        }
        band.fxOverrides = list
    }

    // The one timer: created on demand, and — the
    // discipline the set stands on — invalidated by
    // the tick itself the moment nothing is left
    // animating. A page with no motion has no timer.
    private func ensureFXTimer() {
        if fxTimer != nil { return }
        fxTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0,
                                       repeats: true) { [weak self] _ in
            self?.fxTick()
        }
    }

    private func fxTick() {
        guard let storage = textStorage else {
            fxTimer?.invalidate()
            fxTimer = nil
            return
        }
        // A hidden window's animations wait — the tick
        // costs a guard and nothing else.
        if let window = window,
           !window.occlusionState.contains(.visible) { return }
        let now = Date()
        var dirty: [NSRange] = []
        var running: [TBTransition] = []
        for tr in transitions {
            let p = tr.progress(at: now)
            let e = tr.timing.evaluate(p)
            dirty.append(tr.range)
            switch tr.property {
            case "color", "background-color":
                let attr: NSAttributedString.Key = tr.property == "color"
                    ? .foregroundColor : .backgroundColor
                if p >= 1 {
                    if let to = tr.toColor {
                        storage.addAttribute(attr, value: to,
                                             range: tr.range)
                    } else {
                        storage.removeAttribute(attr, range: tr.range)
                    }
                } else if let from = tr.fromColor, let to = tr.toColor {
                    storage.addAttribute(
                        attr, value: tbLerpColor(from, to, CGFloat(e)),
                        range: tr.range)
                    running.append(tr)
                } else if let from = tr.fromColor {
                    // A color leaving for no color fades
                    // out through its own alpha.
                    storage.addAttribute(
                        attr,
                        value: tbLerpColor(
                            from, from.withAlphaComponent(0), CGFloat(e)),
                        range: tr.range)
                    running.append(tr)
                } else if let to = tr.toColor {
                    storage.addAttribute(
                        attr,
                        value: tbLerpColor(
                            to.withAlphaComponent(0), to, CGFloat(e)),
                        range: tr.range)
                    running.append(tr)
                } else if p < 1 {
                    running.append(tr)
                }
            case "opacity":
                if p >= 1 {
                    if var fx = transitionFX[tr.key] {
                        fx.opacity = nil
                        transitionFX[tr.key] = fx
                    }
                } else {
                    let from = tr.fromOpacity ?? 1
                    let to = tr.toOpacity ?? 1
                    transitionFX[tr.key] = (
                        opacity: from + (to - from) * CGFloat(e),
                        transform: transitionFX[tr.key]?.transform)
                    running.append(tr)
                }
            case "transform":
                if p >= 1 {
                    if var fx = transitionFX[tr.key] {
                        fx.transform = nil
                        transitionFX[tr.key] = fx
                    }
                } else {
                    transitionFX[tr.key] = (
                        opacity: transitionFX[tr.key]?.opacity,
                        transform: tbLerpTransforms(
                            tr.fromTransform, tr.toTransform, CGFloat(e),
                            pivotRect: fxPivotRect(for: tr.range)))
                    running.append(tr)
                }
            default:
                if p < 1 { running.append(tr) }
            }
        }
        transitions = running
        advanceKeyframes(now: now, storage: storage, dirty: &dirty)
        rebuildFXOverrides()
        for range in dirty {
            invalidateTextRange(range)
        }
        if transitions.isEmpty && keyframeAnims.isEmpty {
            fxTimer?.invalidate()
            fxTimer = nil
        }
    }

    // Advance every keyframe run to now: the cycle
    // position through the spec's direction and
    // timing, the surrounding stops' traits
    // interpolated — a trait a stop does not name
    // reads from the element's resting paint, as CSS
    // directs — colors written over the resting
    // snapshot's own runs, opacity and transforms
    // through the effects table. A finished run puts
    // its resting paint back and is gone (fill modes
    // are not read).
    private func advanceKeyframes(now: Date, storage: NSTextStorage,
                                  dirty: inout [NSRange]) {
        guard !keyframeAnims.isEmpty else { return }
        var alive: [TBKeyframeAnim] = []
        for anim in keyframeAnims {
            let spec = anim.spec
            let elapsed = now.timeIntervalSince(anim.start) - spec.delay
            if elapsed < 0 {
                alive.append(anim)
                continue
            }
            let cycle = elapsed / spec.duration
            if spec.iterations.isFinite && cycle >= spec.iterations {
                restoreKeyframeResting(anim, storage: storage)
                keyframeFX.removeAll { $0.range == anim.range }
                dirty.append(anim.range)
                continue
            }
            dirty.append(anim.range)
            let iteration = cycle.rounded(.down)
            var frac = cycle - iteration
            let reversed: Bool
            switch spec.direction {
            case "reverse": reversed = true
            case "alternate":
                reversed = iteration.truncatingRemainder(dividingBy: 2) == 1
            case "alternate-reverse":
                reversed = iteration.truncatingRemainder(dividingBy: 2) == 0
            default: reversed = false
            }
            if reversed { frac = 1 - frac }
            let eased = spec.timing.evaluate(frac)
            var lower = spec.stops.first
            var upper = spec.stops.last
            for stop in spec.stops {
                if stop.offset <= eased { lower = stop }
                if stop.offset >= eased { upper = stop; break }
            }
            let span = (upper?.offset ?? 1) - (lower?.offset ?? 0)
            let local = span > 0
                ? CGFloat((eased - (lower?.offset ?? 0)) / span) : 1
            let lt = lower?.traits
            let ut = upper?.traits
            if lt?.foreground != nil || ut?.foreground != nil
                || lt?.background != nil || ut?.background != nil {
                for rest in anim.resting {
                    if lt?.foreground != nil || ut?.foreground != nil {
                        let a = lt?.foreground ?? rest.fg
                        let b = ut?.foreground ?? rest.fg
                        if let a = a, let b = b {
                            storage.addAttribute(
                                .foregroundColor,
                                value: tbLerpColor(a, b, local),
                                range: rest.range)
                        }
                    }
                    if lt?.background != nil || ut?.background != nil {
                        let a = lt?.background ?? rest.bg
                        let b = ut?.background ?? rest.bg
                        if let a = a, let b = b {
                            storage.addAttribute(
                                .backgroundColor,
                                value: tbLerpColor(a, b, local),
                                range: rest.range)
                        }
                    }
                }
            }
            var fxOpacity: CGFloat? = nil
            var fxTransform: TBTransformSpec? = nil
            if lt?.opacity != nil || ut?.opacity != nil {
                let a = lt?.opacity ?? anim.restingOpacity ?? 1
                let b = ut?.opacity ?? anim.restingOpacity ?? 1
                fxOpacity = a + (b - a) * local
            }
            if lt?.transform != nil || ut?.transform != nil {
                fxTransform = tbLerpTransforms(
                    lt?.transform ?? anim.restingTransform,
                    ut?.transform ?? anim.restingTransform,
                    local, pivotRect: fxPivotRect(for: anim.range))
            }
            keyframeFX.removeAll { $0.range == anim.range }
            if fxOpacity != nil || fxTransform != nil {
                keyframeFX.append((range: anim.range, opacity: fxOpacity,
                                   transform: fxTransform))
            }
            alive.append(anim)
        }
        keyframeAnims = alive
    }

    private func restoreKeyframeResting(_ anim: TBKeyframeAnim,
                                        storage: NSTextStorage) {
        for rest in anim.resting {
            if let fg = rest.fg {
                storage.addAttribute(.foregroundColor, value: fg,
                                     range: rest.range)
            } else {
                storage.removeAttribute(.foregroundColor,
                                        range: rest.range)
            }
            if let bg = rest.bg {
                storage.addAttribute(.backgroundColor, value: bg,
                                     range: rest.range)
            } else {
                storage.removeAttribute(.backgroundColor,
                                        range: rest.range)
            }
        }
    }

    // Find the new text's keyframe runs and snapshot
    // the resting paint each will borrow traits from
    // and return to. Reduced motion discovers
    // nothing — and the engine stamps nothing then
    // either, so the page simply rests.
    private func discoverAnimations() {
        keyframeAnims = []
        keyframeFX = []
        guard let storage = textStorage, storage.length > 0,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(TBAnimationKey, in: full,
                                   options: []) { value, range, _ in
            guard let spec = value as? TBAnimationSpec else { return }
            var cuts = Set<Int>([range.location, NSMaxRange(range)])
            for attr in [NSAttributedString.Key.foregroundColor,
                         .backgroundColor] {
                storage.enumerateAttribute(attr, in: range,
                                           options: []) { _, r, _ in
                    cuts.insert(r.location)
                    cuts.insert(NSMaxRange(r))
                }
            }
            let points = cuts.sorted()
            var resting: [(range: NSRange, fg: NSColor?,
                           bg: NSColor?)] = []
            for i in 0..<(points.count - 1)
            where points[i + 1] > points[i] {
                let sub = NSRange(location: points[i],
                                  length: points[i + 1] - points[i])
                resting.append((
                    range: sub,
                    fg: storage.attribute(.foregroundColor, at: sub.location,
                                          effectiveRange: nil) as? NSColor,
                    bg: storage.attribute(.backgroundColor, at: sub.location,
                                          effectiveRange: nil) as? NSColor))
            }
            let restingOpacity = (storage.attribute(
                TBOpacityKey, at: range.location,
                effectiveRange: nil) as? TBOpacitySpec)?.value
            let restingTransform = storage.attribute(
                TBTransformKey, at: range.location,
                effectiveRange: nil) as? TBTransformSpec
            keyframeAnims.append(TBKeyframeAnim(
                range: range, spec: spec, start: Date(),
                resting: resting, restingOpacity: restingOpacity,
                restingTransform: restingTransform))
        }
        if !keyframeAnims.isEmpty {
            ensureFXTimer()
        }
    }

    // A transform interpolation (0.27): the two
    // specs' matrices resolved at the range's own
    // rect and blended component by component — the
    // working approximation every small engine makes;
    // true matrix decomposition is not attempted.
    private func tbLerpTransforms(_ a: TBTransformSpec?,
                                  _ b: TBTransformSpec?,
                                  _ t: CGFloat,
                                  pivotRect: NSRect) -> TBTransformSpec? {
        guard a != nil || b != nil else { return nil }
        let ma = a?.matrix(in: pivotRect) ?? .identity
        let mb = b?.matrix(in: pivotRect) ?? .identity
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            x + (y - x) * t
        }
        let spec = TBTransformSpec()
        spec.resolvedMatrix = CGAffineTransform(
            a: mix(ma.a, mb.a), b: mix(ma.b, mb.b),
            c: mix(ma.c, mb.c), d: mix(ma.d, mb.d),
            tx: mix(ma.tx, mb.tx), ty: mix(ma.ty, mb.ty))
        spec.originX = (a ?? b)?.originX ?? .percent(50)
        spec.originY = (a ?? b)?.originY ?? .percent(50)
        return spec
    }

    // The range's own rect in container coordinates,
    // from its line fragments — the box a transform
    // interpolation resolves percentages against.
    private func fxPivotRect(for range: NSRange) -> NSRect {
        guard let band = layoutManager as? TBBandLayoutManager,
              let storage = textStorage, storage.length > 0,
              range.location < storage.length else { return .zero }
        let glyphs = band.glyphRange(forCharacterRange: range,
                                     actualCharacterRange: nil)
        var union = NSRect.null
        if glyphs.length > 0 {
            band.enumerateLineFragments(forGlyphRange: glyphs) {
                _, usedRect, _, _, _ in
                union = union.union(usedRect)
            }
        }
        return union.isNull ? .zero : union
    }

    // Ask for one range's repaint, widened past its
    // fragments — a transform or a shadow spills
    // beyond the glyphs' own boxes.
    private func invalidateTextRange(_ range: NSRange) {
        guard let band = layoutManager as? TBBandLayoutManager,
              let storage = textStorage, storage.length > 0,
              range.location < storage.length else { return }
        let clamped = NSIntersectionRange(
            range, NSRange(location: 0, length: storage.length))
        guard clamped.length > 0 else { return }
        let glyphs = band.glyphRange(forCharacterRange: clamped,
                                     actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        var union = NSRect.null
        band.enumerateLineFragments(forGlyphRange: glyphs) {
            _, usedRect, _, _, _ in
            union = union.union(usedRect)
        }
        guard !union.isNull else { return }
        let rect = NSRect(x: textContainerOrigin.x + union.minX,
                          y: textContainerOrigin.y + union.minY,
                          width: union.width, height: union.height)
            .insetBy(dx: -28, dy: -28)
        setNeedsDisplay(rect, avoidAdditionalLayout: true)
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
    // The paint & motion set (0.27): the box's shadows,
    // paint transform and opacity.
    var boxShadows: TBBoxShadowSet? { get }
    var transformSpec: TBTransformSpec? { get }
    var opacityValue: CGFloat { get }
}

// A transform-origin component against its base
// (0.27): points are themselves; a percentage is that
// share of the base.
func tbInsetPoints(_ value: TBInsetValue, base: CGFloat) -> CGFloat {
    switch value {
    case .points(let p): return p
    case .percent(let pct): return base * pct / 100
    }
}

// Interpolate two colors in sRGB (0.27), the space
// the paint traits are compared and blended in.
func tbLerpColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    guard let ca = a.usingColorSpace(.sRGB),
          let cb = b.usingColorSpace(.sRGB)
    else { return t < 0.5 ? a : b }
    func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
    return NSColor(srgbRed: mix(ca.redComponent, cb.redComponent),
                   green: mix(ca.greenComponent, cb.greenComponent),
                   blue: mix(ca.blueComponent, cb.blueComponent),
                   alpha: mix(ca.alphaComponent, cb.alphaComponent))
}

func tbColorsEqual(_ a: NSColor?, _ b: NSColor?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x?, y?):
        guard let cx = x.usingColorSpace(.sRGB),
              let cy = y.usingColorSpace(.sRGB)
        else { return x.isEqual(y) }
        return abs(cx.redComponent - cy.redComponent) < 0.004
            && abs(cx.greenComponent - cy.greenComponent) < 0.004
            && abs(cx.blueComponent - cy.blueComponent) < 0.004
            && abs(cx.alphaComponent - cy.alphaComponent) < 0.004
    default: return false
    }
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
    // The interaction set (0.26): the sticky shifts the
    // coordinator has resolved for this page, keyed by
    // spec — a spec absent here, and every box-content
    // manager (which never receives any), paints its
    // sticky runs at their flow seat.
    var stickyShifts: [ObjectIdentifier: CGFloat] = [:]
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
    // from the stamp the renderer left on the text. The
    // interaction set (0.26): a sticky element's shift
    // rides the same path, added to any relative offset —
    // the coordinator resolves the shifts against the
    // scroll position (repositionStickyElements) and
    // hands them over in stickyShifts.
    // The paint & motion set (0.27): what the text
    // view hands this manager to paint — the state
    // background layers currently worn (in wearing
    // order), and the effects table: opacity and
    // transform overrides over ranges, composed by the
    // view from worn states, running transitions and
    // keyframe animations, later entries winning. The
    // surface rect of each stamped transform is also
    // recorded as its band paints, for the glyph
    // path's pivot.
    var stateLayerPaints: [(range: NSRange, box: TBBackgroundBox,
                            widen: Bool)] = []
    var fxOverrides: [(range: NSRange, opacity: CGFloat?,
                       transform: TBTransformSpec?)] = []
    var transformPivots: [ObjectIdentifier: NSRect] = [:]

    func fxTraits(at charIndex: Int)
        -> (opacity: CGFloat?, transform: TBTransformSpec?) {
        var opacity: CGFloat? = nil
        var transform: TBTransformSpec? = nil
        for entry in fxOverrides.reversed()
        where charIndex >= entry.range.location
            && charIndex < NSMaxRange(entry.range) {
            if opacity == nil { opacity = entry.opacity }
            if transform == nil { transform = entry.transform }
            if opacity != nil && transform != nil { break }
        }
        return (opacity, transform)
    }

    // The full paint affine for a transform about a
    // pivot rect, in the rect's own coordinate space:
    // translate(pivot) · matrix · translate(−pivot),
    // composed arithmetically, so drawing code only
    // ever concatenates one finished transform.
    static func fxAffine(for spec: TBTransformSpec,
                         pivotRect: NSRect) -> CGAffineTransform {
        let m = spec.matrix(in: pivotRect)
        let px = pivotRect.minX
            + tbInsetPoints(spec.originX, base: pivotRect.width)
        let py = pivotRect.minY
            + tbInsetPoints(spec.originY, base: pivotRect.height)
        return CGAffineTransform(
            a: m.a, b: m.b, c: m.c, d: m.d,
            tx: m.tx + px - m.a * px - m.c * py,
            ty: m.ty + py - m.b * px - m.d * py)
    }

    // Outer box shadows under a box (0.27): each
    // shadow is its rect outset by the spread and
    // shifted by the offset, filled with the shadow
    // color under the shadow's own blur — but clipped
    // to everywhere EXCEPT the box itself, so the
    // shadow never paints inside the box it belongs
    // to, exactly as CSS draws it. First-listed
    // shadows paint last (on top). No shadow is ever
    // issued for a rect with no area.
    static func paintBoxShadows(_ set: TBBoxShadowSet, in rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        for shadow in set.shadows.reversed() {
            let shape = rect.insetBy(dx: -shadow.spread,
                                     dy: -shadow.spread)
                .offsetBy(dx: shadow.dx, dy: shadow.dy)
            guard shape.width > 0, shape.height > 0 else { continue }
            let cover = shape.insetBy(dx: -(shadow.blur * 2 + 8),
                                      dy: -(shadow.blur * 2 + 8))
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: cover)
            clip.append(NSBezierPath(rect: rect))
            clip.windingRule = .evenOdd
            clip.addClip()
            if shadow.blur > 0 {
                let ns = NSShadow()
                ns.shadowColor = shadow.color
                ns.shadowBlurRadius = shadow.blur
                ns.shadowOffset = .zero
                ns.set()
            }
            shadow.color.setFill()
            NSBezierPath(rect: shape).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // Text shadows under a private layout's glyphs
    // (0.27): for each stamped run, the glyphs drawn
    // once per shadow, shifted by the shadow's offset,
    // blurred by its radius when it has one, and
    // colored by the shadow's color through the
    // manager's temporary attributes — the text
    // storage itself is never touched.
    static func paintTextShadows(manager: NSLayoutManager,
                                 glyphRange: NSRange, at origin: NSPoint) {
        guard let storage = manager.textStorage, storage.length > 0
        else { return }
        let chars = manager.characterRange(forGlyphRange: glyphRange,
                                           actualGlyphRange: nil)
        storage.enumerateAttribute(TBTextShadowKey, in: chars) {
            value, range, _ in
            guard let set = value as? TBTextShadowSet else { return }
            let glyphs = manager.glyphRange(forCharacterRange: range,
                                            actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            for shadow in set.shadows.reversed() {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext
                    .translateBy(x: shadow.dx, y: shadow.dy)
                if shadow.blur > 0 {
                    let ns = NSShadow()
                    ns.shadowColor = shadow.color
                    ns.shadowBlurRadius = shadow.blur
                    ns.shadowOffset = .zero
                    ns.set()
                }
                manager.setTemporaryAttributes(
                    [.foregroundColor: shadow.color],
                    forCharacterRange: range)
                manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
                manager.removeTemporaryAttribute(
                    .foregroundColor, forCharacterRange: range)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    private func paintOffset(at charIndex: Int, in storage: NSTextStorage) -> NSPoint {
        guard storage.length > 0 else { return .zero }
        let clamped = min(max(charIndex, 0), storage.length - 1)
        var point = NSPoint.zero
        if let value = storage.attribute(TBRelOffsetKey, at: clamped,
                                         effectiveRange: nil) as? NSValue {
            point = value.pointValue
        }
        if !stickyShifts.isEmpty,
           let spec = storage.attribute(TBStickyKey, at: clamped,
                                        effectiveRange: nil) as? TBStickySpec,
           let dy = stickyShifts[ObjectIdentifier(spec)] {
            point.y += dy
        }
        return point
    }

    // The paint & motion set (0.27): a run's
    // background fill takes its element's opacity and
    // paint transform with it — the transform about
    // the run's own surface rect where one was
    // recorded, else about the run's line fragments,
    // in the coordinates the fills are handed over
    // in. The fill below is the one this class has
    // always made, wrapped.
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>,
                                          count rectCount: Int,
                                          forCharacterRange charRange: NSRange,
                                          color: NSColor) {
        guard rectCount > 0, let storage = textStorage,
              storage.length > 0, charRange.location < storage.length
        else {
            super.fillBackgroundRectArray(rectArray, count: rectCount,
                                          forCharacterRange: charRange,
                                          color: color)
            return
        }
        let fx = fxTraits(at: charRange.location)
        let transform = fx.transform
            ?? storage.attribute(TBTransformKey, at: charRange.location,
                                 effectiveRange: nil) as? TBTransformSpec
        let opacity = fx.opacity
            ?? (storage.attribute(TBOpacityKey, at: charRange.location,
                                  effectiveRange: nil)
                as? TBOpacitySpec)?.value
        guard transform != nil || (opacity != nil && opacity! < 1) else {
            fillBackgroundRectArrayUnwrapped(
                rectArray, count: rectCount,
                forCharacterRange: charRange, color: color)
            return
        }
        NSGraphicsContext.saveGraphicsState()
        if let opacity = opacity, opacity < 1 {
            NSGraphicsContext.current?.cgContext.setAlpha(opacity)
        }
        if let transform = transform {
            NSGraphicsContext.current?.cgContext.concatenate(
                TBBandLayoutManager.fxAffine(
                    for: transform,
                    pivotRect: fillPivotRect(charRange: charRange,
                                             spec: transform)))
        }
        fillBackgroundRectArrayUnwrapped(
            rectArray, count: rectCount,
            forCharacterRange: charRange, color: color)
        NSGraphicsContext.restoreGraphicsState()
    }

    // The pivot rect for a run's fill transform: the
    // band rect recorded when its surface painted,
    // else the union of the run's line fragments —
    // both in the fills' own coordinates (the band
    // painter's convention: the origin joins x, the
    // fragments carry y).
    private func fillPivotRect(charRange: NSRange,
                               spec: TBTransformSpec) -> NSRect {
        if let cached = transformPivots[ObjectIdentifier(spec)],
           let view = textContainers.first?.textView {
            return NSRect(x: view.textContainerOrigin.x + cached.minX,
                          y: cached.minY,
                          width: cached.width, height: cached.height)
        }
        let glyphs = glyphRange(forCharacterRange: charRange,
                                actualCharacterRange: nil)
        var union = NSRect.null
        if glyphs.length > 0 {
            enumerateLineFragments(forGlyphRange: glyphs) {
                _, usedRect, _, _, _ in
                union = union.union(usedRect)
            }
        }
        guard !union.isNull,
              let view = textContainers.first?.textView
        else { return .zero }
        return NSRect(x: view.textContainerOrigin.x + union.minX,
                      y: union.minY,
                      width: union.width, height: union.height)
    }

    private func fillBackgroundRectArrayUnwrapped(_ rectArray: UnsafePointer<NSRect>,
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
        paintStateLayers(at: origin)
    }

    // State background layers (0.27): the layer boxes
    // the text view registered for the states currently
    // worn, painted in wearing order over everything
    // else the background pass drew — the layers belong
    // to the worn state, as its colors do, and they
    // lift with it. Each paints into its range's line
    // fragments; a box that came from a block stamp
    // widens to the container, as the state's color
    // does on a band.
    private func paintStateLayers(at origin: NSPoint) {
        guard !stateLayerPaints.isEmpty,
              let storage = textStorage, storage.length > 0,
              let container = textContainers.first else { return }
        for entry in stateLayerPaints {
            let range = NSIntersectionRange(
                entry.range, NSRange(location: 0, length: storage.length))
            guard range.length > 0 else { continue }
            let glyphs = glyphRange(forCharacterRange: range,
                                    actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            if entry.widen {
                // The banding repair (0.29): a block stamp's
                // layers paint ONCE, into the union of its
                // fragment rects — the block's whole extent,
                // margins bridged as the surface painter
                // bridges them — never once per line. A
                // photo or gradient anchored to a single
                // line's rect re-anchors at every line of
                // the block, slicing a multi-line block's
                // hover background into bands exactly as
                // the surface painter's range-sliced paints
                // once did (see paintContinuousSurfaces).
                var union = NSRect.null
                enumerateLineFragments(forGlyphRange: glyphs) {
                    _, usedRect, _, _, _ in
                    union = union.union(NSRect(
                        x: origin.x, y: origin.y + usedRect.minY,
                        width: container.size.width,
                        height: usedRect.height))
                }
                if !union.isNull {
                    TBBandLayoutManager.paintBackgroundLayers(entry.box,
                                                              in: union)
                }
                continue
            }
            enumerateLineFragments(forGlyphRange: glyphs) {
                _, usedRect, _, _, _ in
                let rect = NSRect(x: origin.x + usedRect.minX,
                                  y: origin.y + usedRect.minY,
                                  width: usedRect.width,
                                  height: usedRect.height)
                TBBandLayoutManager.paintBackgroundLayers(entry.box,
                                                          in: rect)
            }
        }
    }

    // One paragraph's surface band, as the surface
    // painter below reckons bands: its fill color, layer
    // box and shadow set (each read at the paragraph's
    // last character, where its closing separator
    // carries the stamps), the band's span — its line
    // fragments widened by the surface-edge extensions
    // stamped on it — its relative offset, and the
    // effects table's opacity and transform for it.
    private typealias TBSurfaceBand = (color: NSColor?,
                                       box: TBBackgroundBox?,
                                       boxID: ObjectIdentifier?,
                                       top: CGFloat, bottom: CGFloat,
                                       dx: CGFloat, dy: CGFloat,
                                       shadowSet: TBBoxShadowSet?,
                                       shadowID: ObjectIdentifier?,
                                       transform: TBTransformSpec?,
                                       transformID: ObjectIdentifier?,
                                       opacity: CGFloat)

    // A paragraph's line-fragment span, band or not —
    // the growth walk in paintContinuousSurfaces
    // measures unstamped paragraphs by it.
    private func paragraphSpan(paragraph: NSRange)
        -> (top: CGFloat, bottom: CGFloat)? {
        var top: CGFloat? = nil
        var bottom: CGFloat = 0
        let pGlyphs = glyphRange(forCharacterRange: paragraph,
                                 actualCharacterRange: nil)
        enumerateLineFragments(forGlyphRange: pGlyphs) {
            rect, _, _, _, _ in
            if top == nil { top = rect.minY }
            bottom = rect.maxY
        }
        guard let top = top else { return nil }
        return (top, bottom)
    }

    private func surfaceBand(storage: NSTextStorage, paragraph: NSRange,
                             canvas: NSColor) -> TBSurfaceBand? {
        let lastIndex = paragraph.location + paragraph.length - 1
        let box = storage.attribute(TBBackgroundKey, at: lastIndex,
                                    effectiveRange: nil) as? TBBackgroundBox
        let surface = surfaceColor(storage: storage, paragraph: paragraph)
        let fill = (surface != nil && !surface!.isEqual(canvas)) ? surface : nil
        // The paint & motion set (0.27): a paragraph can
        // carry a surface for its shadow's sake alone —
        // the stamps ride at its last character, where
        // the layer box rides.
        let shadowSet = storage.attribute(TBBoxShadowKey,
                                          at: lastIndex,
                                          effectiveRange: nil)
            as? TBBoxShadowSet
        guard fill != nil || box != nil || shadowSet != nil,
              let span = paragraphSpan(paragraph: paragraph) else {
            return nil
        }
        // Surface edges (0.15): the surface's first
        // paragraph carries the inside space above it,
        // its last the space below — extend the band
        // through both, so a padded container's color
        // and photo reach their true edges.
        let extTop = (storage.attribute(TBExtTopKey, at: paragraph.location,
                                        effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
        let extBottom = (storage.attribute(TBExtBottomKey, at: paragraph.location,
                                           effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
        let boxID = box.map { ObjectIdentifier($0) }
        // The effects table (worn states, transitions,
        // keyframe runs) overrides the paragraph's own
        // stamps — an animated surface fades and moves
        // as one piece, band and glyphs together.
        let bandFX = fxTraits(at: lastIndex)
        let transform = bandFX.transform
            ?? storage.attribute(TBTransformKey,
                                 at: lastIndex,
                                 effectiveRange: nil)
            as? TBTransformSpec
        let opacity = bandFX.opacity
            ?? (storage.attribute(TBOpacityKey,
                                  at: lastIndex,
                                  effectiveRange: nil)
            as? TBOpacitySpec)?.value ?? 1
        // Positioned layout (0.17): a relatively offset
        // surface paints shifted, as one band of its own.
        let offset = paintOffset(at: paragraph.location, in: storage)
        return (color: fill, box: box, boxID: boxID,
                top: span.top - CGFloat(extTop),
                bottom: span.bottom + CGFloat(extBottom),
                dx: offset.x, dy: offset.y,
                shadowSet: shadowSet,
                shadowID: shadowSet.map { ObjectIdentifier($0) },
                transform: transform,
                transformID: transform.map { ObjectIdentifier($0) },
                opacity: opacity)
    }

    // Whether two bands carry the same surface — the
    // coalescing rule in paintContinuousSurfaces, word
    // for word, so the growth walk there extends a run
    // exactly where a whole-range pass would merge the
    // band and stops exactly where it would not. (The
    // 64-point reach itself is tested by the caller,
    // whose two bands stand in a known order.)
    private func surfaceCompatible(_ a: TBSurfaceBand,
                                   _ b: TBSurfaceBand) -> Bool {
        a.boxID == b.boxID && a.shadowID == b.shadowID
            && a.transformID == b.transformID
            && a.opacity == b.opacity && a.dx == b.dx && a.dy == b.dy
            && ((a.color == nil && b.color == nil)
                || (a.color != nil && b.color != nil
                    && a.color!.isEqual(b.color!)))
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
        var bands: [TBSurfaceBand] = []
        var firstPara: NSRange? = nil
        var lastPara: NSRange? = nil
        var index = charRange.location
        let end = min(NSMaxRange(charRange), string.length)
        while index < end {
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            if paragraph.length == 0 { break }
            if firstPara == nil { firstPara = paragraph }
            lastPara = paragraph
            if let band = surfaceBand(storage: storage, paragraph: paragraph,
                                      canvas: canvas) {
                bands.append(band)
            }
            index = NSMaxRange(paragraph)
        }
        // The banding repair (0.29): grow the band list
        // outward to the whole surface run this draw
        // touches, before coalescing. A surface's
        // decomposition — which of its paragraphs merge,
        // and the one rect its photo and gradient layers
        // anchor to — must never depend on which
        // paragraphs this draw was asked for: AppKit
        // repaints in slices (a scroll exposes a strip
        // at a time; the state and motion machinery
        // invalidates one element's range at a time),
        // and a run computed from a slice anchors its
        // layers to the slice. The slices then disagree,
        // and the disagreement is what showed: a hero
        // photo restarting at every repaint boundary,
        // and a color fill bridged across an
        // unbackgrounded paragraph in one draw but
        // clipped to half of it in the next, its other
        // half left erased. Grown whole, every draw
        // computes the same surfaces and the same
        // anchors, and lays down exactly the pixels a
        // full pass lays down — the graphics context
        // still clips the paint to the region asked
        // for. The walk tests each neighbouring band
        // with the coalescing rule itself, so it
        // extends a run precisely where a whole-range
        // pass would merge and stops precisely where
        // it would not; a paragraph carrying no surface
        // spends only distance, measured on its own
        // fragment span, and the walk stops once no
        // band beyond it could still reach the run.
        if !bands.isEmpty, let firstPara = firstPara,
           let lastPara = lastPara {
            var edge = bands.first!
            var cursor = firstPara
            while cursor.location > 0 {
                let prev = string.paragraphRange(
                    for: NSRange(location: cursor.location - 1, length: 0))
                if prev.length == 0 { break }
                if let cand = surfaceBand(storage: storage,
                                          paragraph: prev,
                                          canvas: canvas) {
                    guard surfaceCompatible(cand, edge),
                          edge.top - cand.bottom <= 64 else { break }
                    bands.insert(cand, at: 0)
                    edge = cand
                } else {
                    guard let span = paragraphSpan(paragraph: prev),
                          edge.top - span.top <= 64 else { break }
                }
                cursor = prev
            }
            var edgeF = bands.last!
            var cursorF = lastPara
            while NSMaxRange(cursorF) < string.length {
                let next = string.paragraphRange(
                    for: NSRange(location: NSMaxRange(cursorF), length: 0))
                if next.length == 0 { break }
                if let cand = surfaceBand(storage: storage,
                                          paragraph: next,
                                          canvas: canvas) {
                    guard surfaceCompatible(edgeF, cand),
                          cand.top - edgeF.bottom <= 64 else { break }
                    bands.append(cand)
                    edgeF = cand
                } else {
                    guard let span = paragraphSpan(paragraph: next),
                          span.bottom - edgeF.bottom <= 64 else { break }
                }
                cursorF = next
            }
        }

        if bands.isEmpty { return }
        // Coalesce neighbouring bands that share a surface
        // (same color, same layer box) across the ordinary
        // spacing between paragraphs, so one element's
        // background reads as one continuous surface.
        var surfaces: [TBSurfaceBand] = []
        for band in bands {
            if let last = surfaces.last, last.boxID == band.boxID,
               last.shadowID == band.shadowID,
               last.transformID == band.transformID,
               last.opacity == band.opacity,
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
            // The paint & motion set (0.27): the band's
            // shadows paint under its fill, and its
            // opacity and transform wrap the whole band —
            // fill, layers and shadow together, about the
            // band's own rect, its transform-origin
            // against the surface it stands on. The
            // band's container-space rect is recorded for
            // the glyph path's pivot.
            let bandFX = band.shadowSet != nil
                || band.transform != nil || band.opacity < 1
            if bandFX {
                NSGraphicsContext.saveGraphicsState()
                if band.opacity < 1 {
                    NSGraphicsContext.current?.cgContext
                        .setAlpha(band.opacity)
                }
                if let transform = band.transform {
                    transformPivots[ObjectIdentifier(transform)] =
                        NSRect(x: band.dx, y: band.top + band.dy,
                               width: container.size.width,
                               height: band.bottom - band.top)
                    NSGraphicsContext.current?.cgContext.concatenate(
                        TBBandLayoutManager.fxAffine(for: transform,
                                                     pivotRect: rect))
                }
                if let shadows = band.shadowSet {
                    TBBandLayoutManager.paintBoxShadows(shadows, in: rect)
                }
            }
            if let color = band.color {
                color.setFill()
                rect.fill()
            }
            if let box = band.box {
                TBBandLayoutManager.paintBackgroundLayers(box, in: rect)
            }
            if bandFX {
                NSGraphicsContext.restoreGraphicsState()
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
            // The paint & motion set (0.27): the
            // container's opacity and transform wrap the
            // whole block — rules, columns and spanners
            // together — about the seat's rect.
            let containerFX = spec.transformSpec != nil
                || spec.opacityValue < 1
            if containerFX {
                NSGraphicsContext.saveGraphicsState()
                if spec.opacityValue < 1 {
                    NSGraphicsContext.current?.cgContext
                        .setAlpha(spec.opacityValue)
                }
                if let transform = spec.transformSpec {
                    NSGraphicsContext.current?.cgContext.concatenate(
                        TBBandLayoutManager.fxAffine(for: transform,
                                                     pivotRect: rect))
                }
            }
            // The block's parts in order (0.27): column
            // runs and spanning elements, each in its
            // own slice of the seat, the rules standing
            // under each run's columns. A spec with no
            // parts — none should arrive; the renderer
            // always cuts them — paints as the single
            // column run 0.22 knew.
            var parts = spec.parts
            if parts.isEmpty {
                let legacy = TBColumnPart()
                legacy.content = spec.content
                legacy.height = spec.columnHeight
                parts = [legacy]
            }
            var y = rect.minY
            for part in parts {
                let partRect = NSRect(x: rect.minX, y: y,
                                      width: rect.width,
                                      height: part.height)
                if part.isSpanner {
                    drawSpannerPart(part, spec: spec, in: partRect)
                } else {
                    paintColumnRules(spec, in: partRect)
                    drawColumnPart(part, spec: spec, in: partRect)
                }
                y += part.height
            }
            if containerFX {
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // One rule per gap in a column part, as tall as
    // the part, centered in the gap. Of the border
    // styles, solid paints as a fill — and double,
    // groove, ridge, inset and outset paint solid
    // too: a rule a point or three wide has no bevel
    // to show. Dotted and dashed stroke a line with a
    // dash pattern instead. A rule of no height is
    // not drawn at all (0.25.0): a zero-height fill,
    // or a path from a point to itself, is a
    // zero-size draw.
    private func paintColumnRules(_ spec: TBMultiColumnSpec,
                                  in rect: NSRect) {
        if spec.columnCount > 1, spec.ruleWidth > 0,
           rect.height > 0,
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
                                          y: rect.minY + rect.height))
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
                           height: rect.height).fill()
                }
            }
        }
    }

    // Lay one column part's contents out across its
    // containers — one per column, each the column's
    // width and the part's height — and paint them
    // side by side: the text flows down one column and
    // continues at the top of the next, the layout
    // manager's own chaining. The layout is cached per
    // part until the page resolves again, as a floated
    // box's contents are.
    private func drawColumnPart(_ part: TBColumnPart,
                                spec: TBMultiColumnSpec, in rect: NSRect) {
        guard let content = part.content, content.length > 0,
              spec.columnCount > 0 else { return }
        let key = ObjectIdentifier(part)
        let manager: NSLayoutManager
        let containers: [NSTextContainer]
        if let cached = columnLayouts[key],
           cached.2.count == spec.columnCount, !cached.2.isEmpty,
           cached.2[0].size == NSSize(width: spec.columnWidth,
                                      height: part.height) {
            manager = cached.1
            containers = cached.2
        } else {
            // The storage is built first and attached
            // to the manager before its containers —
            // the floated-box painter's established
            // order (0.25.0) — and the cache keeps the
            // storage itself, not just the manager and
            // containers: a layout manager holds its
            // text storage only weakly, and a cache that
            // kept only the manager left every repaint
            // holding no text at all.
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            var built: [NSTextContainer] = []
            for _ in 0..<spec.columnCount {
                let container = NSTextContainer(
                    size: NSSize(width: spec.columnWidth,
                                 height: part.height))
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
            TBBandLayoutManager.paintTextShadows(manager: manager,
                                                 glyphRange: glyphs,
                                                 at: at)
            manager.drawGlyphs(forGlyphRange: glyphs, at: at)
            // Flexbox (0.24) and grid (0.25): a
            // container nested in the columns paints
            // at its seat in this column, like one
            // nested anywhere else.
            let chars = manager.characterRange(forGlyphRange: glyphs,
                                               actualGlyphRange: nil)
            paintFlexSeats(in: content, manager: manager, at: at,
                           charRange: chars)
            paintGridSeats(in: content, manager: manager, at: at,
                           charRange: chars)
        }
    }

    // A spanning part (0.27): the spanner's contents
    // laid out once, at the block's full width, in a
    // single container of the part's own height, and
    // painted where the part stands in the seat.
    private func drawSpannerPart(_ part: TBColumnPart,
                                 spec: TBMultiColumnSpec,
                                 in rect: NSRect) {
        guard let content = part.content, content.length > 0
        else { return }
        let key = ObjectIdentifier(part)
        let manager: NSLayoutManager
        let container: NSTextContainer
        if let cached = columnLayouts[key], cached.2.count == 1,
           cached.2[0].size == NSSize(width: spec.totalWidth,
                                      height: part.height) {
            manager = cached.1
            container = cached.2[0]
        } else {
            let storage = NSTextStorage(attributedString: content)
            manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            container = NSTextContainer(
                size: NSSize(width: spec.totalWidth,
                             height: part.height))
            manager.addTextContainer(container)
            columnLayouts[key] = (storage, manager, [container])
        }
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return }
        manager.drawBackground(forGlyphRange: glyphs, at: rect.origin)
        TBBandLayoutManager.paintTextShadows(manager: manager,
                                             glyphRange: glyphs,
                                             at: rect.origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: rect.origin)
        let chars = manager.characterRange(forGlyphRange: glyphs,
                                           actualGlyphRange: nil)
        paintFlexSeats(in: content, manager: manager, at: rect.origin,
                       charRange: chars)
        paintGridSeats(in: content, manager: manager, at: rect.origin,
                       charRange: chars)
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
        // The paint & motion set (0.27): the container's
        // opacity and transform wrap its items whole,
        // about the union of their boxes.
        var union = NSRect.null
        for item in spec.items { union = union.union(item.rect) }
        let containerFX = (spec.transformSpec != nil
            || spec.opacityValue < 1) && !union.isNull
        if containerFX {
            NSGraphicsContext.saveGraphicsState()
            if spec.opacityValue < 1 {
                NSGraphicsContext.current?.cgContext
                    .setAlpha(spec.opacityValue)
            }
            if let transform = spec.transformSpec {
                NSGraphicsContext.current?.cgContext.concatenate(
                    TBBandLayoutManager.fxAffine(
                        for: transform,
                        pivotRect: NSRect(x: origin.x + union.minX,
                                          y: origin.y + union.minY,
                                          width: union.width,
                                          height: union.height)))
            }
        }
        for item in spec.items {
            let rect = NSRect(x: origin.x + item.rect.minX,
                              y: origin.y + item.rect.minY,
                              width: item.rect.width,
                              height: item.rect.height)
            // The paint & motion set (0.27): the item's
            // shadows under it, its opacity and
            // transform around it — background, layers
            // and contents together, about its own rect.
            let itemFX = item.transformSpec != nil
                || item.opacityValue < 1 || item.boxShadows != nil
            if itemFX {
                NSGraphicsContext.saveGraphicsState()
                if item.opacityValue < 1 {
                    NSGraphicsContext.current?.cgContext
                        .setAlpha(item.opacityValue)
                }
                if let transform = item.transformSpec {
                    NSGraphicsContext.current?.cgContext.concatenate(
                        TBBandLayoutManager.fxAffine(for: transform,
                                                     pivotRect: rect))
                }
                if let shadows = item.boxShadows {
                    TBBandLayoutManager.paintBoxShadows(shadows, in: rect)
                }
            }
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
            if itemFX {
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if containerFX {
            NSGraphicsContext.restoreGraphicsState()
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
        TBBandLayoutManager.paintTextShadows(manager: manager,
                                             glyphRange: glyphs,
                                             at: rect.origin)
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
        // The paint & motion set (0.27): the container's
        // opacity and transform wrap its items whole,
        // about the union of their boxes.
        var union = NSRect.null
        for item in spec.items { union = union.union(item.rect) }
        let containerFX = (spec.transformSpec != nil
            || spec.opacityValue < 1) && !union.isNull
        if containerFX {
            NSGraphicsContext.saveGraphicsState()
            if spec.opacityValue < 1 {
                NSGraphicsContext.current?.cgContext
                    .setAlpha(spec.opacityValue)
            }
            if let transform = spec.transformSpec {
                NSGraphicsContext.current?.cgContext.concatenate(
                    TBBandLayoutManager.fxAffine(
                        for: transform,
                        pivotRect: NSRect(x: origin.x + union.minX,
                                          y: origin.y + union.minY,
                                          width: union.width,
                                          height: union.height)))
            }
        }
        for item in spec.items {
            let rect = NSRect(x: origin.x + item.rect.minX,
                              y: origin.y + item.rect.minY,
                              width: item.rect.width,
                              height: item.rect.height)
            // The paint & motion set (0.27): the item's
            // shadows under it, its opacity and
            // transform around it — background, layers
            // and contents together, about its own rect.
            let itemFX = item.transformSpec != nil
                || item.opacityValue < 1 || item.boxShadows != nil
            if itemFX {
                NSGraphicsContext.saveGraphicsState()
                if item.opacityValue < 1 {
                    NSGraphicsContext.current?.cgContext
                        .setAlpha(item.opacityValue)
                }
                if let transform = item.transformSpec {
                    NSGraphicsContext.current?.cgContext.concatenate(
                        TBBandLayoutManager.fxAffine(for: transform,
                                                     pivotRect: rect))
                }
                if let shadows = item.boxShadows {
                    TBBandLayoutManager.paintBoxShadows(shadows, in: rect)
                }
            }
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
            if itemFX {
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if containerFX {
            NSGraphicsContext.restoreGraphicsState()
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
        TBBandLayoutManager.paintTextShadows(manager: manager,
                                             glyphRange: glyphs,
                                             at: rect.origin)
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
        // The paint & motion set (0.27): the box's
        // shadows paint first, under everything the box
        // will draw, and its opacity and transform wrap
        // the whole box — background, picture or
        // contents — about the box's own rect.
        let boxFX = source.transformSpec != nil
            || source.opacityValue < 1 || source.boxShadows != nil
        if boxFX {
            NSGraphicsContext.saveGraphicsState()
            if source.opacityValue < 1 {
                NSGraphicsContext.current?.cgContext
                    .setAlpha(source.opacityValue)
            }
            if let transform = source.transformSpec {
                NSGraphicsContext.current?.cgContext.concatenate(
                    TBBandLayoutManager.fxAffine(for: transform,
                                                 pivotRect: rect))
            }
            if let shadows = source.boxShadows {
                TBBandLayoutManager.paintBoxShadows(shadows, in: rect)
            }
        }
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
        if boxFX {
            NSGraphicsContext.restoreGraphicsState()
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

    // The interaction set (0.26): a sticky element being
    // held paints ABOVE the words that scroll under it,
    // as a positioned box does — its color band and its
    // glyphs are painted a second time, at the shifted
    // place, after the ordinary pass. The shift rides on
    // the graphics state, so the glyphs paint through
    // drawGlyphs' above-pass gate untouched. A band
    // richer than a plain color — a photo, a gradient —
    // is not re-painted here; the ordinary pass already
    // drew it at the shifted place, under the crossing
    // words, and the glyphs alone ride above it.
    func paintStickyAbove(at origin: NSPoint, dirtyRect: NSRect) {
        guard let storage = textStorage, storage.length > 0,
              !stickyShifts.isEmpty,
              let container = textContainers.first else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(TBStickyKey, in: full) { value, range, _ in
            guard let spec = value as? TBStickySpec,
                  let dy = stickyShifts[ObjectIdentifier(spec)], dy != 0
            else { return }
            let glyphs = glyphRange(forCharacterRange: range,
                                    actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            // The shifted band's union, in view coords —
            // nothing outside the dirty rect is re-painted.
            var union = NSRect.null
            enumerateLineFragments(forGlyphRange: glyphs) {
                _, usedRect, _, _, _ in
                union = union.union(NSRect(
                    x: origin.x + usedRect.minX,
                    y: origin.y + usedRect.minY + dy,
                    width: usedRect.width, height: usedRect.height))
            }
            guard !union.isNull, union.intersects(dirtyRect) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext
                .translateBy(x: origin.x, y: origin.y + dy)
            storage.enumerateAttribute(.backgroundColor, in: range) {
                colorValue, runRange, _ in
                guard let color = colorValue as? NSColor else { return }
                let runGlyphs = glyphRange(forCharacterRange: runRange,
                                           actualCharacterRange: nil)
                guard runGlyphs.length > 0 else { return }
                let band = isBandRun(storage: storage, charRange: runRange,
                                     color: color)
                color.setFill()
                enumerateLineFragments(forGlyphRange: runGlyphs) {
                    _, usedRect, _, _, _ in
                    let fill = band
                        ? NSRect(x: 0, y: usedRect.minY,
                                 width: container.size.width,
                                 height: usedRect.height)
                        : usedRect
                    guard fill.width > 0, fill.height > 0 else { return }
                    fill.fill()
                }
            }
            inStickyAbovePass = true
            drawGlyphs(forGlyphRange: glyphs, at: .zero)
            inStickyAbovePass = false
            NSGraphicsContext.restoreGraphicsState()
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
        TBBandLayoutManager.paintTextShadows(manager: manager,
                                             glyphRange: glyphs,
                                             at: rect.origin)
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
    private var inStickyAbovePass = false

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        // The interaction set (0.26): the sticky
        // above-pass paints through this method with the
        // shift already on the graphics state — straight
        // to super, no second shift.
        if inStickyAbovePass {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        guard let storage = textStorage, storage.length > 0 else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let charRange = characterRange(forGlyphRange: glyphsToShow,
                                       actualGlyphRange: nil)
        // The segments are cut at every stamp boundary
        // that changes a segment's paint: the relative
        // and sticky offsets (0.26), and — the paint &
        // motion set (0.27) — the transform, opacity and
        // text-shadow stamps, plus the effects table's
        // edges. With no paint of any kind in the range
        // the whole range draws in one call, exactly as
        // before.
        var cuts: Set<Int> = [charRange.location, NSMaxRange(charRange)]
        storage.enumerateAttribute(TBRelOffsetKey, in: charRange) { _, range, _ in
            cuts.insert(range.location)
            cuts.insert(NSMaxRange(range))
        }
        if !stickyShifts.isEmpty {
            storage.enumerateAttribute(TBStickyKey, in: charRange) { _, range, _ in
                cuts.insert(range.location)
                cuts.insert(NSMaxRange(range))
            }
        }
        var hasPaint = false
        for key in [TBTransformKey, TBOpacityKey, TBTextShadowKey] {
            storage.enumerateAttribute(key, in: charRange) { value, range, _ in
                cuts.insert(range.location)
                cuts.insert(NSMaxRange(range))
                if value != nil { hasPaint = true }
            }
        }
        for entry in fxOverrides {
            if entry.range.location > charRange.location,
               entry.range.location < NSMaxRange(charRange) {
                cuts.insert(entry.range.location)
            }
            let entryEnd = NSMaxRange(entry.range)
            if entryEnd > charRange.location,
               entryEnd < NSMaxRange(charRange) {
                cuts.insert(entryEnd)
            }
            if NSIntersectionRange(entry.range, charRange).length > 0 {
                hasPaint = true
            }
        }
        let points = cuts.filter {
            $0 >= charRange.location && $0 <= NSMaxRange(charRange)
        }.sorted()
        var segments: [(range: NSRange, offset: NSPoint)] = []
        var hasOffset = false
        if points.count > 1 {
            for i in 0..<(points.count - 1) {
                let range = NSRange(location: points[i],
                                    length: points[i + 1] - points[i])
                guard range.length > 0 else { continue }
                let offset = paintOffset(at: range.location, in: storage)
                if offset != .zero { hasOffset = true }
                segments.append((range: range, offset: offset))
            }
        }
        guard hasOffset || hasPaint else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        for entry in segments {
            let segment = glyphRange(forCharacterRange: entry.range,
                                     actualCharacterRange: nil)
            guard segment.length > 0 else { continue }
            // Text shadows first, under the glyphs they
            // belong to (0.27).
            paintTextShadowPass(charRange: entry.range, at: origin,
                                offset: entry.offset)
            let fx = fxTraits(at: entry.range.location)
            let transform = fx.transform
                ?? storage.attribute(TBTransformKey,
                                     at: entry.range.location,
                                     effectiveRange: nil)
                    as? TBTransformSpec
            let opacity = fx.opacity
                ?? (storage.attribute(TBOpacityKey,
                                      at: entry.range.location,
                                      effectiveRange: nil)
                    as? TBOpacitySpec)?.value
            if entry.offset == .zero, transform == nil,
               opacity == nil || opacity! >= 1 {
                super.drawGlyphs(forGlyphRange: segment, at: origin)
            } else {
                NSGraphicsContext.saveGraphicsState()
                let context = NSGraphicsContext.current?.cgContext
                if entry.offset != .zero {
                    context?.translateBy(x: entry.offset.x,
                                         y: entry.offset.y)
                }
                if let opacity = opacity, opacity < 1 {
                    context?.setAlpha(opacity)
                }
                if let transform = transform {
                    context?.concatenate(TBBandLayoutManager.fxAffine(
                        for: transform,
                        pivotRect: glyphPivotRect(charRange: entry.range,
                                                  at: origin,
                                                  spec: transform)))
                }
                super.drawGlyphs(forGlyphRange: segment, at: origin)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // Text shadows under this manager's own glyphs
    // (0.27): the static painter's twin, drawing
    // through super — the override above must not
    // recurse into itself — with the segment's offset
    // riding along, so a shadow follows its glyphs
    // wherever their paint goes.
    private func paintTextShadowPass(charRange: NSRange, at origin: NSPoint,
                                     offset: NSPoint) {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(TBTextShadowKey, in: charRange) {
            value, range, _ in
            guard let set = value as? TBTextShadowSet else { return }
            let glyphs = glyphRange(forCharacterRange: range,
                                    actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            for shadow in set.shadows.reversed() {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.translateBy(
                    x: offset.x + shadow.dx, y: offset.y + shadow.dy)
                if shadow.blur > 0 {
                    let ns = NSShadow()
                    ns.shadowColor = shadow.color
                    ns.shadowBlurRadius = shadow.blur
                    ns.shadowOffset = .zero
                    ns.set()
                }
                setTemporaryAttributes([.foregroundColor: shadow.color],
                                       forCharacterRange: range)
                super.drawGlyphs(forGlyphRange: glyphs, at: origin)
                removeTemporaryAttribute(.foregroundColor,
                                         forCharacterRange: range)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // The pivot rect for a glyph segment's transform,
    // in view coordinates: the band rect its surface
    // recorded, where it has one, else the union of
    // the segment's own line fragments.
    private func glyphPivotRect(charRange: NSRange, at origin: NSPoint,
                                spec: TBTransformSpec) -> NSRect {
        if let cached = transformPivots[ObjectIdentifier(spec)] {
            return NSRect(x: origin.x + cached.minX,
                          y: origin.y + cached.minY,
                          width: cached.width, height: cached.height)
        }
        let glyphs = glyphRange(forCharacterRange: charRange,
                                actualCharacterRange: nil)
        var union = NSRect.null
        if glyphs.length > 0 {
            enumerateLineFragments(forGlyphRange: glyphs) {
                _, usedRect, _, _, _ in
                union = union.union(usedRect)
            }
        }
        if union.isNull {
            return NSRect(x: origin.x, y: origin.y, width: 0, height: 0)
        }
        return NSRect(x: origin.x + union.minX,
                      y: origin.y + union.minY,
                      width: union.width, height: union.height)
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
        // The paint & motion set (0.27): the fixed box's
        // shadows under it, its opacity and transform
        // around the whole box — restored by defer, on
        // every way out of this draw.
        let fx = spec.opacityValue < 1 || spec.transformSpec != nil
            || spec.boxShadows != nil
        if fx {
            NSGraphicsContext.saveGraphicsState()
            if spec.opacityValue < 1 {
                NSGraphicsContext.current?.cgContext
                    .setAlpha(spec.opacityValue)
            }
            if let transform = spec.transformSpec {
                NSGraphicsContext.current?.cgContext.concatenate(
                    TBBandLayoutManager.fxAffine(for: transform,
                                                 pivotRect: bounds))
            }
            if let shadows = spec.boxShadows {
                TBBandLayoutManager.paintBoxShadows(shadows, in: bounds)
            }
        }
        defer {
            if fx { NSGraphicsContext.restoreGraphicsState() }
        }
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
        TBBandLayoutManager.paintTextShadows(manager: manager,
                                             glyphRange: glyphs,
                                             at: contentRect.origin)
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
