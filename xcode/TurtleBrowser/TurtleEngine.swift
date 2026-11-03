//
//  TurtleEngine.swift
//  Turtle Browser — engine 0.6 (Swift)
//
//  Our own browser engine, ported from the Python original.
//  No WebKit, no Chromium: this file fetches pages itself,
//  parses the HTML into a document tree with its own parser,
//  and renders the tree into readable, clickable text.
//
//  CSS support so far:
//    * Step one (0.2): <style> blocks and inline style=""
//      attributes; element/class/id selectors; the cascade;
//      color, background-color, font-weight, font-style,
//      font-size, text-align, text-decoration, display: none,
//      visibility: hidden; inheritance of colors and font traits.
//    * Step two (0.3): the full selector grammar this engine
//      aims at — compound selectors (a.card, .banner.intro),
//      descendant selectors (.banner h1), child selectors
//      (ul > li), and the universal selector (*), matched
//      against a real ancestor chain; plus external stylesheets
//      fetched from <link rel="stylesheet">, woven into the
//      cascade in document order alongside <style> blocks.
//    * Step three (0.4): CSS variables. Custom properties
//      (--ink, --bg, ...) are collected from :root and any other
//      rule, inherited down the tree like real CSS, and var()
//      references — with fallbacks — are substituted into every
//      declaration before it is painted. The one media query
//      the engine evaluates is prefers-color-scheme: when the
//      Mac is in dark mode, variables (and any other rules)
//      inside @media (prefers-color-scheme: dark) join the
//      cascade, exactly as a real browser would apply them.
//    * Step four (0.5): box backgrounds. A container's
//      background-color now paints behind everything inside it
//      (nearest background wins; a nearer element's own
//      background is never painted over), the color layer of
//      the `background:` shorthand is honored, and the page's
//      own background color becomes the window's canvas color.
//    * Layout step one (0.6): the flow starts listening to
//      `display` — an element styled block, flex, or grid
//      becomes its own block (link cards finally stand apart
//      instead of running together), and one styled inline
//      flows inline; margins and padding become paragraph
//      spacing and indents; line-height is honored; lengths
//      understand clamp(), min(), and max().
//  Not yet: other pseudo-classes (:hover) and @-rules,
//  color-mix(), the font: shorthand, true box positioning
//  (columns, floats, centered fixed-width columns, full-width
//  background bands — those want a richer paint surface than
//  a text view), images (labelled placeholders),
//  JavaScript (the mountain).
//

import Foundation
import AppKit

let TB_HOME_HTML = """
<!DOCTYPE html>
<html>
<head><title>Turtle Home</title></head>
<body>
<h1>Turtle Browser</h1>
<p>A browser for Catholics, by Catholics. Private, simple, and ours.</p>
<h2>Your word is a lamp to my feet</h2>
<p>"Your word is a lamp to my feet, and a light for my path."
&mdash; Psalm 119:105 (World English Bible)</p>
<h2>Doors</h2>
<ul>
<li><a href="https://jesuslovestyler.github.io/Catholic-Bible/">Catholic Bible</a></li>
<li><a href="https://jesuslovestyler.github.io/Catholic-Study-Bible/">Catholic Study Bible</a></li>
<li><a href="https://jesuslovestyler.github.io/Library-of-Faith/">Library of Faith</a></li>
<li><a href="https://jesuslovestyler.github.io/Vigil/">Vigil</a></li>
<li><a href="https://jesuslovestyler.com/">Jesus Loves Tyler &mdash; the hub</a></li>
</ul>
<h2>Our promises</h2>
<p>No tracking. No ads. No selling data. A family filter that is on
on purpose, not buried in a settings page.</p>
</body>
</html>
"""

// MARK: - Entities

func tbDecodeEntities(_ s: String) -> String {
    guard s.contains("&") else { return s }
    let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "mdash": "\u{2014}", "ndash": "\u{2013}",
        "hellip": "\u{2026}", "copy": "\u{00A9}", "reg": "\u{00AE}",
        "trade": "\u{2122}", "lsquo": "\u{2018}", "rsquo": "\u{2019}",
        "ldquo": "\u{201C}", "rdquo": "\u{201D}", "laquo": "\u{00AB}",
        "raquo": "\u{00BB}", "times": "\u{00D7}", "divide": "\u{00F7}",
        "plusmn": "\u{00B1}", "deg": "\u{00B0}", "middot": "\u{00B7}",
        "bull": "\u{2022}", "dagger": "\u{2020}", "sect": "\u{00A7}",
        "para": "\u{00B6}", "iexcl": "\u{00A1}", "iquest": "\u{00BF}",
        "cent": "\u{00A2}", "pound": "\u{00A3}", "yen": "\u{00A5}",
        "euro": "\u{20AC}", "larr": "\u{2190}", "rarr": "\u{2192}",
        "hearts": "\u{2665}", "star": "\u{2605}", "check": "\u{2713}"
    ]
    var out = ""
    let chars = Array(s)
    var i = 0
    while i < chars.count {
        if chars[i] == "&" {
            var j = i + 1
            var entity = ""
            while j < chars.count && j - i <= 10 && chars[j] != ";" && chars[j] != " " && chars[j] != "&" {
                entity.append(chars[j])
                j += 1
            }
            if j < chars.count && chars[j] == ";" && !entity.isEmpty {
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    if let v = Int(entity.dropFirst(2), radix: 16), v >= 0,
                       let scalar = UnicodeScalar(UInt32(v)) {
                        out.append(Character(scalar))
                        i = j + 1
                        continue
                    }
                } else if entity.hasPrefix("#") {
                    if let v = Int(entity.dropFirst()), v >= 0,
                       let scalar = UnicodeScalar(UInt32(v)) {
                        out.append(Character(scalar))
                        i = j + 1
                        continue
                    }
                } else if let rep = named[entity] {
                    out += rep
                    i = j + 1
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        } else {
            out.append(chars[i])
            i += 1
        }
    }
    return out
}

