//
//  ChirpyPaint.swift
//  Chirpy Browser — engine 0.39.5 (Swift)
//
//  The paint system: Chirpy's drawing.
//  This file takes the laid-out page and
//  makes it visible. It holds the
//  renderer's background-surface machinery
//  and its background box, and, as
//  extensions of TBRenderer, the
//  renderer's whole paint & motion
//  country: the shadow, transform,
//  opacity, transition and animation
//  parsing, the hover, focus and active
//  paint styles, the image and background
//  finishes, the first paint and the
//  arrivals finish, and the walk itself,
//  which draws the text into the
//  attributed string the window shows.
//  TBRenderer itself - its stored state,
//  its style resolutions, and its forms -
//  stays in ChirpyEngine.swift; these are
//  its methods still, written as
//  extensions, exactly as class methods in
//  Swift are allowed to be spelled.
//
//  This file was ChirpyEngine.swift's
//  paint country - the surface-edge
//  machinery, the background box, and
//  everything under the paint & motion
//  mark - until 0.39.5, when it moved here
//  whole: the fifth step of splitting the
//  codebase into files of their own, at
//  Tyler's direction, so each part can be
//  fixed and built quicker. Nothing in
//  the move changed the paint system
//  itself; the section intros that stood
//  over its parts in the engine file stand
//  below, as they were written.
//  ChirpyEngine.swift keeps short markers
//  where the sections lived, pointing
//  here.
//
//  Public domain (Unlicense), like the
//  rest of Chirpy.
//

import Foundation
import AppKit


extension TBRenderer {
        private func edgeIndex(color: NSColor?, box: TBBackgroundBox?) -> Int? {
            surfaceEdges.lastIndex { edge in
                guard edge.box === box else { return false }
                if edge.color == nil && color == nil { return true }
                if let a = edge.color, let b = color { return a.isEqual(b) }
                return false
            }
        }

        // A paragraph has just been appended under a surface:
        // the surface's first paragraph is stamped with the
        // inside space above it (the surface's top edge), and
        // every paragraph becomes the surface's latest — the
        // one its bottom edge will be stamped on when the
        // declaring element closes. A paragraph belonging to
        // the declaring element itself contributes no after
        // (its margin lies outside its own surface; its
        // padding is added separately when the edge closes).
        func noteSurfaceParagraph(range: NSRange, color: NSColor?,
                                          box: TBBackgroundBox?,
                                          after: CGFloat, ownSurface: Bool) {
            guard let idx = edgeIndex(color: color, box: box) else { return }
            if !surfaceEdges[idx].topStamped {
                surfaceEdges[idx].topStamped = true
                let ext = surfaceEdges[idx].topCarry
                if ext > 0 {
                    out.addAttribute(TBExtTopKey,
                                     value: NSNumber(value: Double(ext)),
                                     range: range)
                }
            }
            surfaceEdges[idx].lastParaRange = range
            surfaceEdges[idx].lastParaAfter = ownSurface ? 0 : after
            surfaceEdges[idx].bottomCarry = 0
        }

        // A block is closing. Its own declared surface, if
        // any, closes first: the bottom edge — the last
        // paragraph's after-space, the pure containers'
        // afters accumulated inside since, and the element's
        // own bottom padding — is stamped on that paragraph.
        // Then, if the block flushed nothing of its own, its
        // after-spacing joins the carry (to be consumed above
        // the next paragraph, as its before was) and counts
        // toward the bottom edges of the surfaces around it.
        private func closeSurfaceEdges(declaresSurface: Bool, pure: Bool,
                                       after: CGFloat) {
            if declaresSurface, !surfaceEdges.isEmpty {
                let edge = surfaceEdges.removeLast()
                if let range = edge.lastParaRange {
                    let ext = edge.lastParaAfter + edge.bottomCarry + edge.padBottom
                    if ext > 0 {
                        out.addAttribute(TBExtBottomKey,
                                         value: NSNumber(value: Double(ext)),
                                         range: range)
                    }
                }
            }
            if pure {
                spaceCarry += after
                for i in surfaceEdges.indices {
                    surfaceEdges[i].bottomCarry += after
                }
            }
        }

}

extension TBRenderer {
        // The background layers this element declares, if any.
        func backgroundBox(decls: [String: String]) -> TBBackgroundBox? {
            guard let spec = tbBackgroundSpec(decls, base: base) else { return nil }
            if let cached = backgroundBoxes[spec.key] { return cached }
            backgroundBoxes[spec.key] = spec.box
            return spec.box
        }

}

extension TBRenderer {
        // MARK: - Paint & motion parsing (0.27)

        // A CSS time: "0.4s" or "400ms", in seconds.
        private func timeValue(_ token: String) -> Double? {
            let t = token.trimmingCharacters(in: .whitespaces).lowercased()
            if t.hasSuffix("ms"), let v = Double(t.dropLast(2)) { return v / 1000 }
            if t.hasSuffix("s"), let v = Double(t.dropLast()) { return v }
            return nil
        }

        // A CSS angle, in radians: deg, rad, turn and grad
        // by their suffixes; a bare number reads as degrees
        // (lenient, as this engine reads most things).
        private func angleValue(_ token: String) -> CGFloat {
            let t = token.trimmingCharacters(in: .whitespaces).lowercased()
            if t.hasSuffix("deg"), let v = Double(t.dropLast(3)) {
                return CGFloat(v) * .pi / 180
            }
            if t.hasSuffix("rad"), let v = Double(t.dropLast(3)) {
                return CGFloat(v)
            }
            if t.hasSuffix("turn"), let v = Double(t.dropLast(4)) {
                return CGFloat(v) * 2 * .pi
            }
            if t.hasSuffix("grad"), let v = Double(t.dropLast(4)) {
                return CGFloat(v) * .pi / 200
            }
            if let v = Double(t) { return CGFloat(v) * .pi / 180 }
            return 0
        }

        // box-shadow: comma-separated shadows, each a run
        // of lengths (offset-x, offset-y, blur, spread)
        // with a color wherever the page put it, and
        // currentColor — the element's own color, passed
        // in — when it put none. The inset keyword
        // rides along on its own shadow (0.30); the
        // painters draw that kind inside its box.
        func boxShadowSet(_ decls: [String: String],
                                  color: NSColor?,
                                  fontSize: CGFloat) -> TBBoxShadowSet? {
            guard let raw = decls["box-shadow"],
                  raw.trimmingCharacters(in: .whitespaces).lowercased() != "none"
            else { return nil }
            let set = TBBoxShadowSet()
            for layer in tbSplitLayers(raw) {
                var lengths: [CGFloat] = []
                var shadowColor: NSColor? = nil
                var inset = false
                var valid = true
                for token in valueTokens(layer) {
                    let word = token.lowercased()
                    if word == "inset" { inset = true; continue }
                    if let parsed = tbParseColor(token) {
                        shadowColor = parsed
                        continue
                    }
                    if let length = tbLengthValue(token, fontSize: fontSize) {
                        lengths.append(length)
                        continue
                    }
                    if word == "0" { lengths.append(0); continue }
                    valid = false
                }
                guard valid, lengths.count >= 2 else { continue }
                let blur = lengths.count > 2 ? lengths[2] : 0
                guard blur >= 0 else { continue }
                set.shadows.append(TBBoxShadow(
                    dx: lengths[0], dy: lengths[1], blur: blur,
                    spread: lengths.count > 3 ? lengths[3] : 0,
                    color: shadowColor ?? color ?? .black,
                    inset: inset))
            }
            return set.shadows.isEmpty ? nil : set
        }

