//
//  ChirpyLayout.swift
//  Chirpy Browser — engine 0.39.4 (Swift)
//
//  The layout system: Chirpy's arrangement.
//  This file decides where each element's box
//  stands and how big it is. It holds the
//  top-level layout helpers - box shorthands,
//  length values, fixed width caps, and the
//  block metrics a block's spacing is read
//  into - and, as extensions of TBRenderer,
//  the renderer's own layout regions:
//  positioned layout (floats and clears,
//  0.17), multi-column layout (0.22), flexbox
//  (0.24), grid (0.25), and the positioned
//  layout pass (0.21) with the inline walk
//  that has always stood at the class's end.
//  TBRenderer itself - its stored state, its
//  core walk, and its paint and motion
//  parsing - stays in ChirpyEngine.swift;
//  these are its methods still, written as
//  extensions, exactly as class methods in
//  Swift are allowed to be spelled.
//
//  This file was ChirpyEngine.swift's Layout
//  country - the layout helpers just before
//  the Render mark, and TBRenderer's layout
//  regions - until 0.39.4, when it moved here
//  whole: the fourth step of splitting the
//  codebase into files of their own, at
//  Tyler's direction, so each part can be
//  fixed and built quicker. Nothing in the
//  move changed the layout system itself;
//  the section intros that stood over its
//  parts in the engine file stand below, as
//  they were written. ChirpyEngine.swift
//  keeps short markers where the sections
//  lived, pointing here.
//
//  Public domain (Unlicense), like the rest
//  of Chirpy.
//

import Foundation
import AppKit

// MARK: - Layout (step one)

// Expand a box shorthand (margin / padding) into top, right,
// bottom, left raw values; longhand properties win over the
// shorthand. Tokens split on whitespace outside parentheses,
// so a value like clamp(54px, 9vw, 100px) stays in one piece.
func tbBoxValues(_ decls: [String: String], _ base: String) -> [String] {
    var sides = ["", "", "", ""]
    if let shorthand = decls[base] {
        var tokens: [String] = []
        var depth = 0
        var current = ""
        for c in shorthand {
            if c == "(" { depth += 1 }
            else if c == ")" { depth -= 1 }
            if tbIsSpace(c) && depth == 0 {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        switch tokens.count {
        case 1: sides = [tokens[0], tokens[0], tokens[0], tokens[0]]
        case 2: sides = [tokens[0], tokens[1], tokens[0], tokens[1]]
        case 3: sides = [tokens[0], tokens[1], tokens[2], tokens[1]]
        default:
            if tokens.count >= 4 {
                sides = [tokens[0], tokens[1], tokens[2], tokens[3]]
            }
        }
    }
    let names = ["\(base)-top", "\(base)-right", "\(base)-bottom", "\(base)-left"]
    for i in 0..<4 {
        if let longhand = decls[names[i]] { sides[i] = longhand }
    }
    return sides
}

// One CSS length in points. px and pt are taken at face value;
// em is relative to the element's font size, rem to the root
// 14; % and vw resolve against a nominal 1000pt-wide page.
// clamp(), min(), and max() combine their arguments (clamp
// yields the middle of its three). "auto" and anything
// unparseable yield nil.
func tbLengthValue(_ raw: String?, fontSize: CGFloat) -> CGFloat? {
    guard let raw = raw else { return nil }
    let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if v.isEmpty || v == "auto" { return nil }
    for fn in ["clamp", "min", "max"] {
        if v.hasPrefix(fn + "(") && v.hasSuffix(")") {
            let inner = String(v.dropFirst(fn.count + 1).dropLast())
            var parts: [String] = []
            var depth = 0
            var current = ""
            for c in inner {
                if c == "(" { depth += 1 }
                else if c == ")" { depth -= 1 }
                if c == "," && depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            parts.append(current)
            var args: [CGFloat] = []
            for part in parts {
                if let value = tbLengthValue(part, fontSize: fontSize) {
                    args.append(value)
                }
            }
            if args.isEmpty { return nil }
            switch fn {
            case "min": return args.min()
            case "max": return args.max()
            default: return args.sorted()[args.count / 2]   // clamp: middle value
            }
        }
    }
    if v.hasSuffix("rem"), let d = Double(String(v.dropLast(3))) { return CGFloat(14 * d) }
    if v.hasSuffix("px"), let d = Double(String(v.dropLast(2))) { return CGFloat(d) }
    if v.hasSuffix("pt"), let d = Double(String(v.dropLast(2))) { return CGFloat(d) }
    if v.hasSuffix("em"), let d = Double(String(v.dropLast(2))) { return fontSize * CGFloat(d) }
    if v.hasSuffix("vw"), let d = Double(String(v.dropLast(2))) { return 1000 * CGFloat(d) / 100 }
    if v.hasSuffix("%"), let d = Double(String(v.dropLast(1))) { return 1000 * CGFloat(d) / 100 }
    if let d = Double(v) { return CGFloat(d) }
    return nil
}

// The fixed cap inside a width or max-width: the length the
// box settles at when the window is wide. A plain length is
// itself; min() is capped by its smallest fixed argument
// (percentage arguments only shrink it further); max() caps
// only when every argument is fixed.
func tbFixedCap(_ raw: String) -> CGFloat? {
    let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
    for fn in ["min", "max"] {
        if v.hasPrefix(fn + "(") && v.hasSuffix(")") {
            let inner = String(v.dropFirst(fn.count + 1).dropLast())
            var parts: [String] = []
            var depth = 0
            var current = ""
            for c in inner {
                if c == "(" { depth += 1 }
                else if c == ")" { depth -= 1 }
                if c == "," && depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(c)
                }
            }
            parts.append(current)
            let fixed = parts.compactMap { tbLengthValue($0, fontSize: 14) }
            if fn == "min" { return fixed.min() }
            return fixed.count == parts.count ? fixed.max() : nil
        }
    }
    return tbLengthValue(v, fontSize: 14)
}

struct TBBlockMetrics {
    var before: CGFloat = 0
    var after: CGFloat = 0
    var lineMultiple: CGFloat = 0
    var extraLineSpacing: CGFloat = 0
    var indent: CGFloat = 0
    var tailIndent: CGFloat = 0
    var hasAny: Bool {
        before > 0 || after > 0 || lineMultiple > 0
            || extraLineSpacing > 0 || indent > 0 || tailIndent > 0
    }
}

// A block's spacing in the text flow: margin + padding above
// and below become paragraph spacing, left/right become
// indents, and line-height becomes line spacing. Real box
// layout positions boxes on a surface; in a text flow these
// are the honest equivalents.
func tbBlockMetrics(_ decls: [String: String], fontSize: CGFloat) -> TBBlockMetrics {
    var m = TBBlockMetrics()
    let margin = tbBoxValues(decls, "margin")
    let padding = tbBoxValues(decls, "padding")
    func len(_ s: String) -> CGFloat { tbLengthValue(s, fontSize: fontSize) ?? 0 }
    m.before = min(max(len(margin[0]) + len(padding[0]), 0), 240)
    m.after = min(max(len(margin[2]) + len(padding[2]), 0), 240)
    m.indent = min(max(len(margin[3]) + len(padding[3]), 0), 400)
    m.tailIndent = min(max(len(margin[1]) + len(padding[1]), 0), 400)
    if let lh = decls["line-height"] {
        let v = lh.trimmingCharacters(in: .whitespaces).lowercased()
        if let multiple = Double(v) {
            m.lineMultiple = CGFloat(multiple)
        } else if v.hasSuffix("%"), let p = Double(String(v.dropLast(1))) {
            m.lineMultiple = CGFloat(p) / 100
        } else if let length = tbLengthValue(v, fontSize: fontSize) {
            m.extraLineSpacing = max(length - fontSize, 0)
        }
    }
    return m
}

extension TBRenderer {
        // MARK: - Positioned layout (0.17)

        func floatSide(_ raw: String?) -> TBFloatSide? {
            switch (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
            case "left": return .left
            case "right": return .right
            default: return nil
            }
        }

        func clearSide(_ raw: String?) -> TBClearSide? {
            switch (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
            case "left": return .left
            case "right": return .right
            case "both": return .both
            default: return nil
            }
        }

        // position:relative's shift: left wins over right and
        // top over bottom (the CSS rule for the over-constrained
        // case); percentages resolve against the nominal page
        // width, as lengths do throughout this engine.
        func relativeOffset(_ decls: [String: String], fontSize: CGFloat)
            -> (dx: CGFloat, dy: CGFloat)? {
            guard (decls["position"] ?? "").lowercased() == "relative" else { return nil }
            func length(_ raw: String?) -> CGFloat? {
                guard let raw = raw?.trimmingCharacters(in: .whitespaces),
                      !raw.isEmpty, raw.lowercased() != "auto" else { return nil }
                return tbLengthValue(raw, fontSize: fontSize)
            }
            var dx: CGFloat = 0
            var dy: CGFloat = 0
            if let left = length(decls["left"]) { dx = left }
            else if let right = length(decls["right"]) { dx = -right }
            if let top = length(decls["top"]) { dy = top }
            else if let bottom = length(decls["bottom"]) { dy = -bottom }
            return (dx, dy)
        }

        // Positioned layout (0.21): which out-of-flow
        // position a box declares, if any. Relative stays in
        // the flow (its offset is the 0.17 machinery above);
        // sticky stays in the flow too and is read in
        // walkBlock (0.26) — it is never an answer here.
        func positionKind(_ raw: String?) -> TBPositionKind? {
            switch (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
            case "absolute": return .absolute
            case "fixed": return .fixed
            default: return nil
            }
        }

        // One positioned inset, parsed: a length in points,
        // or a percentage kept raw — tbLengthValue would
        // resolve a percentage against the nominal width at
        // once, but an inset's percentage belongs to the
        // containing block (or the viewport), which only
        // the view knows. Missing and "auto" are nil.
        func insetValue(_ raw: String?, fontSize: CGFloat) -> TBInsetValue? {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces),
                  !raw.isEmpty else { return nil }
            let v = raw.lowercased()
            if v == "auto" { return nil }
            if v.hasSuffix("%"), let pct = Double(v.dropLast()) {
                return .percent(CGFloat(pct))
            }
            if let points = tbLengthValue(v, fontSize: fontSize) {
                return .points(points)
            }
            return nil
        }

        // z-index: an integer, or 0 for "auto" and anything
        // unparseable — the document order then decides, as
        // it does among equals in CSS.
        private func zIndexValue(_ raw: String?) -> Int {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces) else { return 0 }
            return Int(raw) ?? 0
        }

        // A box's four margin or padding lengths, in the
        // engine's [top, right, bottom, left] order.
        func boxLengths(_ decls: [String: String], _ property: String,
                                fontSize: CGFloat)
            -> (top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat) {
            let values = tbBoxValues(decls, property)
            func length(_ index: Int) -> CGFloat {
                guard index < values.count else { return 0 }
                return tbLengthValue(values[index], fontSize: fontSize) ?? 0
            }
            return (length(0), length(1), length(2), length(3))
        }

        // Does this block keep its floated children inside
        // itself? The CSS answers — a non-visible overflow, a
        // flow root, a table, a float of its own — plus this
        // engine's pragmatic one: a block that paints a surface
        // contains its floats, because on float-era pages a
        // backgrounded wrapper is expected to wrap them (see
        // the containment clear in walkBlock).
        func establishesContainment(_ own: [String: String]) -> Bool {
            for key in ["overflow", "overflow-x", "overflow-y"] {
                if let value = own[key]?.lowercased(),
                   ["hidden", "auto", "scroll", "clip"].contains(value) { return true }
            }
            let display = (own["display"] ?? "").lowercased()
            if display == "flow-root" || display == "table" { return true }
            if floatSide(own["float"]) != nil { return true }
            return tbBackgroundColor(own) != nil || backgroundBox(decls: own) != nil
        }

        func registerImageFloat(_ node: TBNode, own: [String: String],
                                        side: TBFloatSide, font: NSFont) {
            let src = (node.attrs["src"] ?? "").trimmingCharacters(in: .whitespaces)
            // A declared 1x1 is a tracking pixel, not a picture.
            let isPixel = node.attrs["width"] == "1" || node.attrs["height"] == "1"
            guard !src.isEmpty, !isPixel else { return }
            let ownFont = tbFontApplying(own, to: font)
            let declaredW = tbLengthValue(own["width"] ?? node.attrs["width"],
                                          fontSize: ownFont.pointSize)
            let declaredH = tbLengthValue(own["height"] ?? node.attrs["height"],
                                          fontSize: ownFont.pointSize)
            let spec = TBFloatSpec(anchorCharIndex: out.length, side: side, isImage: true,
                                   borderWidth: declaredW ?? 220,
                                   borderHeight: declaredH ?? 140)
            spec.widthDeclared = declaredW != nil
            spec.heightDeclared = declaredH != nil
            spec.alt = node.attrs["alt"] ?? ""
            let margins = boxLengths(own, "margin", fontSize: ownFont.pointSize)
            spec.marginTop = margins.top
            spec.marginRight = margins.right
            spec.marginBottom = margins.bottom
            spec.marginLeft = margins.left
            let absolute = src.hasPrefix("data:")
                ? src
                : (URL(string: src, relativeTo: URL(string: base))?.absoluteString ?? src)
            spec.boxShadows = boxShadowSet(own, color: nil,
                                           fontSize: ownFont.pointSize)
            spec.transformSpec = transformSpec(own,
                                               fontSize: ownFont.pointSize)
            spec.opacityValue = opacityValue(own) ?? 1
            layoutEvents.append(.float(spec))
            floatCount += 1
            floatImageJobs.append((spec: spec, url: absolute))
        }

        func registerBlockFloat(_ node: TBNode, own: [String: String],
                                        side: TBFloatSide, font: NSFont,
                                        color: NSColor?, align: NSTextAlignment) {
            let childFont = tbFontApplying(own, to: font)
            let fontSize = childFont.pointSize
            let margins = boxLengths(own, "margin", fontSize: fontSize)
            let padding = boxLengths(own, "padding", fontSize: fontSize)
            // A percentage width (0.25.0) is NOT resolved
            // here: tbLengthValue would settle it against a
            // flat thousand points, which is how a declared
            // 44% came out at 44% of a page the float had
            // never seen — wider than its own wrapper. The
            // percent is kept raw on the spec for the view
            // to resolve against the containing block's
            // real content width; the provisional below,
            // resolved against the nominal content width,
            // only stands in for this renderer's own
            // height measurement.
            var widthPercent: CGFloat? = nil
            var declaredW = tbLengthValue(own["width"], fontSize: fontSize)
            if let raw = own["width"]?.trimmingCharacters(in: .whitespaces)
                .lowercased(),
               raw.hasSuffix("%"), let pct = Double(raw.dropLast()), pct > 0 {
                widthPercent = CGFloat(pct)
                declaredW = CGFloat(pct) / 100
                    * max(nominalWidth - ancestorPaddingH, 10)
            }
            let declaredH = tbLengthValue(own["height"], fontSize: fontSize)
            let spec = TBFloatSpec(anchorCharIndex: out.length, side: side, isImage: false,
                                   borderWidth: declaredW ?? 0,
                                   borderHeight: declaredH ?? 0)
            // A floated anchor (0.37.3): the box IS the
            // link, so the seat carries the destination.
            if node.tag == "a", let href = node.attrs["href"], !href.isEmpty {
                spec.containerLink = URL(string: href,
                                         relativeTo: URL(string: base))?.absoluteString
                    ?? href
                if let link = spec.containerLink {
                    containerLinkSeats.append((kind: "float", link: link))
                }
            }
            spec.widthDeclared = declaredW != nil
            spec.heightDeclared = declaredH != nil
            spec.widthPercent = widthPercent
            spec.containingPaddingH = ancestorPaddingH
            spec.marginTop = margins.top
            spec.marginRight = margins.right
            spec.marginBottom = margins.bottom
            spec.marginLeft = margins.left
            spec.paddingTop = padding.top
            spec.paddingRight = padding.right
            spec.paddingBottom = padding.bottom
            spec.paddingLeft = padding.left
            spec.backgroundColor = tbBackgroundColor(own)
            spec.backgroundBox = backgroundBox(decls: own)
            spec.boxShadows = boxShadowSet(own, color: color,
                                           fontSize: fontSize)
            spec.transformSpec = transformSpec(own, fontSize: fontSize)
            spec.opacityValue = opacityValue(own) ?? 1
            // The float's contents render in a renderer of their
            // own — same rules, same base — which records no
            // layout events: a float inside a float simply flows.
            let sub = TBRenderer(base: base)
            sub.rules = rules
            sub.visitedURLs = visitedURLs
            sub.insideFloat = true
            sub.nominalWidth = nominalWidth
            sub.walkBlock(node: node, style: tbStyle(for: node.tag), baseFont: childFont,
                          color: color, align: align,
                          inheritedBackground: nil, inheritedBackgroundBox: nil)
            layoutEvents.append(.float(spec))
            floatCount += 1
            pendingBlockFloats.append((spec: spec, sub: sub))
        }

        // Measure text the way the view will lay it out: its
        // own layout manager and container, at a given width.
        func measureText(_ string: NSAttributedString, width: CGFloat) -> CGSize {
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

        // A block float's contents are finished (its pictures
        // fetched, its failures labelled): take out what
        // cannot work inside a painted box — the [n] markers
        // (they point into the page's link list, which this
        // box is not part of), and the form controls, for
        // which bracketed labels stand in — then size the
        // box: a declared width wins, else the box shrinks
        // to its contents' natural width, capped at the
        // column; a declared height wins, else the measured
        // height of the contents at the final width. Links
        // inside a floated box kept their colors in 0.17 but
        // were not clickable — the box was paint, not text;
        // since 0.36 they keep their targets too, and the
        // view hit-tests the painted box and follows them.
        private func finalizeBlockFloat(spec: TBFloatSpec, sub: TBRenderer) {
            let cleaned = NSMutableAttributedString(attributedString: sub.out)
            var swaps: [(range: NSRange, text: String)] = []
            cleaned.enumerateAttribute(
                .attachment, in: NSRange(location: 0, length: cleaned.length)
            ) { value, range, _ in
                if let submit = value as? TBSubmitAttachment {
                    swaps.append((range: range, text: " [\(submit.label)] "))
                } else if let field = value as? TBFieldAttachment {
                    let name = sub.fields.first { $0.id == field.fieldID }
                        .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                    swaps.append((range: range, text: " [\(name)] "))
                } else if let select = value as? TBSelectAttachment {
                    // Live controls (0.31): the popup stands
                    // in for its resting choice's label.
                    let label = select.selectedIndex >= 0
                        && select.selectedIndex < select.options.count
                        ? select.options[select.selectedIndex].label : "select"
                    swaps.append((range: range, text: " [\(label)] "))
                } else if let area = value as? TBTextAreaAttachment {
                    let name = sub.fields.first { $0.id == area.fieldID }
                        .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                    swaps.append((range: range, text: " [\(name)] "))
                }
            }
            cleaned.enumerateAttribute(
                .link, in: NSRange(location: 0, length: cleaned.length)
            ) { _, range, _ in
                let text = (cleaned.string as NSString).substring(with: range)
                if text.hasPrefix(" ["), text.hasSuffix("]") {
                    let digits = text.dropFirst(2).dropLast()
                    if !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) {
                        swaps.append((range: range, text: ""))
                    }
                }
            }
            for swap in swaps.sorted(by: { $0.range.location > $1.range.location }) {
                cleaned.replaceCharacters(in: swap.range, with: NSAttributedString(
                    string: swap.text,
                    attributes: [.font: NSFont.systemFont(ofSize: 12),
                                 .foregroundColor: NSColor.secondaryLabelColor]))
            }
            // The speed stage (0.36): the box's links
            // KEEP their targets — the view hit-tests
            // painted boxes now and follows them. The
            // [n] markers above still come out: they
            // numbered the page's flow links, not the
            // box's own.
            spec.content = cleaned
            let padH = spec.paddingLeft + spec.paddingRight
            let padV = spec.paddingTop + spec.paddingBottom
            // Flexbox (0.24): a flex container inside this
            // box was walked against the page's nominal
            // width; correct it to the width it stands in
            // here, now that this box's own width is final.
            // Grid (0.25): a grid container inside the box
            // is corrected by the same pass to the same
            // width — one finalize path serves both.
            correctFlexSeats(in: cleaned,
                             availableWidth: max(spec.borderWidth - padH, 10))
            correctGridSeats(in: cleaned,
                             availableWidth: max(spec.borderWidth - padH, 10))
            if !spec.widthDeclared {
                let natural = measureText(cleaned, width: nominalWidth).width
                spec.borderWidth = min(max(natural + padH, 1), nominalWidth)
            }
            if !spec.heightDeclared {
                let contentWidth = max(spec.borderWidth - padH, 10)
                spec.borderHeight = measureText(cleaned, width: contentWidth).height + padV
            }
            spec.borderWidth = max(spec.borderWidth, 1)
            spec.borderHeight = max(spec.borderHeight, 1)
        }

}

extension TBRenderer {
        // MARK: - Multi-column layout (0.22)

        // Split a declaration value at spaces outside
        // parentheses — the token walk tbBoxValues does for
        // box values, needed again here because a shorthand's
        // color may be a function with spaces of its own (a
        // color-mix, an rgb()).
        func valueTokens(_ raw: String) -> [String] {
            var tokens: [String] = []
            var depth = 0
            var current = ""
            for c in raw {
                if c == "(" { depth += 1 }
                else if c == ")" { depth -= 1 }
                if tbIsSpace(c) && depth == 0 {
                    if !current.isEmpty { tokens.append(current); current = "" }
                } else {
                    current.append(c)
                }
            }
            if !current.isEmpty { tokens.append(current) }
            return tokens
        }