// MARK: - Fetch

func tbFetch(urlString: String) async throws -> (finalURL: String, html: String) {
    if urlString == "turtle://home" {
        return (urlString, TB_HOME_HTML)
    }
    guard let url = URL(string: urlString) else {
        throw NSError(domain: "TurtleBrowser", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "That address could not be understood."])
    }
    var request = URLRequest(url: url)
    request.setValue("TurtleBrowser/0.6 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    let final = response.url?.absoluteString ?? urlString
    let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    return (final, html)
}

// Fetch a plain text resource (used for external stylesheets).
// Failures return nil: a page must still render without its CSS.
func tbFetchText(urlString: String) async -> String? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.setValue("TurtleBrowser/0.6 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("text/css,*/*", forHTTPHeaderField: "Accept")
    guard let (data, _) = try? await URLSession.shared.data(for: request) else {
        return nil
    }
    return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
}

// MARK: - Parse

final class TBNode {
    var tag: String
    var attrs: [String: String] = [:]
    var children: [TBNode] = []
    var text: String = ""
    weak var parent: TBNode?   // CSS step two matches ancestors.
    init(tag: String, text: String = "") {
        self.tag = tag
        self.text = text
    }
}

let TBVoidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr",
                               "img", "input", "link", "meta", "param",
                               "source", "track", "wbr"]
let TBSkipTags: Set<String> = ["script", "noscript", "template",
                               "svg", "iframe"]

func tbIsSpace(_ c: Character) -> Bool {
    c == " " || c == "\n" || c == "\t" || c == "\r"
}

func tbParse(html: String) -> TBNode {
    let chars = Array(html)
    let n = chars.count
    var i = 0
    let root = TBNode(tag: "document")
    var stack: [TBNode] = [root]

    // Index of the "<" of the next "</name" at or after `start`, or -1.
    func findCloseTag(_ name: String, from start: Int) -> Int {
        let needle = Array("</" + name)
        var m = start
        while m + needle.count <= n {
            var ok = true
            for t in 0..<needle.count {
                if String(chars[m + t]).lowercased() != String(needle[t]) {
                    ok = false
                    break
                }
            }
            if ok { return m }
            m += 1
        }
        return -1
    }

    // Index just past the ">" that ends the tag starting at `tagStart`.
    func afterTag(_ tagStart: Int) -> Int {
        var e = tagStart
        while e < n && chars[e] != ">" { e += 1 }
        return min(e + 1, n)
    }

    while i < n {
        if chars[i] == "<" {
            // Comment: skip to -->
            if i + 3 < n && chars[i + 1] == "!" && chars[i + 2] == "-" && chars[i + 3] == "-" {
                var j = i + 4
                while j + 2 < n && !(chars[j] == "-" && chars[j + 1] == "-" && chars[j + 2] == ">") {
                    j += 1
                }
                i = min(j + 3, n)
                continue
            }
            // Find the closing > (respecting quotes)
            var j = i + 1
            var quote: Character? = nil
            while j < n {
                let c = chars[j]
                if let q = quote {
                    if c == q { quote = nil }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if c == ">" {
                    break
                }
                j += 1
            }
            if j >= n { break }
            let inner = String(chars[(i + 1)..<j])
            i = j + 1
            let trimmed = inner.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("!") || trimmed.hasPrefix("?") { continue }

            if trimmed.hasPrefix("/") {
                // End tag: pop back to the matching open tag.
                let rest = trimmed.dropFirst()
                let name = rest.split(whereSeparator: { tbIsSpace($0) }).first.map(String.init) ?? ""
                let lname = name.lowercased()
                if stack.count > 1 {
                    var idx = stack.count - 1
                    while idx >= 1 {
                        if stack[idx].tag == lname {
                            stack.removeSubrange(idx...)
                            break
                        }
                        idx -= 1
                    }
                }
                continue
            }

            // Start tag
            var selfClosing = false
            var body = trimmed
            if body.hasSuffix("/") {
                selfClosing = true
                body = String(body.dropLast())
            }
            let bchars = Array(body)
            var k = 0
            var name = ""
            while k < bchars.count && !tbIsSpace(bchars[k]) {
                name.append(bchars[k])
                k += 1
            }
            let lname = name.lowercased()
            if lname.isEmpty { continue }

            if lname == "style" && !selfClosing {
                // Raw-text element: everything up to </style is CSS,
                // kept undecoded as a single text child.
                let closeStart = findCloseTag("style", from: i)
                let rawEnd = closeStart >= 0 ? closeStart : n
                let node = TBNode(tag: "style")
                node.parent = stack[stack.count - 1]
                if rawEnd > i {
                    let textNode = TBNode(tag: "#text", text: String(chars[i..<rawEnd]))
                    textNode.parent = node
                    node.children.append(textNode)
                }
                stack[stack.count - 1].children.append(node)
                i = closeStart >= 0 ? afterTag(closeStart) : n
                continue
            }

            if TBSkipTags.contains(lname) {
                if !selfClosing {
                    let closeStart = findCloseTag(lname, from: i)
                    i = closeStart >= 0 ? afterTag(closeStart) : n
                }
                continue
            }

            // Attributes
            var attrs: [String: String] = [:]
            while k < bchars.count {
                while k < bchars.count && tbIsSpace(bchars[k]) { k += 1 }
                if k >= bchars.count { break }
                var aname = ""
                while k < bchars.count && bchars[k] != "=" && !tbIsSpace(bchars[k]) {
                    aname.append(bchars[k])
                    k += 1
                }
                while k < bchars.count && tbIsSpace(bchars[k]) { k += 1 }
                var avalue = ""
                if k < bchars.count && bchars[k] == "=" {
                    k += 1
                    while k < bchars.count && tbIsSpace(bchars[k]) { k += 1 }
                    if k < bchars.count && (bchars[k] == "\"" || bchars[k] == "'") {
                        let q = bchars[k]
                        k += 1
                        while k < bchars.count && bchars[k] != q {
                            avalue.append(bchars[k])
                            k += 1
                        }
                        if k < bchars.count { k += 1 }
                    } else {
                        while k < bchars.count && !tbIsSpace(bchars[k]) {
                            avalue.append(bchars[k])
                            k += 1
                        }
                    }
                }
                if !aname.isEmpty {
                    attrs[aname.lowercased()] = tbDecodeEntities(avalue)
                }
            }

            let node = TBNode(tag: lname)
            node.attrs = attrs
            node.parent = stack[stack.count - 1]
            stack[stack.count - 1].children.append(node)
            if !selfClosing && !TBVoidTags.contains(lname) {
                stack.append(node)
            }
        } else {
            var j = i
            while j < n && chars[j] != "<" { j += 1 }
            let raw = String(chars[i..<j])
            let decoded = tbDecodeEntities(raw)
            if !decoded.isEmpty {
                let textNode = TBNode(tag: "#text", text: decoded)
                textNode.parent = stack[stack.count - 1]
                stack[stack.count - 1].children.append(textNode)
            }
            i = j
        }
    }
    return root
}

func tbExtractTitle(html: String) -> String {
    guard let open = html.range(of: "<title", options: .caseInsensitive),
          let gt = html.range(of: ">", range: open.upperBound..<html.endIndex),
          let close = html.range(of: "</title>", options: .caseInsensitive,
                                  range: gt.upperBound..<html.endIndex)
    else { return "" }
    let raw = String(html[gt.upperBound..<close.lowerBound])
    return tbDecodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - CSS

// One compound selector: an optional element name plus any number
// of class and id conditions, e.g. `a.card`, `.banner.intro`,
// `#main`, or `*` (no conditions at all — matches any element).
struct TBCompound {
    var tag: String? = nil
    var classes: [String] = []
    var id: String? = nil
    var isRoot = false   // :root — matches the <html> element
    var specificity: Int {
        (id != nil ? 100 : 0) + classes.count * 10 + (tag != nil ? 1 : 0)
            + (isRoot ? 10 : 0)   // a pseudo-class counts as a class
    }
}

enum TBCombinator {
    case descendant   // .banner h1 — any ancestor
    case child        // ul > li  — the direct parent
}

// A full selector: compounds left to right, joined by combinators.
struct TBSelector {
    var compounds: [TBCompound]
    var combinators: [TBCombinator]   // combinators[i] joins compounds[i] and [i+1]
    var specificity: Int { compounds.reduce(0) { $0 + $1.specificity } }
}

struct TBCSSRule {
    var selector: TBSelector
    var order: Int
    var declarations: [String: String]
}

func tbIsNameChar(_ c: Character) -> Bool {
    c.isLetter || c.isNumber || c == "-" || c == "_"
}

// Parse one compound selector token, e.g. "div", ".card", "a.card",
// "#main", "div#main.card", "*". Element names are case-insensitive
// (lowercased here); class and id names keep their case, as CSS
// requires. Returns nil for anything outside this grammar.
func tbParseCompound(_ token: String) -> TBCompound? {
    if token.isEmpty { return nil }
    var compound = TBCompound()
    let chars = Array(token)
    var i = 0
    if token.hasPrefix(":root") {
        compound.isRoot = true
        i = 5
    } else if chars[0] == "*" {
        i = 1   // universal: no element condition
    } else if tbIsNameChar(chars[0]) {
        var name = ""
        while i < chars.count && tbIsNameChar(chars[i]) {
            name.append(chars[i])
            i += 1
        }
        compound.tag = name.lowercased()
    }
    while i < chars.count {
        let marker = chars[i]
        guard marker == "." || marker == "#" else { return nil }
        i += 1
        var name = ""
        while i < chars.count && tbIsNameChar(chars[i]) {
            name.append(chars[i])
            i += 1
        }
        if name.isEmpty { return nil }
        if marker == "." {
            compound.classes.append(name)
        } else {
            if compound.id != nil { return nil }   // two ids in one compound
            compound.id = name
        }
    }
    return compound
}

// Parse a full selector: compounds joined by descendant (space)
// and child (>) combinators. Pseudo-classes and elements other
// than :root (:hover, ::before), attribute selectors ([href]),
// and the sibling combinators (+, ~) are outside the grammar: nil.
func tbParseSelector(_ raw: String) -> TBSelector? {
    let withoutRoot = raw.replacingOccurrences(of: ":root", with: "")
    if raw.isEmpty || withoutRoot.contains(":") || raw.contains("[")
        || raw.contains("]") || raw.contains("+") || raw.contains("~") {
        return nil
    }
    let spaced = raw.replacingOccurrences(of: ">", with: " > ")
    let tokens = spaced.split(whereSeparator: { tbIsSpace($0) }).map(String.init)
    if tokens.isEmpty { return nil }
    var compounds: [TBCompound] = []
    var combinators: [TBCombinator] = []
    var pendingChild = false
    var expectCompound = true
    for token in tokens {
        if token == ">" {
            if expectCompound { return nil }   // '>' with nothing on its left
            pendingChild = true
            expectCompound = true
            continue
        }
        guard let compound = tbParseCompound(token) else { return nil }
        if !compounds.isEmpty {
            combinators.append(pendingChild ? .child : .descendant)
        }
        compounds.append(compound)
        pendingChild = false
        expectCompound = false
    }
    if expectCompound { return nil }   // trailing '>'
    return TBSelector(compounds: compounds, combinators: combinators)
}

func tbCompoundMatches(_ compound: TBCompound, node: TBNode) -> Bool {
    if node.tag == "#text" || node.tag == "document" { return false }
    if compound.isRoot && node.tag != "html" { return false }
    if let tag = compound.tag, tag != node.tag { return false }
    if let id = compound.id, node.attrs["id"] != id { return false }
    if !compound.classes.isEmpty {
        let have = (node.attrs["class"] ?? "")
            .split(whereSeparator: { tbIsSpace($0) }).map(String.init)
        for wanted in compound.classes where !have.contains(wanted) {
            return false
        }
    }
    return true
}

// Selector matching walks right to left: the element itself must
// match the last compound; combinators then climb the ancestors.
func tbSelectorMatches(_ selector: TBSelector, node: TBNode) -> Bool {
    func matchFrom(_ index: Int, _ current: TBNode) -> Bool {
        guard tbCompoundMatches(selector.compounds[index], node: current) else {
            return false
        }
        if index == 0 { return true }
        switch selector.combinators[index - 1] {
        case .child:
            guard let parent = current.parent else { return false }
            return matchFrom(index - 1, parent)
        case .descendant:
            var ancestor = current.parent
            while let candidate = ancestor {
                if matchFrom(index - 1, candidate) { return true }
                ancestor = candidate.parent
            }
            return false
        }
    }
    return matchFrom(selector.compounds.count - 1, node)
}

func tbParseDeclarations(_ body: String) -> [String: String] {
    var out: [String: String] = [:]
    for part in body.split(separator: ";") {
        guard let colon = part.firstIndex(of: ":") else { continue }
        let prop = String(part[part.startIndex..<colon])
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var value = String(part[part.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix("!important") {
            value = String(value.dropLast(10)).trimmingCharacters(in: .whitespaces)
        }
        if !prop.isEmpty && !value.isEmpty {
            out[prop] = value
        }
    }
    return out
}

func tbParseCSS(_ css: String, orderStart: Int) -> [TBCSSRule] {
    // Strip /* ... */ comments.
    var cleaned = css
    while let open = cleaned.range(of: "/*"),
          let close = cleaned.range(of: "*/", range: open.upperBound..<cleaned.endIndex) {
        cleaned.removeSubrange(open.lowerBound..<close.upperBound)
    }
    var rules: [TBCSSRule] = []
    var order = orderStart
    for chunk in cleaned.split(separator: "}") {
        let halves = chunk.split(separator: "{", maxSplits: 1)
        if halves.count != 2 { continue }
        var selectorText = String(halves[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        // A statement at-rule (@import, @charset) can share this
        // chunk with the rule that follows it; the real selector
        // is what comes after the last ';'. (Tyler's hub puts its
        // :root variables right after a Google Fonts @import.)
        if let semi = selectorText.lastIndex(of: ";") {
            selectorText = String(selectorText[selectorText.index(after: semi)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if selectorText.hasPrefix("@") { continue }
        let declarations = tbParseDeclarations(String(halves[1]))
        if declarations.isEmpty { continue }
        for rawSelector in selectorText.split(separator: ",") {
            let s = String(rawSelector).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let selector = tbParseSelector(s) else { continue }
            rules.append(TBCSSRule(selector: selector, order: order,
                                   declarations: declarations))
            order += 1
        }
    }
    return rules
}

// Rules inside `@media (prefers-color-scheme: dark)` blocks,
// lifted out so the renderer can add them to the cascade when
// the Mac is in dark mode — the one media query this engine
// evaluates. Other @media blocks (widths, motion) stay unread.
func tbParseDarkSchemeCSS(_ css: String, orderStart: Int) -> [TBCSSRule] {
    var cleaned = css
    while let open = cleaned.range(of: "/*"),
          let close = cleaned.range(of: "*/", range: open.upperBound..<cleaned.endIndex) {
        cleaned.removeSubrange(open.lowerBound..<close.upperBound)
    }
    var rules: [TBCSSRule] = []
    var order = orderStart
    var searchFrom = cleaned.startIndex
    while let mediaRange = cleaned.range(of: "@media", options: .caseInsensitive,
                                         range: searchFrom..<cleaned.endIndex),
          let braceOpen = cleaned.range(of: "{", range: mediaRange.upperBound..<cleaned.endIndex) {
        let prelude = cleaned[mediaRange.upperBound..<braceOpen.lowerBound].lowercased()
        var depth = 1
        var j = braceOpen.upperBound
        while j < cleaned.endIndex && depth > 0 {
            if cleaned[j] == "{" { depth += 1 }
            else if cleaned[j] == "}" { depth -= 1 }
            j = cleaned.index(after: j)
        }
        if prelude.contains("prefers-color-scheme") && prelude.contains("dark") {
            let inner = String(cleaned[braceOpen.upperBound..<cleaned.index(before: j)])
            let parsed = tbParseCSS(inner, orderStart: order)
            rules.append(contentsOf: parsed)
            order += parsed.count
        }
        searchFrom = j
    }
    return rules
}

enum TBStyleSource {
    case inline(String)     // a <style> block's text
    case external(String)   // absolute URL of a linked stylesheet
}

// Stylesheet sources in document order — <style> blocks and
// <link rel="stylesheet"> references interleaved as the page
// declares them, which is the order the cascade honors.
func tbCollectStyleSources(_ node: TBNode, base: String,
                           into sources: inout [TBStyleSource]) {
    if node.tag == "style" {
        for child in node.children where child.tag == "#text" {
            sources.append(.inline(child.text))
        }
        return
    }
    if node.tag == "link" {
        let relTokens = (node.attrs["rel"] ?? "").lowercased()
            .split(whereSeparator: { tbIsSpace($0) }).map(String.init)
        let href = node.attrs["href"] ?? ""
        if relTokens.contains("stylesheet") && !href.isEmpty {
            let absolute = URL(string: href, relativeTo: URL(string: base))?.absoluteString ?? href
            sources.append(.external(absolute))
        }
        return
    }
    for child in node.children {
        tbCollectStyleSources(child, base: base, into: &sources)
    }
}

// The declarations that apply to one element: matching rules in
// cascade order (specificity first, then source order), with the
// element's inline style on top.
func tbResolveStyle(node: TBNode, rules: [TBCSSRule]) -> [String: String] {
    if node.tag == "#text" { return [:] }
    var matched: [TBCSSRule] = []
    for rule in rules where tbSelectorMatches(rule.selector, node: node) {
        matched.append(rule)
    }
    matched.sort {
        ($0.selector.specificity, $0.order) < ($1.selector.specificity, $1.order)
    }
    var out: [String: String] = [:]
    for rule in matched {
        for (k, v) in rule.declarations { out[k] = v }
    }
    if let inlineStyle = node.attrs["style"] {
        for (k, v) in tbParseDeclarations(inlineStyle) { out[k] = v }
    }
    return out
}

// MARK: - CSS variables

// The custom-property environment of one element: every --name
// defined on the element or inherited from its ancestors, with
// nearer and stronger definitions winning, as in real CSS.
func tbVariableEnvironment(node: TBNode, rules: [TBCSSRule]) -> [String: String] {
    var chain: [TBNode] = []
    var current: TBNode? = node
    while let element = current, element.tag != "document" {
        chain.append(element)
        current = element.parent
    }
    var env: [String: String] = [:]
    for element in chain.reversed() {
        var matched: [TBCSSRule] = []
        for rule in rules where tbSelectorMatches(rule.selector, node: element) {
            matched.append(rule)
        }
        matched.sort {
            ($0.selector.specificity, $0.order) < ($1.selector.specificity, $1.order)
        }
        for rule in matched {
            for (name, value) in rule.declarations where name.hasPrefix("--") {
                env[name] = value
            }
        }
        if let inlineStyle = element.attrs["style"] {
            for (name, value) in tbParseDeclarations(inlineStyle) where name.hasPrefix("--") {
                env[name] = value
            }
        }
    }
    return env
}

// Substitute var(--name) and var(--name, fallback) references in
// one declaration value. A variable's own value may itself use
// var(), so substitution recurses (depth-capped against cycles).
// An unresolvable reference with no fallback makes the whole
// declaration invalid, as the CSS spec requires: nil.
func tbSubstituteVars(_ value: String, env: [String: String], depth: Int = 0) -> String? {
    guard value.contains("var(") else { return value }
    if depth > 8 { return nil }
    var result = ""
    var i = value.startIndex
    while i < value.endIndex {
        if value[i...].hasPrefix("var(") {
            var j = value.index(i, offsetBy: 4)
            var nest = 1
            var close: String.Index? = nil
            while j < value.endIndex {
                if value[j] == "(" { nest += 1 }
                else if value[j] == ")" {
                    nest -= 1
                    if nest == 0 { close = j; break }
                }
                j = value.index(after: j)
            }
            guard let closeIdx = close else { return nil }
            let inner = String(value[value.index(i, offsetBy: 4)..<closeIdx])
            var name = inner
            var fallback: String? = nil
            var nest2 = 0
            for k in inner.indices {
                if inner[k] == "(" { nest2 += 1 }
                else if inner[k] == ")" { nest2 -= 1 }
                else if inner[k] == "," && nest2 == 0 {
                    name = String(inner[inner.startIndex..<k])
                    fallback = String(inner[inner.index(after: k)...])
                    break
                }
            }
            let key = name.trimmingCharacters(in: .whitespaces)
            var replacement: String? = nil
            if key.hasPrefix("--"), let defined = env[key] {
                replacement = tbSubstituteVars(defined, env: env, depth: depth + 1)
            }
            if replacement == nil, let fb = fallback {
                replacement = tbSubstituteVars(fb.trimmingCharacters(in: .whitespaces),
                                               env: env, depth: depth + 1)
            }
            guard let rep = replacement else { return nil }
            result += rep
            i = value.index(after: closeIdx)
        } else {
            result.append(value[i])
            i = value.index(after: i)
        }
    }
    return result
}

func tbIsHidden(_ decls: [String: String]) -> Bool {
    decls["display"]?.lowercased() == "none"
        || decls["visibility"]?.lowercased() == "hidden"
}

// MARK: - Colors

let TBNamedColors: [String: String] = [
    "black": "#000000", "white": "#FFFFFF", "red": "#FF0000",
    "green": "#008000", "blue": "#0000FF", "yellow": "#FFFF00",
    "orange": "#FFA500", "purple": "#800080", "pink": "#FFC0CB",
    "brown": "#A52A2A", "gray": "#808080", "grey": "#808080",
    "silver": "#C0C0C0", "maroon": "#800000", "olive": "#808000",
    "lime": "#00FF00", "aqua": "#00FFFF", "cyan": "#00FFFF",
    "teal": "#008080", "navy": "#000080", "fuchsia": "#FF00FF",
    "magenta": "#FF00FF", "gold": "#FFD700", "beige": "#F5F5DC",
    "ivory": "#FFFFF0", "coral": "#FF7F50", "salmon": "#FA8072",
    "khaki": "#F0E68C", "lavender": "#E6E6FA", "violet": "#EE82EE",
    "indigo": "#4B0082", "turquoise": "#40E0D0", "tan": "#D2B48C",
    "skyblue": "#87CEEB", "lightblue": "#ADD8E6", "lightgreen": "#90EE90",
    "lightgray": "#D3D3D3", "lightgrey": "#D3D3D3", "darkblue": "#00008B",
    "darkgreen": "#006400", "darkred": "#8B0000", "darkgray": "#A9A9A9",
    "darkgrey": "#A9A9A9", "crimson": "#DC143C", "forestgreen": "#228B22",
    "royalblue": "#4169E1", "steelblue": "#4682B4", "seagreen": "#2E8B57",
    "slategray": "#708090", "tomato": "#FF6347", "orchid": "#DA70D6",
    "plum": "#DDA0DD", "chocolate": "#D2691E", "peru": "#CD853F",
    "sienna": "#A0522D", "firebrick": "#B22222", "goldenrod": "#DAA520",
    "hotpink": "#FF69B4", "lightyellow": "#FFFFE0", "whitesmoke": "#F5F5F5",
    "snow": "#FFFAFA", "linen": "#FAF0E6", "antiquewhite": "#FAEBD7",
    "rebeccapurple": "#663399", "midnightblue": "#191970",
    "dimgray": "#696969", "dimgrey": "#696969"
]

func tbHexColor(_ hex: String) -> NSColor? {
    var h = hex
    if h.hasPrefix("#") { h.removeFirst() }
    if h.count == 3 {
        h = h.map { "\($0)\($0)" }.joined()
    }
    guard h.count == 6, let v = Int(h, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

func tbParseColor(_ raw: String?) -> NSColor? {
    guard let raw = raw else { return nil }
    let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
    if v.isEmpty { return nil }
    if let hex = TBNamedColors[v] { return tbHexColor(hex) }
    if v.hasPrefix("#") { return tbHexColor(v) }
    if v.hasPrefix("rgb") {
        let inner = v.drop(while: { $0 != "(" }).dropFirst().dropLast()
        let parts = inner.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 3,
           let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) {
            return NSColor(srgbRed: CGFloat(r / 255), green: CGFloat(g / 255),
                           blue: CGFloat(b / 255), alpha: 1)
        }
    }
    return nil
}

// The background color an element's declarations call for:
// background-color itself, or the color layer of the
// `background:` shorthand. In the shorthand, only the final
// layer may carry a color (it paints beneath any images or
// gradients in the earlier layers), so the color is looked
// for there — or in a lone single-layer value.
func tbBackgroundColor(_ decls: [String: String]) -> NSColor? {
    if let color = tbParseColor(decls["background-color"]) {
        return color
    }
    guard let shorthand = decls["background"] else { return nil }
    // Split into layers at commas that sit outside parentheses.
    var layers: [String] = []
    var depth = 0
    var current = ""
    for c in shorthand {
        if c == "(" { depth += 1 }
        else if c == ")" { depth -= 1 }
        if c == "," && depth == 0 {
            layers.append(current)
            current = ""
        } else {
            current.append(c)
        }
    }
    layers.append(current)
    guard let last = layers.last else { return nil }
    let trimmed = last.trimmingCharacters(in: .whitespaces)
    if let color = tbParseColor(trimmed) { return color }
    for token in trimmed.split(whereSeparator: { tbIsSpace($0) }) {
        if let color = tbParseColor(String(token)) { return color }
    }
    return nil
}

// MARK: - Font helpers

func tbFontSizeValue(_ raw: String, relativeTo base: CGFloat) -> CGFloat? {
    let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
    switch v {
    case "xx-small": return 9
    case "x-small": return 10
    case "small": return 12
    case "medium": return 14
    case "large": return 18
    case "x-large": return 24
    case "xx-large": return 32
    case "larger": return base * 1.2
    case "smaller": return base / 1.2
    default: break
    }
    if v.hasSuffix("rem"), let d = Double(String(v.dropLast(3))) {
        return CGFloat(14 * d)
    }
    if v.hasSuffix("px"), let d = Double(String(v.dropLast(2))) {
        return CGFloat(d)
    }
    if v.hasSuffix("pt"), let d = Double(String(v.dropLast(2))) {
        return CGFloat(d)
    }
    if v.hasSuffix("em"), let d = Double(String(v.dropLast(2))) {
        return base * CGFloat(d)
    }
    if v.hasSuffix("%"), let d = Double(String(v.dropLast(1))) {
        return base * CGFloat(d) / 100
    }
    if let d = Double(v) { return CGFloat(d) }
    return nil
}

// Apply one element's own font declarations to a font. Size is
// relative to the incoming font, so ancestors' sizes carry down
// through the font object itself.
func tbFontApplying(_ decls: [String: String], to font: NSFont) -> NSFont {
    var f = font
    let fm = NSFontManager.shared
    if let w = decls["font-weight"]?.lowercased() {
        let numeric = Int(w)
        if w == "bold" || w == "bolder" || (numeric ?? 0) >= 600 {
            f = fm.convert(f, toHaveTrait: .boldFontMask)
        } else if w == "normal" || w == "lighter" || numeric != nil {
            f = fm.convert(f, toNotHaveTrait: .boldFontMask)
        }
    }
    if let st = decls["font-style"]?.lowercased() {
        if st == "italic" || st == "oblique" {
            f = fm.convert(f, toHaveTrait: .italicFontMask)
        } else if st == "normal" {
            f = fm.convert(f, toNotHaveTrait: .italicFontMask)
        }
    }
    if let fs = decls["font-size"], let size = tbFontSizeValue(fs, relativeTo: f.pointSize) {
        f = fm.convert(f, toSize: size)
    }
    return f
}

func tbAlignment(_ decls: [String: String], fallback: NSTextAlignment) -> NSTextAlignment {
    switch decls["text-align"]?.lowercased() {
    case "center": return .center
    case "right", "end": return .right
    case "justify": return .justified
    case "left", "start": return .left
    default: return fallback
    }
}

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

// MARK: - Render

let TBBlockTags: Set<String> = ["p", "div", "section", "article", "main",
                                "header", "footer", "li", "blockquote",
                                "pre", "tr", "figure", "figcaption",
                                "h1", "h2", "h3", "h4", "h5", "h6"]
let TBHeadingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
let TBRenderSkipTags: Set<String> = ["head", "title", "style", "meta",
                                     "link", "base", "script"]

func tbStyle(for tag: String) -> String {
    if TBHeadingTags.contains(tag) { return tag }
    if tag == "blockquote" { return "quote" }
    if tag == "li" { return "li" }
    return "p"
}

func tbFont(for style: String) -> NSFont {
    switch style {
    case "h1": return NSFont.boldSystemFont(ofSize: 26)
    case "h2": return NSFont.boldSystemFont(ofSize: 21)
    case "h3": return NSFont.boldSystemFont(ofSize: 17)
    case "h4", "h5", "h6": return NSFont.boldSystemFont(ofSize: 15)
    case "quote":
        return NSFont(name: "Georgia-Italic", size: 14) ?? NSFont.systemFont(ofSize: 14)
    default:
        return NSFont.systemFont(ofSize: 14)
    }
}

final class TBRenderer {
    let base: String
    var links: [String] = []
    var rules: [TBCSSRule] = []
    var pageBackground: NSColor? = nil
    let out = NSMutableAttributedString()

    init(base: String) { self.base = base }

    // The Mac's own appearance decides prefers-color-scheme,
    // exactly as it does for a real browser on this machine.
    var darkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // An element's declarations with var() references resolved
    // against its inherited custom properties.
    func resolvedStyle(node: TBNode) -> [String: String] {
        let raw = tbResolveStyle(node: node, rules: rules)
        if raw.isEmpty { return raw }
        let env = tbVariableEnvironment(node: node, rules: rules)
        var out: [String: String] = [:]
        for (name, value) in raw {
            if name.hasPrefix("--") { continue }
            if let resolved = tbSubstituteVars(value, env: env) {
                out[name] = resolved
            }
        }
        return out
    }

    func render(root: TBNode) async -> NSAttributedString {
        var sources: [TBStyleSource] = []
        tbCollectStyleSources(root, base: base, into: &sources)
        var order = 0
        for source in sources {
            let cssText: String?
            switch source {
            case .inline(let text): cssText = text
            case .external(let url): cssText = await tbFetchText(urlString: url)
            }
            guard let text = cssText else { continue }
            let parsed = tbParseCSS(text, orderStart: order)
            rules.append(contentsOf: parsed)
            order += parsed.count
            if darkAppearance {
                let dark = tbParseDarkSchemeCSS(text, orderStart: order)
                rules.append(contentsOf: dark)
                order += dark.count
            }
        }
        walkBlock(node: root, style: "p", baseFont: tbFont(for: "p"),
                  color: nil, align: .left, inheritedBackground: nil)
        if let body = findTag(root, "body") ?? findTag(root, "html") {
            pageBackground = tbBackgroundColor(resolvedStyle(node: body))
        }
        return out
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

    private func flush(buffer: inout NSMutableAttributedString, style: String,
                       font: NSFont, align: NSTextAlignment, background: NSColor?,
                       metrics: TBBlockMetrics) {
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
            let blockRange = NSRange(location: 0, length: buffer.length)
            if align != .left || metrics.hasAny {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = align
                if metrics.before > 0 { paragraph.paragraphSpacingBefore = metrics.before }
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
            out.append(buffer)
            // The gap between blocks belongs to the same box:
            // paint it too, so a background reads as one band.
            if let background = background {
                out.append(NSAttributedString(
                    string: "\n\n", attributes: [.backgroundColor: background]))
            } else {
                out.append(NSAttributedString(string: "\n\n"))
            }
        }
        buffer = NSMutableAttributedString()
    }

    private func walkBlock(node: TBNode, style: String, baseFont: NSFont,
                           color: NSColor?, align: NSTextAlignment,
                           inheritedBackground: NSColor?) {
        let own = resolvedStyle(node: node)
        if node.tag != "document" && tbIsHidden(own) { return }
        let effFont = tbFontApplying(own, to: baseFont)
        let effColor = tbParseColor(own["color"]) ?? color
        let effAlign = tbAlignment(own, fallback: align)
        // The background showing through this whole subtree: this
        // element's own background if it declares one, else the
        // nearest ancestor's. (CSS backgrounds are not inherited
        // as values — they show through, which amounts to this.)
        let effBackground = tbBackgroundColor(own) ?? inheritedBackground
        let metrics = tbBlockMetrics(own, fontSize: effFont.pointSize)

        var buffer = NSMutableAttributedString()
        for child in node.children {
            if TBRenderSkipTags.contains(child.tag) { continue }
            // Layout step one: the child's computed display decides
            // whether it stands as its own block or flows inline —
            // a link styled display:grid is a card, not a word.
            let childOwn = child.tag == "#text" ? [:] : resolvedStyle(node: child)
            if child.tag != "#text" && tbIsHidden(childOwn) { continue }
            let display = (childOwn["display"] ?? "").lowercased()
            let forceBlock = ["block", "flex", "grid", "list-item",
                              "table", "flow-root"].contains(display)
            let forceInline = ["inline", "inline-block", "inline-flex",
                               "inline-grid", "contents"].contains(display)
            if forceBlock || (TBBlockTags.contains(child.tag) && !forceInline) {
                flush(buffer: &buffer, style: style, font: effFont,
                      align: effAlign, background: effBackground, metrics: metrics)
                let childStyle = tbStyle(for: child.tag)
                let childBase = TBHeadingTags.contains(child.tag)
                    ? tbFont(for: child.tag) : effFont
                walkBlock(node: child, style: childStyle, baseFont: childBase,
                          color: effColor, align: effAlign,
                          inheritedBackground: effBackground)
            } else if child.tag == "html" || child.tag == "body" || child.tag == "document" || hasBlock(child) {
                flush(buffer: &buffer, style: style, font: effFont,
                      align: effAlign, background: effBackground, metrics: metrics)
                walkBlock(node: child, style: style, baseFont: effFont,
                          color: effColor, align: effAlign,
                          inheritedBackground: effBackground)
            } else {
                buffer.append(inline(child, font: effFont, color: effColor))
            }
        }
        flush(buffer: &buffer, style: style, font: effFont,
              align: effAlign, background: effBackground, metrics: metrics)
    }

    private func inline(_ node: TBNode, font: NSFont, color: NSColor?) -> NSAttributedString {
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
            return NSAttributedString(
                string: " [Image: \(alt)] ",
                attributes: [.font: f, .foregroundColor: NSColor.secondaryLabelColor])
        }

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
                linked.append(NSAttributedString(string: " [\(links.count)]", attributes: linkAttrs))
                result.append(linked)
            } else {
                result.append(inner)
            }
        } else {
            for child in node.children {
                result.append(inline(child, font: f, color: effColor))
            }
        }

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
        return result
    }
}

func tbRenderPage(html: String, base: String) async
    -> (title: String, body: NSAttributedString, pageBackground: NSColor?) {
    let title = tbExtractTitle(html: html)
    let tree = tbParse(html: html)
    let renderer = TBRenderer(base: base)
    let body = await renderer.render(root: tree)
    return (title.isEmpty ? base : title, body, renderer.pageBackground)
}