        // text-shadow: the same reading, minus spread and
        // inset — a text shadow has neither in CSS.
        private func textShadowSet(_ decls: [String: String],
                                   color: NSColor?,
                                   fontSize: CGFloat) -> TBTextShadowSet? {
            guard let raw = decls["text-shadow"],
                  raw.trimmingCharacters(in: .whitespaces).lowercased() != "none"
            else { return nil }
            let set = TBTextShadowSet()
            for layer in tbSplitLayers(raw) {
                var lengths: [CGFloat] = []
                var shadowColor: NSColor? = nil
                var valid = true
                for token in valueTokens(layer) {
                    if let parsed = tbParseColor(token) {
                        shadowColor = parsed
                        continue
                    }
                    if let length = tbLengthValue(token, fontSize: fontSize) {
                        lengths.append(length)
                        continue
                    }
                    if token == "0" { lengths.append(0); continue }
                    valid = false
                }
                guard valid, lengths.count >= 2 else { continue }
                let blur = lengths.count > 2 ? lengths[2] : 0
                guard blur >= 0 else { continue }
                set.shadows.append(TBTextShadow(
                    dx: lengths[0], dy: lengths[1], blur: blur,
                    color: shadowColor ?? color ?? .black))
            }
            return set.shadows.isEmpty ? nil : set
        }

        // transform: the 2D function list, kept unresolved
        // (see TBTransformSpec), with transform-origin
        // riding along — keywords and lengths against the
        // element's own box, the center by default. An
        // unrecognized function leaves the whole transform
        // unread rather than half-applied.
        func transformSpec(_ decls: [String: String],
                                   fontSize: CGFloat) -> TBTransformSpec? {
            guard let raw = decls["transform"],
                  raw.trimmingCharacters(in: .whitespaces).lowercased() != "none"
            else { return nil }
            let spec = TBTransformSpec()
            var i = raw.startIndex
            while i < raw.endIndex {
                while i < raw.endIndex, raw[i] == " " || raw[i] == "," {
                    i = raw.index(after: i)
                }
                guard i < raw.endIndex else { break }
                guard let open = raw.range(of: "(", range: i..<raw.endIndex)
                else { return nil }
                let name = String(raw[i..<open.lowerBound])
                    .trimmingCharacters(in: .whitespaces).lowercased()
                guard let close = raw.range(of: ")",
                                            range: open.upperBound..<raw.endIndex)
                else { return nil }
                let args = String(raw[open.upperBound..<close.lowerBound])
                let tokens = args.split { $0 == "," || $0 == " " || $0 == "\t" }
                    .map { String($0) }
                func lengths() -> [TBTransformValue] {
                    tokens.map { token in
                        if let v = insetValue(token, fontSize: fontSize) {
                            return .length(v)
                        }
                        if let n = Double(token) { return .number(CGFloat(n)) }
                        return .number(0)
                    }
                }
                func numbers() -> [TBTransformValue] {
                    tokens.map { .number(CGFloat(Double($0) ?? 0)) }
                }
                func angles() -> [TBTransformValue] {
                    tokens.map { .angle(angleValue($0)) }
                }
                switch name {
                case "translate", "translatex", "translatey":
                    spec.functions.append((name: name, values: lengths()))
                case "scale", "scalex", "scaley", "matrix":
                    spec.functions.append((name: name, values: numbers()))
                case "rotate", "skewx", "skewy", "skew":
                    spec.functions.append((name: name, values: angles()))
                default:
                    return nil
                }
                i = raw.index(after: close.lowerBound)
            }
            if spec.functions.isEmpty { return nil }
            if let originRaw = decls["transform-origin"] {
                var x: TBInsetValue? = nil
                var y: TBInsetValue? = nil
                for token in valueTokens(originRaw) {
                    switch token.lowercased() {
                    case "left": x = .percent(0)
                    case "right": x = .percent(100)
                    case "top": y = .percent(0)
                    case "bottom": y = .percent(100)
                    case "center":
                        if x == nil { x = .percent(50) }
                        else if y == nil { y = .percent(50) }
                    default:
                        if let v = insetValue(token, fontSize: fontSize) {
                            if x == nil { x = v }
                            else if y == nil { y = v }
                        }
                    }
                }
                if let x = x { spec.originX = x }
                if let y = y { spec.originY = y }
            }
            return spec
        }

        // opacity: a number or a percentage, held to
        // [0, 1] as the spec directs.
        func opacityValue(_ decls: [String: String]) -> CGFloat? {
            guard let raw = decls["opacity"] else { return nil }
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("%"), let pct = Double(t.dropLast()) {
                return min(max(CGFloat(pct) / 100, 0), 1)
            }
            guard let value = Double(t) else { return nil }
            return min(max(CGFloat(value), 0), 1)
        }