        // column-rule, shorthand first and longhands over it,
        // token by token: a width (a length, or thin / medium
        // / thick), a style word, and a color — in whatever
        // order the page wrote them, as CSS allows. Defaults
        // are the spec's own: medium width, no style (so no
        // rule paints), and no color — the caller substitutes
        // the element's text color, currentColor as directed.
        private func columnRule(_ own: [String: String], fontSize: CGFloat)
            -> (width: CGFloat, style: String, color: NSColor?) {
            var width: CGFloat? = nil
            var style: String? = nil
            var color: NSColor? = nil
            let styles: Set<String> = ["none", "hidden", "dotted", "dashed",
                                       "solid", "double", "groove", "ridge",
                                       "inset", "outset"]
            func widthWord(_ t: String) -> CGFloat? {
                switch t {
                case "thin": return 1
                case "medium": return 3
                case "thick": return 5
                default: return tbLengthValue(t, fontSize: fontSize)
                }
            }
            func read(_ raw: String) {
                for token in valueTokens(raw) {
                    let t = token.lowercased()
                    if styles.contains(t) { style = t }
                    else if let w = widthWord(t) { width = w }
                    else if let c = tbParseColor(token) { color = c }
                }
            }
            if let shorthand = own["column-rule"] { read(shorthand) }
            if let raw = own["column-rule-style"] {
                let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if styles.contains(t) { style = t }
            }
            if let raw = own["column-rule-width"],
               let w = widthWord(raw.trimmingCharacters(in: .whitespaces)
                                    .lowercased()) {
                width = w
            }
            if let c = tbParseColor(own["column-rule-color"]) { color = c }
            return (width ?? 3, style ?? "none", color)
        }

        // The interaction set (0.26): a border's or an
        // outline's three parts, read the column rule's way —
        // the shorthand's tokens in whatever order (a width,
        // a style word, a color), then the longhands over
        // them. For a border, a per-side width (border-top-
        // width and kin) answers when no uniform width is
        // declared; the control that wears the border is
        // small enough that one width serves all four sides.
        // The defaults are the spec's own: medium width,
        // style none (so nothing paints).
        private func borderParts(_ decls: [String: String], base: String,
                                 fontSize: CGFloat)
            -> (width: CGFloat, style: String, color: NSColor?) {
            var width: CGFloat? = nil
            var style: String? = nil
            var color: NSColor? = nil
            let styles: Set<String> = ["none", "hidden", "dotted", "dashed",
                                       "solid", "double", "groove", "ridge",
                                       "inset", "outset"]
            func widthWord(_ t: String) -> CGFloat? {
                switch t {
                case "thin": return 1
                case "medium": return 3
                case "thick": return 5
                default: return tbLengthValue(t, fontSize: fontSize)
                }
            }
            func read(_ raw: String) {
                for token in valueTokens(raw) {
                    let t = token.lowercased()
                    if styles.contains(t) { style = t }
                    else if let w = widthWord(t) { width = w }
                    else if let c = tbParseColor(token) { color = c }
                }
            }
            if let shorthand = decls[base] { read(shorthand) }
            if let raw = decls["\(base)-style"] {
                let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if styles.contains(t) { style = t }
            }
            if let raw = decls["\(base)-width"],
               let w = widthWord(raw.trimmingCharacters(in: .whitespaces)
                                    .lowercased()) {
                width = w
            }
            if base == "border", width == nil {
                for side in ["top", "right", "bottom", "left"] {
                    if let raw = decls["border-\(side)-width"],
                       let w = widthWord(raw.trimmingCharacters(
                                            in: .whitespaces).lowercased()) {
                        width = w
                        break
                    }
                }
            }
            if let c = tbParseColor(decls["\(base)-color"]) { color = c }
            return (width ?? 3, style ?? "none", color)
        }

        // The interaction set (0.26): one live control's
        // style, resolved from its element: the resting
        // traits from its computed declarations, and the
        // focus and active traits from its state
        // resolutions — the border a focus wears, and the
        // outline a page declares for the focus, which the
        // view rides as the control's border ring while
        // the focus lasts. Padding is not carried: a
        // native field's text inset is AppKit's own, and
        // the seat already honors the declared width.
        func controlStyle(node: TBNode, own: [String: String],
                                  font: NSFont) -> TBControlStyle {
            let style = TBControlStyle()
            style.font = font
            style.textColor = tbParseColor(own["color"])
            style.backgroundColor = tbBackgroundColor(own)
            let border = borderParts(own, base: "border",
                                     fontSize: font.pointSize)
            if border.style != "none" && border.style != "hidden"
                && border.width > 0 {
                style.borderColor = border.color
                style.borderWidth = border.width
            }
            if let raw = own["border-radius"],
               let first = valueTokens(raw).first,
               let radius = tbLengthValue(first, fontSize: font.pointSize) {
                style.cornerRadius = radius
            }
            if focusRulePresent {
                let decls = resolvedFocusStyle(node: node)
                if !decls.isEmpty {
                    style.focusTextColor = tbParseColor(decls["color"])
                    style.focusBackgroundColor = tbBackgroundColor(decls)
                    let focusBorder = borderParts(decls, base: "border",
                                                  fontSize: font.pointSize)
                    if focusBorder.style != "none"
                        && focusBorder.style != "hidden" {
                        style.focusBorderColor = focusBorder.color
                    }
                    let outline = borderParts(decls, base: "outline",
                                              fontSize: font.pointSize)
                    if outline.style != "none" && outline.style != "hidden"
                        && outline.width > 0, let outlineColor = outline.color {
                        style.outlineColor = outlineColor
                        style.outlineWidth = outline.width
                    }
                }
            }
            if activeRulePresent {
                let decls = resolvedActiveStyle(node: node)
                if !decls.isEmpty {
                    style.activeTextColor = tbParseColor(decls["color"])
                    style.activeBackgroundColor = tbBackgroundColor(decls)
                }
            }
            return style
        }

        // A block's column declarations, resolved to the
        // geometry the columns will stand in — or nil when
        // the block declares no columns, or they resolve to
        // a single column: one column is just the flow, and
        // the painted-box bargain (below) is not worth
        // striking for it.
        func multiColumnSpec(_ own: [String: String],
                                     fontSize: CGFloat,
                                     totalWidth: CGFloat) -> TBMultiColumnSpec? {
            var count: Int? = nil
            var width: CGFloat? = nil
            if let shorthand = own["columns"] {
                for token in valueTokens(shorthand) {
                    let t = token.lowercased()
                    if t == "auto" { continue }
                    if let n = Int(t) { count = n }
                    else if let w = tbLengthValue(t, fontSize: fontSize) { width = w }
                }
            }
            if let raw = own["column-count"],
               let n = Int(raw.trimmingCharacters(in: .whitespaces)) {
                count = n
            }
            if let w = tbLengthValue(own["column-width"], fontSize: fontSize) {
                width = w
            }
            guard count != nil || width != nil, totalWidth >= 120 else { return nil }
            // column-gap: a length, or `normal` — the spec's
            // own word for 1em of the block's font, which is
            // also the gap when the page declares none.
            var gap = fontSize
            if let raw = own["column-gap"]?.lowercased()
                .trimmingCharacters(in: .whitespaces),
               raw != "normal", let value = tbLengthValue(raw, fontSize: fontSize) {
                gap = max(0, value)
            }
            var n: Int
            if let w = width, w > 0 {
                // The spec's formula for a declared width: as
                // many columns as the block's width holds,
                // gaps between them — and a declared count, if
                // there is one too, only ever lowers that.
                let fit = max(1, Int(((totalWidth + gap) / (w + gap)).rounded(.down)))
                n = count.map { min($0, fit) } ?? fit
            } else if let c = count {
                n = c
            } else {
                return nil
            }
            n = max(1, min(n, 12))
            // A column narrower than 60 points cannot hold
            // text honestly; shed columns until each can.
            while n > 1 && (totalWidth - CGFloat(n - 1) * gap) / CGFloat(n) < 60 {
                n -= 1
            }
            guard n >= 2 else { return nil }
            let columnWidth = (totalWidth - CGFloat(n - 1) * gap) / CGFloat(n)
            let spec = TBMultiColumnSpec(columnCount: n, columnWidth: columnWidth,
                                         gap: gap, totalWidth: totalWidth)
            let rule = columnRule(own, fontSize: fontSize)
            spec.ruleWidth = rule.width
            spec.ruleStyle = rule.style
            spec.ruleColor = rule.color
            return spec
        }

        // The balanced height of a block's contents laid
        // across `count` columns of one width: the smallest
        // container height at which the layout manager's own
        // chaining — down one container, continuing at the
        // top of the next — gets every character laid. Found
        // by binary search between a point and the height the
        // contents stand at in a single column; the search
        // IS the balancing real CSS does, measured with the
        // same containers the view will paint from, so the
        // number the seat reserves is the number the paint
        // needs. (Trailing separator newlines are discounted
        // from the target: whether the last empty paragraph
        // earns a glyph is the layout manager's business, and
        // a column plan must not hinge on it.)
        private func balanceColumns(_ content: NSAttributedString,
                                    count: Int, columnWidth: CGFloat) -> CGFloat {
            guard content.length > 0, count > 0 else { return 0 }
            let full = measureText(content, width: columnWidth).height
            guard full > 0 else { return 0 }
            var target = content.length
            let string = content.string as NSString
            while target > 0 && string.character(at: target - 1) == 10 {
                target -= 1
            }
            func fits(_ height: CGFloat) -> Bool {
                let storage = NSTextStorage(attributedString: content)
                let manager = NSLayoutManager()
                storage.addLayoutManager(manager)
                var containers: [NSTextContainer] = []
                for _ in 0..<count {
                    let container = NSTextContainer(
                        size: NSSize(width: columnWidth, height: height))
                    manager.addTextContainer(container)
                    containers.append(container)
                }
                guard let last = containers.last else { return true }
                manager.ensureLayout(for: last)
                var laid = 0
                for container in containers {
                    let glyphs = manager.glyphRange(for: container)
                    if glyphs.length > 0 {
                        laid = max(laid, NSMaxRange(manager.characterRange(
                            forGlyphRange: glyphs, actualGlyphRange: nil)))
                    }
                }
                return laid >= target
            }
            var lo: CGFloat = 1
            var hi = full
            var probes = 0
            while hi - lo > 1 && probes < 24 {
                probes += 1
                let mid = (lo + hi) / 2
                if fits(mid) { hi = mid } else { lo = mid }
            }
            return hi
        }

        // A multicolumn block, walked: its contents render in
        // a renderer of their own — same rules, same base —
        // which records no layout events (inside the columns,
        // floats, positioned boxes and further column blocks
        // simply flow, the way they do inside a floated box),
        // and the block takes its place in this renderer's
        // flow as a single seat: one attachment character as
        // wide and as tall as the balanced columns, in a
        // paragraph carrying the spacing and surface stamps
        // flush would have given the block's own first
        // paragraph. The view resolves the seat's line and
        // paints the columns into it.
        func renderColumns(node: TBNode, spec: TBMultiColumnSpec,
                                   font: NSFont, color: NSColor?,
                                   align: NSTextAlignment,
                                   background: NSColor?,
                                   backgroundBox: TBBackgroundBox?,
                                   metrics: TBBlockMetrics,
                                   ownSurface: Bool) -> Bool {
            // The paint & motion set (0.27): column-span:
            // all — a block child declaring it breaks the
            // column flow, so the children are first cut
            // into segments at each spanner. Every segment
            // is rendered by a sub-renderer of its own that
            // walks this node under a filter admitting only
            // its segment's children, and the segments
            // become the spec's parts in order: column runs
            // balanced at the column width, spanners
            // measured at the full width. With no spanner
            // there is one segment, and the path below is
            // the one 0.22 built.
            var segments: [(children: [TBNode], isSpanner: Bool)] = []
            var current: [TBNode] = []
            for child in node.children {
                if columnSpanner(child) {
                    segments.append((children: current, isSpanner: false))
                    current = []
                    segments.append((children: [child], isSpanner: true))
                } else {
                    current.append(child)
                }
            }
            segments.append((children: current, isSpanner: false))
            var parts: [TBColumnPart] = []
            var subs: [(part: TBColumnPart, sub: TBRenderer)] = []
            var totalHeight: CGFloat = 0
            for segment in segments {
                if segment.children.isEmpty { continue }
                let sub = TBRenderer(base: base)
                sub.rules = rules
                sub.visitedURLs = visitedURLs
                sub.insideFloat = true
                sub.nominalWidth = segment.isSpanner
                    ? spec.totalWidth : nominalWidth
                sub.columnChildFilter = Set(
                    segment.children.map { ObjectIdentifier($0) })
                sub.walkBlock(node: node, style: tbStyle(for: node.tag),
                              baseFont: font, color: color, align: align,
                              inheritedBackground: nil,
                              inheritedBackgroundBox: nil)
                let visible = (sub.out.string as NSString)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if visible.isEmpty { continue }
                let part = TBColumnPart()
                part.isSpanner = segment.isSpanner
                part.content = sub.out
                part.height = segment.isSpanner
                    ? ceil(measureText(sub.out, width: spec.totalWidth).height)
                    : balanceColumns(sub.out, count: spec.columnCount,
                                     columnWidth: spec.columnWidth)
                parts.append(part)
                subs.append((part: part, sub: sub))
                totalHeight += part.height
            }
            guard !parts.isEmpty else { return false }
            spec.parts = parts
            spec.content = parts.first?.content
            spec.columnHeight = parts.first(where: { !$0.isSpanner })?.height ?? 0
            spec.totalHeight = totalHeight
            let seat = TBColumnSeatAttachment()
            seat.image = tbClearSeat(width: spec.totalWidth,
                                     height: spec.totalHeight)
            seat.bounds = CGRect(x: 0, y: 0, width: spec.totalWidth,
                                 height: spec.totalHeight)
            spec.seat = seat
            let para = NSMutableAttributedString(attributedString: NSAttributedString(attachment: seat))
            para.addAttribute(.font, value: font,
                              range: NSRange(location: 0, length: para.length))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            if spaceCarry > 0 { paragraph.paragraphSpacingBefore = spaceCarry }
            if metrics.after > 0 { paragraph.paragraphSpacing = metrics.after }
            if metrics.indent > 0 {
                paragraph.headIndent = metrics.indent
                paragraph.firstLineHeadIndent = metrics.indent
            }
            if metrics.tailIndent > 0 { paragraph.tailIndent = -metrics.tailIndent }
            para.addAttribute(.paragraphStyle, value: paragraph,
                              range: NSRange(location: 0, length: para.length))
            if let background = background {
                para.addAttribute(.backgroundColor, value: background,
                                  range: NSRange(location: 0, length: para.length))
            }
            let paraStart = out.length
            spec.anchorCharIndex = paraStart
            out.append(para)
            lastFlushRange = NSRange(location: paraStart, length: para.length)
            if relDX != 0 || relDY != 0 {
                out.addAttribute(TBRelOffsetKey,
                                 value: NSValue(point: NSPoint(x: relDX, y: relDY)),
                                 range: NSRange(location: paraStart,
                                                length: para.length))
            }
            if !pendingClears.isEmpty {
                for clearSpec in pendingClears {
                    clearSpec.anchorCharIndex = paraStart
                }
                pendingClears = []
            }
            var separatorAttrs: [NSAttributedString.Key: Any] = [:]
            if let background = background {
                separatorAttrs[.backgroundColor] = background
            }
            if let backgroundBox = backgroundBox {
                separatorAttrs[TBBackgroundKey] = backgroundBox
            }
            out.append(NSAttributedString(string: "\n\n", attributes: separatorAttrs))
            noteSurfaceParagraph(
                range: NSRange(location: paraStart, length: para.length),
                color: background, box: backgroundBox,
                after: metrics.after, ownSurface: ownSurface)
            spaceCarry = 0
            layoutEvents.append(.columns(spec))
            if let link = spec.containerLink {
                containerLinkSeats.append((kind: "columns", link: link))
            }
            pendingColumns.append((spec: spec, subs: subs))
            return true
        }

        // A multicolumn block's contents are finished (its
        // pictures fetched, its failures labelled): strip
        // what cannot work inside a painted box — the link
        // targets and their [n] markers, and the form
        // controls, for which bracketed labels stand in —
        // exactly the cleaning a floated box's contents get —
        // then measure the part again on the finished text:
        // a column run re-balances, a spanner re-measures
        // at the full width (0.27).
        private func finalizeColumnPart(spec: TBMultiColumnSpec,
                                        part: TBColumnPart, sub: TBRenderer) {
            let cleaned = NSMutableAttributedString(attributedString: sub.out)
            var swaps: [(range: NSRange, text: String)] = []
            cleaned.enumerateAttribute(
                .attachment, in: NSRange(location: 0, length: cleaned.length)
            ) { value, range, _ in
                if let submit = value as? TBSubmitAttachment {
                    swaps.append((range: range, text: " [\(submit.label)] "))
                } else if let field = value as? TBFieldAttachment {
                    let name = sub.fields.first { $0.id == field.fieldID }
                        .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                    swaps.append((range: range, text: " [\(name)] "))
                } else if let select = value as? TBSelectAttachment {
                    // Live controls (0.31): the popup stands
                    // in for its resting choice's label.
                    let label = select.selectedIndex >= 0
                        && select.selectedIndex < select.options.count
                        ? select.options[select.selectedIndex].label : "select"
                    swaps.append((range: range, text: " [\(label)] "))
                } else if let area = value as? TBTextAreaAttachment {
                    let name = sub.fields.first { $0.id == area.fieldID }
                        .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                    swaps.append((range: range, text: " [\(name)] "))
                }
            }
            cleaned.enumerateAttribute(
                .link, in: NSRange(location: 0, length: cleaned.length)
            ) { _, range, _ in
                let text = (cleaned.string as NSString).substring(with: range)
                if text.hasPrefix(" ["), text.hasSuffix("]") {
                    let digits = text.dropFirst(2).dropLast()
                    if !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) {
                        swaps.append((range: range, text: ""))
                    }
                }
            }
            for swap in swaps.sorted(by: { $0.range.location > $1.range.location }) {
                cleaned.replaceCharacters(in: swap.range, with: NSAttributedString(
                    string: swap.text,
                    attributes: [.font: NSFont.systemFont(ofSize: 12),
                                 .foregroundColor: NSColor.secondaryLabelColor]))
            }
            // The speed stage (0.36): the box's links
            // KEEP their targets — the view hit-tests
            // painted boxes now and follows them. The
            // [n] markers above still come out: they
            // numbered the page's flow links, not the
            // box's own.
            part.content = cleaned
            // Flexbox (0.24) and grid (0.25): a container
            // inside the part was walked against the page's
            // nominal width; it is corrected to the width
            // the part truly stands in — the column's for a
            // column run, the block's whole width for a
            // spanner.
            let partWidth = part.isSpanner ? spec.totalWidth : spec.columnWidth
            correctFlexSeats(in: cleaned, availableWidth: partWidth)
            correctGridSeats(in: cleaned, availableWidth: partWidth)
            part.height = part.isSpanner
                ? ceil(measureText(cleaned, width: spec.totalWidth).height)
                : balanceColumns(cleaned, count: spec.columnCount,
                                 columnWidth: spec.columnWidth)
        }

        // Arrivals for the multicolumn blocks (0.22): each
        // part's own pictures and backgrounds land first,
        // then its contents are cleaned and re-measured —
        // the same two-stage life the block floats lead —
        // and the seat in the page is corrected to the
        // final height, so the re-installed page reserves
        // the truth.
        func finishColumns() async {
            for pending in pendingColumns {
                for entry in pending.subs {
                    await entry.sub.finishImages()
                    await entry.sub.finishBackgrounds()
                    await entry.sub.finishFlex()
                    await entry.sub.finishGrid()
                    finalizeColumnPart(spec: pending.spec, part: entry.part,
                                       sub: entry.sub)
                }
                let spec = pending.spec
                spec.totalHeight = spec.parts.reduce(0) { $0 + $1.height }
                spec.columnHeight = spec.parts
                    .first(where: { !$0.isSpanner })?.height ?? 0
                spec.content = spec.parts.first?.content
                if let seat = spec.seat {
                    seat.image = tbClearSeat(width: spec.totalWidth,
                                             height: spec.totalHeight)
                    seat.bounds = CGRect(x: 0, y: 0, width: spec.totalWidth,
                                         height: spec.totalHeight)
                }
            }
            pendingColumns = []
        }

}

extension TBRenderer {
        // MARK: - Flexbox (0.24)

        // One length as flex reads it: a plain percentage
        // is kept as a percentage (its base is the flex
        // container's own size, which only the layout pass
        // knows); anything else resolves to points through
        // the ordinary length reader. "auto" and the
        // unreadable yield nil.
        func flexLength(_ raw: String?,
                                fontSize: CGFloat) -> TBInsetValue? {
            guard let raw = raw?.trimmingCharacters(in: .whitespaces)
                    .lowercased(),
                  !raw.isEmpty, raw != "auto" else { return nil }
            if raw.hasSuffix("%"), let pct = Double(raw.dropLast()) {
                return .percent(CGFloat(pct))
            }
            if let value = tbLengthValue(raw, fontSize: fontSize) {
                return .points(value)
            }
            return nil
        }