        // transition: the shorthand's layers (property,
        // duration, timing, delay — the first time is the
        // duration, the second the delay), with the
        // longhands combined by index over it when the
        // page wrote them. Nil when nothing would move.
        func transitionSpec(_ decls: [String: String]) -> TBTransitionSpec? {
            var entries: [TBTransitionEntry] = []
            if let shorthand = decls["transition"],
               shorthand.trimmingCharacters(in: .whitespaces).lowercased() != "none" {
                for layer in tbSplitLayers(shorthand) {
                    var property = "all"
                    var duration: Double? = nil
                    var delay: Double = 0
                    var timing = TBTimingFunction.ease
                    for token in valueTokens(layer) {
                        if let time = timeValue(token) {
                            if duration == nil { duration = time }
                            else { delay = time }
                            continue
                        }
                        let word = token.lowercased()
                        if word == "linear" || word == "ease"
                            || word == "ease-in" || word == "ease-out"
                            || word == "ease-in-out"
                            || word.hasPrefix("cubic-bezier(")
                            || word.hasPrefix("steps(")
                            || word == "step-start" || word == "step-end" {
                            timing = tbTimingFunction(token)
                            continue
                        }
                        property = word
                    }
                    entries.append(TBTransitionEntry(
                        property: property, duration: duration ?? 0,
                        delay: delay, timing: timing))
                }
            }
            if let propsRaw = decls["transition-property"] {
                let props = tbSplitLayers(propsRaw).map {
                    $0.trimmingCharacters(in: .whitespaces).lowercased()
                }
                let durations = (decls["transition-duration"]
                    .map { tbSplitLayers($0) } ?? [])
                    .map { timeValue($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                let delays = (decls["transition-delay"]
                    .map { tbSplitLayers($0) } ?? [])
                    .map { timeValue($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
                let timings = (decls["transition-timing-function"]
                    .map { tbSplitLayers($0) } ?? [])
                    .map { tbTimingFunction($0) }
                entries = props.enumerated().map { i, property in
                    TBTransitionEntry(
                        property: property,
                        duration: durations.isEmpty
                            ? 0 : durations[i % durations.count],
                        delay: delays.isEmpty ? 0 : delays[i % delays.count],
                        timing: timings.isEmpty
                            ? .ease : timings[i % timings.count])
                }
            }
            guard entries.contains(where: { $0.duration > 0 }) else { return nil }
            let spec = TBTransitionSpec()
            spec.entries = entries
            return spec
        }

        // animation: the element's name, duration, delay,
        // iteration count, direction and timing, resolved
        // against the keyframes the sheets carried. The
        // stops are reduced to paint traits here — layout
        // traits in a keyframe are simply never read.
        // Reduced motion stands the whole thing down: no
        // spec, no stamp, nothing for the view to run.
        func animationSpec(_ decls: [String: String],
                                   fontSize: CGFloat) -> TBAnimationSpec? {
            guard !reducedMotion else { return nil }
            var name = decls["animation-name"]?
                .trimmingCharacters(in: .whitespaces)
            var duration: Double? = decls["animation-duration"]
                .flatMap { timeValue($0) }
            var delay: Double = decls["animation-delay"]
                .flatMap { timeValue($0) } ?? 0
            var iterations: Double = 1
            var direction = "normal"
            var timing = TBTimingFunction.ease
            if let raw = decls["animation-iteration-count"] {
                let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
                iterations = t == "infinite" ? .infinity : (Double(t) ?? 1)
            }
            if let raw = decls["animation-direction"] {
                direction = raw.trimmingCharacters(in: .whitespaces).lowercased()
            }
            if let raw = decls["animation-timing-function"] {
                timing = tbTimingFunction(raw)
            }
            if let shorthand = decls["animation"] {
                var shorthandName: String? = nil
                var shorthandDuration: Double? = nil
                for token in valueTokens(shorthand) {
                    if let time = timeValue(token) {
                        if shorthandDuration == nil { shorthandDuration = time }
                        else { delay = time }
                        continue
                    }
                    let word = token.lowercased()
                    if word == "infinite" { iterations = .infinity; continue }
                    if let count = Double(word) { iterations = count; continue }
                    if ["normal", "reverse", "alternate",
                        "alternate-reverse"].contains(word) {
                        direction = word
                        continue
                    }
                    if word == "linear" || word.hasPrefix("ease")
                        || word.hasPrefix("cubic-bezier(")
                        || word.hasPrefix("steps(")
                        || word == "step-start" || word == "step-end" {
                        timing = tbTimingFunction(token)
                        continue
                    }
                    if ["none", "forwards", "backwards", "both",
                        "running", "paused"].contains(word) { continue }
                    shorthandName = token
                }
                if let shorthandName = shorthandName { name = shorthandName }
                if let shorthandDuration = shorthandDuration {
                    duration = shorthandDuration
                }
            }
            guard let name = name, !name.isEmpty,
                  name.lowercased() != "none",
                  let rule = keyframes[name],
                  let duration = duration, duration > 0
            else { return nil }
            let spec = TBAnimationSpec()
            spec.duration = duration
            spec.delay = delay
            spec.iterations = iterations
            spec.direction = direction
            spec.timing = timing
            spec.stops = rule.stops.map { stop in
                var traits = TBAnimTraits()
                traits.foreground = tbParseColor(stop.decls["color"])
                traits.background = tbBackgroundColor(stop.decls)
                traits.opacity = opacityValue(stop.decls)
                traits.transform = transformSpec(stop.decls,
                                                 fontSize: fontSize)
                return (offset: stop.offset, traits: traits)
            }
            return spec
        }

        // The part of a state style the 0.23 traits cannot
        // hold (0.27): background layers, opacity and a
        // paint transform, attached to the style the plain
        // traits built — or standing alone when the state
        // names nothing else paintable. Lengths in a state
        // transform read against the 16pt reference size:
        // states overwhelmingly translate in pixels.
        private func attachStateExtras(_ style: TBHoverStyle?,
                                       decls: [String: String]) -> TBHoverStyle? {
            let box = backgroundBox(decls: decls)
            let opacity = opacityValue(decls)
            let transform = transformSpec(decls, fontSize: 16)
            if box == nil, opacity == nil, transform == nil { return style }
            let s = style ?? TBHoverStyle()
            if let box = box { s.backgroundBox = box }
            if let opacity = opacity { s.opacityValue = opacity }
            if let transform = transform { s.transformSpec = transform }
            return s
        }

        // A multicolumn block's spanning child (0.27): a
        // block-level child declaring column-span: all,
        // judged by the same display reading the walk's
        // own child loop makes.
        func columnSpanner(_ child: TBNode) -> Bool {
            guard child.tag != "#text", child.tag != "img" else { return false }
            let childOwn = resolvedStyle(node: child)
            guard (childOwn["column-span"] ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased() == "all",
                  !tbIsHidden(childOwn) else { return false }
            let display = (childOwn["display"] ?? "").lowercased()
            if ["inline", "inline-block", "inline-flex",
                "inline-grid", "contents"].contains(display) { return false }
            return TBBlockTags.contains(child.tag)
                || ["block", "flex", "grid", "list-item",
                    "table", "flow-root"].contains(display)
                || hasBlock(child)
        }

        // The element's hover paint (0.23), ready to stamp: the
        // resolved hover declarations reduced to the traits the
        // view can repaint without moving any text. Nil when no
        // :hover rule in this sheet touches the element, or the
        // ones that do name nothing paintable — the walk then
        // stamps nothing, and the page hovers exactly as pages
        // did before the finishing set.
        func hoverPaintStyle(node: TBNode) -> TBHoverStyle? {
            guard hoverRulePresent else { return nil }
            let decls = resolvedHoverStyle(node: node)
            if decls.isEmpty { return nil }
            return attachStateExtras(tbHoverPaintAttrs(decls), decls: decls)
        }

        // The element's focus paint (0.26), ready to stamp —
        // hoverPaintStyle's twin under the focus keys. Nil
        // when no :focus rule touches the element, or the
        // ones that do name nothing paintable.
        func focusPaintStyle(node: TBNode) -> TBHoverStyle? {
            guard focusRulePresent else { return nil }
            let decls = resolvedFocusStyle(node: node)
            if decls.isEmpty { return nil }
            return attachStateExtras(tbHoverPaintAttrs(decls), decls: decls)
        }

        // The element's active paint (0.26) — the third twin,
        // worn while the reader presses the element.
        func activePaintStyle(node: TBNode) -> TBHoverStyle? {
            guard activeRulePresent else { return nil }
            let decls = resolvedActiveStyle(node: node)
            if decls.isEmpty { return nil }
            return attachStateExtras(tbHoverPaintAttrs(decls), decls: decls)
        }

        // Fetch every registered image — with bounded
        // concurrency since 0.19 — and seat it
        // in its attachment, fitted to its CSS/attribute box, or
        // its natural size capped at the nominal page width. An
        // image that cannot be fetched or decoded is replaced in
        // the text by its labelled placeholder — honest, never
        // a silent hole.
        func finishImages() async {
            if imageJobs.isEmpty { return }
            var dataByIndex: [Int: Data] = [:]
            // Data URIs decode in place; the rest fetch with
            // bounded concurrency (0.19) — at most six in
            // flight — with every result in hand, keyed by
            // job, before the seating below proceeds.
            var fetchJobs: [(index: Int, url: String)] = []
            for (index, job) in imageJobs.enumerated() {
                if job.url.hasPrefix("data:") {
                    dataByIndex[index] = tbDecodeDataURI(job.url)
                } else {
                    fetchJobs.append((index: index, url: job.url))
                }
            }
            let fetched = await tbFetchDataBatch(fetchJobs, pageURL: base)
            for (index, data) in fetched {
                dataByIndex[index] = data
            }
            var failedIndices = Set<Int>()
            for (index, job) in imageJobs.enumerated() {
                guard let data = dataByIndex[index], let image = NSImage(data: data) else {
                    failedIndices.insert(index)
                    continue
                }
                let natural = image.size
                if natural.width < 2 || natural.height < 2 {
                    failedIndices.insert(index)
                    continue
                }
                var width = job.preferredWidth ?? natural.width
                var height = job.preferredHeight ?? natural.height
                if job.preferredWidth != nil && job.preferredHeight == nil {
                    height = natural.height * (width / natural.width)
                } else if job.preferredHeight != nil && job.preferredWidth == nil {
                    width = natural.width * (height / natural.height)
                }
                if width > 1000 {
                    height *= 1000 / width
                    width = 1000
                }
                job.attachment.image = image
                job.attachment.bounds = CGRect(x: 0, y: 0, width: width, height: height)
            }
            // Replace attachments that never got a picture with
            // their labels, found by identity, replaced backwards
            // so earlier ranges stay put.
            // Failure is tracked by job, not by the attachment's
            // image: since 0.20 an attachment may already carry
            // its clear seat from the walk, so a nil image no
            // longer means "never arrived".
            let failedIDs = Set(failedIndices.map {
                ObjectIdentifier(imageJobs[$0].attachment)
            })
            if !failedIDs.isEmpty {
                var failed: [(range: NSRange, alt: String)] = []
                out.enumerateAttribute(.attachment,
                                       in: NSRange(location: 0, length: out.length)) { value, range, _ in
                    if let attachment = value as? NSTextAttachment,
                       failedIDs.contains(ObjectIdentifier(attachment)) {
                        let alt = imageJobs.first { $0.attachment === attachment }?.alt ?? "image"
                        failed.append((range: range, alt: alt))
                    }
                }
                for entry in failed.reversed() {
                    out.replaceCharacters(in: entry.range, with: NSAttributedString(
                        string: " [Image: \(entry.alt)] ",
                        attributes: [.font: NSFont.systemFont(ofSize: 12),
                                     .foregroundColor: NSColor.secondaryLabelColor]))
                }
            }
            imageJobs = []
        }

        // Fetch the photo layers of every registered background
        // box (data: URIs decode in place). A photo that fails
        // simply never paints — the color and gradients remain.
        func finishBackgrounds() async {
            var jobs: [(layer: TBBackgroundLayer, url: String)] = []
            for box in backgroundBoxes.values {
                for layer in box.layers {
                    if case .image(let url) = layer.kind {
                        jobs.append((layer: layer, url: url))
                    }
                }
            }
            if jobs.isEmpty { return }
            let capped = Array(jobs.prefix(8))
            var dataByIndex: [Int: Data] = [:]
            // The same bounded fetching as the flow's images
            // (0.19): the cap of eight jobs still applies
            // first, then at most six fly at once.
            var fetchJobs: [(index: Int, url: String)] = []
            for (index, job) in capped.enumerated() {
                if job.url.hasPrefix("data:") {
                    dataByIndex[index] = tbDecodeDataURI(job.url)
                } else {
                    fetchJobs.append((index: index, url: job.url))
                }
            }
            let fetched = await tbFetchDataBatch(fetchJobs, pageURL: base)
            for (index, data) in fetched {
                dataByIndex[index] = data
            }
            for (index, job) in capped.enumerated() {
                if let data = dataByIndex[index] {
                    job.layer.image = NSImage(data: data)
                }
            }
        }

        // First paint (0.20), the first stage: styles, then
        // the walk. The string this returns is the page the
        // window shows at once — text complete, links live,
        // declared picture boxes reserved — while everything
        // the walk registered as still-to-fetch waits for
        // finishArrivals().
        func renderFirstPaint(root: TBNode) async -> NSAttributedString {
            var sources: [TBStyleSource] = []
            tbCollectStyleSources(root, base: base, into: &sources)
            // Every external stylesheet fetches concurrently
            // (0.19) — a page's sheets no longer queue behind
            // one another's round trips — but they are parsed
            // and appended strictly in document order below:
            // the cascade honors the order the page declares,
            // never the order the replies land in. A sheet
            // that fails to arrive is skipped, exactly as it
            // was when the fetches ran one by one.
            var sheetTexts: [Int: String] = [:]
            var sheetJobs: [(index: Int, url: String)] = []
            for (index, source) in sources.enumerated() {
                if case .external(let url) = source {
                    sheetJobs.append((index: index, url: url))
                }
            }
            if !sheetJobs.isEmpty {
                let pageBase = base
                await withTaskGroup(of: (Int, String?).self) { group in
                    for job in sheetJobs {
                        group.addTask { (job.index, await tbFetchText(urlString: job.url, pageURLString: pageBase)) }
                    }
                    for await (index, text) in group {
                        if let text = text { sheetTexts[index] = text }
                    }
                }
            }
            // One media context for the whole render (0.23): the
            // appearance, the window's text width as this load
            // began (the renderer's standing 1000 when no width
            // was handed down), and the system's reduce-motion
            // setting. Queries are answered once, here — resizing
            // the window re-settles the layout, it does not
            // re-run the cascade.
            let mediaContext = TBMediaContext(dark: darkAppearance,
                                              width: mediaWidth ?? 1000,
                                              reducedMotion: reducedMotion)
            var order = 0
            for (index, source) in sources.enumerated() {
                let cssText: String?
                switch source {
                case .inline(let text): cssText = text
                case .external: cssText = sheetTexts[index]
                }
                guard let text = cssText else { continue }
                // @keyframes rules (0.27) are collected from
                // the sheet's raw text before the cascade
                // parse strips them; a later sheet's rule of
                // the same name replaces an earlier one's.
                for (name, rule) in tbParseKeyframes(text) {
                    keyframes[name] = rule
                }
                let parsed = tbParseCSS(text, orderStart: order)
                rules.append(contentsOf: parsed)
                order += parsed.count
                // @media (0.23): the blocks whose queries match
                // join the cascade after the sheet's plain rules —
                // prefers-color-scheme among them, as before.
                let media = tbParseMediaCSS(text, orderStart: order,
                                            context: mediaContext)
                rules.append(contentsOf: media)
                order += media.count
            }
            nominalWidth = columnTextWidth(root: root) ?? 1000
            walkBlock(node: root, style: "p", baseFont: tbFont(for: "p"),
                      color: nil, align: .left, inheritedBackground: nil, inheritedBackgroundBox: nil)
            if let body = findTag(root, "body") ?? findTag(root, "html") {
                pageBackground = tbBackgroundColor(resolvedStyle(node: body))
            }
            return out
        }

        // First paint (0.20): is anything still out fetching?
        // The window shows the walked page immediately and
        // notes in its status line that pictures are still
        // arriving; this is what tells it so.
        var hasPendingArrivals: Bool {
            if !imageJobs.isEmpty || !floatImageJobs.isEmpty
                || !pendingBlockFloats.isEmpty
                || !positionedImageJobs.isEmpty
                || !pendingPositioned.isEmpty
                || !pendingColumns.isEmpty
                || !pendingFlex.isEmpty
                || !pendingGrid.isEmpty { return true }
            for box in backgroundBoxes.values {
                for layer in box.layers {
                    if case .image = layer.kind { return true }
                }
            }
            return false
        }

        // First paint (0.20), the second stage: fetch
        // everything the walk registered, in the order the
        // old single-pass render finished them — the flow's
        // pictures seat themselves (or become their labels),
        // background photos fill their layers, and the
        // floated pictures land in their specs while the
        // block floats are measured and given their contents.
        func finishArrivals() async {
            await finishImages()
            await finishBackgrounds()
            await finishFloatImages()
            await finishPositioned()
            await finishColumns()
            await finishFlex()
            await finishGrid()
        }

        private func findTag(_ node: TBNode, _ tag: String) -> TBNode? {
            if node.tag == tag { return node }
            for child in node.children {
                if let found = findTag(child, tag) { return found }
            }
            return nil
        }

        private func hasBlock(_ node: TBNode) -> Bool {
            for child in node.children where child.tag != "#text" {
                if TBBlockTags.contains(child.tag) || hasBlock(child) { return true }
            }
            return false
        }

        @discardableResult
        private func flush(buffer: inout NSMutableAttributedString, style: String,
                           font: NSFont, align: NSTextAlignment, background: NSColor?,
                           backgroundBox: TBBackgroundBox?,
                           metrics: TBBlockMetrics,
                           ownSurface: Bool = false) -> Bool {
            func isWS(_ s: String) -> Bool {
                s == " " || s == "\n" || s == "\t" || s == "\r"
            }
            while buffer.length > 0 {
                let first = (buffer.string as NSString).substring(with: NSRange(location: 0, length: 1))
                if isWS(first) {
                    buffer.deleteCharacters(in: NSRange(location: 0, length: 1))
                } else { break }
            }
            while buffer.length > 0 {
                let last = (buffer.string as NSString).substring(with: NSRange(location: buffer.length - 1, length: 1))
                if isWS(last) {
                    buffer.deleteCharacters(in: NSRange(location: buffer.length - 1, length: 1))
                } else { break }
            }
            if buffer.length > 0 {
                if style == "li" {
                    buffer.insert(NSAttributedString(string: "\u{2022} ", attributes: [.font: font]), at: 0)
                }
                // The paint & motion set (0.27): text-overflow:
                // ellipsis — a nowrap block whose overflow is
                // not visible and whose line runs past its
                // content width is cut at the edge and closed
                // with an ellipsis. The cut is made in the
                // text itself: the page's string truly ends
                // at the ellipsis, so selection and copying
                // give the truncated words — the honesty the
                // finishing2 test page states.
                if let avail = ellipsisWidth,
                   measureText(buffer, width: 100000).width > avail {
                    var lo = 0
                    var hi = buffer.length
                    while lo < hi {
                        let mid = (lo + hi + 1) / 2
                        let prefix = NSMutableAttributedString(
                            attributedString: buffer.attributedSubstring(
                                from: NSRange(location: 0, length: mid)))
                        prefix.append(NSAttributedString(string: "\u{2026}"))
                        if measureText(prefix, width: 100000).width <= avail {
                            lo = mid
                        } else {
                            hi = mid - 1
                        }
                    }
                    let kept = NSMutableAttributedString(
                        attributedString: buffer.attributedSubstring(
                            from: NSRange(location: 0, length: lo)))
                    kept.append(NSAttributedString(
                        string: "\u{2026}",
                        attributes: buffer.attributes(
                            at: lo > 0 ? lo - 1 : 0, effectiveRange: nil)))
                    buffer = kept
                }
                let blockRange = NSRange(location: 0, length: buffer.length)
                if align != .left || metrics.hasAny || spaceCarry > 0 || nowrapClips {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = align
                    if nowrapClips { paragraph.lineBreakMode = .byClipping }
                    if spaceCarry > 0 { paragraph.paragraphSpacingBefore = spaceCarry }
                    if metrics.after > 0 { paragraph.paragraphSpacing = metrics.after }
                    if metrics.lineMultiple > 0 { paragraph.lineHeightMultiple = metrics.lineMultiple }
                    if metrics.extraLineSpacing > 0 { paragraph.lineSpacing = metrics.extraLineSpacing }
                    if metrics.indent > 0 {
                        paragraph.headIndent = metrics.indent
                        paragraph.firstLineHeadIndent = metrics.indent
                    }
                    if metrics.tailIndent > 0 { paragraph.tailIndent = -metrics.tailIndent }
                    buffer.addAttribute(.paragraphStyle, value: paragraph, range: blockRange)
                }
                if let background = background {
                    // Paint behind only the runs not already carrying
                    // a nearer element's own background.
                    var unpainted: [NSRange] = []
                    buffer.enumerateAttribute(.backgroundColor, in: blockRange,
                                               options: []) { value, range, _ in
                        if value == nil { unpainted.append(range) }
                    }
                    for range in unpainted {
                        buffer.addAttribute(.backgroundColor, value: background, range: range)
                    }
                }
                let paraStart = out.length
                out.append(buffer)
                lastFlushRange = NSRange(location: paraStart, length: buffer.length)
                // Positioned layout (0.17): a paragraph flushed
                // under position:relative ancestors carries their
                // accumulated offset, and a clear registered by
                // the block this paragraph opens anchors here, at
                // its first character.
                if relDX != 0 || relDY != 0 {
                    out.addAttribute(TBRelOffsetKey,
                                     value: NSValue(point: NSPoint(x: relDX, y: relDY)),
                                     range: NSRange(location: paraStart,
                                                    length: buffer.length))
                }
                if !pendingClears.isEmpty {
                    for spec in pendingClears { spec.anchorCharIndex = paraStart }
                    pendingClears = []
                }
                // The paint & motion set (0.27): the text
                // shadows in force ride on the paragraph, for
                // the glyph painters to draw beneath it.
                if let shadows = textShadowSetCurrent {
                    out.addAttribute(TBTextShadowKey, value: shadows,
                                     range: NSRange(location: paraStart,
                                                    length: buffer.length))
                }
                // The gap between blocks belongs to the same box:
                // paint it too, so a background reads as one band.
                // The closing newline also carries the box's
                // background layers, where the layout manager
                // reads them when it paints the surface.
                var separatorAttrs: [NSAttributedString.Key: Any] = [:]
                if let background = background {
                    separatorAttrs[.backgroundColor] = background
                }
                if let backgroundBox = backgroundBox {
                    separatorAttrs[TBBackgroundKey] = backgroundBox
                }
                out.append(NSAttributedString(string: "\n\n", attributes: separatorAttrs))
                noteSurfaceParagraph(
                    range: NSRange(location: paraStart, length: buffer.length),
                    color: background, box: backgroundBox,
                    after: metrics.after, ownSurface: ownSurface)
                spaceCarry = 0
                buffer = NSMutableAttributedString()
                return true
            }
            buffer = NSMutableAttributedString()
            return false
        }

        // A float met mid-paragraph splits the paragraph: the
        // words before the float keep their place, and the
        // words after it flow on beside (or below) the float.
        // In CSS the split is still one paragraph, so the gap
        // the block's spacing would have put after it must not
        // appear at the split — zero it on the paragraph just
        // appended; the block's spacing lands after its true
        // last paragraph as usual.
        @discardableResult
        private func flushForFloat(buffer: inout NSMutableAttributedString, style: String,
                                   font: NSFont, align: NSTextAlignment,
                                   background: NSColor?, backgroundBox: TBBackgroundBox?,
                                   metrics: TBBlockMetrics, ownSurface: Bool) -> Bool {
            let flushed = flush(buffer: &buffer, style: style, font: font, align: align,
                                background: background, backgroundBox: backgroundBox,
                                metrics: metrics, ownSurface: ownSurface)
            if flushed, let range = lastFlushRange, NSMaxRange(range) <= out.length,
               let paragraph = out.attribute(.paragraphStyle, at: range.location,
                                             effectiveRange: nil) as? NSParagraphStyle,
               paragraph.paragraphSpacing != 0 {
                let tightened = paragraph.mutableCopy() as! NSMutableParagraphStyle
                tightened.paragraphSpacing = 0
                out.addAttribute(.paragraphStyle, value: tightened, range: range)
            }
            return flushed
        }

        // Joining two sibling elements whose source carries no
        // whitespace between them — a card's name span hard against
        // its description span: a real layout separates them with
        // gaps and columns; a text flow separates them with a
        // space. Only element pieces trigger this, so words split
        // across <b>/<i> stay whole, and a piece opening with
        // punctuation never gains a space before it.
        func appendJoined(_ buffer: NSMutableAttributedString,
                                  _ piece: NSAttributedString, isElement: Bool) {
            if isElement, piece.length > 0,
               let last = buffer.string.last, let first = piece.string.first,
               !last.isWhitespace, !first.isWhitespace, !first.isPunctuation {
                buffer.append(NSAttributedString(string: " "))
            }
            buffer.append(piece)
        }

        func walkBlock(node: TBNode, style: String, baseFont: NSFont,
                               color: NSColor?, align: NSTextAlignment,
                               inheritedBackground: NSColor?,
                               inheritedBackgroundBox: TBBackgroundBox?) {
            let own = resolvedStyle(node: node)
            if node.tag != "document" && tbIsHidden(own) { return }
            // Positioned layout (0.17): where this block's own
            // content begins, and how many floats precede it —
            // the containment check at the block's close reads
            // both.
            let entryLength = out.length
            let floatsAtEntry = floatCount
            let effFont = tbFontApplying(own, to: baseFont)
            let effColor = tbParseColor(own["color"]) ?? color
            let effAlign = tbAlignment(own, fallback: align)
            // The background showing through this whole subtree: this
            // element's own background if it declares one, else the
            // nearest ancestor's. (CSS backgrounds are not inherited
            // as values — they show through, which amounts to this.)
            let effBackground = tbBackgroundColor(own) ?? inheritedBackground
            // Background layers show through the same way the
            // color does: the nearest declaring ancestor's box.
            let effBox = backgroundBox(decls: own) ?? inheritedBackgroundBox
            let metrics = tbBlockMetrics(own, fontSize: effFont.pointSize)
            // Positioned layout (0.17): this block's own clear
            // registers now and anchors at the first paragraph
            // flushed beneath it; its relative offset joins the
            // accumulation this block's paragraphs are stamped
            // with, and leaves when the block does.
            if !insideFloat, node.tag != "document",
               let side = clearSide(own["clear"]) {
                let spec = TBClearSpec(anchorCharIndex: out.length,
                                       side: side, rangeStart: nil)
                layoutEvents.append(.clear(spec))
                pendingClears.append(spec)
            }
            let savedRelDX = relDX
            let savedRelDY = relDY
            let savedAncestorPaddingH = ancestorPaddingH
            let savedDefiniteAncestorHeight = definiteAncestorHeight
            // The paint & motion set (0.27): this block's
            // paint state — text-shadow inherits, so a
            // declared set replaces the inherited one for
            // the block's subtree; nowrap and the ellipsis
            // width are the block's own, read by flush()
            // while its paragraphs land. Restored at the
            // close, beside the relative offsets.
            let savedTextShadows = textShadowSetCurrent
            if let shadows = textShadowSet(own, color: effColor,
                                           fontSize: effFont.pointSize) {
                textShadowSetCurrent = shadows
            }
            let savedNowrapClips = nowrapClips
            nowrapClips = (own["white-space"] ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased() == "nowrap"
            let savedEllipsisWidth = ellipsisWidth
            ellipsisWidth = nil
            if nowrapClips, !insideFloat, node.tag != "document",
               let overflow = (own["overflow"] ?? own["overflow-x"])?
                .trimmingCharacters(in: .whitespaces).lowercased(),
               ["hidden", "clip", "scroll", "auto"].contains(overflow),
               (own["text-overflow"] ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased() == "ellipsis" {
                ellipsisWidth = max(10, nominalWidth - metrics.indent
                                    - metrics.tailIndent)
            }
            if let offset = relativeOffset(own, fontSize: effFont.pointSize) {
                relDX += offset.dx
                relDY += offset.dy
            }
            // Positioned layout (0.21): a relatively positioned
            // block is the containing block for the absolutely
            // positioned descendants walked beneath it — open
            // its range now; the close at the end of this walk
            // patches where the range ends. (A span carrying
            // block descendants is walked here too, so its
            // range is tracked; a span walked purely inline,
            // inside a sentence, establishes none — its
            // positioned descendants resolve against the next
            // block ancestor out, or the page.)
            var openedContainingBlock: TBContainingBlock? = nil
            if !insideFloat, node.tag != "document",
               (own["position"] ?? "").lowercased() == "relative" {
                let block = TBContainingBlock(startCharIndex: entryLength)
                containingBlocks.append(block)
                openedContainingBlock = block
            }
            // The interaction set (0.26): every block's own
            // range is tracked while it is open — the record
            // a sticky element reads its containing block
            // from (its parent block, the stack's top before
            // its own range is pushed). A block declaring
            // position:sticky additionally records its event
            // here: its insets are read beside positionKind's
            // family (it never leaves the flow, so
            // positionKind's out-of-flow answer stays no),
            // and the close below patches its range's end
            // and stamps its spec onto its text.
            var openedRangeBlock: TBContainingBlock? = nil
            var stickySpec: TBStickySpec? = nil
            if !insideFloat, node.tag != "document" {
                let rangeBlock = TBContainingBlock(startCharIndex: entryLength)
                if (own["position"] ?? "").lowercased() == "sticky" {
                    let spec = TBStickySpec(rangeBlock: rangeBlock,
                                            containingBlock: blockRanges.last)
                    spec.top = insetValue(own["top"],
                                          fontSize: effFont.pointSize)
                    spec.bottom = insetValue(own["bottom"],
                                             fontSize: effFont.pointSize)
                    layoutEvents.append(.sticky(spec))
                    stickySpec = spec
                }
                blockRanges.append(rangeBlock)
                openedRangeBlock = rangeBlock
            }
            // Surface edges (0.15): this block's before-spacing
            // joins the carry — its own first flushed paragraph
            // consumes it, and a block that flushes nothing (a
            // pure container) passes it down to the first text
            // inside it, so a padded wrapper's spacing enters
            // the flow instead of vanishing. Open surfaces also
            // count the spacing as inside themselves, above
            // their first text.
            spaceCarry += metrics.before
            for i in surfaceEdges.indices where !surfaceEdges[i].topStamped {
                surfaceEdges[i].topCarry += metrics.before
            }
            // An element declaring its own background opens a
            // surface edge context: its padding belongs to its
            // surface's edges; its margin does not.
            let declaresSurface = tbBackgroundColor(own) != nil
                || backgroundBox(decls: own) != nil
            if declaresSurface {
                let padding = tbBoxValues(own, "padding")
                func plen(_ s: String) -> CGFloat {
                    tbLengthValue(s, fontSize: effFont.pointSize) ?? 0
                }
                surfaceEdges.append(TBSurfaceEdge(
                    color: effBackground, box: effBox,
                    padTop: plen(padding[0]), padBottom: plen(padding[2]),
                    topCarry: plen(padding[0])))
            }
            // Percentage float widths (0.25.0): this block's
            // own horizontal padding joins the accumulation,
            // so a floated child met in the loop below reads
            // its containing block's inset from the spec it
            // is registered with. Restored at the close,
            // beside the relative offsets.
            let ownPadding = boxLengths(own, "padding", fontSize: effFont.pointSize)
            ancestorPaddingH += ownPadding.left + ownPadding.right
            // Percentage container heights (0.30): this
            // block's own definite content height, for
            // the children the loop below walks — pushed
            // just before that loop, so this block's own
            // flex and grid specs still resolve against
            // the height open above it, never against
            // itself.
            var ownDefiniteHeight: CGFloat? = nil
            if node.tag != "document",
               let declared = flexLength(own["height"],
                                         fontSize: effFont.pointSize),
               let v = resolveFlexLength(declared,
                                         against: definiteAncestorHeight) {
                ownDefiniteHeight = max(v - ownPadding.top
                    - ownPadding.bottom, 0)
            }
            var flushedOwn = false
            let linkStart = out.length   // for block-level anchors, below
            let isForm = node.tag == "form"
            if isForm { enterForm(node) }

            var buffer = NSMutableAttributedString()
            // Flexbox (0.24): a block with display:flex hands
            // its children to the flex layout at once — each
            // child sub-rendered as an item, the items laid
            // out and seated in the flow as one block — the
            // multicolumn bargain, struck for a container
            // whose children stand in rows or columns of
            // their own instead of in flowing text. CSS gives
            // a flex container's contents to flex entirely
            // (its column properties fall silent), so this
            // path is tried before the columns'. Unlike the
            // columns, it is taken inside painted boxes too:
            // a flex container nested in a float, a column
            // block or another item records no layout event,
            // and its seat carries its spec as an attribute
            // instead — the view finds it when it paints the
            // box. The entry and closing bookkeeping around
            // it is shared exactly as it stands.
            // A seat container that is itself an anchor
            // (0.37.3): the card links of the real web
            // are <a> elements styled as grid or flex
            // containers. Their children never join
            // this string, so the close-time stamp below
            // (which covers what the children DID lay
            // down) finds nothing to stamp for them —
            // the seat carries the destination instead,
            // and the view's hover and click lookups
            // consult it after the seat's own text.
            let containerLink: String? = {
                guard node.tag == "a",
                      let href = node.attrs["href"], !href.isEmpty
                else { return nil }
                return URL(string: href,
                           relativeTo: URL(string: base))?.absoluteString
                    ?? href
            }()
            var tookFlex = false
            if node.tag != "document", flexCount < 60,
               let flexSpec = flexContainerSpec(own, fontSize: effFont.pointSize,
                                                metrics: metrics) {
                flexSpec.containerLink = containerLink
                flexSpec.boxShadows = boxShadowSet(
                    own, color: effColor, fontSize: effFont.pointSize)
                flexSpec.transformSpec = transformSpec(
                    own, fontSize: effFont.pointSize)
                flexSpec.opacityValue = opacityValue(own) ?? 1
                tookFlex = renderFlex(
                    node: node, spec: flexSpec, font: effFont,
                    color: effColor, align: effAlign, background: effBackground,
                    backgroundBox: effBox, metrics: metrics,
                    ownSurface: declaresSurface)
                flushedOwn = tookFlex
            }
            // Grid (0.25): a block with display:grid hands
            // its children to the grid layout the same way —
            // each child sub-rendered as an item, the items
            // placed and sized by the renderer, the container
            // seated in the flow as one block. CSS gives a
            // grid container's contents to grid entirely, so
            // this path is tried after flex and before the
            // columns'; and like flex it is taken inside
            // painted boxes too, the seat carrying its spec
            // as an attribute where no event is recorded.
            // The cap (0.34): twelve hundred containers,
            // not sixty — the hub's directory alone
            // declares two hundred grids (every card and
            // every arrow disc among them), and past the
            // old cap the rest silently flowed un-gridded.
            var tookGrid = false
            if !tookFlex, node.tag != "document", gridCount < 1200,
               let gridSpec = gridContainerSpec(own, fontSize: effFont.pointSize,
                                                metrics: metrics) {
                gridSpec.containerLink = containerLink
                gridSpec.boxShadows = boxShadowSet(
                    own, color: effColor, fontSize: effFont.pointSize)
                gridSpec.transformSpec = transformSpec(
                    own, fontSize: effFont.pointSize)
                gridSpec.opacityValue = opacityValue(own) ?? 1
                tookGrid = renderGrid(
                    node: node, spec: gridSpec, font: effFont,
                    color: effColor, align: effAlign, background: effBackground,
                    backgroundBox: effBox, metrics: metrics,
                    ownSurface: declaresSurface)
                flushedOwn = tookGrid
            }
            // Multi-column layout (0.22): a block declaring
            // columns hands its whole contents to the columns
            // at once — sub-rendered, balanced, and seated in
            // the flow — instead of flowing child by child, so
            // the loop below stands down for it. The block's
            // entry bookkeeping above (its spacing's carry,
            // its surface, its clear) and the closing
            // bookkeeping below (containment, the relative
            // restore, a block-level anchor's link) are shared
            // exactly as they stand; only the content between
            // is the columns'. A block inside a painted box
            // (insideFloat) never takes this path — nested
            // columns simply flow.
            var tookColumns = false
            if !tookFlex, !tookGrid, !insideFloat, node.tag != "document",
               let columnSpec = multiColumnSpec(
                   own, fontSize: effFont.pointSize,
                   totalWidth: nominalWidth - metrics.indent - metrics.tailIndent) {
                if columnSpec.ruleColor == nil {
                    columnSpec.ruleColor = effColor
                }
                columnSpec.containerLink = containerLink
                columnSpec.boxShadows = boxShadowSet(
                    own, color: effColor, fontSize: effFont.pointSize)
                columnSpec.transformSpec = transformSpec(
                    own, fontSize: effFont.pointSize)
                columnSpec.opacityValue = opacityValue(own) ?? 1
                tookColumns = renderColumns(
                    node: node, spec: columnSpec, font: effFont,
                    color: color, align: align, background: effBackground,
                    backgroundBox: effBox, metrics: metrics,
                    ownSurface: declaresSurface)
                flushedOwn = tookColumns
            }
            definiteAncestorHeight = ownDefiniteHeight
            let segmentFilter = columnChildFilter
            columnChildFilter = nil
            for child in (tookFlex || tookGrid || tookColumns) ? [] : node.children {
                if let segmentFilter = segmentFilter,
                   !segmentFilter.contains(ObjectIdentifier(child)) { continue }
                if TBRenderSkipTags.contains(child.tag) { continue }
                // Layout step one: the child's computed display decides
                // whether it stands as its own block or flows inline —
                // a link styled display:grid is a card, not a word.
                let childOwn = child.tag == "#text" ? [:] : resolvedStyle(node: child)
                if child.tag != "#text" && tbIsHidden(childOwn) { continue }
                // Positioned layout (0.17): a floated child leaves
                // the stack here — the words before it flush (with
                // no invented gap), the float is recorded for the
                // view to place, and the walk flows on. Form
                // controls keep their in-flow seating even when a
                // page styles them floated; past sixty floats the
                // rest simply flow, as they did before 0.17.
                // Positioned layout (0.21): a child lifted by
                // position:absolute or position:fixed leaves
                // the flow entirely — no exclusion, no wrap; it
                // overlays, resolved by the view like the
                // floats are. Position is checked before float:
                // CSS computes float away on a positioned box.
                // The words before it flush first (with no
                // invented gap), exactly as they do for a float.
                if !insideFloat, child.tag != "#text", positionedCount < 60,
                   !["input", "select", "textarea", "button"].contains(child.tag),
                   let kind = positionKind(childOwn["position"]) {
                    flushedOwn = flushForFloat(buffer: &buffer, style: style, font: effFont,
                                               align: effAlign, background: effBackground,
                                               backgroundBox: effBox, metrics: metrics,
                                               ownSurface: declaresSurface) || flushedOwn
                    if child.tag == "img" {
                        registerPositionedImage(child, own: childOwn, kind: kind,
                                                font: effFont)
                    } else {
                        registerPositionedBlock(child, own: childOwn, kind: kind,
                                                font: effFont, color: effColor,
                                                align: effAlign)
                    }
                    continue
                }
                if !insideFloat, child.tag != "#text", floatCount < 60,
                   !["input", "select", "textarea", "button"].contains(child.tag),
                   let side = floatSide(childOwn["float"]) {
                    flushedOwn = flushForFloat(buffer: &buffer, style: style, font: effFont,
                                               align: effAlign, background: effBackground,
                                               backgroundBox: effBox, metrics: metrics,
                                               ownSurface: declaresSurface) || flushedOwn
                    if child.tag == "img" {
                        registerImageFloat(child, own: childOwn, side: side, font: effFont)
                    } else {
                        registerBlockFloat(child, own: childOwn, side: side,
                                           font: effFont, color: effColor, align: effAlign)
                    }
                    continue
                }
                let display = (childOwn["display"] ?? "").lowercased()
                let forceBlock = ["block", "flex", "grid", "list-item",
                                  "table", "flow-root"].contains(display)
                let forceInline = ["inline", "inline-block", "inline-flex",
                                   "inline-grid", "contents"].contains(display)
                // An <img> is a replaced element: it always flows
                // through inline(), where its attachment is seated,
                // whatever display its CSS claims.
                if child.tag != "img" && (forceBlock || (TBBlockTags.contains(child.tag) && !forceInline)) {
                    flushedOwn = flush(buffer: &buffer, style: style, font: effFont,
                                       align: effAlign, background: effBackground, backgroundBox: effBox, metrics: metrics, ownSurface: declaresSurface) || flushedOwn
                    let childStyle = tbStyle(for: child.tag)
                    let childBase = TBHeadingTags.contains(child.tag)
                        ? tbFont(for: child.tag) : effFont
                    walkBlock(node: child, style: childStyle, baseFont: childBase,
                              color: effColor, align: effAlign,
                              inheritedBackground: effBackground, inheritedBackgroundBox: effBox)
                } else if child.tag == "html" || child.tag == "body" || child.tag == "document" || hasBlock(child) {
                    flushedOwn = flush(buffer: &buffer, style: style, font: effFont,
                                       align: effAlign, background: effBackground, backgroundBox: effBox, metrics: metrics, ownSurface: declaresSurface) || flushedOwn
                    walkBlock(node: child, style: style, baseFont: effFont,
                              color: effColor, align: effAlign,
                              inheritedBackground: effBackground, inheritedBackgroundBox: effBox)
                } else {
                    appendJoined(buffer, inline(child, font: effFont, color: effColor),
                                 isElement: child.tag != "#text")
                }
            }
            flushedOwn = flush(buffer: &buffer, style: style, font: effFont,
                               align: effAlign, background: effBackground, backgroundBox: effBox, metrics: metrics, ownSurface: declaresSurface) || flushedOwn
            if isForm { exitForm() }
            closeSurfaceEdges(declaresSurface: declaresSurface,
                              pure: !flushedOwn, after: metrics.after)

            // Float containment (0.17): floats anchored inside
            // this block must not spill past its bottom when the
            // block establishes containment — it clips or
            // scrolls (overflow other than visible), it is a
            // flow root or a table, it is itself floated — or,
            // the float-era reality this engine chooses, it
            // simply paints a surface: a backgrounded wrapper is
            // expected to wrap its floats, clearfix or no. The
            // containment clear counts only the floats anchored
            // inside this block, and pushes only what follows.
            if !insideFloat && floatCount > floatsAtEntry && establishesContainment(own) {
                layoutEvents.append(.clear(TBClearSpec(anchorCharIndex: out.length,
                                                       side: .both,
                                                       rangeStart: entryLength)))
            }
            relDX = savedRelDX
            relDY = savedRelDY
            ancestorPaddingH = savedAncestorPaddingH
            definiteAncestorHeight = savedDefiniteAncestorHeight
            textShadowSetCurrent = savedTextShadows
            nowrapClips = savedNowrapClips
            ellipsisWidth = savedEllipsisWidth

            // A block-level anchor (a card styled display:grid, say)
            // never passes through inline(), where links are made —
            // so make the whole block clickable here, keeping the
            // colors its own CSS gave it, and give it its [n] marker.
            if node.tag == "a", let href = node.attrs["href"], !href.isEmpty,
               (out.length > linkStart || containerLink != nil) {
                let absolute = URL(string: href, relativeTo: URL(string: base))?.absoluteString ?? href
                links.append(absolute)
                out.addAttribute(.link, value: absolute,
                                 range: NSRange(location: linkStart,
                                                length: out.length - linkStart))
                // The marker honors the reader's
                // setting (0.35): with link numbers
                // off, the block is simply its link.
                let marker = NSAttributedString(
                    string: TBSettings.showLinkNumbers
                        ? " [\(links.count)]" : "",
                    attributes: [.font: effFont, .link: absolute,
                                 .foregroundColor: NSColor.linkColor,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue])
                // The marker closes this block's own text. The output
                // may end with separator newlines — this block's own,
                // or a trailing child block's — so step back over
                // them and place the marker at the last real
                // character; appended blindly, it would surface at
                // the head of whatever renders next.
                var insertAt = out.length
                let outputSoFar = out.string as NSString
                while insertAt > linkStart && outputSoFar.character(at: insertAt - 1) == 10 {
                    insertAt -= 1
                }
                out.insert(marker, at: insertAt)
                if out.length > linkStart, linkStart < insertAt {
                    // The seat case (0.37.3): the card's
                    // characters live in the seat's own
                    // string, so the only walked text is
                    // the bare separator — stamp the link
                    // over the whole block range so the
                    // characters the seat sits on carry it
                    // and the native hover/click roads see
                    // the card as the link it is.
                    out.addAttribute(.link, value: absolute,
                                     range: NSRange(location: linkStart,
                                                    length: out.length - linkStart))
                }
            }

            // Anchor names (0.37.3): a block carrying an
            // id (or an <a name>) names a place a fragment
            // can land on. The name stamps over the
            // block's own walked range, so the view can
            // find it and scroll — the fragment road's
            // other half (the click that sets the
            // fragment is handled where links navigate).
            // Anchors inside a seat's own contents live
            // in that seat's private string and are not
            // reachable this way — a named limit.
            if node.tag != "document", out.length > entryLength {
                let anchorName = node.attrs["id"]
                    ?? (node.tag == "a" ? node.attrs["name"] : nil)
                if let anchorName = anchorName, !anchorName.isEmpty {
                    out.addAttribute(TBAnchorNameKey, value: anchorName,
                                     range: NSRange(location: entryLength,
                                                    length: out.length - entryLength))
                }
            }

            // Hover paint (0.23): a block's hover style is
            // stamped as the block closes, over everything its
            // walk laid down, under the block key — child blocks
            // closed (and stamped) before it and keep their
            // ground; the view merges this under the element
            // stamp when the pointer arrives.
            if node.tag != "document", out.length > entryLength,
               let hover = hoverPaintStyle(node: node) {
                tbStampHover(out,
                             range: NSRange(location: entryLength,
                                            length: out.length - entryLength),
                             key: TBHoverBlockAttrsKey, style: hover)
            }

            // The interaction set (0.26): the block's focus
            // and active styles stamp the same way, under
            // their own block keys.
            if node.tag != "document", out.length > entryLength,
               let focus = focusPaintStyle(node: node) {
                tbStampHover(out,
                             range: NSRange(location: entryLength,
                                            length: out.length - entryLength),
                             key: TBFocusBlockAttrsKey, style: focus)
            }
            if node.tag != "document", out.length > entryLength,
               let active = activePaintStyle(node: node) {
                tbStampHover(out,
                             range: NSRange(location: entryLength,
                                            length: out.length - entryLength),
                             key: TBActiveBlockAttrsKey, style: active)
            }

            // The paint & motion set (0.27): the block's
            // shadows, paint transform, opacity, transition
            // and animation specs stamp as the block closes,
            // under their own keys, fill-gaps like the state
            // stamps — a child block's own declarations keep
            // their ground inside it.
            if node.tag != "document", out.length > entryLength {
                let range = NSRange(location: entryLength,
                                    length: out.length - entryLength)
                if let shadows = boxShadowSet(own, color: effColor,
                                              fontSize: effFont.pointSize) {
                    tbStampValue(out, range: range, key: TBBoxShadowKey,
                                 value: shadows)
                }
                if let transform = transformSpec(own,
                                                 fontSize: effFont.pointSize) {
                    tbStampValue(out, range: range, key: TBTransformKey,
                                 value: transform)
                }
                if let opacity = opacityValue(own) {
                    tbStampValue(out, range: range, key: TBOpacityKey,
                                 value: TBOpacitySpec(opacity))
                }
                if let transition = transitionSpec(own) {
                    tbStampValue(out, range: range, key: TBTransitionKey,
                                 value: transition)
                }
                if let animation = animationSpec(own,
                                                 fontSize: effFont.pointSize) {
                    tbStampValue(out, range: range, key: TBAnimationKey,
                                 value: animation)
                }
            }

            // The interaction set (0.26): a sticky block's
            // range ends where its content did, and its spec
            // is stamped onto its text for the layout manager
            // to shift as the page scrolls.
            if let spec = stickySpec {
                spec.rangeBlock.endCharIndex = out.length
                if out.length > entryLength {
                    tbStampSticky(out,
                                  range: NSRange(location: entryLength,
                                                 length: out.length - entryLength),
                                  spec: spec)
                }
            }
            if let rangeBlock = openedRangeBlock {
                rangeBlock.endCharIndex = out.length
                blockRanges.removeLast()
            }

            // Positioned layout (0.21): this block's range as a
            // containing block ends where its content did.
            if let block = openedContainingBlock {
                block.endCharIndex = out.length
                containingBlocks.removeLast()
            }
        }
}