        // A flex length against its base: points are
        // themselves; a percentage of an indefinite base
        // resolves to nothing, and the caller reads that
        // as the spec directs (usually: as content).
        func resolveFlexLength(_ value: TBInsetValue?,
                                       against base: CGFloat?) -> CGFloat? {
            guard let value = value else { return nil }
            switch value {
            case .points(let v): return v
            case .percent(let pct): return base.map { $0 * pct / 100 }
            }
        }

        // The alignment words align-items and align-self
        // share, normalized; anything else (or nothing)
        // yields nil, and the caller substitutes its
        // default.
        private func flexAlignWord(_ raw: String?) -> String? {
            guard let v = raw?.trimmingCharacters(in: .whitespaces)
                    .lowercased() else { return nil }
            switch v {
            case "flex-start", "start", "self-start": return "flex-start"
            case "flex-end", "end", "self-end": return "flex-end"
            case "center": return "center"
            case "stretch": return "stretch"
            case "baseline": return "baseline"
            default: return nil
            }
        }

        // A block's flex declarations, resolved to the
        // spec the layout pass works from — or nil when
        // the block is no flex container. The container's
        // width is the flow's span for the block, capped
        // by a declared width or max-width (a declared
        // percentage against the containing block's
        // content width as this renderer knows it — the
        // nominal width less the ancestors' padding, the
        // float widths' own precedent — never the length
        // parser's flat thousand). A declared height is
        // kept as the content height it implies; a
        // percentage height resolves against the
        // definite height of the block ancestor the walk
        // has open (0.30), and reads as no height where
        // none is definite.
        func flexContainerSpec(_ own: [String: String],
                                       fontSize: CGFloat,
                                       metrics: TBBlockMetrics)
            -> TBFlexSpec? {
            let display = (own["display"] ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard display == "flex" || display == "inline-flex"
            else { return nil }
            var direction: TBFlexDirection = .row
            var wraps = false
            var wrapReverse = false
            func directionWord(_ t: String) {
                switch t {
                case "row": direction = .row
                case "row-reverse": direction = .rowReverse
                case "column": direction = .column
                case "column-reverse": direction = .columnReverse
                default: break
                }
            }
            func wrapWord(_ t: String) {
                switch t {
                case "wrap": wraps = true; wrapReverse = false
                case "nowrap": wraps = false; wrapReverse = false
                // wrap-reverse (0.30): the cross axis runs
                // flipped — the layout measures every
                // cross answer from the cross end.
                case "wrap-reverse": wraps = true; wrapReverse = true
                default: break
                }
            }
            if let flow = own["flex-flow"] {
                for token in valueTokens(flow) {
                    let t = token.lowercased()
                    directionWord(t)
                    wrapWord(t)
                }
            }
            if let raw = own["flex-direction"] {
                directionWord(raw.trimmingCharacters(in: .whitespaces)
                                .lowercased())
            }
            if let raw = own["flex-wrap"] {
                wrapWord(raw.trimmingCharacters(in: .whitespaces)
                            .lowercased())
            }
            var justify = "flex-start"
            switch (own["justify-content"] ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased() {
            case "flex-end", "end": justify = "flex-end"
            case "center": justify = "center"
            case "space-between": justify = "space-between"
            case "space-around": justify = "space-around"
            case "space-evenly": justify = "space-evenly"
            default: break
            }
            let alignItems = flexAlignWord(own["align-items"]) ?? "stretch"
            // align-content (0.30): the same distribution
            // words justify-content reads, with stretch
            // admitted — a wrapped stack's lines grow
            // into the leftover alike.
            var alignContent = "flex-start"
            switch (own["align-content"] ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased() {
            case "flex-end", "end": alignContent = "flex-end"
            case "center": alignContent = "center"
            case "space-between": alignContent = "space-between"
            case "space-around": alignContent = "space-around"
            case "space-evenly": alignContent = "space-evenly"
            case "stretch", "normal": alignContent = "stretch"
            default: break
            }
            // The gaps: the shorthand first (one value for
            // both axes, or row then column), the longhands
            // over it — the box shorthands' own convention.
            var gapRow: TBInsetValue? = nil
            var gapColumn: TBInsetValue? = nil
            if let raw = own["gap"] {
                let tokens = valueTokens(raw)
                if let first = tokens.first,
                   let v = flexLength(first, fontSize: fontSize) {
                    gapRow = v
                    gapColumn = v
                }
                if tokens.count > 1,
                   let v = flexLength(tokens[1], fontSize: fontSize) {
                    gapColumn = v
                }
            }
            if let v = flexLength(own["row-gap"], fontSize: fontSize) {
                gapRow = v
            }
            if let v = flexLength(own["column-gap"], fontSize: fontSize) {
                gapColumn = v
            }
            let padding = boxLengths(own, "padding", fontSize: fontSize)
            let padH = padding.left + padding.right
            let padV = padding.top + padding.bottom
            var contentW = nominalWidth - metrics.indent - metrics.tailIndent
            var widthCap: CGFloat? = nil
            if let declared = flexLength(own["width"], fontSize: fontSize) {
                let borderW: CGFloat?
                switch declared {
                case .points(let v): borderW = v
                case .percent(let pct):
                    // The containing block's content width:
                    // the accumulated padding of the
                    // ancestors, without this block's own —
                    // the accumulation the walk keeps
                    // includes it by the time this runs.
                    borderW = pct / 100
                        * max(nominalWidth - ancestorPaddingH + padH, 10)
                }
                if let bw = borderW {
                    contentW = min(contentW, max(bw - padH, 10))
                    widthCap = contentW
                }
            }
            if let maxDecl = flexLength(own["max-width"], fontSize: fontSize),
               case .points(let v) = maxDecl {
                contentW = min(contentW, max(v - padH, 10))
                widthCap = contentW
            }
            contentW = max(contentW, 10)
            // Heights (0.30): a height in points stands
            // as the content height it implies; a
            // percentage resolves against the definite
            // height the walk has open above this block,
            // and against nothing reads as no height at
            // all — the clamps resolve the same way.
            var declaredHeight: CGFloat? = nil
            if let declared = flexLength(own["height"], fontSize: fontSize),
               let v = resolveFlexLength(declared,
                                         against: definiteAncestorHeight) {
                declaredHeight = max(v - padV, 0)
            }
            var minHeightClamp: CGFloat? = nil
            var maxHeightClamp: CGFloat? = nil
            if let declared = flexLength(own["min-height"], fontSize: fontSize),
               let v = resolveFlexLength(declared,
                                         against: definiteAncestorHeight) {
                minHeightClamp = max(v - padV, 0)
            }
            if let declared = flexLength(own["max-height"], fontSize: fontSize),
               let v = resolveFlexLength(declared,
                                         against: definiteAncestorHeight) {
                maxHeightClamp = max(v - padV, 0)
            }
            let spec = TBFlexSpec(direction: direction, totalWidth: contentW)
            spec.wraps = wraps
            spec.justify = justify
            spec.alignItems = alignItems
            spec.alignContent = alignContent
            spec.wrapReverse = wrapReverse
            spec.gapRow = gapRow
            spec.gapColumn = gapColumn
            spec.declaredHeight = declaredHeight
            spec.minHeightClamp = minHeightClamp
            spec.maxHeightClamp = maxHeightClamp
            spec.declaredContentWidth = widthCap
            spec.flowIndent = metrics.indent
            spec.flowTailIndent = metrics.tailIndent
            return spec
        }

        // An item's flex properties from its declarations:
        // the flex shorthand first (its standard spellings:
        // none, auto, initial, a lone grow factor, a lone
        // basis, or grow, shrink and basis in their
        // order-flexible forms), the longhands over it —
        // the order the engine reads every shorthand — then
        // order, alignment, sizes and clamps, margins and
        // padding, and the backgrounds the painter needs.
        private func dressFlexItem(_ item: TBFlexItem,
                                   own: [String: String],
                                   fontSize: CGFloat) {
            if let raw = own["flex"] {
                let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if v == "none" {
                    item.grow = 0
                    item.shrink = 0
                    item.basis = nil
                    item.basisContent = false
                } else if v == "auto" {
                    item.grow = 1
                    item.shrink = 1
                    item.basis = nil
                    item.basisContent = false
                } else if v == "initial" {
                    item.grow = 0
                    item.shrink = 1
                    item.basis = nil
                    item.basisContent = false
                } else {
                    var numbers: [Double] = []
                    var basisSet = false
                    for token in valueTokens(v) {
                        if let n = Double(token) {
                            numbers.append(n)
                        } else if token == "auto" {
                            item.basis = nil
                            item.basisContent = false
                            basisSet = true
                        } else if token == "content" {
                            item.basis = nil
                            item.basisContent = true
                            basisSet = true
                        } else if let length = flexLength(token,
                                                          fontSize: fontSize) {
                            item.basis = length
                            item.basisContent = false
                            basisSet = true
                        }
                    }
                    if let g = numbers.first { item.grow = g }
                    if numbers.count > 1 { item.shrink = numbers[1] }
                    if !basisSet, !numbers.isEmpty {
                        // A factor alone (or two) leaves the
                        // basis at the shorthand's own zero.
                        item.basis = .percent(0)
                        item.basisContent = false
                    } else if numbers.isEmpty, basisSet {
                        item.grow = 1
                        item.shrink = 1
                    }
                }
            }
            if let raw = own["flex-grow"],
               let n = Double(raw.trimmingCharacters(in: .whitespaces)) {
                item.grow = n
            }
            if let raw = own["flex-shrink"],
               let n = Double(raw.trimmingCharacters(in: .whitespaces)) {
                item.shrink = n
            }
            item.grow = max(0, item.grow)
            item.shrink = max(0, item.shrink)
            if let raw = own["flex-basis"] {
                let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if v == "auto" {
                    item.basis = nil
                    item.basisContent = false
                } else if v == "content" {
                    item.basis = nil
                    item.basisContent = true
                } else if let length = flexLength(v, fontSize: fontSize) {
                    item.basis = length
                    item.basisContent = false
                }
            }
            if let raw = own["order"],
               let n = Int(raw.trimmingCharacters(in: .whitespaces)) {
                item.order = n
            }
            item.alignSelf = flexAlignWord(own["align-self"])
            item.widthDecl = flexLength(own["width"], fontSize: fontSize)
            item.heightDecl = flexLength(own["height"], fontSize: fontSize)
            item.minWidth = flexLength(own["min-width"], fontSize: fontSize)
            item.maxWidth = flexLength(own["max-width"], fontSize: fontSize)
            item.minHeight = flexLength(own["min-height"], fontSize: fontSize)
            item.maxHeight = flexLength(own["max-height"], fontSize: fontSize)
            let margins = boxLengths(own, "margin", fontSize: fontSize)
            item.marginTop = margins.top
            item.marginRight = margins.right
            item.marginBottom = margins.bottom
            item.marginLeft = margins.left
            let padding = boxLengths(own, "padding", fontSize: fontSize)
            item.paddingTop = padding.top
            item.paddingRight = padding.right
            item.paddingBottom = padding.bottom
            item.paddingLeft = padding.left
            item.backgroundColor = tbBackgroundColor(own)
            item.backgroundBox = backgroundBox(decls: own)
            item.boxShadows = boxShadowSet(own, color: nil,
                                           fontSize: fontSize)
            item.transformSpec = transformSpec(own, fontSize: fontSize)
            item.opacityValue = opacityValue(own) ?? 1
        }

        // A flex container, walked: its children become
        // items — each element child an item of its own
        // (a picture walked inside a holder, since a
        // picture has no children for the walk to seat),
        // and each run of text and inline children one
        // anonymous item, as the spec requires — each item
        // sub-rendered in a renderer of its own, the
        // floated box's arrangement, and the container
        // taking its place in this renderer's flow as a
        // single seat: one attachment character as wide
        // and as tall as the laid-out container, in a
        // paragraph carrying the spacing and surface
        // stamps flush would have given the block's own
        // first paragraph, and the spec stamped on the
        // seat under TBFlexSpecKey for whoever paints it.
        // Absolutely positioned children are no items:
        // they register with the ordinary machinery as
        // the walk meets them. Floated children simply
        // itemize — CSS computes float away on an item.
        // Past sixty items, further children flow into
        // the last item, as past sixty floats the rest
        // simply flow.
        func renderFlex(node: TBNode, spec: TBFlexSpec,
                                font: NSFont, color: NSColor?,
                                align: NSTextAlignment,
                                background: NSColor?,
                                backgroundBox: TBBackgroundBox?,
                                metrics: TBBlockMetrics,
                                ownSurface: Bool) -> Bool {
            var subs: [TBRenderer] = []
            var items: [TBFlexItem] = []
            var run: [TBNode] = []

            func makeItem(walkNode: TBNode, own: [String: String],
                          baseFont: NSFont, fontSize: CGFloat) {
                if items.count >= 60, let lastSub = subs.last,
                   let last = items.last {
                    lastSub.walkBlock(node: walkNode,
                                      style: tbStyle(for: walkNode.tag),
                                      baseFont: baseFont, color: color,
                                      align: align, inheritedBackground: nil,
                                      inheritedBackgroundBox: nil)
                    last.content = lastSub.out
                    return
                }
                let item = TBFlexItem()
                dressFlexItem(item, own: own, fontSize: fontSize)
                let sub = TBRenderer(base: base)
                sub.rules = rules
                sub.visitedURLs = visitedURLs
                sub.insideFloat = true
                sub.nominalWidth = nominalWidth
                sub.walkBlock(node: walkNode, style: tbStyle(for: walkNode.tag),
                              baseFont: baseFont, color: color, align: align,
                              inheritedBackground: nil,
                              inheritedBackgroundBox: nil)
                item.content = sub.out
                items.append(item)
                subs.append(sub)
            }
            func flushRun() {
                guard !run.isEmpty else { return }
                let meaningful = run.contains {
                    $0.tag != "#text" || !$0.text.allSatisfy { tbIsSpace($0) }
                }
                let children = run
                run = []
                guard meaningful else { return }
                let holder = TBNode(tag: "#flexrun")
                holder.children = children
                makeItem(walkNode: holder, own: [:], baseFont: font,
                         fontSize: font.pointSize)
            }

            for child in node.children {
                if TBRenderSkipTags.contains(child.tag) { continue }
                if child.tag == "#text" {
                    run.append(child)
                    continue
                }
                let childOwn = resolvedStyle(node: child)
                if tbIsHidden(childOwn) { continue }
                if !insideFloat, positionedCount < 60,
                   !["input", "select", "textarea", "button"].contains(child.tag),
                   let kind = positionKind(childOwn["position"]) {
                    flushRun()
                    if child.tag == "img" {
                        registerPositionedImage(child, own: childOwn, kind: kind,
                                                font: font)
                    } else {
                        registerPositionedBlock(child, own: childOwn, kind: kind,
                                                font: font, color: color,
                                                align: align)
                    }
                    continue
                }
                let display = (childOwn["display"] ?? "").lowercased()
                let forceBlock = ["block", "flex", "grid", "list-item",
                                  "table", "flow-root"].contains(display)
                let forceInline = ["inline", "inline-block", "inline-flex",
                                   "inline-grid", "contents"].contains(display)
                let isItem = child.tag == "img"
                    || ["input", "select", "textarea", "button"].contains(child.tag)
                    || forceBlock
                    || (TBBlockTags.contains(child.tag) && !forceInline)
                if isItem {
                    flushRun()
                    let childFont = tbFontApplying(childOwn, to: font)
                    if child.tag == "img" {
                        let holder = TBNode(tag: "#flexrun")
                        holder.children = [child]
                        makeItem(walkNode: holder, own: childOwn,
                                 baseFont: font, fontSize: childFont.pointSize)
                    } else {
                        let baseFont = TBHeadingTags.contains(child.tag)
                            ? tbFont(for: child.tag) : font
                        makeItem(walkNode: child, own: childOwn,
                                 baseFont: baseFont,
                                 fontSize: childFont.pointSize)
                    }
                } else {
                    run.append(child)
                }
            }
            flushRun()
            guard !items.isEmpty else { return false }
            spec.items = items
            computeFlexLayout(spec: spec)
            let seat = TBFlexSeatAttachment()
            seat.image = tbClearSeat(width: spec.totalWidth,
                                     height: spec.totalHeight)
            seat.bounds = CGRect(x: 0, y: 0, width: spec.totalWidth,
                                 height: spec.totalHeight)
            spec.seat = seat
            let para = NSMutableAttributedString(
                attributedString: NSAttributedString(attachment: seat))
            para.addAttribute(.font, value: font,
                              range: NSRange(location: 0, length: para.length))
            para.addAttribute(TBFlexSpecKey, value: spec,
                              range: NSRange(location: 0, length: para.length))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            if spaceCarry > 0 { paragraph.paragraphSpacingBefore = spaceCarry }
            if metrics.after > 0 { paragraph.paragraphSpacing = metrics.after }
            if metrics.indent > 0 {
                paragraph.headIndent = metrics.indent
                paragraph.firstLineHeadIndent = metrics.indent
            }
            if metrics.tailIndent > 0 { paragraph.tailIndent = -metrics.tailIndent }
            para.addAttribute(.paragraphStyle, value: paragraph,
                              range: NSRange(location: 0, length: para.length))
            if let background = background {
                para.addAttribute(.backgroundColor, value: background,
                                  range: NSRange(location: 0, length: para.length))
            }
            let paraStart = out.length
            spec.anchorCharIndex = paraStart
            out.append(para)
            lastFlushRange = NSRange(location: paraStart, length: para.length)
            if relDX != 0 || relDY != 0 {
                out.addAttribute(TBRelOffsetKey,
                                 value: NSValue(point: NSPoint(x: relDX, y: relDY)),
                                 range: NSRange(location: paraStart,
                                                length: para.length))
            }
            if !pendingClears.isEmpty {
                for clearSpec in pendingClears {
                    clearSpec.anchorCharIndex = paraStart
                }
                pendingClears = []
            }
            var separatorAttrs: [NSAttributedString.Key: Any] = [:]
            if let background = background {
                separatorAttrs[.backgroundColor] = background
            }
            if let backgroundBox = backgroundBox {
                separatorAttrs[TBBackgroundKey] = backgroundBox
            }
            out.append(NSAttributedString(string: "\n\n",
                                          attributes: separatorAttrs))
            noteSurfaceParagraph(
                range: NSRange(location: paraStart, length: para.length),
                color: background, box: backgroundBox,
                after: metrics.after, ownSurface: ownSurface)
            spaceCarry = 0
            if !insideFloat {
                layoutEvents.append(.flex(spec))
            }
            if let link = spec.containerLink {
                containerLinkSeats.append((kind: "flex", link: link))
            }
            pendingFlex.append((spec: spec, subs: subs))
            flexCount += 1
            return true
        }

        // The first text baseline of a string laid out at
        // a width: the first line fragment's top, plus the
        // first glyph's own rise from it — the two calls
        // the float anchor and the column seats are
        // already resolved with, turned to measuring
        // instead of placing. Attachments answer with
        // their foot on the baseline, as replaced elements
        // do.
        private func measureFirstBaseline(_ string: NSAttributedString,
                                          width: CGFloat) -> CGFloat? {
            guard string.length > 0 else { return nil }
            let storage = NSTextStorage(attributedString: string)
            let manager = NSLayoutManager()
            let container = NSTextContainer(
                size: NSSize(width: max(width, 10),
                             height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            guard manager.numberOfGlyphs > 0 else { return nil }
            let fragment = manager.lineFragmentRect(forGlyphAt: 0,
                                                    effectiveRange: nil)
            let spot = manager.location(forGlyphAt: 0)
            return fragment.minY + spot.y
        }

        // Lay a flex container out: resolve every item's
        // border box in the container's content-box
        // coordinates, and the container's own height.
        // The shape of CSS's own algorithm, at this
        // engine's scale: order the items; find each
        // item's flex base size (its basis, its main-size
        // property, or its contents — declared sizes read
        // as the whole box, the floated boxes' convention
        // throughout this engine) and clamp it to the
        // hypothetical size; collect the items into lines
        // when the container wraps; resolve the flexible
        // lengths line by line — grow sharing the free
        // space by factor (factors summing under one
        // share only that much of it), shrink taking the
        // overflow by shrink-times-base — freezing items
        // at their min and max clamps as the distribution
        // reaches them, with an item's own content as its
        // floor under shrink, as min-width:auto directs;
        // then measure the cross sizes at the final main
        // sizes, share each line's leftover by
        // justify-content, place the items across by
        // align-items and align-self (baseline groups
        // sharing the line's deepest baseline), and
        // mirror the main axis for the reverse directions.
        private func computeFlexLayout(spec: TBFlexSpec) {
            let items = spec.items
            let horizontal = spec.direction == .row
                || spec.direction == .rowReverse
            let reversed = spec.direction == .rowReverse
                || spec.direction == .columnReverse
            let contentW = spec.totalWidth
            let gapColumn = resolveFlexLength(spec.gapColumn,
                                              against: contentW) ?? 0
            let gapRow = resolveFlexLength(spec.gapRow,
                                           against: spec.declaredHeight) ?? 0
            let mainGap = horizontal ? gapColumn : gapRow
            let crossGap = horizontal ? gapRow : gapColumn
            let containerMain: CGFloat? = horizontal ? contentW
                : spec.declaredHeight
            let containerCross: CGFloat? = horizontal ? spec.declaredHeight
                : contentW
            let sorted = items.indices.sorted {
                (items[$0].order, $0) < (items[$1].order, $1)
            }
            var base = [CGFloat](repeating: 0, count: items.count)
            var hypo = [CGFloat](repeating: 0, count: items.count)
            var minBound = [CGFloat](repeating: 0, count: items.count)
            var maxBound = [CGFloat](repeating: .greatestFiniteMagnitude,
                                     count: items.count)
            var minContent = [CGFloat](repeating: 0, count: items.count)
            var cross = [CGFloat](repeating: 0, count: items.count)
            var crossDeclared = [Bool](repeating: false, count: items.count)
            var mainSize = [CGFloat](repeating: 0, count: items.count)
            var mainAt = [CGFloat](repeating: 0, count: items.count)
            var crossAt = [CGFloat](repeating: 0, count: items.count)
            var crossBox = [CGFloat](repeating: 0, count: items.count)

            for i in items.indices {
                let item = items[i]
                let content = item.content ?? NSAttributedString()
                let padMain = item.paddingMain(horizontal: horizontal)
                let padCross = item.paddingCross(horizontal: horizontal)
                // The natural main size of the contents,
                // and their minimum: for a row, the longest
                // unwrapped line and the widest unbreakable
                // piece; for a column, both are the height
                // at the item's cross width — a column
                // item's cross size is settled first, since
                // its height is measured standing in it.
                let naturalMain: CGFloat
                if horizontal {
                    naturalMain = measureText(content, width: 100_000).width
                        + padMain
                    minContent[i] = measureText(content, width: 10).width
                        + padMain
                } else {
                    if let w = resolveFlexLength(item.widthDecl,
                                                 against: contentW) {
                        cross[i] = w
                        crossDeclared[i] = true
                    } else {
                        let natural = measureText(content,
                                                  width: 100_000).width
                        cross[i] = min(max(natural + padCross, 1), contentW)
                    }
                    crossBox[i] = cross[i]
                    naturalMain = measureText(
                        content, width: max(cross[i] - padCross, 10)).height
                        + padMain
                    minContent[i] = naturalMain
                }
                // The flex base size: the basis when it
                // resolves (a percentage of an indefinite
                // main size does not, and reads as content,
                // as the spec directs), else — basis auto —
                // the main-size property, else the contents.
                var resolved = naturalMain
                if !item.basisContent {
                    if let b = item.basis,
                       let v = resolveFlexLength(b, against: containerMain) {
                        resolved = v
                    } else if item.basis == nil {
                        let decl = horizontal ? item.widthDecl : item.heightDecl
                        if let v = resolveFlexLength(decl,
                                                     against: containerMain) {
                            resolved = v
                        }
                    }
                }
                base[i] = resolved
                let minDecl = horizontal ? item.minWidth : item.minHeight
                let maxDecl = horizontal ? item.maxWidth : item.maxHeight
                minBound[i] = resolveFlexLength(minDecl,
                                                against: containerMain) ?? 0
                maxBound[i] = resolveFlexLength(maxDecl,
                                                against: containerMain)
                    ?? .greatestFiniteMagnitude
                hypo[i] = min(max(base[i], minBound[i]), maxBound[i])
                mainSize[i] = hypo[i]
            }

            // Collect the items into lines.
            var lines: [[Int]] = []
            if !sorted.isEmpty {
                if !spec.wraps || containerMain == nil {
                    lines = [sorted]
                } else if let main = containerMain {
                    var line: [Int] = []
                    var used: CGFloat = 0
                    for i in sorted {
                        let need = hypo[i]
                            + items[i].marginMain(horizontal: horizontal)
                        let extra = line.isEmpty ? need : used + mainGap + need
                        if !line.isEmpty && extra > main + 0.5 {
                            lines.append(line)
                            line = [i]
                            used = need
                        } else {
                            line.append(i)
                            used = extra
                        }
                    }
                    if !line.isEmpty { lines.append(line) }
                }
            }

            var lineCrosses: [CGFloat] = []
            var lineBaselines: [[Int: CGFloat]] = []
            var lineAscents: [CGFloat] = []
            var lineDescents: [CGFloat] = []
            var mainExtent: CGFloat = containerMain ?? 0
            for line in lines {
                // Resolve the flexible lengths of this line.
                if let main = containerMain {
                    let gapsTotal = mainGap * CGFloat(max(line.count - 1, 0))
                    func usedMain() -> CGFloat {
                        line.reduce(0) {
                            $0 + mainSize[$1]
                                + items[$1].marginMain(horizontal: horizontal)
                        } + gapsTotal
                    }
                    var free = main - usedMain()
                    if free > 0.5 {
                        var rounds = 0
                        while free > 0.5 && rounds <= line.count {
                            rounds += 1
                            let active = line.filter {
                                items[$0].grow > 0
                                    && mainSize[$0] < maxBound[$0] - 0.01
                            }
                            if active.isEmpty { break }
                            let totalGrow = active.reduce(0) {
                                $0 + items[$1].grow
                            }
                            if totalGrow <= 0 { break }
                            let pool = free * min(1, totalGrow)
                            var froze = false
                            for i in active {
                                var next = mainSize[i]
                                    + pool * CGFloat(items[i].grow / totalGrow)
                                if next >= maxBound[i] {
                                    next = maxBound[i]
                                    froze = true
                                }
                                mainSize[i] = next
                            }
                            free = main - usedMain()
                            if !froze { break }
                        }
                    } else if free < -0.5 {
                        var rounds = 0
                        while free < -0.5 && rounds <= line.count {
                            rounds += 1
                            func floorOf(_ i: Int) -> CGFloat {
                                max(minBound[i], minContent[i])
                            }
                            let active = line.filter {
                                items[$0].shrink > 0
                                    && mainSize[$0] > floorOf($0) + 0.01
                            }
                            if active.isEmpty { break }
                            let totalScaled = active.reduce(0) {
                                $0 + items[$1].shrink * Double(base[$1])
                            }
                            if totalScaled <= 0 { break }
                            var froze = false
                            for i in active {
                                let share = -free * CGFloat(
                                    items[i].shrink * Double(base[i]) / totalScaled)
                                var next = mainSize[i] - share
                                if next <= floorOf(i) {
                                    next = floorOf(i)
                                    froze = true
                                }
                                mainSize[i] = next
                            }
                            free = main - usedMain()
                            if !froze { break }
                        }
                    }
                }

                // Cross sizes at the final main sizes (a
                // row item's height is the height of its
                // contents standing at its flexed width),
                // and the line's cross size.
                let alignOf: (Int) -> String = {
                    items[$0].alignSelf ?? spec.alignItems
                }
                var baselines: [Int: CGFloat] = [:]
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                if horizontal {
                    for i in line {
                        let item = items[i]
                        if let h = resolveFlexLength(item.heightDecl,
                                                     against: containerCross) {
                            cross[i] = h
                            crossDeclared[i] = true
                        } else {
                            let cw = max(mainSize[i]
                                - item.paddingMain(horizontal: true), 10)
                            cross[i] = measureText(
                                item.content ?? NSAttributedString(),
                                width: cw).height
                                + item.paddingCross(horizontal: true)
                        }
                        crossBox[i] = cross[i]
                    }
                    for i in line where alignOf(i) == "baseline" {
                        let item = items[i]
                        let cw = max(mainSize[i]
                            - item.paddingMain(horizontal: true), 10)
                        if let b = measureFirstBaseline(
                            item.content ?? NSAttributedString(), width: cw) {
                            let offset = item.paddingTop + b
                            baselines[i] = offset
                            ascent = max(ascent, item.marginTop + offset)
                            descent = max(descent,
                                          cross[i] - offset + item.marginBottom)
                        }
                    }
                }
                var lineCross: CGFloat = 0
                for i in line {
                    if baselines[i] != nil {
                        lineCross = max(lineCross, ascent + descent)
                    } else {
                        lineCross = max(lineCross, cross[i]
                            + items[i].marginCross(horizontal: horizontal))
                    }
                }
                // A lone line in a container of definite
                // cross size stands the container's whole
                // cross size — the spec's own rule, and the
                // one that makes centering in a declared-
                // height bar, or stretching across a column
                // container's width, land where the page
                // expects. (A lone line is also why
                // align-content, below, distributes only
                // among two lines or more: the spec gives
                // it nothing to share out in one.)
                if lines.count == 1, let cc = containerCross {
                    lineCross = cc
                }

                // Share the line's leftover along the main
                // axis, as justify-content directs.
                let gapsTotal = mainGap * CGFloat(max(line.count - 1, 0))
                let lineUsed = line.reduce(0) {
                    $0 + mainSize[$1]
                        + items[$1].marginMain(horizontal: horizontal)
                } + gapsTotal
                let leftover = max((containerMain ?? lineUsed) - lineUsed, 0)
                var lead: CGFloat = 0
                var extra: CGFloat = 0
                switch spec.justify {
                case "flex-end": lead = leftover
                case "center": lead = leftover / 2
                case "space-between":
                    if line.count > 1 {
                        extra = leftover / CGFloat(line.count - 1)
                    }
                case "space-around":
                    if !line.isEmpty {
                        let unit = leftover / CGFloat(line.count)
                        lead = unit / 2
                        extra = unit
                    }
                case "space-evenly":
                    let unit = leftover / CGFloat(line.count + 1)
                    lead = unit
                    extra = unit
                default: break
                }
                var cursor = lead
                for i in line {
                    let item = items[i]
                    let mStart = horizontal ? item.marginLeft : item.marginTop
                    let mEnd = horizontal ? item.marginRight : item.marginBottom
                    mainAt[i] = cursor + mStart
                    cursor += mStart + mainSize[i] + mEnd + mainGap + extra
                }
                if containerMain == nil {
                    mainExtent = max(mainExtent, lineUsed)
                }

                lineCrosses.append(lineCross)
                lineBaselines.append(baselines)
                lineAscents.append(ascent)
                lineDescents.append(descent)
            }

            // The container's own height: across the lines
            // for a row, along them for a column — the
            // declared height when the page declared one,
            // clamped by its own min and max.
            let crossTotal: CGFloat
            if let cc = containerCross {
                crossTotal = cc
            } else {
                crossTotal = lineCrosses.reduce(0, +)
                    + crossGap * CGFloat(max(lineCrosses.count - 1, 0))
            }

            // align-content (0.30): where each line stands
            // along the cross axis. Packed from the cross
            // start, the lines stand at their measured
            // sizes in file order; a definite cross size's
            // leftover is shared among two or more lines
            // as align-content directs — stretch growing
            // every line alike (its stretch and center
            // items then answer inside the grown line, in
            // the placement below), the space
            // distributions widening the gaps between
            // lines, flex-end and center shifting the
            // whole stack. An indefinite cross size has
            // no leftover to share, and one line stands
            // under the rule above.
            var lineStarts: [CGFloat] = []
            var startCursor: CGFloat = 0
            for k in lines.indices {
                lineStarts.append(startCursor)
                startCursor += lineCrosses[k] + crossGap
            }
            if lines.count > 1, containerCross != nil {
                let packed = lineCrosses.reduce(0, +)
                    + crossGap * CGFloat(lines.count - 1)
                let leftover = crossTotal - packed
                switch spec.alignContent {
                case "flex-end":
                    for k in lines.indices { lineStarts[k] += leftover }
                case "center":
                    for k in lines.indices {
                        lineStarts[k] += leftover / 2
                    }
                case "space-between":
                    if leftover > 0 {
                        let extra = leftover / CGFloat(lines.count - 1)
                        for k in lines.indices {
                            lineStarts[k] += extra * CGFloat(k)
                        }
                    }
                case "space-around":
                    if leftover > 0 {
                        let unit = leftover / CGFloat(lines.count)
                        for k in lines.indices {
                            lineStarts[k] += unit / 2 + unit * CGFloat(k)
                        }
                    }
                case "space-evenly":
                    if leftover > 0 {
                        let unit = leftover / CGFloat(lines.count + 1)
                        for k in lines.indices {
                            lineStarts[k] += unit + unit * CGFloat(k)
                        }
                    }
                case "stretch":
                    if leftover > 0 {
                        let each = leftover / CGFloat(lines.count)
                        for k in lines.indices { lineCrosses[k] += each }
                        var cursor: CGFloat = 0
                        for k in lines.indices {
                            lineStarts[k] = cursor
                            cursor += lineCrosses[k] + crossGap
                        }
                    }
                default: break
                }
            }

            // Place the items across their lines, each at
            // its line's settled start, every position
            // reckoned from the line's cross-start edge.
            // In wrap-reverse the cross start is the far
            // edge: the margin standing at it is the
            // physical end margin, the item's place
            // mirrors inside its line and the line's
            // inside the container, and a baseline sits
            // its descent's distance from the cross start
            // instead of its ascent's. The words keep
            // their meanings against the flipped axis.
            for (k, line) in lines.enumerated() {
                let lineCross = lineCrosses[k]
                let lineStart = lineStarts[k]
                let baselines = lineBaselines[k]
                let ascent = lineAscents[k]
                let descent = lineDescents[k]
                for i in line {
                    let item = items[i]
                    let physicalStart = horizontal ? item.marginTop
                        : item.marginLeft
                    let physicalEnd = horizontal ? item.marginBottom
                        : item.marginRight
                    let mCrossStart = spec.wrapReverse ? physicalEnd
                        : physicalStart
                    let mCrossEnd = spec.wrapReverse ? physicalStart
                        : physicalEnd
                    let align = items[i].alignSelf ?? spec.alignItems
                    var box = cross[i]
                    var s: CGFloat
                    if let offset = baselines[i], align == "baseline" {
                        s = spec.wrapReverse
                            ? descent - (cross[i] - offset)
                            : ascent - offset
                    } else if align == "stretch", !crossDeclared[i] {
                        box = max(lineCross - mCrossStart - mCrossEnd, 0)
                        s = mCrossStart
                    } else if align == "flex-end" {
                        s = lineCross - mCrossEnd - box
                    } else if align == "center" {
                        s = (lineCross - box - mCrossStart - mCrossEnd) / 2
                            + mCrossStart
                    } else {
                        // flex-start — and baseline across a
                        // column container, whose items stand
                        // one above another with no shared
                        // line of text to align to (their
                        // baselines are never measured: the
                        // measurement runs across a row).
                        s = mCrossStart
                    }
                    if spec.wrapReverse {
                        let linePhysical = crossTotal - lineStart
                            - lineCross
                        crossAt[i] = linePhysical + lineCross - s - box
                    } else {
                        crossAt[i] = lineStart + s
                    }
                    crossBox[i] = box
                }
            }
            var total = horizontal ? crossTotal
                : (spec.declaredHeight ?? mainExtent)
            if let lo = spec.minHeightClamp { total = max(total, lo) }
            if let hi = spec.maxHeightClamp { total = min(total, hi) }
            spec.totalHeight = max(total, 0)

            // The items' border boxes, mirrored for the
            // reverse directions: the layout above ran
            // from the main start, and a reversed
            // container's main start is the other edge —
            // mirroring every box in the container's main
            // extent puts the first item at that edge and
            // justify-content's packing with it, exactly
            // as the reversed directions direct.
            let mirrorExtent = horizontal ? contentW
                : (spec.declaredHeight ?? mainExtent)
            for i in items.indices {
                var rect: NSRect
                if horizontal {
                    rect = NSRect(x: mainAt[i], y: crossAt[i],
                                  width: mainSize[i], height: crossBox[i])
                    if reversed {
                        rect.origin.x = contentW - (rect.minX + rect.width)
                    }
                } else {
                    rect = NSRect(x: crossAt[i], y: mainAt[i],
                                  width: crossBox[i], height: mainSize[i])
                    if reversed {
                        rect.origin.y = mirrorExtent
                            - (rect.minY + rect.height)
                    }
                }
                items[i].rect = rect
            }
            if let seat = spec.seat {
                seat.image = tbClearSeat(width: spec.totalWidth,
                                         height: spec.totalHeight)
                seat.bounds = CGRect(x: 0, y: 0, width: spec.totalWidth,
                                     height: spec.totalHeight)
            }
        }

        // A flex container nested in painted contents was
        // walked against the page's nominal width, but it
        // stands in the width its box gives it: correct
        // its span to that width (inside its own flow
        // indents, and never past a width it declared),
        // lay it out again there, and do the same for the
        // containers nested in its items, at the widths
        // the new layout gives them. Called by every
        // finalize that settles a painted box's contents,
        // and by finalizeFlex for its own items.
        private func correctFlexSeats(in content: NSAttributedString,
                                      availableWidth: CGFloat,
                                      depth: Int = 0) {
            guard depth < 8 else { return }
            var found: [TBFlexSpec] = []
            content.enumerateAttribute(
                TBFlexSpecKey, in: NSRange(location: 0, length: content.length)
            ) { value, _, _ in
                if let spec = value as? TBFlexSpec { found.append(spec) }
            }
            for spec in found {
                var width = max(availableWidth - spec.flowIndent
                    - spec.flowTailIndent, 10)
                if let cap = spec.declaredContentWidth {
                    width = min(width, cap)
                }
                if let link = spec.containerLink,
                   !containerLinkSeats.contains(where: { $0.link == link }) {
                    containerLinkSeats.append((kind: "flex", link: link))
                }
                spec.totalWidth = width
                computeFlexLayout(spec: spec)
                for item in spec.items {
                    guard let itemContent = item.content else { continue }
                    let itemWidth = max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10)
                    correctFlexSeats(in: itemContent,
                                     availableWidth: itemWidth,
                                     depth: depth + 1)
                    correctGridSeats(in: itemContent,
                                     availableWidth: itemWidth,
                                     depth: depth + 1)
                }
            }
        }

        // A flex container's items are finished (their
        // pictures fetched, their failures labelled):
        // strip what cannot work inside a painted box —
        // the link targets and their [n] markers, and the
        // form controls, for which bracketed labels stand
        // in — exactly the cleaning a floated box's
        // contents get — then lay the container out on
        // the finished text, correct the containers
        // nested in its items to the widths the layout
        // gave them, and lay out again, twice over, so a
        // nested container's corrected height settles
        // into the outer lines before the seat in the
        // page is corrected the final time.
        private func finalizeFlex(spec: TBFlexSpec, subs: [TBRenderer]) {
            for (index, item) in spec.items.enumerated() {
                guard index < subs.count else { break }
                let sub = subs[index]
                let cleaned = NSMutableAttributedString(attributedString: sub.out)
                var swaps: [(range: NSRange, text: String)] = []
                cleaned.enumerateAttribute(
                    .attachment, in: NSRange(location: 0, length: cleaned.length)
                ) { value, range, _ in
                    if let submit = value as? TBSubmitAttachment {
                        swaps.append((range: range, text: " [\(submit.label)] "))
                    } else if let field = value as? TBFieldAttachment {
                        let name = sub.fields.first { $0.id == field.fieldID }
                            .map { $0.placeholder.isEmpty ? "field" : $0.placeholder }
                            ?? "field"
                        swaps.append((range: range, text: " [\(name)] "))
                    } else if let select = value as? TBSelectAttachment {
                        // Live controls (0.31): the popup
                        // stands in for its resting
                        // choice's label.
                        let label = select.selectedIndex >= 0
                            && select.selectedIndex < select.options.count
                            ? select.options[select.selectedIndex].label : "select"
                        swaps.append((range: range, text: " [\(label)] "))
                    } else if let area = value as? TBTextAreaAttachment {
                        let name = sub.fields.first { $0.id == area.fieldID }
                            .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                        swaps.append((range: range, text: " [\(name)] "))
                    }
                }
                cleaned.enumerateAttribute(
                    .link, in: NSRange(location: 0, length: cleaned.length)
                ) { _, range, _ in
                    let text = (cleaned.string as NSString).substring(with: range)
                    if text.hasPrefix(" ["), text.hasSuffix("]") {
                        let digits = text.dropFirst(2).dropLast()
                        if !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) {
                            swaps.append((range: range, text: ""))
                        }
                    }
                }
                for swap in swaps.sorted(by: { $0.range.location > $1.range.location }) {
                    cleaned.replaceCharacters(in: swap.range, with: NSAttributedString(
                        string: swap.text,
                        attributes: [.font: NSFont.systemFont(ofSize: 12),
                                     .foregroundColor: NSColor.secondaryLabelColor]))
                }
                // Links in the item keep their
                // targets now (0.36): the view
                // hit-tests painted items and
                // follows them.
                item.content = cleaned
            }
            computeFlexLayout(spec: spec)
            for item in spec.items {
                guard let content = item.content else { continue }
                correctFlexSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
                correctGridSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
            }
            computeFlexLayout(spec: spec)
            for item in spec.items {
                guard let content = item.content else { continue }
                correctFlexSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
                correctGridSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
            }
            computeFlexLayout(spec: spec)
        }

        // Arrivals for the flex containers (0.24): each
        // item's own pictures and backgrounds land first
        // (and any containers nested deeper, through the
        // same pass on the item's renderer), then the
        // container is cleaned and laid out for the last
        // time — the two-stage life every painted
        // construct in this engine leads.
        func finishFlex() async {
            for pending in pendingFlex {
                for sub in pending.subs {
                    await sub.finishImages()
                    await sub.finishBackgrounds()
                    await sub.finishFlex()
                    await sub.finishGrid()
                }
                finalizeFlex(spec: pending.spec, subs: pending.subs)
            }
            pendingFlex = []
        }

}

extension TBRenderer {
        // MARK: - Grid (0.25)

        // The alignment words justify-items, align-items
        // and their self variants share on a grid,
        // normalized to the grid's own spelling: start,
        // end, center, stretch. Anything else (or nothing)
        // yields nil, and the caller substitutes its
        // default. Baseline reads as start: real grid
        // baseline alignment lines items up on a shared
        // text baseline across their row, and that is
        // more machinery than this pass carries — the
        // header names it, so the page is not silently
        // promised it.
        private func gridAlignWord(_ raw: String?) -> String? {
            guard let v = raw?.trimmingCharacters(in: .whitespaces)
                    .lowercased() else { return nil }
            switch v {
            case "flex-start", "start", "self-start": return "start"
            case "flex-end", "end", "self-end": return "end"
            case "center": return "center"
            case "stretch": return "stretch"
            case "baseline": return "start"
            default: return nil
            }
        }

        // The distribution words justify-content and
        // align-content share on a grid, normalized;
        // anything else (or nothing) reads as start.
        private func gridContentWord(_ raw: String?) -> String {
            switch (raw ?? "").trimmingCharacters(in: .whitespaces)
                .lowercased() {
            case "flex-end", "end": return "end"
            case "center": return "center"
            case "space-between": return "space-between"
            case "space-around": return "space-around"
            case "space-evenly": return "space-evenly"
            default: return "start"
            }
        }

        // The grid-template shorthand's two halves,
        // split at its top-level slash in the RAW text —
        // the name and area reading (0.30) needs the
        // halves before gridStripNames takes the names
        // away. No slash: the whole text is the rows
        // half (the areas-only spelling) and there is
        // no columns half.
        private func gridTemplateParts(_ raw: String)
            -> (rows: String, cols: String?) {
            var depth = 0
            var bracket = 0
            var quote: Character? = nil
            for i in raw.indices {
                let c = raw[i]
                if let q = quote {
                    if c == q { quote = nil }
                    continue
                }
                if c == "\"" || c == "'" { quote = c; continue }
                if c == "[" { bracket += 1; continue }
                if c == "]" { bracket = max(0, bracket - 1); continue }
                if bracket > 0 { continue }
                if c == "(" { depth += 1; continue }
                if c == ")" { depth -= 1; continue }
                if c == "/", depth == 0 {
                    return (String(raw[..<i]),
                            String(raw[raw.index(after: i)...]))
                }
            }
            return (raw, nil)
        }

        // A template's line names by 1-based line index
        // (0.30): the scan walks the raw template text —
        // a bracketed group names the line the walk
        // stands on; each track size steps it one line
        // on; a fixed repeat() steps by its count times
        // its body's track count, though names written
        // inside it are not read (the repeat is a
        // stencil; this engine names only what was
        // written once, plainly); an auto-fill or
        // auto-fit repeat ends the reading where it
        // stands, its track count known only at layout,
        // so no name past it can be indexed honestly.
        // Quoted strings (the shorthand's area rows)
        // name nothing and size nothing; the size token
        // beside them steps the line.
        private func gridTemplateLineNames(_ raw: String?)
            -> [Int: [String]] {
            guard let raw = raw else { return [:] }
            let chars = Array(raw)
            var names: [Int: [String]] = [:]
            var line = 1
            var i = 0
            func skipSpace() {
                while i < chars.count,
                      chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" {
                    i += 1
                }
            }
            // One token from the walk's place: a
            // bracketed group, a quoted string, or a run
            // to the next top-level whitespace.
            func nextToken() -> String {
                skipSpace()
                guard i < chars.count else { return "" }
                if chars[i] == "[" {
                    var token = ""
                    while i < chars.count, chars[i] != "]" {
                        token.append(chars[i]); i += 1
                    }
                    if i < chars.count {
                        token.append(chars[i]); i += 1
                    }
                    return token
                }
                if chars[i] == "\"" || chars[i] == "'" {
                    let q = chars[i]
                    var token = ""
                    token.append(chars[i]); i += 1
                    while i < chars.count, chars[i] != q {
                        token.append(chars[i]); i += 1
                    }
                    if i < chars.count {
                        token.append(chars[i]); i += 1
                    }
                    return token
                }
                var token = ""
                var depth = 0
                while i < chars.count {
                    let c = chars[i]
                    if c == "(" { depth += 1 }
                    if c == ")" { depth -= 1 }
                    if depth == 0,
                       c == " " || c == "\n" || c == "\t" { break }
                    token.append(c); i += 1
                }
                return token
            }
            while true {
                skipSpace()
                guard i < chars.count else { break }
                let token = nextToken()
                if token.hasPrefix("[") {
                    let inner = token.dropFirst().dropLast()
                    let words = inner.split(separator: " ")
                        .map { String($0).lowercased() }
                    if !words.isEmpty {
                        names[line, default: []]
                            .append(contentsOf: words)
                    }
                    continue
                }
                if token.hasPrefix("\"") || token.hasPrefix("'") {
                    continue
                }
                let lowered = token.lowercased()
                if lowered.hasPrefix("repeat("),
                   lowered.hasSuffix(")") {
                    let inner = String(lowered.dropFirst(7).dropLast())
                    let parts = tbSplitLayers(inner)
                    let countWord = parts.first?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    if countWord == "auto-fill"
                        || countWord == "auto-fit" { break }
                    guard let times = Int(countWord) else { break }
                    var bodyTracks = 0
                    for piece in parts.dropFirst() {
                        bodyTracks += gridCountTrackTokens(piece)
                    }
                    line += times * bodyTracks
                    continue
                }
                if !token.isEmpty { line += 1 }
            }
            return names
        }

        // How many tracks a run of template text stands
        // for, names and strings aside — the counting a
        // fixed repeat's body needs above.
        private func gridCountTrackTokens(_ raw: String) -> Int {
            var count = 0
            var depth = 0
            var bracket = 0
            var quote: Character? = nil
            var inToken = false
            for c in raw {
                if let q = quote {
                    if c == q { quote = nil }
                    continue
                }
                if c == "\"" || c == "'" { quote = c; continue }
                if c == "[" { bracket += 1; continue }
                if c == "]" { bracket = max(0, bracket - 1); continue }
                if bracket > 0 { continue }
                if c == "(" { depth += 1 }
                if c == ")" { depth -= 1 }
                if depth == 0, c == " " || c == "\n" || c == "\t" {
                    inToken = false
                } else if !inToken {
                    inToken = true
                    count += 1
                }
            }
            return count
        }

        // grid-template-areas, read whole (0.30): each
        // quoted string is one row, its words the cells
        // — a run of dots is an unnamed cell, any other
        // word names the area that cell belongs to.
        // Every name must fill its rectangle exactly,
        // and every row must count the same cells, else
        // the whole map is void — the spec's own
        // ruling — and placement falls back to the
        // ordinary roads. The map answers line numbers,
        // 1-based, end lines one past the last cell.
        private func gridTemplateAreas(_ raw: String?)
            -> [String: (rowStart: Int, colStart: Int,
                         rowEnd: Int, colEnd: Int)] {
            guard let raw = raw else { return [:] }
            var rows: [[String]] = []
            var buffer = ""
            var quote: Character? = nil
            for c in raw {
                if let q = quote {
                    if c == q {
                        rows.append(buffer.split(separator: " ")
                            .map { String($0).lowercased() })
                        buffer = ""
                        quote = nil
                    } else {
                        buffer.append(c)
                    }
                } else if c == "\"" || c == "'" {
                    quote = c
                }
            }
            guard !rows.isEmpty, rows[0].count > 0,
                  rows.allSatisfy({ $0.count == rows[0].count })
            else { return [:] }
            var cells: [String: [(Int, Int)]] = [:]
            for (r, row) in rows.enumerated() {
                for (c, word) in row.enumerated()
                    where !word.allSatisfy({ $0 == "." }) {
                    cells[word, default: []].append((r, c))
                }
            }
            var areas: [String: (rowStart: Int, colStart: Int,
                                 rowEnd: Int, colEnd: Int)] = [:]
            for (name, positions) in cells {
                let rs = positions.map { $0.0 }
                let cs = positions.map { $0.1 }
                guard let r0 = rs.min(), let r1 = rs.max(),
                      let c0 = cs.min(), let c1 = cs.max(),
                      positions.count == (r1 - r0 + 1) * (c1 - c0 + 1)
                else { return [:] }
                areas[name] = (rowStart: r0 + 1, colStart: c0 + 1,
                               rowEnd: r1 + 2, colEnd: c1 + 2)
            }
            return areas
        }

        // A grid placement side with its name resolved
        // (0.30): an explicit line name of that axis
        // first (its nth bearer, when the page counted),
        // then an area's generated edge name
        // (<area>-start / <area>-end), then an area's
        // own name, which on a start side means the
        // area's first line on that axis and on an end
        // side its last. A name nothing answers reads
        // as auto — the fallback a page is left with
        // when its names do not resolve.
        private func resolvedGridSide(_ side: TBGridSide,
                                      rowAxis: Bool, isStart: Bool,
                                      spec: TBGridSpec) -> TBGridSide {
            guard case .name(let name, let occurrence) = side
            else { return side }
            let lineNames = rowAxis ? spec.rowLineNames
                : spec.columnLineNames
            let bearers = lineNames.filter { $0.value.contains(name) }
                .map { $0.key }.sorted()
            if occurrence >= 1, occurrence <= bearers.count {
                return .line(bearers[occurrence - 1])
            }
            for (areaName, rect) in spec.templateAreas {
                if name == areaName {
                    if rowAxis {
                        return .line(isStart ? rect.rowStart : rect.rowEnd)
                    }
                    return .line(isStart ? rect.colStart : rect.colEnd)
                }
                if name == areaName + "-start" {
                    return .line(rowAxis ? rect.rowStart : rect.colStart)
                }
                if name == areaName + "-end" {
                    return .line(rowAxis ? rect.rowEnd : rect.colEnd)
                }
            }
            return .auto
        }

        // Drop what a template may carry besides track
        // sizes: the bracketed line names and the quoted
        // area strings of grid-template. The names are
        // read on their own road now (0.30) — this strip
        // only keeps them from reaching the track
        // parser as sizes.
        private func gridStripNames(_ raw: String) -> String {
            var out = ""
            var bracket = 0
            var quote: Character? = nil
            for c in raw {
                if let q = quote {
                    if c == q { quote = nil }
                    continue
                }
                if c == "\"" || c == "'" { quote = c; continue }
                if c == "[" { bracket += 1; continue }
                if c == "]" { bracket = max(0, bracket - 1); continue }
                if bracket > 0 { continue }
                out.append(c)
            }
            return out
        }

        // One track size from its text: a length or a
        // percentage (min and max alike), a bare fr, the
        // word auto, or a minmax() whose ends are any of
        // those. A minimum written in fr reads as no
        // minimum — the contents floor it, as the header
        // says — and an end that fails to read leaves that
        // side to the contents.
        private func gridTrack(_ token: String, fontSize: CGFloat)
            -> TBGridTrack? {
            let t = token.trimmingCharacters(in: .whitespaces).lowercased()
            if t.hasPrefix("minmax("), t.hasSuffix(")") {
                let inner = String(t.dropFirst(7).dropLast())
                let parts = tbSplitLayers(inner)
                guard parts.count == 2 else { return nil }
                var track = TBGridTrack()
                let lo = parts[0].trimmingCharacters(in: .whitespaces)
                let hi = parts[1].trimmingCharacters(in: .whitespaces)
                if lo != "auto", !lo.hasSuffix("fr") {
                    track.minLength = flexLength(lo, fontSize: fontSize)
                }
                if hi == "auto" {
                    track.maxContent = true
                } else if hi.hasSuffix("fr"),
                          let f = Double(hi.dropLast(2)) {
                    track.maxFr = max(f, 0)
                } else {
                    track.maxLength = flexLength(hi, fontSize: fontSize)
                }
                if track.maxLength == nil, track.maxFr == nil,
                   !track.maxContent {
                    track.maxContent = true
                }
                return track
            }
            if t == "auto" {
                var track = TBGridTrack()
                track.maxContent = true
                return track
            }
            if t.hasSuffix("fr"), let f = Double(t.dropLast(2)) {
                var track = TBGridTrack()
                track.maxFr = max(f, 0)
                return track
            }
            if let length = flexLength(t, fontSize: fontSize) {
                var track = TBGridTrack()
                track.minLength = length
                track.maxLength = length
                return track
            }
            return nil
        }

        // A grid template's track list, read whole: plain
        // tracks, minmax(), and repeat() — at a fixed
        // count, or with auto-fill / auto-fit where the
        // spec's own count formula applies: the axis has a
        // definite size (mainSize) and every repeated
        // track carries a definite minimum, the count
        // being how many minimum tracks and their gaps
        // fit. Without those, the repeat stands once.
        // auto-fit's tracks are flagged, so the layout
        // can collapse the ones no item lands in. No axis
        // grows past sixty tracks, the item cap's kin.
        private func gridTrackList(_ raw: String?, fontSize: CGFloat,
                                   mainSize: CGFloat?, mainGap: CGFloat)
            -> [TBGridTrack] {
            guard let raw = raw else { return [] }
            var tracks: [TBGridTrack] = []
            for token in valueTokens(gridStripNames(raw)) {
                let t = token.lowercased()
                if t.hasPrefix("repeat("), t.hasSuffix(")") {
                    let inner = String(t.dropFirst(7).dropLast())
                    let parts = tbSplitLayers(inner)
                    guard parts.count >= 2 else { continue }
                    let countWord = parts[0]
                        .trimmingCharacters(in: .whitespaces)
                    var repeated: [TBGridTrack] = []
                    for piece in parts.dropFirst() {
                        for sub in valueTokens(
                            piece.trimmingCharacters(in: .whitespaces)) {
                            if let track = gridTrack(sub, fontSize: fontSize) {
                                repeated.append(track)
                            }
                        }
                    }
                    guard !repeated.isEmpty else { continue }
                    var times = 1
                    var autoFit = false
                    if let n = Int(countWord) {
                        times = max(n, 0)
                    } else if countWord == "auto-fill"
                                || countWord == "auto-fit" {
                        autoFit = countWord == "auto-fit"
                        if let main = mainSize {
                            var per: CGFloat = 0
                            var definite = true
                            for track in repeated {
                                if let minL = track.minLength,
                                   let v = resolveFlexLength(minL,
                                                             against: main) {
                                    per += v
                                } else {
                                    definite = false
                                    break
                                }
                            }
                            if definite, per > 0 {
                                times = max(1, Int((main + mainGap)
                                    / (per + mainGap)))
                            }
                        }
                    }
                    var added = 0
                    while added < times, tracks.count < 60 {
                        for track in repeated {
                            if tracks.count >= 60 { break }
                            var copy = track
                            if autoFit { copy.fromAutoFit = true }
                            tracks.append(copy)
                        }
                        added += 1
                    }
                    continue
                }
                if tracks.count < 60,
                   let track = gridTrack(t, fontSize: fontSize) {
                    tracks.append(track)
                }
            }
            return tracks
        }

        // One side of a placement, as written: a line
        // number, a span, a name (0.30 — alone, or with
        // its count, in either order), or auto. A
        // written zero lands on auto, zero being no
        // line at all in CSS; a span by name (span
        // <name>) is not read — it answers auto, as the
        // README says.
        private func gridSide(_ raw: String) -> TBGridSide {
            let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if t.isEmpty || t == "auto" { return .auto }
            let words = t.split(separator: " ").map { String($0) }
            if words.first == "span" {
                if words.count == 2, let n = Int(words[1]), n > 0 {
                    return .span(n)
                }
                return .auto
            }
            if words.count == 1 {
                if let n = Int(words[0]), n != 0 { return .line(n) }
                return .name(words[0], 1)
            }
            if words.count == 2 {
                if let n = Int(words[1]) { return .name(words[0], n) }
                if let n = Int(words[0]) { return .name(words[1], n) }
            }
            return .auto
        }

        // An axis's two sides combined into a start line
        // (1-based, as written — negatives resolve at
        // dress time) and a span, by the spec's own rules:
        // two lines give the span between them, the later
        // standing as the start when the page wrote them
        // backwards; a line and a span count the span from
        // the line; a lone line spans one; a lone span
        // leaves the start automatic. A span counted back
        // from an end line that would start before the
        // first line clamps to it — this engine grows no
        // implicit tracks before the explicit grid.
        private func gridCombine(_ first: TBGridSide, _ second: TBGridSide)
            -> (line: Int?, span: Int) {
            switch (first, second) {
            // Names resolve at dress time, before this
            // runs; one arriving unresolved reads as auto.
            case (.name(_, _), _), (_, .name(_, _)):
                return (nil, 1)
            case (.line(let a), .line(let b)):
                if b > a { return (a, b - a) }
                if b < a { return (b, a - b) }
                return (a, 1)
            case (.line(let a), .span(let s)):
                return (a, s)
            case (.span(let s), .line(let b)):
                if b - s < 1 { return (1, max(b - 1, 1)) }
                return (b - s, s)
            case (.line(let a), .auto):
                return (a, 1)
            case (.auto, .line(let b)):
                if b <= 1 { return (1, 1) }
                return (b - 1, 1)
            case (.span(let s), .auto), (.auto, .span(let s)):
                return (nil, s)
            case (.span(let s), .span):
                return (nil, s)
            case (.auto, .auto):
                return (nil, 1)
            }
        }

        // A placement line as written, resolved against
        // the explicit grid: a positive line stands as
        // written; a negative line counts back from the
        // explicit grid's last line, and one counting
        // past the first line lands on it.
        private func resolveGridLine(_ line: Int, explicit: Int) -> Int {
            if line > 0 { return line }
            return max(explicit + 2 + line, 1)
        }

        // A block's grid declarations, resolved to the
        // spec the layout pass works from — or nil when
        // the block is no grid container. The container's
        // width is the flow's span for the block, capped
        // by a declared width or max-width exactly as a
        // flex container's is (the flex spec's own
        // resolution, shared word for word); a declared
        // height is kept as the content height it implies,
        // a percentage height resolving as a flex
        // container's does (0.30). The grid-template shorthand (its
        // rows, a slash, its columns) is read first, the
        // template longhands over it — the order this
        // engine reads every shorthand in.
        func gridContainerSpec(_ own: [String: String],
                                       fontSize: CGFloat,
                                       metrics: TBBlockMetrics)
            -> TBGridSpec? {
            let display = (own["display"] ?? "")
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard display == "grid" || display == "inline-grid"
            else { return nil }
            // The gaps: the shorthand first, the longhands
            // over it, and the grid-prefixed longhands over
            // those — the box shorthands' own convention,
            // and the order flex reads its gaps in.
            var gapRow: TBInsetValue? = nil
            var gapColumn: TBInsetValue? = nil
            if let raw = own["gap"] {
                let tokens = valueTokens(raw)
                if let first = tokens.first,
                   let v = flexLength(first, fontSize: fontSize) {
                    gapRow = v
                    gapColumn = v
                }
                if tokens.count > 1,
                   let v = flexLength(tokens[1], fontSize: fontSize) {
                    gapColumn = v
                }
            }
            if let v = flexLength(own["row-gap"], fontSize: fontSize) {
                gapRow = v
            }
            if let v = flexLength(own["column-gap"], fontSize: fontSize) {
                gapColumn = v
            }
            if let v = flexLength(own["grid-row-gap"], fontSize: fontSize) {
                gapRow = v
            }
            if let v = flexLength(own["grid-column-gap"], fontSize: fontSize) {
                gapColumn = v
            }
            let padding = boxLengths(own, "padding", fontSize: fontSize)
            let padH = padding.left + padding.right
            let padV = padding.top + padding.bottom
            var contentW = nominalWidth - metrics.indent - metrics.tailIndent
            var widthCap: CGFloat? = nil
            if let declared = flexLength(own["width"], fontSize: fontSize) {
                let borderW: CGFloat?
                switch declared {
                case .points(let v): borderW = v
                case .percent(let pct):
                    borderW = pct / 100
                        * max(nominalWidth - ancestorPaddingH + padH, 10)
                }
                if let bw = borderW {
                    contentW = min(contentW, max(bw - padH, 10))
                    widthCap = contentW
                }
            }
            if let maxDecl = flexLength(own["max-width"], fontSize: fontSize),
               case .points(let v) = maxDecl {
                contentW = min(contentW, max(v - padH, 10))
                widthCap = contentW
            }
            contentW = max(contentW, 10)
            // Heights (0.30): a height in points stands
            // as the content height it implies; a
            // percentage resolves against the definite
            // height the walk has open above this block,
            // and against nothing reads as no height at
            // all — the clamps resolve the same way.
            var declaredHeight: CGFloat? = nil
            if let declared = flexLength(own["height"], fontSize: fontSize),
               let v = resolveFlexLength(declared,
                                         against: definiteAncestorHeight) {
                declaredHeight = max(v - padV, 0)
            }
            var minHeightClamp: CGFloat? = nil
            var maxHeightClamp: CGFloat? = nil
            if let declared = flexLength(own["min-height"], fontSize: fontSize),
               let v = resolveFlexLength(declared,
                                         against: definiteAncestorHeight) {
                minHeightClamp = max(v - padV, 0)
            }
            if let declared = flexLength(own["max-height"], fontSize: fontSize),
               let v = resolveFlexLength(declared,
                                         against: definiteAncestorHeight) {
                maxHeightClamp = max(v - padV, 0)
            }
            let spec = TBGridSpec(totalWidth: contentW)
            spec.gapRow = gapRow
            spec.gapColumn = gapColumn
            spec.declaredHeight = declaredHeight
            spec.minHeightClamp = minHeightClamp
            spec.maxHeightClamp = maxHeightClamp
            spec.declaredContentWidth = widthCap
            spec.flowIndent = metrics.indent
            spec.flowTailIndent = metrics.tailIndent
            spec.justifyItems = gridAlignWord(own["justify-items"]) ?? "stretch"
            spec.alignItems = gridAlignWord(own["align-items"]) ?? "stretch"
            spec.justifyContent = gridContentWord(own["justify-content"])
            spec.alignContent = gridContentWord(own["align-content"])
            // grid-auto-flow (0.30): row by default;
            // column fills down a column before marching
            // to the next; dense, on either flow,
            // restarts the placement cursor at the first
            // cell for every item, backfilling holes.
            if let flow = own["grid-auto-flow"] {
                for token in valueTokens(flow.lowercased()) {
                    if token == "column" { spec.autoFlowColumn = true }
                    if token == "dense" { spec.autoFlowDense = true }
                }
            }
            // The resolved gaps the repetition count of an
            // auto-fill or auto-fit repeat divides by: a
            // percentage column-gap against the content
            // width, a percentage row-gap against the
            // declared height — an indefinite one counting
            // as nothing, as the spec directs.
            let gapColumnPts = resolveFlexLength(gapColumn,
                                                 against: contentW) ?? 0
            let gapRowPts = resolveFlexLength(gapRow,
                                              against: declaredHeight) ?? 0
            if let template = own["grid-template"] {
                // The small completions (0.30): the
                // shorthand's line names and areas, read
                // from its raw halves before the strip
                // below takes the names away — the
                // longhands further down replace them per
                // axis, as they replace the tracks.
                let halves = gridTemplateParts(template)
                spec.rowLineNames = gridTemplateLineNames(halves.rows)
                if let colsHalf = halves.cols {
                    spec.columnLineNames
                        = gridTemplateLineNames(colsHalf)
                }
                spec.templateAreas = gridTemplateAreas(template)
                let cleaned = gridStripNames(template)
                var depth = 0
                var slash: String.Index? = nil
                for i in cleaned.indices {
                    let c = cleaned[i]
                    if c == "(" { depth += 1 }
                    else if c == ")" { depth -= 1 }
                    else if c == "/", depth == 0 { slash = i; break }
                }
                if let slash = slash {
                    let rowsRaw = String(cleaned[..<slash])
                    let colsRaw = String(cleaned[cleaned.index(after: slash)...])
                    spec.rowTracks = gridTrackList(rowsRaw, fontSize: fontSize,
                                                   mainSize: declaredHeight,
                                                   mainGap: gapRowPts)
                    spec.columnTracks = gridTrackList(colsRaw, fontSize: fontSize,
                                                      mainSize: contentW,
                                                      mainGap: gapColumnPts)
                }
            }
            if own["grid-template-rows"] != nil {
                spec.rowLineNames
                    = gridTemplateLineNames(own["grid-template-rows"])
                spec.rowTracks = gridTrackList(own["grid-template-rows"],
                                               fontSize: fontSize,
                                               mainSize: declaredHeight,
                                               mainGap: gapRowPts)
            }
            if own["grid-template-columns"] != nil {
                spec.columnLineNames
                    = gridTemplateLineNames(own["grid-template-columns"])
                spec.columnTracks = gridTrackList(own["grid-template-columns"],
                                                  fontSize: fontSize,
                                                  mainSize: contentW,
                                                  mainGap: gapColumnPts)
            }
            if let areasRaw = own["grid-template-areas"] {
                // A longhand map that reads replaces the
                // shorthand's; one that voids itself (a
                // name filling no rectangle) leaves the
                // shorthand's standing, as a dropped
                // declaration should.
                let areas = gridTemplateAreas(areasRaw)
                if !areas.isEmpty { spec.templateAreas = areas }
            }
            return spec
        }

        // An item's grid properties from its declarations:
        // its placement — grid-area's four line slots
        // first (row start, column start, row end, column
        // end, in the shorthand's own order), the axis
        // shorthands over it, the longhands over them, each
        // layer replacing only the sides it names — then
        // its alignment within its area, its sizes, and the
        // margins, padding and backgrounds the painter
        // needs, exactly as a flex item is dressed.
        // Negative lines resolve here, against the
        // container's explicit track counts, because this
        // is where the written line becomes the item's own.
        private func dressGridItem(_ item: TBGridItem,
                                   own: [String: String],
                                   fontSize: CGFloat,
                                   explicitCols: Int, explicitRows: Int,
                                   spec: TBGridSpec) {
            var rowStart = TBGridSide.auto
            var rowEnd = TBGridSide.auto
            var colStart = TBGridSide.auto
            var colEnd = TBGridSide.auto
            func sides(of raw: String) -> (TBGridSide, TBGridSide) {
                let parts = raw.split(separator: "/",
                                      omittingEmptySubsequences: false)
                let a = parts.count > 0 ? gridSide(String(parts[0])) : .auto
                let b = parts.count > 1 ? gridSide(String(parts[1])) : .auto
                return (a, b)
            }
            if let area = own["grid-area"] {
                // grid-area: <name> (0.30): a lone name
                // with an area behind it sets the
                // shorthand's four sides to the area's
                // four lines — the layers below still
                // replace the axes they name. A name with
                // no area falls through to the line
                // reading, where it resolves to auto.
                let trimmed = area.trimmingCharacters(in: .whitespaces)
                    .lowercased()
                if !trimmed.contains("/"),
                   let rect = spec.templateAreas[trimmed] {
                    rowStart = .line(rect.rowStart)
                    colStart = .line(rect.colStart)
                    rowEnd = .line(rect.rowEnd)
                    colEnd = .line(rect.colEnd)
                } else {
                    let parts = area.split(separator: "/",
                                           omittingEmptySubsequences: false)
                        .map { gridSide(String($0)) }
                    if parts.count > 0 { rowStart = parts[0] }
                    if parts.count > 1 { colStart = parts[1] }
                    if parts.count > 2 { rowEnd = parts[2] }
                    if parts.count > 3 { colEnd = parts[3] }
                }
            }
            if let raw = own["grid-row"] { (rowStart, rowEnd) = sides(of: raw) }
            if let raw = own["grid-column"] { (colStart, colEnd) = sides(of: raw) }
            if let raw = own["grid-row-start"] { rowStart = gridSide(raw) }
            if let raw = own["grid-row-end"] { rowEnd = gridSide(raw) }
            if let raw = own["grid-column-start"] { colStart = gridSide(raw) }
            if let raw = own["grid-column-end"] { colEnd = gridSide(raw) }
            // Named sides (0.30) resolve here, where the
            // container's names are known — each side
            // against its own axis, its own end.
            rowStart = resolvedGridSide(rowStart, rowAxis: true,
                                        isStart: true, spec: spec)
            rowEnd = resolvedGridSide(rowEnd, rowAxis: true,
                                      isStart: false, spec: spec)
            colStart = resolvedGridSide(colStart, rowAxis: false,
                                        isStart: true, spec: spec)
            colEnd = resolvedGridSide(colEnd, rowAxis: false,
                                      isStart: false, spec: spec)
            let rowAxis = gridCombine(rowStart, rowEnd)
            let colAxis = gridCombine(colStart, colEnd)
            item.rowSpan = min(max(rowAxis.span, 1), 60)
            item.colSpan = min(max(colAxis.span, 1), 60)
            item.rowLine = rowAxis.line.map {
                resolveGridLine($0, explicit: explicitRows)
            }
            item.colLine = colAxis.line.map {
                resolveGridLine($0, explicit: explicitCols)
            }
            item.justifySelf = gridAlignWord(own["justify-self"])
            item.alignSelf = gridAlignWord(own["align-self"])
            item.widthDecl = flexLength(own["width"], fontSize: fontSize)
            item.heightDecl = flexLength(own["height"], fontSize: fontSize)
            let margins = boxLengths(own, "margin", fontSize: fontSize)
            item.marginTop = margins.top
            item.marginRight = margins.right
            item.marginBottom = margins.bottom
            item.marginLeft = margins.left
            let padding = boxLengths(own, "padding", fontSize: fontSize)
            item.paddingTop = padding.top
            item.paddingRight = padding.right
            item.paddingBottom = padding.bottom
            item.paddingLeft = padding.left
            item.backgroundColor = tbBackgroundColor(own)
            item.backgroundBox = backgroundBox(decls: own)
            item.boxShadows = boxShadowSet(own, color: nil,
                                           fontSize: fontSize)
            item.transformSpec = transformSpec(own, fontSize: fontSize)
            item.opacityValue = opacityValue(own) ?? 1
        }

        // A grid container, walked: its children become
        // items exactly as a flex container's do — each
        // element child an item of its own (a picture
        // walked inside a holder, since a picture has no
        // children for the walk to seat), and each run of
        // text and inline children one anonymous item, as
        // the spec requires — each item sub-rendered in a
        // renderer of its own, and the container taking
        // its place in this renderer's flow as a single
        // seat: one attachment character as wide and as
        // tall as the laid-out container, in a paragraph
        // carrying the spacing and surface stamps flush
        // would have given the block's own first paragraph,
        // and the spec stamped on the seat under
        // TBGridSpecKey for whoever paints it. Absolutely
        // positioned children are no items: they register
        // with the ordinary machinery as the walk meets
        // them. Floated children simply itemize — CSS
        // computes float away on an item. Past sixty
        // items, further children flow into the last item,
        // as past sixty floats the rest simply flow.
        func renderGrid(node: TBNode, spec: TBGridSpec,
                                font: NSFont, color: NSColor?,
                                align: NSTextAlignment,
                                background: NSColor?,
                                backgroundBox: TBBackgroundBox?,
                                metrics: TBBlockMetrics,
                                ownSurface: Bool) -> Bool {
            var subs: [TBRenderer] = []
            var items: [TBGridItem] = []
            var run: [TBNode] = []

            func makeItem(walkNode: TBNode, own: [String: String],
                          baseFont: NSFont, fontSize: CGFloat) {
                if items.count >= 60, let lastSub = subs.last,
                   let last = items.last {
                    lastSub.walkBlock(node: walkNode,
                                      style: tbStyle(for: walkNode.tag),
                                      baseFont: baseFont, color: color,
                                      align: align, inheritedBackground: nil,
                                      inheritedBackgroundBox: nil)
                    last.content = lastSub.out
                    return
                }
                let item = TBGridItem()
                dressGridItem(item, own: own, fontSize: fontSize,
                              explicitCols: spec.columnTracks.count,
                              explicitRows: spec.rowTracks.count,
                              spec: spec)
                let sub = TBRenderer(base: base)
                sub.rules = rules
                sub.visitedURLs = visitedURLs
                sub.insideFloat = true
                sub.nominalWidth = nominalWidth
                sub.walkBlock(node: walkNode, style: tbStyle(for: walkNode.tag),
                              baseFont: baseFont, color: color, align: align,
                              inheritedBackground: nil,
                              inheritedBackgroundBox: nil)
                item.content = sub.out
                items.append(item)
                subs.append(sub)
            }
            func flushRun() {
                guard !run.isEmpty else { return }
                let meaningful = run.contains {
                    $0.tag != "#text" || !$0.text.allSatisfy { tbIsSpace($0) }
                }
                let children = run
                run = []
                guard meaningful else { return }
                let holder = TBNode(tag: "#gridrun")
                holder.children = children
                makeItem(walkNode: holder, own: [:], baseFont: font,
                         fontSize: font.pointSize)
            }

            for child in node.children {
                if TBRenderSkipTags.contains(child.tag) { continue }
                if child.tag == "#text" {
                    run.append(child)
                    continue
                }
                let childOwn = resolvedStyle(node: child)
                if tbIsHidden(childOwn) { continue }
                if !insideFloat, positionedCount < 60,
                   !["input", "select", "textarea", "button"].contains(child.tag),
                   let kind = positionKind(childOwn["position"]) {
                    flushRun()
                    if child.tag == "img" {
                        registerPositionedImage(child, own: childOwn, kind: kind,
                                                font: font)
                    } else {
                        registerPositionedBlock(child, own: childOwn, kind: kind,
                                                font: font, color: color,
                                                align: align)
                    }
                    continue
                }
                // Grid items (0.34): in CSS, EVERY child
                // of a grid container stands as its own
                // item, inline children included — they
                // are blockified — and only loose text
                // gathers into an anonymous item. The
                // 0.25 code gathered inline children into
                // the text run around them, so a card
                // built of spans (the hub's directory
                // cards: a name span, a description span,
                // an arrow span under one display:grid
                // link) collapsed into a single item —
                // name and description flowing together
                // in the first track, the arrow standing
                // in the second, the third track empty.
                let isItem = true
                if isItem {
                    flushRun()
                    let childFont = tbFontApplying(childOwn, to: font)
                    if child.tag == "img" {
                        let holder = TBNode(tag: "#gridrun")
                        holder.children = [child]
                        makeItem(walkNode: holder, own: childOwn,
                                 baseFont: font, fontSize: childFont.pointSize)
                    } else {
                        let baseFont = TBHeadingTags.contains(child.tag)
                            ? tbFont(for: child.tag) : font
                        makeItem(walkNode: child, own: childOwn,
                                 baseFont: baseFont,
                                 fontSize: childFont.pointSize)
                    }
                } else {
                    run.append(child)
                }
            }
            flushRun()
            guard !items.isEmpty else { return false }
            spec.items = items
            computeGridLayout(spec: spec)
            let seat = TBGridSeatAttachment()
            seat.image = tbClearSeat(width: spec.totalWidth,
                                     height: spec.totalHeight)
            seat.bounds = CGRect(x: 0, y: 0, width: spec.totalWidth,
                                 height: spec.totalHeight)
            spec.seat = seat
            let para = NSMutableAttributedString(
                attributedString: NSAttributedString(attachment: seat))
            para.addAttribute(.font, value: font,
                              range: NSRange(location: 0, length: para.length))
            para.addAttribute(TBGridSpecKey, value: spec,
                              range: NSRange(location: 0, length: para.length))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            if spaceCarry > 0 { paragraph.paragraphSpacingBefore = spaceCarry }
            if metrics.after > 0 { paragraph.paragraphSpacing = metrics.after }
            if metrics.indent > 0 {
                paragraph.headIndent = metrics.indent
                paragraph.firstLineHeadIndent = metrics.indent
            }
            if metrics.tailIndent > 0 { paragraph.tailIndent = -metrics.tailIndent }
            para.addAttribute(.paragraphStyle, value: paragraph,
                              range: NSRange(location: 0, length: para.length))
            if let background = background {
                para.addAttribute(.backgroundColor, value: background,
                                  range: NSRange(location: 0, length: para.length))
            }
            let paraStart = out.length
            spec.anchorCharIndex = paraStart
            out.append(para)
            lastFlushRange = NSRange(location: paraStart, length: para.length)
            if relDX != 0 || relDY != 0 {
                out.addAttribute(TBRelOffsetKey,
                                 value: NSValue(point: NSPoint(x: relDX, y: relDY)),
                                 range: NSRange(location: paraStart,
                                                length: para.length))
            }
            if !pendingClears.isEmpty {
                for clearSpec in pendingClears {
                    clearSpec.anchorCharIndex = paraStart
                }
                pendingClears = []
            }
            var separatorAttrs: [NSAttributedString.Key: Any] = [:]
            if let background = background {
                separatorAttrs[.backgroundColor] = background
            }
            if let backgroundBox = backgroundBox {
                separatorAttrs[TBBackgroundKey] = backgroundBox
            }
            out.append(NSAttributedString(string: "\n\n",
                                          attributes: separatorAttrs))
            noteSurfaceParagraph(
                range: NSRange(location: paraStart, length: para.length),
                color: background, box: backgroundBox,
                after: metrics.after, ownSurface: ownSurface)
            spaceCarry = 0
            if !insideFloat {
                layoutEvents.append(.grid(spec))
            }
            if let link = spec.containerLink {
                containerLinkSeats.append((kind: "grid", link: link))
            }
            pendingGrid.append((spec: spec, subs: subs))
            gridCount += 1
            return true
        }

        // Lay a grid container out: place every item,
        // size the tracks, and resolve every item's
        // border box in the container's content-box
        // coordinates, with the container's own height.
        // Placement first, in the spec's order — items
        // definite in both axes, then items locked to
        // their flow line at the first free run along
        // it, then the rest from the shared cursor —
        // restarted at the first cell for every item
        // under dense packing, so holes backfill. Then
        // columns: bases from the items' measured outer
        // sizes, fixed tracks at their lengths, content
        // and flexible tracks raised by what stands in
        // them, an item spanning several tracks sharing
        // its excess across the growable ones it spans,
        // and the leftover shared among the fr tracks
        // with each freezing at its minimum. Then the
        // items' widths stand (a declared width, the
        // whole area under stretch, else the natural
        // width capped by the area), their heights are
        // measured standing at those widths, and the
        // rows size by the same machinery against the
        // declared height when there is one — an fr row
        // under an indefinite height sizes to its
        // contents, as the spec directs. Percentages
        // resolve against the container's true content
        // size on each axis, in this pass, never a
        // nominal page.
        private func computeGridLayout(spec: TBGridSpec) {
            let items = spec.items
            let contentW = spec.totalWidth
            let gapColumn = resolveFlexLength(spec.gapColumn,
                                              against: contentW) ?? 0
            let gapRow = resolveFlexLength(spec.gapRow,
                                           against: spec.declaredHeight) ?? 0

            // Placement (0.30): the algorithm runs in
            // flow coordinates — a along the auto-flow
            // axis (the rows in row flow, the columns in
            // column flow), b across it — so one cursor
            // serves both flows, transposed exactly as
            // the spec writes its own algorithm. Items
            // definite in both axes stand first; items
            // definite along the flow axis scan the
            // cross axis for their first free run; the
            // rest follow the shared cursor, stepping
            // around what stands. Dense packing restarts
            // the cursor at the first cell for every
            // item, so a late small item backfills a
            // hole the sparse cursor has passed.
            let columnFlow = spec.autoFlowColumn
            func aLine(_ item: TBGridItem) -> Int? {
                columnFlow ? item.colLine : item.rowLine
            }
            func bLine(_ item: TBGridItem) -> Int? {
                columnFlow ? item.rowLine : item.colLine
            }
            func aSpan(_ item: TBGridItem) -> Int {
                columnFlow ? item.colSpan : item.rowSpan
            }
            func bSpan(_ item: TBGridItem) -> Int {
                columnFlow ? item.rowSpan : item.colSpan
            }
            // The cross-axis tracks the flow may fill:
            // the template's own count on that axis,
            // grown by every definite cross placement
            // and every cross span.
            var bCount = max(columnFlow ? spec.rowTracks.count
                                        : spec.columnTracks.count, 1)
            for item in items {
                if let line = bLine(item) {
                    bCount = max(bCount, line - 1 + bSpan(item))
                }
                bCount = max(bCount, bSpan(item))
            }
            var occupied = Set<Int>()
            func cellKey(_ row: Int, _ col: Int) -> Int { row * 65536 + col }
            func areaFree(_ row: Int, _ col: Int,
                          _ rowSpan: Int, _ colSpan: Int) -> Bool {
                for r in row..<(row + rowSpan) {
                    for c in col..<(col + colSpan) {
                        if occupied.contains(cellKey(r, c)) { return false }
                    }
                }
                return true
            }
            func markArea(_ row: Int, _ col: Int,
                          _ rowSpan: Int, _ colSpan: Int) {
                for r in row..<(row + rowSpan) {
                    for c in col..<(col + colSpan) {
                        occupied.insert(cellKey(r, c))
                    }
                }
            }
            func freeAB(_ a: Int, _ b: Int, _ item: TBGridItem) -> Bool {
                if columnFlow {
                    return areaFree(b, a, bSpan(item), aSpan(item))
                }
                return areaFree(a, b, aSpan(item), bSpan(item))
            }
            func markAB(_ a: Int, _ b: Int, _ item: TBGridItem) {
                if columnFlow {
                    markArea(b, a, bSpan(item), aSpan(item))
                } else {
                    markArea(a, b, aSpan(item), bSpan(item))
                }
            }
            var placedA = [Int](repeating: -1, count: items.count)
            var placedB = [Int](repeating: -1, count: items.count)
            for i in items.indices {
                guard let al = aLine(items[i]), let bl = bLine(items[i])
                else { continue }
                placedA[i] = al - 1
                placedB[i] = bl - 1
                markAB(al - 1, bl - 1, items[i])
            }
            for i in items.indices where placedA[i] < 0 {
                guard let al = aLine(items[i]), bLine(items[i]) == nil
                else { continue }
                let a = al - 1
                var b = 0
                while !freeAB(a, b, items[i]) { b += 1 }
                placedA[i] = a
                placedB[i] = b
                markAB(a, b, items[i])
                bCount = max(bCount, b + bSpan(items[i]))
            }
            var cursorA = 0
            var cursorB = 0
            for i in items.indices where placedA[i] < 0 {
                let item = items[i]
                if spec.autoFlowDense { cursorA = 0; cursorB = 0 }
                if let bl = bLine(item) {
                    let b = bl - 1
                    if b < cursorB { cursorA += 1 }
                    var a = cursorA
                    while !freeAB(a, b, item) { a += 1 }
                    placedA[i] = a
                    placedB[i] = b
                    markAB(a, b, item)
                    cursorA = a
                    cursorB = b
                } else {
                    var a = cursorA
                    var b = cursorB
                    while true {
                        if b + bSpan(item) > bCount {
                            a += 1
                            b = 0
                            continue
                        }
                        if freeAB(a, b, item) { break }
                        b += 1
                    }
                    placedA[i] = a
                    placedB[i] = b
                    markAB(a, b, item)
                    cursorA = a
                    cursorB = b
                }
            }
            var placedRow = [Int](repeating: -1, count: items.count)
            var placedCol = [Int](repeating: -1, count: items.count)
            var colCount = max(spec.columnTracks.count, 1)
            for i in items.indices {
                if columnFlow {
                    placedRow[i] = placedB[i]
                    placedCol[i] = placedA[i]
                } else {
                    placedRow[i] = placedA[i]
                    placedCol[i] = placedB[i]
                }
                colCount = max(colCount, placedCol[i] + items[i].colSpan)
            }
            // The working column list: the template padded
            // with implicit content tracks out to the
            // column count the placement reached.
            var colTracks = spec.columnTracks
            while colTracks.count < colCount {
                colTracks.append(TBGridTrack())
            }
            // auto-fit: tracks the repeat produced that no
            // item landed in collapse, as the spec directs
            // — the placements remap onto the kept tracks.
            if colTracks.contains(where: { $0.fromAutoFit }) {
                var used = Set<Int>()
                for i in items.indices {
                    for c in placedCol[i]..<(placedCol[i] + items[i].colSpan) {
                        used.insert(c)
                    }
                }
                var remap: [Int: Int] = [:]
                var kept: [TBGridTrack] = []
                for (index, track) in colTracks.enumerated() {
                    if track.fromAutoFit, !used.contains(index) { continue }
                    remap[index] = kept.count
                    kept.append(track)
                }
                if kept.count != colTracks.count {
                    colTracks = kept
                    colCount = kept.count
                    for i in items.indices {
                        placedCol[i] = remap[placedCol[i]] ?? placedCol[i]
                    }
                }
            }

            // The items' outer natural and minimum widths:
            // the contents measured unwrapped and at a
            // sliver, plus padding and margins — except a
            // declared width, which reads as the whole box
            // (the floated boxes' convention) and so
            // contributes itself, plus its margins.
            var naturalW = [CGFloat](repeating: 0, count: items.count)
            var minimumW = [CGFloat](repeating: 0, count: items.count)
            for i in items.indices {
                let item = items[i]
                let content = item.content ?? NSAttributedString()
                let margins = item.marginLeft + item.marginRight
                if let declared = resolveFlexLength(item.widthDecl,
                                                    against: contentW) {
                    naturalW[i] = declared + margins
                    minimumW[i] = naturalW[i]
                } else {
                    let extra = item.paddingLeft + item.paddingRight + margins
                    naturalW[i] = measureText(content, width: 100_000).width
                        + extra
                    minimumW[i] = measureText(content, width: 10).width + extra
                }
            }

            // One axis's track bases and minimums: fixed
            // tracks at their lengths (a fixed percentage
            // against an indefinite container size unread,
            // and read as content instead), content and
            // flexible tracks raised by the contributions
            // of the items standing in them, multi-span
            // items sharing their excess across the spanned
            // tracks free to grow — and standing overflowed
            // when none are.
            func trackBases(
                _ tracks: inout [TBGridTrack], containerBase: CGFloat?,
                gap: CGFloat,
                contributions: [(track: Int, span: Int,
                                 natural: CGFloat, minimum: CGFloat)]
            ) -> (base: [CGFloat], minimum: [CGFloat]) {
                var base = [CGFloat](repeating: 0, count: tracks.count)
                var minimum = [CGFloat](repeating: 0, count: tracks.count)
                for t in tracks.indices {
                    let track = tracks[t]
                    if let fixed = track.maxLength {
                        if let v = resolveFlexLength(fixed,
                                                     against: containerBase) {
                            base[t] = v
                            minimum[t] = v
                            if let minL = track.minLength,
                               let mv = resolveFlexLength(minL,
                                                          against: containerBase) {
                                minimum[t] = min(mv, v)
                            }
                            continue
                        }
                        tracks[t].maxLength = nil
                        tracks[t].maxContent = true
                    }
                    if let minL = track.minLength,
                       let mv = resolveFlexLength(minL,
                                                  against: containerBase) {
                        minimum[t] = mv
                        base[t] = max(base[t], mv)
                    }
                }
                for c in contributions where c.span == 1 {
                    let t = c.track
                    guard t >= 0, t < tracks.count else { continue }
                    if tracks[t].maxLength == nil {
                        base[t] = max(base[t], c.natural)
                    }
                    if tracks[t].minLength == nil {
                        minimum[t] = max(minimum[t], c.minimum)
                    }
                }
                func spread(_ c: (track: Int, span: Int,
                                  natural: CGFloat, minimum: CGFloat),
                            need: CGFloat, into sizes: inout [CGFloat],
                            growable: (TBGridTrack) -> Bool) {
                    let range = c.track..<(c.track + c.span)
                    guard range.lowerBound >= 0,
                          range.upperBound <= tracks.count else { return }
                    let have = range.reduce(0) { $0 + sizes[$1] }
                        + gap * CGFloat(c.span - 1)
                    guard need > have + 0.5 else { return }
                    let targets = range.filter { growable(tracks[$0]) }
                    guard !targets.isEmpty else { return }
                    let each = (need - have) / CGFloat(targets.count)
                    for t in targets { sizes[t] += each }
                }
                let wide = contributions.filter { $0.span > 1 }
                    .sorted { $0.span < $1.span }
                for c in wide {
                    spread(c, need: c.natural, into: &base) {
                        $0.maxLength == nil
                    }
                    spread(c, need: c.minimum, into: &minimum) {
                        $0.minLength == nil
                    }
                }
                return (base, minimum)
            }

            // The leftover shared among one axis's flexible
            // tracks, each freezing at its minimum as the
            // share reaches it — the flex grow loop's
            // shape, on tracks. With no definite container
            // size, or none left over, the bases stand.
            func resolveTracks(base: [CGFloat], minimum: [CGFloat],
                               flexFactor: [Double], containerSize: CGFloat?,
                               gap: CGFloat) -> [CGFloat] {
                var sizes = base
                guard let total = containerSize, !sizes.isEmpty
                else { return sizes }
                let gaps = gap * CGFloat(sizes.count - 1)
                var frozen = Set<Int>()
                var rounds = 0
                while rounds <= sizes.count {
                    rounds += 1
                    let active = sizes.indices.filter {
                        flexFactor[$0] > 0 && !frozen.contains($0)
                    }
                    if active.isEmpty { break }
                    let usedByOthers = sizes.indices.reduce(0) {
                        $0 + (active.contains($1) ? minimum[$1] : sizes[$1])
                    } + gaps
                    let free = total - usedByOthers
                    let totalFr = active.reduce(0) { $0 + flexFactor[$1] }
                    if free <= 0 || totalFr <= 0 { break }
                    let unit = free / CGFloat(totalFr)
                    var froze = false
                    for i in active {
                        let share = unit * CGFloat(flexFactor[i])
                        if share < minimum[i] {
                            sizes[i] = minimum[i]
                            frozen.insert(i)
                            froze = true
                        } else {
                            sizes[i] = share
                        }
                    }
                    if !froze { break }
                }
                for i in sizes.indices where flexFactor[i] > 0 {
                    sizes[i] = max(sizes[i], minimum[i])
                }
                return sizes
            }

            // The columns.
            let colContribs: [(track: Int, span: Int,
                               natural: CGFloat, minimum: CGFloat)]
                = items.indices.map {
                    (track: placedCol[$0], span: items[$0].colSpan,
                     natural: naturalW[$0], minimum: minimumW[$0])
                }
            let colBM = trackBases(&colTracks, containerBase: contentW,
                                   gap: gapColumn, contributions: colContribs)
            let colSizes = resolveTracks(
                base: colBM.base, minimum: colBM.minimum,
                flexFactor: colTracks.map { $0.maxFr ?? 0 },
                containerSize: contentW, gap: gapColumn)

            // The items' border-box widths, from the
            // columns now sized.
            var borderW = [CGFloat](repeating: 0, count: items.count)
            for i in items.indices {
                let item = items[i]
                var area: CGFloat = 0
                for c in placedCol[i]..<(placedCol[i] + item.colSpan) {
                    area += colSizes[c]
                }
                area += gapColumn * CGFloat(item.colSpan - 1)
                let margins = item.marginLeft + item.marginRight
                if let declared = resolveFlexLength(item.widthDecl,
                                                    against: contentW) {
                    borderW[i] = declared
                } else if (item.justifySelf ?? spec.justifyItems) == "stretch" {
                    borderW[i] = max(area - margins, 0)
                } else {
                    borderW[i] = max(min(naturalW[i] - margins,
                                         area - margins), 0)
                }
            }

            // The items' outer heights, standing at those
            // widths — a declared height contributing
            // itself, as a declared width did.
            var naturalH = [CGFloat](repeating: 0, count: items.count)
            for i in items.indices {
                let item = items[i]
                let margins = item.marginTop + item.marginBottom
                if let declared = resolveFlexLength(item.heightDecl,
                                                    against: spec.declaredHeight) {
                    naturalH[i] = declared + margins
                } else {
                    let cw = max(borderW[i] - item.paddingLeft
                        - item.paddingRight, 10)
                    naturalH[i] = measureText(
                        item.content ?? NSAttributedString(), width: cw).height
                        + item.paddingTop + item.paddingBottom + margins
                }
            }

            // The rows: the template padded with implicit
            // content tracks out to the deepest placement.
            var rowCount = spec.rowTracks.count
            for i in items.indices {
                rowCount = max(rowCount, placedRow[i] + items[i].rowSpan)
            }
            var rowTracks = spec.rowTracks
            while rowTracks.count < rowCount {
                rowTracks.append(TBGridTrack())
            }
            let rowContribs: [(track: Int, span: Int,
                               natural: CGFloat, minimum: CGFloat)]
                = items.indices.map {
                    (track: placedRow[$0], span: items[$0].rowSpan,
                     natural: naturalH[$0], minimum: naturalH[$0])
                }
            let rowBM = trackBases(&rowTracks,
                                   containerBase: spec.declaredHeight,
                                   gap: gapRow, contributions: rowContribs)
            let rowSizes = resolveTracks(
                base: rowBM.base, minimum: rowBM.minimum,
                flexFactor: rowTracks.map { $0.maxFr ?? 0 },
                containerSize: spec.declaredHeight, gap: gapRow)

            // The container's own height: the rows and
            // their gaps, or the declared height when the
            // page declared one — clamped by its own min
            // and max, as a flex container's is.
            let rowsTotal = rowSizes.reduce(0, +)
                + gapRow * CGFloat(max(rowSizes.count - 1, 0))
            var total = spec.declaredHeight ?? rowsTotal
            if let lo = spec.minHeightClamp { total = max(total, lo) }
            if let hi = spec.maxHeightClamp { total = min(total, hi) }
            spec.totalHeight = max(total, 0)

            // Distribution: a track set that does not fill
            // its container is shared out as
            // justify-content and align-content direct.
            var shiftX: CGFloat = 0
            var extraGapX: CGFloat = 0
            let colsUsed = colSizes.reduce(0, +)
                + gapColumn * CGFloat(max(colSizes.count - 1, 0))
            let leftoverX = contentW - colsUsed
            if leftoverX > 0.5 {
                switch spec.justifyContent {
                case "end": shiftX = leftoverX
                case "center": shiftX = leftoverX / 2
                case "space-between":
                    if colSizes.count > 1 {
                        extraGapX = leftoverX / CGFloat(colSizes.count - 1)
                    }
                case "space-around":
                    if !colSizes.isEmpty {
                        let unit = leftoverX / CGFloat(colSizes.count)
                        shiftX = unit / 2
                        extraGapX = unit
                    }
                case "space-evenly":
                    let unit = leftoverX / CGFloat(colSizes.count + 1)
                    shiftX = unit
                    extraGapX = unit
                default: break
                }
            }
            var shiftY: CGFloat = 0
            var extraGapY: CGFloat = 0
            let leftoverY = spec.totalHeight - rowsTotal
            if leftoverY > 0.5 {
                switch spec.alignContent {
                case "end": shiftY = leftoverY
                case "center": shiftY = leftoverY / 2
                case "space-between":
                    if rowSizes.count > 1 {
                        extraGapY = leftoverY / CGFloat(rowSizes.count - 1)
                    }
                case "space-around":
                    if !rowSizes.isEmpty {
                        let unit = leftoverY / CGFloat(rowSizes.count)
                        shiftY = unit / 2
                        extraGapY = unit
                    }
                case "space-evenly":
                    let unit = leftoverY / CGFloat(rowSizes.count + 1)
                    shiftY = unit
                    extraGapY = unit
                default: break
                }
            }

            // Track origins, then every item's border box
            // inside its area.
            var colX = [CGFloat](repeating: 0, count: colSizes.count)
            var nextX = shiftX
            for c in colSizes.indices {
                colX[c] = nextX
                nextX += colSizes[c] + gapColumn + extraGapX
            }
            var rowY = [CGFloat](repeating: 0, count: rowSizes.count)
            var nextY = shiftY
            for r in rowSizes.indices {
                rowY[r] = nextY
                nextY += rowSizes[r] + gapRow + extraGapY
            }
            for i in items.indices {
                let item = items[i]
                let c0 = placedCol[i]
                let r0 = placedRow[i]
                var areaW: CGFloat = 0
                for c in c0..<(c0 + item.colSpan) { areaW += colSizes[c] }
                areaW += (gapColumn + extraGapX) * CGFloat(item.colSpan - 1)
                var areaH: CGFloat = 0
                for r in r0..<(r0 + item.rowSpan) { areaH += rowSizes[r] }
                areaH += (gapRow + extraGapY) * CGFloat(item.rowSpan - 1)
                let justify = item.justifySelf ?? spec.justifyItems
                let align = item.alignSelf ?? spec.alignItems
                let w = borderW[i]
                let h: CGFloat
                if let declared = resolveFlexLength(item.heightDecl,
                                                    against: spec.declaredHeight) {
                    h = declared
                } else if align == "stretch" {
                    h = max(areaH - item.marginTop - item.marginBottom, 0)
                } else {
                    h = max(naturalH[i] - item.marginTop - item.marginBottom, 0)
                }
                var ox = colX[c0]
                switch justify {
                case "end":
                    ox += areaW - item.marginRight - w
                case "center":
                    ox += (areaW - w - item.marginLeft - item.marginRight) / 2
                        + item.marginLeft
                default:
                    ox += item.marginLeft
                }
                var oy = rowY[r0]
                switch align {
                case "end":
                    oy += areaH - item.marginBottom - h
                case "center":
                    oy += (areaH - h - item.marginTop - item.marginBottom) / 2
                        + item.marginTop
                default:
                    oy += item.marginTop
                }
                item.rect = NSRect(x: ox, y: oy, width: w, height: h)
            }
            if let seat = spec.seat {
                seat.image = tbClearSeat(width: spec.totalWidth,
                                         height: spec.totalHeight)
                seat.bounds = CGRect(x: 0, y: 0, width: spec.totalWidth,
                                     height: spec.totalHeight)
            }
        }

        // A grid container nested in painted contents was
        // walked against the page's nominal width, but it
        // stands in the width its box gives it: correct
        // its span to that width (inside its own flow
        // indents, and never past a width it declared),
        // lay it out again there, and do the same for the
        // containers nested in its items — grid and flex
        // alike, the one shared finalize path — at the
        // widths the new layout gives them. Called by
        // every finalize that settles a painted box's
        // contents, and by finalizeGrid for its own items.
        private func correctGridSeats(in content: NSAttributedString,
                                      availableWidth: CGFloat,
                                      depth: Int = 0) {
            guard depth < 8 else { return }
            var found: [TBGridSpec] = []
            content.enumerateAttribute(
                TBGridSpecKey, in: NSRange(location: 0, length: content.length)
            ) { value, _, _ in
                if let spec = value as? TBGridSpec { found.append(spec) }
            }
            for spec in found {
                var width = max(availableWidth - spec.flowIndent
                    - spec.flowTailIndent, 10)
                if let cap = spec.declaredContentWidth {
                    width = min(width, cap)
                }
                if let link = spec.containerLink,
                   !containerLinkSeats.contains(where: { $0.link == link }) {
                    containerLinkSeats.append((kind: "grid", link: link))
                }
                spec.totalWidth = width
                computeGridLayout(spec: spec)
                for item in spec.items {
                    guard let itemContent = item.content else { continue }
                    let itemWidth = max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10)
                    correctGridSeats(in: itemContent,
                                     availableWidth: itemWidth,
                                     depth: depth + 1)
                    correctFlexSeats(in: itemContent,
                                     availableWidth: itemWidth,
                                     depth: depth + 1)
                }
            }
        }

        // A grid container's items are finished (their
        // pictures fetched, their failures labelled):
        // strip what cannot work inside a painted box —
        // the link targets and their markers, and the
        // form controls, for which bracketed labels stand
        // in — exactly the cleaning a flex container's
        // items get — then lay the container out on the
        // finished text, correct the containers nested in
        // its items to the widths the layout gave them,
        // and lay out again, twice over, so a nested
        // container's corrected height settles into the
        // outer tracks before the seat in the page is
        // corrected the final time.
        private func finalizeGrid(spec: TBGridSpec, subs: [TBRenderer]) {
            for (index, item) in spec.items.enumerated() {
                guard index < subs.count else { break }
                let sub = subs[index]
                let cleaned = NSMutableAttributedString(attributedString: sub.out)
                var swaps: [(range: NSRange, text: String)] = []
                cleaned.enumerateAttribute(
                    .attachment, in: NSRange(location: 0, length: cleaned.length)
                ) { value, range, _ in
                    if let submit = value as? TBSubmitAttachment {
                        swaps.append((range: range, text: " [\(submit.label)] "))
                    } else if let field = value as? TBFieldAttachment {
                        let name = sub.fields.first { $0.id == field.fieldID }
                            .map { $0.placeholder.isEmpty ? "field" : $0.placeholder }
                            ?? "field"
                        swaps.append((range: range, text: " [\(name)] "))
                    } else if let select = value as? TBSelectAttachment {
                        // Live controls (0.31): the popup
                        // stands in for its resting
                        // choice's label.
                        let label = select.selectedIndex >= 0
                            && select.selectedIndex < select.options.count
                            ? select.options[select.selectedIndex].label : "select"
                        swaps.append((range: range, text: " [\(label)] "))
                    } else if let area = value as? TBTextAreaAttachment {
                        let name = sub.fields.first { $0.id == area.fieldID }
                            .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                        swaps.append((range: range, text: " [\(name)] "))
                    }
                }
                cleaned.enumerateAttribute(
                    .link, in: NSRange(location: 0, length: cleaned.length)
                ) { _, range, _ in
                    let text = (cleaned.string as NSString).substring(with: range)
                    if text.hasPrefix(" ["), text.hasSuffix("]") {
                        let digits = text.dropFirst(2).dropLast()
                        if !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) {
                            swaps.append((range: range, text: ""))
                        }
                    }
                }
                for swap in swaps.sorted(by: { $0.range.location > $1.range.location }) {
                    cleaned.replaceCharacters(in: swap.range, with: NSAttributedString(
                        string: swap.text,
                        attributes: [.font: NSFont.systemFont(ofSize: 12),
                                     .foregroundColor: NSColor.secondaryLabelColor]))
                }
                // Links in the item keep their
                // targets now (0.36): the view
                // hit-tests painted items and
                // follows them.
                item.content = cleaned
            }
            computeGridLayout(spec: spec)
            for item in spec.items {
                guard let content = item.content else { continue }
                correctGridSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
                correctFlexSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
            }
            computeGridLayout(spec: spec)
            for item in spec.items {
                guard let content = item.content else { continue }
                correctGridSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
                correctFlexSeats(
                    in: content,
                    availableWidth: max(item.rect.width - item.paddingLeft
                        - item.paddingRight, 10))
            }
            computeGridLayout(spec: spec)
        }

        // Arrivals for the grid containers (0.25): each
        // item's own pictures and backgrounds land first
        // (and any containers nested deeper — grid and
        // flex alike, through the same passes on the
        // item's renderer), then the container is cleaned
        // and laid out for the last time — the two-stage
        // life every painted construct in this engine
        // leads.
        func finishGrid() async {
            for pending in pendingGrid {
                for sub in pending.subs {
                    await sub.finishImages()
                    await sub.finishBackgrounds()
                    await sub.finishFlex()
                    await sub.finishGrid()
                }
                finalizeGrid(spec: pending.spec, subs: pending.subs)
            }
            pendingGrid = []
        }

}

extension TBRenderer {
        // MARK: - Positioned layout (0.21)

        // The declarations every positioned box shares,
        // read once: insets, stacking order, margins and
        // padding, backgrounds, and which of its dimensions
        // the page declared, the insets must derive, or its
        // contents must measure.
        private func dressPositioned(_ spec: TBPositionedSpec,
                                     own: [String: String], fontSize: CGFloat) {
            spec.top = insetValue(own["top"], fontSize: fontSize)
            spec.right = insetValue(own["right"], fontSize: fontSize)
            spec.bottom = insetValue(own["bottom"], fontSize: fontSize)
            spec.left = insetValue(own["left"], fontSize: fontSize)
            spec.zIndex = zIndexValue(own["z-index"])
            let margins = boxLengths(own, "margin", fontSize: fontSize)
            spec.marginTop = margins.top
            spec.marginRight = margins.right
            spec.marginBottom = margins.bottom
            spec.marginLeft = margins.left
            let padding = boxLengths(own, "padding", fontSize: fontSize)
            spec.paddingTop = padding.top
            spec.paddingRight = padding.right
            spec.paddingBottom = padding.bottom
            spec.paddingLeft = padding.left
            spec.backgroundColor = tbBackgroundColor(own)
            spec.backgroundBox = backgroundBox(decls: own)
            spec.boxShadows = boxShadowSet(own, color: nil,
                                           fontSize: fontSize)
            spec.transformSpec = transformSpec(own, fontSize: fontSize)
            spec.opacityValue = opacityValue(own) ?? 1
            spec.widthFromInsets = !spec.widthDeclared
                && spec.left != nil && spec.right != nil
            spec.heightFromInsets = !spec.heightDeclared
                && spec.top != nil && spec.bottom != nil
        }

        func registerPositionedImage(_ node: TBNode, own: [String: String],
                                             kind: TBPositionKind, font: NSFont) {
            let src = (node.attrs["src"] ?? "").trimmingCharacters(in: .whitespaces)
            // A declared 1x1 is a tracking pixel, not a picture.
            let isPixel = node.attrs["width"] == "1" || node.attrs["height"] == "1"
            guard !src.isEmpty, !isPixel else { return }
            let ownFont = tbFontApplying(own, to: font)
            let declaredW = tbLengthValue(own["width"] ?? node.attrs["width"],
                                          fontSize: ownFont.pointSize)
            let declaredH = tbLengthValue(own["height"] ?? node.attrs["height"],
                                            fontSize: ownFont.pointSize)
            let spec = TBPositionedSpec(
                anchorCharIndex: out.length, kind: kind,
                containingBlock: kind == .absolute ? containingBlocks.last : nil,
                isImage: true,
                borderWidth: declaredW ?? 220, borderHeight: declaredH ?? 140)
            spec.widthDeclared = declaredW != nil
            spec.heightDeclared = declaredH != nil
            spec.alt = node.attrs["alt"] ?? ""
            dressPositioned(spec, own: own, fontSize: ownFont.pointSize)
            // A picture the insets must stretch has no size
            // until the view derives it there.
            if spec.widthFromInsets { spec.borderWidth = 0 }
            if spec.heightFromInsets { spec.borderHeight = 0 }
            let absolute = src.hasPrefix("data:")
                ? src
                : (URL(string: src, relativeTo: URL(string: base))?.absoluteString ?? src)
            layoutEvents.append(.positioned(spec))
            positionedCount += 1
            positionedImageJobs.append((spec: spec, url: absolute))
        }

        func registerPositionedBlock(_ node: TBNode, own: [String: String],
                                             kind: TBPositionKind, font: NSFont,
                                             color: NSColor?, align: NSTextAlignment) {
            let childFont = tbFontApplying(own, to: font)
            let fontSize = childFont.pointSize
            let declaredW = tbLengthValue(own["width"], fontSize: fontSize)
            let declaredH = tbLengthValue(own["height"], fontSize: fontSize)
            let spec = TBPositionedSpec(
                anchorCharIndex: out.length, kind: kind,
                containingBlock: kind == .absolute ? containingBlocks.last : nil,
                isImage: false,
                borderWidth: declaredW ?? 0, borderHeight: declaredH ?? 0)
            spec.widthDeclared = declaredW != nil
            spec.heightDeclared = declaredH != nil
            // A positioned anchor (0.37.3): as with the
            // floated one, the box IS the link.
            if node.tag == "a", let href = node.attrs["href"], !href.isEmpty {
                spec.containerLink = URL(string: href,
                                         relativeTo: URL(string: base))?.absoluteString
                    ?? href
                if let link = spec.containerLink {
                    containerLinkSeats.append((kind: "positioned", link: link))
                }
            }
            dressPositioned(spec, own: own, fontSize: fontSize)
            // The box's contents render in a renderer of their
            // own, exactly as a block float's do — same rules,
            // same base, no layout events of its own: a
            // positioned box inside this one simply flows.
            let sub = TBRenderer(base: base)
            sub.rules = rules
            sub.visitedURLs = visitedURLs
            sub.insideFloat = true
            sub.nominalWidth = nominalWidth
            sub.walkBlock(node: node, style: tbStyle(for: node.tag), baseFont: childFont,
                          color: color, align: align,
                          inheritedBackground: nil, inheritedBackgroundBox: nil)
            layoutEvents.append(.positioned(spec))
            positionedCount += 1
            pendingPositioned.append((spec: spec, sub: sub))
        }

        // A positioned block's contents are finished: clean
        // them as a block float's are cleaned (see
        // finalizeBlockFloat — link targets and form
        // controls cannot work inside a painted box), then
        // size the box: a declared dimension wins, a
        // dimension the insets must derive stays at zero
        // for the view to settle, and the rest shrink to
        // the measured contents, capped at the column.
        private func finalizePositioned(spec: TBPositionedSpec, sub: TBRenderer) {
            let cleaned = NSMutableAttributedString(attributedString: sub.out)
            var swaps: [(range: NSRange, text: String)] = []
            cleaned.enumerateAttribute(
                .attachment, in: NSRange(location: 0, length: cleaned.length)
            ) { value, range, _ in
                if let submit = value as? TBSubmitAttachment {
                    swaps.append((range: range, text: " [\(submit.label)] "))
                } else if let field = value as? TBFieldAttachment {
                    let name = sub.fields.first { $0.id == field.fieldID }
                        .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                    swaps.append((range: range, text: " [\(name)] "))
                } else if let select = value as? TBSelectAttachment {
                    // Live controls (0.31): the popup stands
                    // in for its resting choice's label.
                    let label = select.selectedIndex >= 0
                        && select.selectedIndex < select.options.count
                        ? select.options[select.selectedIndex].label : "select"
                    swaps.append((range: range, text: " [\(label)] "))
                } else if let area = value as? TBTextAreaAttachment {
                    let name = sub.fields.first { $0.id == area.fieldID }
                        .map { $0.placeholder.isEmpty ? "field" : $0.placeholder } ?? "field"
                    swaps.append((range: range, text: " [\(name)] "))
                }
            }
            cleaned.enumerateAttribute(
                .link, in: NSRange(location: 0, length: cleaned.length)
            ) { _, range, _ in
                let text = (cleaned.string as NSString).substring(with: range)
                if text.hasPrefix(" ["), text.hasSuffix("]") {
                    let digits = text.dropFirst(2).dropLast()
                    if !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) {
                        swaps.append((range: range, text: ""))
                    }
                }
            }
            for swap in swaps.sorted(by: { $0.range.location > $1.range.location }) {
                cleaned.replaceCharacters(in: swap.range, with: NSAttributedString(
                    string: swap.text,
                    attributes: [.font: NSFont.systemFont(ofSize: 12),
                                 .foregroundColor: NSColor.secondaryLabelColor]))
            }
            // The speed stage (0.36): the box's links
            // KEEP their targets — the view hit-tests
            // painted boxes now and follows them. The
            // [n] markers above still come out: they
            // numbered the page's flow links, not the
            // box's own.
            spec.content = cleaned
            let padH = spec.paddingLeft + spec.paddingRight
            let padV = spec.paddingTop + spec.paddingBottom
            // Flexbox (0.24): correct any flex container
            // nested in this box to the width it stands
            // in — its declared width if it has one, else
            // this box's content width, as the width
            // measurement below settles it. Grid (0.25):
            // any grid container nested in the box is
            // corrected to the same width by the same pass.
            if spec.widthDeclared || spec.widthFromInsets {
                correctFlexSeats(in: cleaned,
                                 availableWidth: max(spec.borderWidth - padH, 10))
                correctGridSeats(in: cleaned,
                                 availableWidth: max(spec.borderWidth - padH, 10))
            } else {
                let natural = measureText(cleaned, width: nominalWidth).width
                correctFlexSeats(
                    in: cleaned,
                    availableWidth: max(min(natural + padH, nominalWidth) - padH, 10))
                correctGridSeats(
                    in: cleaned,
                    availableWidth: max(min(natural + padH, nominalWidth) - padH, 10))
            }
            if !spec.widthDeclared && !spec.widthFromInsets {
                let natural = measureText(cleaned, width: nominalWidth).width
                spec.borderWidth = min(max(natural + padH, 1), nominalWidth)
            }
            if !spec.heightDeclared && !spec.heightFromInsets {
                // A width the view will derive is measured
                // here at the column's width, the honest
                // approximation this engine makes everywhere;
                // the contents re-lay themselves out at the
                // box's true width when the view paints them.
                let measureWidth = spec.widthFromInsets ? nominalWidth : spec.borderWidth
                let contentWidth = max(measureWidth - padH, 10)
                spec.borderHeight = measureText(cleaned, width: contentWidth).height + padV
            }
            if !spec.widthFromInsets { spec.borderWidth = max(spec.borderWidth, 1) }
            if !spec.heightFromInsets { spec.borderHeight = max(spec.borderHeight, 1) }
        }

        // Arrivals for the positioned boxes (0.21): fetch
        // their pictures the bounded way, then measure the
        // block boxes from their finished contents — the
        // same two-stage life floats lead (declared geometry
        // at first paint, measured geometry at arrivals).
        func finishPositioned() async {
            if !positionedImageJobs.isEmpty {
                var dataByIndex: [Int: Data] = [:]
                var fetchJobs: [(index: Int, url: String)] = []
                for (index, job) in positionedImageJobs.enumerated() {
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
                for (index, job) in positionedImageJobs.enumerated() {
                    let spec = job.spec
                    guard let data = dataByIndex[index], let image = NSImage(data: data),
                          image.size.width >= 2, image.size.height >= 2 else {
                        spec.imageFailed = true
                        continue
                    }
                    let natural = image.size
                    var width = spec.widthDeclared ? spec.borderWidth : natural.width
                    var height = spec.heightDeclared ? spec.borderHeight : natural.height
                    if spec.widthDeclared && !spec.heightDeclared {
                        height = natural.height * (width / natural.width)
                    } else if spec.heightDeclared && !spec.widthDeclared {
                        width = natural.width * (height / natural.height)
                    }
                    if width > nominalWidth {
                        height *= nominalWidth / width
                        width = nominalWidth
                    }
                    spec.image = image
                    if !spec.widthFromInsets { spec.borderWidth = width }
                    if !spec.heightFromInsets { spec.borderHeight = height }
                }
                positionedImageJobs = []
            }
            for pending in pendingPositioned {
                await pending.sub.finishImages()
                await pending.sub.finishBackgrounds()
                await pending.sub.finishFlex()
                await pending.sub.finishGrid()
                finalizePositioned(spec: pending.spec, sub: pending.sub)
            }
            pendingPositioned = []
        }

        // Fetch the floated pictures (as finishImages does for
        // the flow) and finish the block floats: a declared
        // dimension wins, the other follows the picture's own
        // proportions, and nothing exceeds the column's width.
        func finishFloatImages() async {
            if !floatImageJobs.isEmpty {
                var dataByIndex: [Int: Data] = [:]
                // The floated pictures fetch the same bounded
                // way as the flow's images (0.19).
                var fetchJobs: [(index: Int, url: String)] = []
                for (index, job) in floatImageJobs.enumerated() {
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
                for (index, job) in floatImageJobs.enumerated() {
                    let spec = job.spec
                    guard let data = dataByIndex[index], let image = NSImage(data: data),
                          image.size.width >= 2, image.size.height >= 2 else {
                        spec.imageFailed = true
                        continue
                    }
                    let natural = image.size
                    var width = spec.widthDeclared ? spec.borderWidth : natural.width
                    var height = spec.heightDeclared ? spec.borderHeight : natural.height
                    if spec.widthDeclared && !spec.heightDeclared {
                        height = natural.height * (width / natural.width)
                    } else if spec.heightDeclared && !spec.widthDeclared {
                        width = natural.width * (height / natural.height)
                    }
                    if width > nominalWidth {
                        height *= nominalWidth / width
                        width = nominalWidth
                    }
                    spec.image = image
                    spec.borderWidth = width
                    spec.borderHeight = height
                }
                floatImageJobs = []
            }
            // The block floats themselves still finish one at
            // a time, in order (0.19's honest limit): each
            // sub-renderer's own pictures and backgrounds now
            // fetch with bounded concurrency inside its finish
            // passes, but overlapping one float's finishing
            // with the next's would mean several renderers'
            // state in flight at once, and this build does
            // not reach across renderers that way.
            for pending in pendingBlockFloats {
                await pending.sub.finishImages()
                await pending.sub.finishBackgrounds()
                await pending.sub.finishFlex()
                finalizeBlockFloat(spec: pending.spec, sub: pending.sub)
            }
            pendingBlockFloats = []
        }

        func inline(_ node: TBNode, font: NSFont, color: NSColor?) -> NSAttributedString {
            if node.tag == "#text" {
                var t = node.text
                t = t.replacingOccurrences(of: "\n", with: " ")
                t = t.replacingOccurrences(of: "\t", with: " ")
                t = t.replacingOccurrences(of: "\r", with: " ")
                var attrs: [NSAttributedString.Key: Any] = [.font: font]
                if let color = color { attrs[.foregroundColor] = color }
                return NSAttributedString(string: t, attributes: attrs)
            }
            let own = resolvedStyle(node: node)
            if tbIsHidden(own) {
                return NSAttributedString(string: "")
            }
            if node.tag == "br" {
                return NSAttributedString(string: " ")
            }
            var f = font
            let fm = NSFontManager.shared
            if node.tag == "b" || node.tag == "strong" {
                f = fm.convert(f, toHaveTrait: .boldFontMask)
            }
            if node.tag == "i" || node.tag == "em" {
                f = fm.convert(f, toHaveTrait: .italicFontMask)
            }
            f = tbFontApplying(own, to: f)
            let effColor = tbParseColor(own["color"]) ?? color

            if node.tag == "img" {
                let alt = node.attrs["alt"] ?? "image"
                let src = (node.attrs["src"] ?? "").trimmingCharacters(in: .whitespaces)
                // A declared 1x1 is a tracking pixel, not a picture.
                let isPixel = node.attrs["width"] == "1" || node.attrs["height"] == "1"
                if !src.isEmpty && !isPixel && imageJobs.count < 24 {
                    let absolute = src.hasPrefix("data:")
                        ? src
                        : (URL(string: src, relativeTo: URL(string: base))?.absoluteString ?? src)
                    let preferredW = tbLengthValue(own["width"] ?? node.attrs["width"],
                                                   fontSize: f.pointSize)
                    let preferredH = tbLengthValue(own["height"] ?? node.attrs["height"],
                                                    fontSize: f.pointSize)
                    let attachment = NSTextAttachment()
                    if let w = preferredW, let h = preferredH {
                        // First paint (0.20): both dimensions are
                        // declared, so the picture's box is
                        // reserved at its final size from the
                        // start — a clear seat, exactly as the
                        // form controls reserve theirs — and the
                        // fetched picture replaces the seat when
                        // it lands, without moving any text.
                        attachment.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                        attachment.image = tbClearSeat(width: w, height: h)
                    } else {
                        attachment.bounds = CGRect(x: 0, y: 0, width: 24, height: 18)
                    }
                    imageJobs.append(TBImageJob(
                        attachment: attachment, url: absolute, alt: alt,
                        preferredWidth: preferredW,
                        preferredHeight: preferredH))
                    return NSAttributedString(attachment: attachment)
                }
                return NSAttributedString(
                    string: " [Image: \(alt)] ",
                    attributes: [.font: f, .foregroundColor: NSColor.secondaryLabelColor])
            }

            if node.tag == "input" {
                return formControl(node, font: f, own: own)
            }
            if node.tag == "select" {
                return formSelect(node, font: f, own: own)
            }
            if node.tag == "textarea" {
                return formTextArea(node, font: f, own: own)
            }
            if node.tag == "button" {
                // A button inside a form submits it, labelled by
                // its own text; a type="button" button, or one
                // outside any form, renders as its label.
                let label = descendantText(node)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let type = (node.attrs["type"] ?? "submit").lowercased()
                if currentFormID >= 0 && type != "button" && type != "reset" {
                    noteSubmit(node)
                    let attachment = TBSubmitAttachment()
                    attachment.formID = currentFormID
                    attachment.label = label.isEmpty ? "Submit" : label
                    // The interaction set (0.26): the button's
                    // style rides on its attachment, as the
                    // submit input's does, with declared sizes
                    // honored the same way.
                    attachment.style = controlStyle(node: node, own: own,
                                                    font: f)
                    let width = tbLengthValue(own["width"], fontSize: f.pointSize)
                        ?? (CGFloat(label.count) * 8 + 30)
                    let height = tbLengthValue(own["height"], fontSize: f.pointSize)
                        ?? 26
                    let box = CGRect(x: 0, y: 0,
                                     width: min(max(width, 40), 560),
                                     height: min(max(height, 20), 120))
                    attachment.bounds = box
                    attachment.image = tbClearSeat(width: box.width, height: box.height)
                    return NSAttributedString(attachment: attachment)
                }
                return NSAttributedString(
                    string: " [\(label)] ",
                    attributes: [.font: f,
                                 .foregroundColor: NSColor.secondaryLabelColor])
            }

            let isForm = node.tag == "form"
            if isForm { enterForm(node) }
            let result = NSMutableAttributedString()
            if node.tag == "a" {
                let inner = NSMutableAttributedString()
                for child in node.children {
                    inner.append(inline(child, font: f, color: effColor))
                }
                let href = node.attrs["href"] ?? ""
                if !href.isEmpty {
                    let absolute = URL(string: href, relativeTo: URL(string: base))?.absoluteString ?? href
                    links.append(absolute)
                    let linkAttrs: [NSAttributedString.Key: Any] = [
                        .font: f,
                        .link: absolute,
                        .foregroundColor: tbParseColor(own["color"]) ?? NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    let linked = NSMutableAttributedString(attributedString: inner)
                    if linked.length > 0 {
                        linked.addAttributes(linkAttrs, range: NSRange(location: 0, length: linked.length))
                    }
                    if TBSettings.showLinkNumbers {
                        linked.append(NSAttributedString(string: " [\(links.count)]", attributes: linkAttrs))
                    }
                    result.append(linked)
                } else {
                    result.append(inner)
                }
            } else {
                for child in node.children {
                    appendJoined(result, inline(child, font: f, color: effColor),
                                 isElement: child.tag != "#text")
                }
            }

            if isForm { exitForm() }

            // Span-level dressing: background, underline, strikethrough.
            if result.length > 0 {
                let full = NSRange(location: 0, length: result.length)
                if let bg = tbBackgroundColor(own) {
                    result.addAttribute(.backgroundColor, value: bg, range: full)
                }
                let decoration = (own["text-decoration"] ?? "").lowercased()
                if node.tag == "u" || decoration.contains("underline") {
                    result.addAttribute(.underlineStyle,
                                        value: NSUnderlineStyle.single.rawValue, range: full)
                }
                if node.tag == "del" || node.tag == "s" || node.tag == "strike"
                    || decoration.contains("line-through") {
                    result.addAttribute(.strikethroughStyle,
                                        value: NSUnderlineStyle.single.rawValue, range: full)
                }
            }
            // Positioned layout (0.17): a relatively positioned
            // inline box carries its offset on its own run; the
            // layout manager shifts that run when painting.
            // (Inside a relatively positioned block, the block's
            // paragraph stamp — the summed offset — governs.)
            if !insideFloat, result.length > 0,
               let offset = relativeOffset(own, fontSize: f.pointSize),
               offset.dx != 0 || offset.dy != 0 {
                result.addAttribute(TBRelOffsetKey,
                                    value: NSValue(point: NSPoint(x: offset.dx, y: offset.dy)),
                                    range: NSRange(location: 0, length: result.length))
            }
            // Hover paint (0.23): this element's hover style is
            // stamped onto its run as the run finishes, under
            // its own key — elements nested inside it stamped
            // theirs first and keep their ground; this stamp
            // fills around them. The view lifts the run into
            // the style while the pointer rests on it.
            if result.length > 0, let hover = hoverPaintStyle(node: node) {
                tbStampHover(result,
                             range: NSRange(location: 0, length: result.length),
                             key: TBHoverAttrsKey, style: hover)
            }
            // The interaction set (0.26): the element's focus
            // and active styles stamp the same way, under
            // their own keys.
            if result.length > 0, let focus = focusPaintStyle(node: node) {
                tbStampHover(result,
                             range: NSRange(location: 0, length: result.length),
                             key: TBFocusAttrsKey, style: focus)
            }
            if result.length > 0, let active = activePaintStyle(node: node) {
                tbStampHover(result,
                             range: NSRange(location: 0, length: result.length),
                             key: TBActiveAttrsKey, style: active)
            }
            // The paint & motion set (0.27): the element's
            // own shadows, paint transform, opacity,
            // transition and animation specs stamp onto its
            // run the same way, under their own keys.
            if result.length > 0 {
                let range = NSRange(location: 0, length: result.length)
                if let shadows = boxShadowSet(own, color: effColor,
                                              fontSize: f.pointSize) {
                    tbStampValue(result, range: range, key: TBBoxShadowKey,
                                 value: shadows)
                }
                if let transform = transformSpec(own, fontSize: f.pointSize) {
                    tbStampValue(result, range: range, key: TBTransformKey,
                                 value: transform)
                }
                if let opacity = opacityValue(own) {
                    tbStampValue(result, range: range, key: TBOpacityKey,
                                 value: TBOpacitySpec(opacity))
                }
                if let transition = transitionSpec(own) {
                    tbStampValue(result, range: range, key: TBTransitionKey,
                                 value: transition)
                }
                if let animation = animationSpec(own, fontSize: f.pointSize) {
                    tbStampValue(result, range: range, key: TBAnimationKey,
                                 value: animation)
                }
            }
            return result
        }
}
