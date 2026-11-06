//
//  ChirpyCSS.swift
//  Chirpy Browser — engine 0.39.3 (Swift)
//
//  The style system: Chirpy's CSS. This file
//  reads style text and answers, for any
//  element in the document tree, the
//  declarations that element wears. It holds
//  the selector grammar and its matching, the
//  stylesheet parser (style blocks, media
//  blocks, keyframes), the cascade - resting,
//  hover, focus, and active - the CSS variable
//  environment and its substitution, and the
//  value readers the rest of the engine
//  shares: colors, layer splitting, font
//  shorthand and sizes, text alignment, and
//  the small stamps that write link and
//  sticky facts onto painted text. What an
//  element's declarations then become - boxes,
//  arrangement, paint - is layout's and the
//  renderer's work, in ChirpyEngine.swift for
//  now; this file only decides what the page
//  asked for.
//
//  This file was ChirpyEngine.swift's CSS
//  country - everything from the CSS mark
//  down through the font helpers, just before
//  the Layout mark - until 0.39.3, when it
//  moved here whole: the third step of
//  splitting the codebase into files of their
//  own, at Tyler's direction, so each part can
//  be fixed and built quicker. Nothing in the
//  move changed the style system itself; the
//  section intros that stood over its parts
//  in the engine file stand below, as they
//  were written. ChirpyEngine.swift keeps a
//  short marker where the sections lived,
//  pointing here.
//
//  Public domain (Unlicense), like the rest
//  of Chirpy.
//

import Foundation
import AppKit

// MARK: - CSS

// An :nth-child() / :nth-of-type() formula, An+B: an element
// matches when its 1-based index among its siblings equals
// A*n + B for some n >= 0.
struct TBNthExpr {
    var a: Int
    var b: Int
}

// The argument of :not(...) — a compound in its own right,
// boxed in a class because a struct cannot hold itself.
final class TBNotBox {
    let compound: TBCompound
    init(_ compound: TBCompound) { self.compound = compound }
}

// One compound selector: an optional element name plus any number
// of class and id conditions, e.g. `a.card`, `.banner.intro`,
// `#main`, or `*` (no conditions at all — matches any element).
// The finishing set (0.23) adds the pseudo-classes this engine
// reads: the structural ones (:first-child and family, :nth-child
// and :nth-of-type with their formulas, :empty, :not with a
// compound argument), the link states (:link, :visited) and
// :hover. The interaction set (0.26) adds :focus and :active —
// states like :hover's, matched only in their own resolutions.
struct TBCompound {
    var tag: String? = nil
    var classes: [String] = []
    var id: String? = nil
    var isRoot = false   // :root — matches the <html> element
    var isHover = false  // :hover — matches only in a hover resolution
    var isFocus = false  // :focus (0.26) — matches only in a focus resolution
    var isActive = false  // :active (0.26) — matches only in an active resolution
    var isLink = false   // :link — an anchor not yet visited
    var isVisited = false   // :visited — an anchor in the session's visited set
    var firstChild = false
    var lastChild = false
    var firstOfType = false
    var lastOfType = false
    var nthChild: TBNthExpr? = nil
    var nthOfType: TBNthExpr? = nil
    var requiresEmpty = false   // :empty
    var notBox: TBNotBox? = nil   // :not(compound)
    var specificity: Int {
        // A pseudo-class counts as a class; :not itself counts
        // for nothing, but its argument counts as it would
        // standing alone — the Selectors rules both.
        var s = (id != nil ? 100 : 0) + classes.count * 10 + (tag != nil ? 1 : 0)
        if isRoot { s += 10 }
        if isHover { s += 10 }
        if isFocus { s += 10 }
        if isActive { s += 10 }
        if isLink { s += 10 }
        if isVisited { s += 10 }
        if firstChild { s += 10 }
        if lastChild { s += 10 }
        if firstOfType { s += 10 }
        if lastOfType { s += 10 }
        if nthChild != nil { s += 10 }
        if nthOfType != nil { s += 10 }
        if requiresEmpty { s += 10 }
        if let notBox = notBox { s += notBox.compound.specificity }
        return s
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

// The parenthesised argument starting at chars[openIndex]
// (which must be "("): the argument's text and the index just
// past its closing ")". Parentheses nest — :not(:nth-child(2))
// wears two pairs. Nil when the parentheses never close.
func tbParenArgument(_ chars: [Character], openIndex: Int)
    -> (arg: String, next: Int)? {
    guard openIndex < chars.count, chars[openIndex] == "(" else { return nil }
    var depth = 0
    var arg = ""
    var j = openIndex
    while j < chars.count {
        let c = chars[j]
        if c == "(" {
            depth += 1
            if depth > 1 { arg.append(c) }
        } else if c == ")" {
            depth -= 1
            if depth == 0 { return (arg, j + 1) }
            arg.append(c)
        } else {
            arg.append(c)
        }
        j += 1
    }
    return nil
}

// An :nth-child() formula: odd, even, a bare index (3), or
// An+B in any of its spellings (n, -n, 2n, 2n+1, -n+3, 3n-2).
func tbParseNth(_ raw: String) -> TBNthExpr? {
    let s = raw.lowercased().filter { !$0.isWhitespace }
    if s == "odd" { return TBNthExpr(a: 2, b: 1) }
    if s == "even" { return TBNthExpr(a: 2, b: 0) }
    if let bare = Int(s) { return TBNthExpr(a: 0, b: bare) }
    guard let nIndex = s.firstIndex(of: "n") else { return nil }
    let aText = String(s[s.startIndex..<nIndex])
    let bText = String(s[s.index(after: nIndex)...])
    let a: Int
    if aText.isEmpty || aText == "+" { a = 1 }
    else if aText == "-" { a = -1 }
    else if let v = Int(aText) { a = v }
    else { return nil }
    var b = 0
    if !bText.isEmpty {
        guard let v = Int(bText) else { return nil }
        b = v
    }
    return TBNthExpr(a: a, b: b)
}

// Parse one compound selector token, e.g. "div", ".card", "a.card",
// "#main", "div#main.card", "*", "li:nth-child(2n+1)", "a:hover",
// "p:not(.skip)". Element names are case-insensitive (lowercased
// here); class and id names keep their case, as CSS requires.
// Pseudo-classes may follow the element name — or stand in for
// one, as in ":root" or ":first-child". Returns nil for anything
// outside this grammar, pseudo-elements (::before) included.
func tbParseCompound(_ token: String) -> TBCompound? {
    if token.isEmpty { return nil }
    var compound = TBCompound()
    let chars = Array(token)
    var i = 0
    var sawComponent = false
    if chars[0] == "*" {
        i = 1   // universal: no element condition
        sawComponent = true
    } else if tbIsNameChar(chars[0]) {
        var name = ""
        while i < chars.count && tbIsNameChar(chars[i]) {
            name.append(chars[i])
            i += 1
        }
        compound.tag = name.lowercased()
        sawComponent = true
    }
    while i < chars.count {
        let marker = chars[i]
        if marker == "." || marker == "#" {
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
        } else if marker == ":" {
            i += 1
            if i < chars.count && chars[i] == ":" { return nil }   // ::before & friends
            var name = ""
            while i < chars.count && tbIsNameChar(chars[i]) {
                name.append(chars[i])
                i += 1
            }
            switch name.lowercased() {
            case "root": compound.isRoot = true
            case "first-child": compound.firstChild = true
            case "last-child": compound.lastChild = true
            case "first-of-type": compound.firstOfType = true
            case "last-of-type": compound.lastOfType = true
            case "empty": compound.requiresEmpty = true
            case "link": compound.isLink = true
            case "visited": compound.isVisited = true
            case "hover": compound.isHover = true
            case "focus": compound.isFocus = true
            case "active": compound.isActive = true
            case "nth-child", "nth-of-type":
                guard let (arg, next) = tbParenArgument(chars, openIndex: i),
                      let nth = tbParseNth(arg) else { return nil }
                if name.lowercased() == "nth-child" {
                    compound.nthChild = nth
                } else {
                    compound.nthOfType = nth
                }
                i = next
            case "not":
                // The argument is a compound like this one —
                // no combinators, and (per Selectors 3) no
                // :not inside it.
                guard let (arg, next) = tbParenArgument(chars, openIndex: i),
                      let inner = tbParseCompound(
                          arg.trimmingCharacters(in: .whitespacesAndNewlines)),
                      inner.notBox == nil else { return nil }
                compound.notBox = TBNotBox(inner)
                i = next
            default:
                return nil   // :lang, :checked, … — not read
            }
        } else {
            return nil
        }
        sawComponent = true
    }
    return sawComponent ? compound : nil
}

// Parse a full selector: compounds joined by descendant (space)
// and child (>) combinators. Attribute selectors ([href]) and
// the sibling combinators (+, ~) are outside the grammar, and
// pseudo-classes are admitted one by one in tbParseCompound —
// anything it refuses fails the selector here too. The scans
// are parenthesis-aware throughout: the "+" in
// :nth-child(2n+1) is a formula, not a combinator, and a
// functional pseudo's argument may contain spaces.
func tbParseSelector(_ raw: String) -> TBSelector? {
    if raw.isEmpty { return nil }
    var depth = 0
    for c in raw {
        if c == "(" { depth += 1 }
        else if c == ")" {
            depth -= 1
            if depth < 0 { return nil }
        } else if depth == 0
                    && (c == "[" || c == "]" || c == "+" || c == "~") {
            return nil
        }
    }
    if depth != 0 { return nil }
    // Tokenize on depth-zero whitespace and ">".
    var tokens: [String] = []
    var current = ""
    depth = 0
    for c in raw {
        if c == "(" { depth += 1 }
        else if c == ")" { depth -= 1 }
        if depth == 0 && tbIsSpace(c) {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else if depth == 0 && c == ">" {
            if !current.isEmpty { tokens.append(current); current = "" }
            tokens.append(">")
        } else {
            current.append(c)
        }
    }
    if !current.isEmpty { tokens.append(current) }
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

// The element siblings a structural pseudo-class counts: the
// parent's children with the text nodes set aside — CSS counts
// elements only, and the parser keeps the whitespace between
// them as text nodes.
func tbElementSiblings(_ node: TBNode) -> [TBNode] {
    guard let parent = node.parent else { return [node] }
    return parent.children.filter { $0.tag != "#text" }
}

// The matcher memo's stamp (0.37.3): walk a subtree
// once and record, per element node, the facts the
// matcher used to re-derive per match — the class
// list as a set, and the node's place among its
// element siblings (and among its same-tag siblings).
// One derivation per parent, shared by its children.
// tbParse stamps every tree it hands out, so these
// are warm before the first match reads them; a node
// built by hand and never stamped simply has no memo
// and the matcher derives as it always did.
func tbStampMatchFacts(_ node: TBNode) {
    if node.tag != "#text" {
        if let classAttr = node.attrs["class"] {
            node.matchClassSet = Set(
                classAttr.split(whereSeparator: { tbIsSpace($0) })
                    .map(String.init))
        } else {
            node.matchClassSet = []
        }
    }
    var elementIndex = 0
    var typeCounts: [String: Int] = [:]
    var typeIndexOf: [ObjectIdentifier: Int] = [:]
    for child in node.children where child.tag != "#text" {
        typeIndexOf[ObjectIdentifier(child)] = typeCounts[child.tag, default: 0]
        typeCounts[child.tag, default: 0] += 1
    }
    for child in node.children {
        if child.tag != "#text" {
            child.matchSiblingIndex = elementIndex
            child.matchSiblingCount = typeCounts.values.reduce(0, +)
            child.matchTypeIndex = typeIndexOf[ObjectIdentifier(child)] ?? 0
            child.matchTypeCount = typeCounts[child.tag] ?? 0
            elementIndex += 1
        }
        tbStampMatchFacts(child)
    }
}

// Does a 1-based index satisfy An+B for some n >= 0?
func tbNthMatches(_ nth: TBNthExpr, index: Int) -> Bool {
    let a = nth.a, b = nth.b
    if a == 0 { return index == b }
    let d = index - b
    if a > 0 { return d >= 0 && d % a == 0 }
    return d <= 0 && d % a == 0
}

// :empty, in the Selectors 4 sense: no element children, and
// no text but whitespace.
func tbIsEmptyElement(_ node: TBNode) -> Bool {
    for child in node.children {
        if child.tag != "#text" { return false }
        if !child.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
    }
    return true
}

func tbCompoundMatches(_ compound: TBCompound, node: TBNode,
                       hoverSatisfied: Bool = false,
                       focusSatisfied: Bool = false,
                       activeSatisfied: Bool = false) -> Bool {
    if node.tag == "#text" || node.tag == "document" { return false }
    // :hover is a state, not a shape: in an ordinary match it
    // is never true (so hover rules stay out of the resting
    // cascade), and in a hover resolution it is treated as
    // satisfied for whichever element the compound binds to —
    // the hovered element itself, or an ancestor of it in a
    // selector like `.card:hover .title`.
    if compound.isHover && !hoverSatisfied { return false }
    // :focus and :active (0.26) are states the same way,
    // each satisfied only in its own resolution.
    if compound.isFocus && !focusSatisfied { return false }
    if compound.isActive && !activeSatisfied { return false }
    if compound.isRoot && node.tag != "html" { return false }
    if let tag = compound.tag, tag != node.tag { return false }
    if let id = compound.id, node.attrs["id"] != id { return false }
    if !compound.classes.isEmpty {
        // The class test (0.37.3): the stamped set
        // when the tree carries one — the split of
        // the class attribute was the matcher's
        // single largest repeated cost — else the
        // derivation as it stood.
        if let have = node.matchClassSet {
            for wanted in compound.classes where !have.contains(wanted) {
                return false
            }
        } else {
            let have = (node.attrs["class"] ?? "")
                .split(whereSeparator: { tbIsSpace($0) }).map(String.init)
            for wanted in compound.classes where !have.contains(wanted) {
                return false
            }
        }
    }
    if let notBox = compound.notBox,
       tbCompoundMatches(notBox.compound, node: node,
                         hoverSatisfied: hoverSatisfied,
                         focusSatisfied: focusSatisfied,
                         activeSatisfied: activeSatisfied) {
        return false
    }
    if compound.isLink || compound.isVisited {
        guard node.tag == "a", node.attrs["href"] != nil else { return false }
        if compound.isLink && node.linkVisited { return false }
        if compound.isVisited && !node.linkVisited { return false }
    }
    if compound.requiresEmpty && !tbIsEmptyElement(node) { return false }
    if compound.firstChild || compound.lastChild || compound.nthChild != nil
        || compound.firstOfType || compound.lastOfType
        || compound.nthOfType != nil {
        // The structural tests (0.37.3): the
        // stamped place among the element
        // siblings when the tree carries one,
        // else the sibling scan as it stood.
        let index: Int
        let siblingCount: Int
        var typeIndex: Int = -1
        var typeCount: Int = -1
        if node.matchSiblingIndex >= 0 {
            index = node.matchSiblingIndex + 1   // CSS counts from 1
            siblingCount = node.matchSiblingCount
            typeIndex = node.matchTypeIndex + 1
            typeCount = node.matchTypeCount
        } else {
            let siblings = tbElementSiblings(node)
            guard let own = siblings.firstIndex(where: { $0 === node })
            else { return false }
            index = own + 1
            siblingCount = siblings.count
            if compound.firstOfType || compound.lastOfType
                || compound.nthOfType != nil {
                let ofType = siblings.filter { $0.tag == node.tag }
                guard let ownType = ofType.firstIndex(where: { $0 === node })
                else { return false }
                typeIndex = ownType + 1
                typeCount = ofType.count
            }
        }
        if compound.firstChild && index != 1 { return false }
        if compound.lastChild && index != siblingCount { return false }
        if let nth = compound.nthChild, !tbNthMatches(nth, index: index) {
            return false
        }
        if compound.firstOfType || compound.lastOfType
            || compound.nthOfType != nil {
            if typeIndex < 0 { return false }
            if compound.firstOfType && typeIndex != 1 { return false }
            if compound.lastOfType && typeIndex != typeCount {
                return false
            }
            if let nth = compound.nthOfType,
               !tbNthMatches(nth, index: typeIndex) { return false }
        }
    }
    return true
}

// Selector matching walks right to left: the element itself must
// match the last compound; combinators then climb the ancestors.
func tbSelectorMatches(_ selector: TBSelector, node: TBNode,
                       hoverSatisfied: Bool = false,
                       focusSatisfied: Bool = false,
                       activeSatisfied: Bool = false) -> Bool {
    func matchFrom(_ index: Int, _ current: TBNode) -> Bool {
        guard tbCompoundMatches(selector.compounds[index], node: current,
                                hoverSatisfied: hoverSatisfied,
                                focusSatisfied: focusSatisfied,
                                activeSatisfied: activeSatisfied) else {
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

// Split a declaration block at semicolons that sit outside
// parentheses. A naive split corrupts values like
// url("data:image/jpeg;base64,…") — the data URI's own
// semicolon lives inside the url(...) parentheses.
func tbSplitDeclarations(_ body: String) -> [String] {
    var parts: [String] = []
    var depth = 0
    var current = ""
    for c in body {
        if c == "(" { depth += 1 }
        else if c == ")" { depth = max(0, depth - 1) }
        if c == ";" && depth == 0 {
            parts.append(current)
            current = ""
        } else {
            current.append(c)
        }
    }
    if !current.isEmpty { parts.append(current) }
    return parts
}

func tbParseDeclarations(_ body: String) -> [String: String] {
    var out: [String: String] = [:]
    for part in tbSplitDeclarations(body) {
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
    // @media blocks never reach the chunking below — the
    // finishing set (0.23) strips them whole, and the ones
    // whose queries match are parsed separately by
    // tbParseMediaCSS. (Before this, a block's second and
    // later rules leaked into the plain cascade.)
    cleaned = tbStripMediaBlocks(cleaned)
    cleaned = tbStripKeyframesBlocks(cleaned)
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

// What the renderer knows about the world when it evaluates
// @media (0.23): the appearance, the width of the window's
// text area as this render began, and the system's
// reduce-motion setting. Everything else a query can ask is
// answered from constants in tbMediaFeatureMatches or not
// answered at all.
struct TBMediaContext {
    var dark: Bool
    var width: CGFloat
    var reducedMotion: Bool
}


// Fill-gaps stamping for a single class value under
// its own key (0.27) — tbStampHover's sibling: runs
// already carrying the key (a nearer element's stamp)
// keep theirs, and the gaps take this value.
func tbStampValue(_ text: NSMutableAttributedString, range: NSRange,
                  key: NSAttributedString.Key, value: Any) {
    var gaps: [NSRange] = []
    text.enumerateAttribute(key, in: range, options: []) {
        existing, sub, _ in
        if existing == nil { gaps.append(sub) }
    }
    for gap in gaps {
        text.addAttribute(key, value: value, range: gap)
    }
}

struct TBKeyframeStop {
    var offset: Double
    var decls: [String: String]
}

final class TBKeyframesRule {
    var stops: [TBKeyframeStop] = []
}

// The @keyframes rules of a sheet (0.27), found by the
// same brace-matching scan that finds @media blocks:
// the name after the at-rule, then stop blocks whose
// selectors are percentages or from/to.
func tbParseKeyframes(_ css: String) -> [String: TBKeyframesRule] {
    var found: [String: TBKeyframesRule] = [:]
    var searchFrom = css.startIndex
    while let atRange = css.range(of: "@keyframes",
                                  options: .caseInsensitive,
                                  range: searchFrom..<css.endIndex) {
        guard let braceOpen = css.range(
                of: "{", range: atRange.upperBound..<css.endIndex)
        else { break }
        let name = String(css[atRange.upperBound..<braceOpen.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var depth = 0
        var j = braceOpen.lowerBound
        var closedAt: String.Index? = nil
        while j < css.endIndex {
            if css[j] == "{" { depth += 1 }
            else if css[j] == "}" {
                depth -= 1
                if depth == 0 { closedAt = j; break }
            }
            j = css.index(after: j)
        }
        guard let close = closedAt else { break }
        let body = String(css[css.index(after: braceOpen.lowerBound)..<close])
        let rule = TBKeyframesRule()
        for chunk in body.split(separator: "}") {
            let halves = chunk.split(separator: "{", maxSplits: 1)
            if halves.count != 2 { continue }
            let decls = tbParseDeclarations(String(halves[1]))
            if decls.isEmpty { continue }
            for rawSelector in halves[0].split(separator: ",") {
                let word = rawSelector
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let offset: Double?
                if word == "from" { offset = 0 }
                else if word == "to" { offset = 1 }
                else if word.hasSuffix("%"),
                        let pct = Double(word.dropLast()) {
                    offset = pct / 100
                } else { offset = nil }
                if let offset = offset {
                    rule.stops.append(TBKeyframeStop(offset: offset,
                                                     decls: decls))
                }
            }
        }
        if !name.isEmpty, !rule.stops.isEmpty {
            rule.stops.sort { $0.offset < $1.offset }
            found[name] = rule
        }
        searchFrom = css.index(after: close)
    }
    return found
}

// @keyframes blocks never reach the plain rule
// chunking (their stops would read as rules with odd
// selectors); strip them whole, as @media blocks are
// stripped — tbParseKeyframes has already read them
// from the sheet's raw text by the time this matters.
func tbStripKeyframesBlocks(_ css: String) -> String {
    var out = ""
    var searchFrom = css.startIndex
    while let atRange = css.range(of: "@keyframes",
                                  options: .caseInsensitive,
                                  range: searchFrom..<css.endIndex) {
        out += css[searchFrom..<atRange.lowerBound]
        guard let braceOpen = css.range(
                of: "{", range: atRange.upperBound..<css.endIndex)
        else {
            searchFrom = css.endIndex
            break
        }
        var depth = 0
        var j = braceOpen.lowerBound
        var closedAt: String.Index? = nil
        while j < css.endIndex {
            if css[j] == "{" { depth += 1 }
            else if css[j] == "}" {
                depth -= 1
                if depth == 0 { closedAt = j; break }
            }
            j = css.index(after: j)
        }
        guard let close = closedAt else {
            searchFrom = css.endIndex
            break
        }
        searchFrom = css.index(after: close)
    }
    out += css[searchFrom..<css.endIndex]
    return out
}

// The outermost @media blocks of a sheet: their condition
// text and their inner CSS, found by a brace-matching scan.
func tbMediaBlocks(_ css: String) -> [(condition: String, body: String)] {
    var blocks: [(condition: String, body: String)] = []
    var searchFrom = css.startIndex
    while let mediaRange = css.range(of: "@media", options: .caseInsensitive,
                                     range: searchFrom..<css.endIndex) {
        guard let braceOpen = css.range(
                of: "{", range: mediaRange.upperBound..<css.endIndex)
        else { break }
        let condition = String(css[mediaRange.upperBound..<braceOpen.lowerBound])
        var depth = 0
        var j = braceOpen.lowerBound
        var closedAt: String.Index? = nil
        while j < css.endIndex {
            if css[j] == "{" { depth += 1 }
            else if css[j] == "}" {
                depth -= 1
                if depth == 0 { closedAt = j; break }
            }
            j = css.index(after: j)
        }
        guard let close = closedAt else { break }
        blocks.append((condition,
                       String(css[css.index(after: braceOpen.lowerBound)..<close])))
        searchFrom = css.index(after: close)
    }
    return blocks
}

// A sheet with its @media blocks lifted out. tbParseCSS runs
// on this: rules written inside a media block must never
// reach the plain cascade — before the finishing set, the
// second and later rules of a block did leak in, whatever
// the query said. A block whose query matches is re-parsed
// by tbParseMediaCSS and appended in source order.
func tbStripMediaBlocks(_ css: String) -> String {
    var out = ""
    var searchFrom = css.startIndex
    while let mediaRange = css.range(of: "@media", options: .caseInsensitive,
                                     range: searchFrom..<css.endIndex) {
        out += css[searchFrom..<mediaRange.lowerBound]
        guard let braceOpen = css.range(
                of: "{", range: mediaRange.upperBound..<css.endIndex)
        else {
            searchFrom = css.endIndex
            break
        }
        var depth = 0
        var j = braceOpen.lowerBound
        var closedAt: String.Index? = nil
        while j < css.endIndex {
            if css[j] == "{" { depth += 1 }
            else if css[j] == "}" {
                depth -= 1
                if depth == 0 { closedAt = j; break }
            }
            j = css.index(after: j)
        }
        guard let close = closedAt else {
            searchFrom = css.endIndex
            break
        }
        searchFrom = css.index(after: close)
    }
    out += css[searchFrom..<css.endIndex]
    return out
}

// One parenthesised media condition, answered against what
// the renderer knows. Widths compare against this render's
// window width in CSS pixels; a width value may carry any
// unit tbFontSizeValue reads, em and rem against the 14px
// base font as media queries define. prefers-color-scheme
// and prefers-reduced-motion come from the window and the
// system. hover and pointer are answered as the constants
// they are on a Mac — a pointer that can hover, and a fine
// one (a mouse or trackpad) — stated plainly here rather
// than dressed up as detection. A feature this engine does
// not know answers false, which keeps the whole query (and
// so the block) from applying: the behavior unknown
// features have always had here.
func tbMediaFeatureMatches(_ feature: String, _ value: String?,
                           context: TBMediaContext) -> Bool {
    switch feature {
    case "prefers-color-scheme":
        guard let value = value else { return true }
        if value == "dark" { return context.dark }
        if value == "light" { return !context.dark }
        return false
    case "prefers-reduced-motion":
        guard let value = value else { return context.reducedMotion }
        if value == "reduce" { return context.reducedMotion }
        if value == "no-preference" { return !context.reducedMotion }
        return false
    case "min-width":
        guard let value = value,
              let limit = tbFontSizeValue(value, relativeTo: 14)
        else { return false }
        return context.width >= limit
    case "max-width":
        guard let value = value,
              let limit = tbFontSizeValue(value, relativeTo: 14)
        else { return false }
        return context.width <= limit
    case "width":
        guard let value = value else { return context.width > 0 }
        guard let limit = tbFontSizeValue(value, relativeTo: 14)
        else { return false }
        return context.width == limit
    case "hover":
        // A Mac's pointer hovers. A constant, stated above.
        guard let value = value else { return true }
        return value == "hover"
    case "pointer":
        // …and it is a fine pointer. A constant, stated above.
        guard let value = value else { return true }
        return value == "fine"
    default:
        return false
    }
}

// One media query: an optional `not` / `only`, an optional
// media type, and parenthesised conditions joined by `and` —
// all of which must hold. The screen is the type this engine
// renders for; print and the rest never match.
func tbMediaQueryMatches(_ queryRaw: String, context: TBMediaContext) -> Bool {
    var rest = queryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    var negate = false
    if rest.hasPrefix("not ") {
        negate = true
        rest = String(rest.dropFirst(4))
    }
    if rest.hasPrefix("only ") { rest = String(rest.dropFirst(5)) }
    rest = rest.trimmingCharacters(in: .whitespaces)
    // Lift the parenthesised conditions out; what remains is
    // the media type and the `and`s.
    var conditions: [(feature: String, value: String?)] = []
    var remainder = ""
    let chars = Array(rest)
    var i = 0
    var malformed = false
    while i < chars.count {
        if chars[i] == "(" {
            guard let (arg, next) = tbParenArgument(chars, openIndex: i)
            else { malformed = true; break }
            let parts = arg.split(separator: ":", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.isEmpty || parts[0].isEmpty {
                malformed = true
                break
            }
            conditions.append((parts[0], parts.count > 1 ? parts[1] : nil))
            i = next
        } else {
            remainder.append(chars[i])
            i += 1
        }
    }
    if malformed { return false }   // a query that cannot be read never matches
    let typeWords = remainder.split(whereSeparator: { tbIsSpace($0) })
        .map(String.init).filter { $0 != "and" }
    var matches = true
    if let type = typeWords.first, type != "screen" && type != "all" {
        matches = false
    }
    if typeWords.count > 1 { matches = false }
    if matches {
        for condition in conditions
        where !tbMediaFeatureMatches(condition.feature, condition.value,
                                     context: context) {
            matches = false
            break
        }
    }
    return negate ? !matches : matches
}

// A full media query list: commas are alternatives — any one
// matching query applies the block.
func tbMediaMatches(_ conditionRaw: String, context: TBMediaContext) -> Bool {
    // Split on commas outside parentheses.
    var queries: [String] = []
    var current = ""
    var depth = 0
    for c in conditionRaw {
        if c == "(" { depth += 1 }
        else if c == ")" { depth -= 1 }
        if c == "," && depth == 0 {
            queries.append(current)
            current = ""
        } else {
            current.append(c)
        }
    }
    queries.append(current)
    return queries.contains { tbMediaQueryMatches($0, context: context) }
}

// The @media rules that apply to this render: every block
// whose query list matches the context, parsed with the
// ordinary machinery and ordered after orderStart. @media
// nested inside @media is not evaluated — the inner parse
// strips those blocks away.
func tbParseMediaCSS(_ css: String, orderStart: Int,
                     context: TBMediaContext) -> [TBCSSRule] {
    var bodies: [String] = []
    for block in tbMediaBlocks(css)
    where tbMediaMatches(block.condition, context: context) {
        bodies.append(block.body)
    }
    if bodies.isEmpty { return [] }
    return tbParseCSS(bodies.joined(separator: "\n"), orderStart: orderStart)
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

// Split a value on the whitespace outside parentheses and
// quotes — the font shorthand's tokenizer, where a family name
// may be quoted ("Helvetica Neue") and a var() may nest.
func tbFontTokens(_ value: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var depth = 0
    var quote: Character? = nil
    for c in value {
        if let q = quote {
            current.append(c)
            if c == q { quote = nil }
            continue
        }
        if c == "\"" || c == "'" { quote = c; current.append(c); continue }
        if c == "(" { depth += 1 }
        else if c == ")" { depth = max(0, depth - 1) }
        if tbIsSpace(c) && depth == 0 {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else {
            current.append(c)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

// The system-font keywords stand alone as a whole font: value;
// this engine maps none of them and sets the declaration aside.
let TBFontSystemKeywords: Set<String> = ["caption", "icon", "menu",
                                         "message-box", "small-caption",
                                         "status-bar"]

// The font: shorthand (0.23), parsed whole: any of the pre-size
// keywords (style, variant, weight, stretch — in any order),
// the required size, an optional /line-height, then the family
// list. What it expands into is the longhands, with the
// shorthand's defining resets made explicit — a component the
// author did not mention returns to normal, it does not keep
// whatever an earlier rule said. Longhands this engine reads:
// font-style, font-weight, font-variant, font-size,
// line-height, font-family. font-stretch is parsed and
// carried, and set aside unread — nothing here applies it.
// Nil for a value outside the grammar (no size, no family, a
// system-font keyword standing alone).
func tbParseFontShorthand(_ raw: String) -> [String: String]? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if TBFontSystemKeywords.contains(value.lowercased()) { return nil }
    let tokens = tbFontTokens(value)
    if tokens.isEmpty { return nil }
    let sizeKeywords: Set<String> = ["xx-small", "x-small", "small",
                                     "medium", "large", "x-large",
                                     "xx-large", "larger", "smaller"]
    let stretchKeywords: Set<String> = ["ultra-condensed",
                                        "extra-condensed", "condensed",
                                        "semi-condensed", "semi-expanded",
                                        "expanded", "extra-expanded",
                                        "ultra-expanded"]
    // A size token: a keyword size, a bare 0, or a number with
    // a length/percentage unit — never a bare number, which in
    // the pre-size run can only be a weight.
    func isSizeToken(_ token: String) -> Bool {
        let head = token.split(separator: "/", maxSplits: 1)
            .first.map(String.init) ?? token
        let low = head.lowercased()
        if sizeKeywords.contains(low) || low == "0" { return true }
        for suffix in ["px", "pt", "em", "rem", "%"] where low.hasSuffix(suffix) {
            return Double(String(low.dropLast(suffix.count))) != nil
        }
        return false
    }
    var style: String? = nil
    var weight: String? = nil
    var variant: String? = nil
    var stretch: String? = nil
    var size: String? = nil
    var lineHeight: String? = nil
    var i = 0
    while i < tokens.count {
        let token = tokens[i]
        let low = token.lowercased()
        if isSizeToken(token) {
            // The size, possibly wearing its line-height:
            // "16px/1.5", "16px/ 1.5", "16px /1.5" and
            // "16px / 1.5" are all one declaration.
            let parts = token.split(separator: "/", maxSplits: 1,
                                    omittingEmptySubsequences: false)
                .map(String.init)
            size = parts[0]
            if parts.count > 1 {
                if parts[1].isEmpty {
                    if i + 1 < tokens.count {
                        lineHeight = tokens[i + 1]
                        i += 1
                    }
                } else {
                    lineHeight = parts[1]
                }
            } else if i + 1 < tokens.count && tokens[i + 1] == "/" {
                if i + 2 < tokens.count {
                    lineHeight = tokens[i + 2]
                    i += 2
                }
            }
            i += 1
            break
        }
        switch low {
        case "italic":
            style = "italic"
        case "oblique":
            style = "oblique"
            // An oblique angle (oblique 20deg) is consumed
            // and set aside — the trait applied is oblique's.
            if i + 1 < tokens.count
                && tokens[i + 1].lowercased().hasSuffix("deg") { i += 1 }
        case "normal":
            break   // a reset of whichever component — all default below
        case "bold", "bolder", "lighter":
            weight = low
        default:
            if low.contains("small-caps") {
                variant = "small-caps"
            } else if stretchKeywords.contains(low) {
                stretch = low
            } else if let n = Int(low), n >= 1, n <= 1000 {
                weight = low   // a numeric weight, 100…900 and kin
            } else {
                return nil
            }
        }
        i += 1
    }
    guard let sizeValue = size else { return nil }
    // Everything past the size is the family list, rejoined
    // as written — commas, quotes and all.
    let family = tokens[i...].joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
    if family.isEmpty { return nil }
    var out: [String: String] = [
        "font-style": style ?? "normal",
        "font-weight": weight ?? "normal",
        "font-variant": variant ?? "normal",
        "font-size": sizeValue,
        "line-height": lineHeight ?? "normal",
        "font-family": family,
    ]
    if let stretchValue = stretch { out["font-stretch"] = stretchValue }
    return out
}

// Merge one declaration block into the cascade output. The
// font: shorthand expands at exactly its own position in
// that flow: its components enter here, and the block's own
// longhands — merged just after — win over them, the same
// house rule the box shorthands follow. A font: whose value
// still carries var() cannot be tokenized yet; it rides
// along under its own key for the renderer's deferred
// expansion, once substitution has made it concrete.
func tbMergeDeclarations(_ decls: [String: String],
                         into out: inout [String: String]) {
    if let font = decls["font"] {
        if font.contains("var(") {
            out["font"] = font
        } else if let parts = tbParseFontShorthand(font) {
            for (k, v) in parts { out[k] = v }
        }
    }
    for (k, v) in decls where k != "font" { out[k] = v }
}

// The deferred second half of the shorthand: a font: that
// reached the renderer still whole (its value came through
// var()) expands now that substitution has happened. By
// then the cascade has closed, so the expansion fills only
// the components no rule set outright — a longhand from any
// rule keeps precedence over a var()-borne shorthand's
// matching part. A plain font: never survives to here; it
// expanded in the merge.
func tbExpandDeferredFont(_ decls: [String: String]) -> [String: String] {
    guard let font = decls["font"] else { return decls }
    var out = decls
    out.removeValue(forKey: "font")
    if let parts = tbParseFontShorthand(font) {
        for (k, v) in parts where out[k] == nil { out[k] = v }
    }
    return out
}

// The declarations that apply to one element: matching rules in
// cascade order (specificity first, then source order), with the
// element's inline style on top.
func tbResolveStyle(node: TBNode, rules: [TBCSSRule]) -> [String: String] {
    if node.tag == "#text" { return [:] }
    // Specificity once each (0.37.3): the sort used to
    // re-derive it — a reduction over the selector's
    // compounds — on every comparison it made.
    var matched: [(spec: Int, order: Int, rule: TBCSSRule)] = []
    for rule in rules where tbSelectorMatches(rule.selector, node: node) {
        matched.append((rule.selector.specificity, rule.order, rule))
    }
    matched.sort { ($0.spec, $0.order) < ($1.spec, $1.order) }
    var out: [String: String] = [:]
    for entry in matched {
        tbMergeDeclarations(entry.rule.declarations, into: &out)
    }
    if let inlineStyle = node.attrs["style"] {
        tbMergeDeclarations(tbParseDeclarations(inlineStyle), into: &out)
    }
    return out
}

// The interactive states (0.23, 0.26): :hover first, and
// :focus and :active beside it — each a state an element
// wears for a while, each resolved apart from the resting
// cascade in the same shape.
enum TBStateFlag { case hover, focus, active }

// Does any compound in this selector carry the state?
func tbSelectorHasState(_ selector: TBSelector,
                        _ flag: TBStateFlag) -> Bool {
    switch flag {
    case .hover: return selector.compounds.contains { $0.isHover }
    case .focus: return selector.compounds.contains { $0.isFocus }
    case .active: return selector.compounds.contains { $0.isActive }
    }
}

// Does any compound in this selector carry :hover?
func tbSelectorHasHover(_ selector: TBSelector) -> Bool {
    tbSelectorHasState(selector, .hover)
}

// A state resolution: the declarations an element wears
// while it is in the state — only rules carrying the
// state, matched with the state treated as satisfied, in
// the same cascade order as the resting resolution. What
// the view does with them is paint, not layout: see
// tbHoverPaintAttrs.
func tbResolveStateStyle(node: TBNode, rules: [TBCSSRule],
                         flag: TBStateFlag) -> [String: String] {
    if node.tag == "#text" { return [:] }
    var matched: [(spec: Int, order: Int, rule: TBCSSRule)] = []
    for rule in rules where tbSelectorHasState(rule.selector, flag)
        && tbSelectorMatches(rule.selector, node: node,
                             hoverSatisfied: flag == .hover,
                             focusSatisfied: flag == .focus,
                             activeSatisfied: flag == .active) {
        matched.append((rule.selector.specificity, rule.order, rule))
    }
    matched.sort { ($0.spec, $0.order) < ($1.spec, $1.order) }
    var out: [String: String] = [:]
    for entry in matched {
        tbMergeDeclarations(entry.rule.declarations, into: &out)
    }
    return out
}

// The hover resolution (0.23): the declarations an element
// wears while the pointer is over it.
func tbResolveHoverStyle(node: TBNode, rules: [TBCSSRule]) -> [String: String] {
    tbResolveStateStyle(node: node, rules: rules, flag: .hover)
}

// MARK: - CSS variables

// The custom-property environment of one element: every --name
// defined on the element or inherited from its ancestors, with
// nearer and stronger definitions winning, as in real CSS.
// The speed stage (0.36): only rules that define a custom
// property can contribute a name here, so only they are
// matched — on the measured Wikipedia article, 4 of 607
// rules define one, and matching the other 603 against
// every ancestor of every element was the single largest
// cost in the whole style stage (a full environment pass
// over the article: 86.7s by the harness's clock, against
// 2.0s for the entire resting cascade).
func tbVariableEnvironment(node: TBNode, rules: [TBCSSRule]) -> [String: String] {
    let customRules = rules.filter { rule in
        rule.declarations.contains { $0.key.hasPrefix("--") }
    }
    return tbVariableEnvironment(node: node, customRules: customRules,
                                 rules: rules)
}

// The environment builder with its custom-property
// rules already filtered (0.37.3): the caller keeps
// the filtered list per rule set instead of paying
// a full-sheet filter per element, and an element
// whose whole chain defines no custom property —
// no matching custom rule, no inline style carrying
// one — returns the empty environment without the
// ancestor walk's matching passes at all. The
// values are the unfiltered walk's values either
// way: a chain that defines nothing has an empty
// environment by definition.
func tbVariableEnvironment(node: TBNode,
                           customRules: [TBCSSRule],
                           rules: [TBCSSRule]) -> [String: String] {
    var chain: [TBNode] = []
    var current: TBNode? = node
    while let element = current, element.tag != "document" {
        chain.append(element)
        current = element.parent
    }
    if !customRules.isEmpty || chain.contains(where: {
        ($0.attrs["style"] ?? "").contains("--")
    }) {
        // Something in the chain may define a name:
        // fall through to the full build below.
    } else {
        return [:]
    }
    var env: [String: String] = [:]
    for element in chain.reversed() {
        var matched: [(spec: Int, order: Int, rule: TBCSSRule)] = []
        for rule in customRules where tbSelectorMatches(rule.selector, node: element) {
            matched.append((rule.selector.specificity, rule.order, rule))
        }
        matched.sort { ($0.spec, $0.order) < ($1.spec, $1.order) }
        for entry in matched {
            for (name, value) in entry.rule.declarations where name.hasPrefix("--") {
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
    if v.hasPrefix("color-mix(") { return tbMixColor(v) }
    if v.hasPrefix("rgb") {
        let inner = v.drop(while: { $0 != "(" }).dropFirst().dropLast()
        var parts = inner.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count < 3 {
            // The space-separated form: rgb(16 24 14 / 0.42)
            parts = inner.replacingOccurrences(of: "/", with: " ")
                .split(separator: " ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        if parts.count >= 3,
           let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) {
            // The fourth component is the alpha, and it is
            // load-bearing: rgba(16, 24, 14, 0.42) is a
            // translucent veil, not the opaque near-black
            // this parser returned before 0.12.
            var alpha: CGFloat = 1
            if parts.count >= 4 {
                if parts[3].hasSuffix("%"), let pct = Double(parts[3].dropLast()) {
                    alpha = CGFloat(pct / 100)
                } else if let a = Double(parts[3]) {
                    alpha = CGFloat(a)
                }
            }
            return NSColor(srgbRed: CGFloat(r / 255), green: CGFloat(g / 255),
                           blue: CGFloat(b / 255),
                           alpha: min(1, max(0, alpha)))
        }
    }
    return nil
}

// color-mix() (0.22): color-mix(in srgb, <color> p%?,
// <color> p%?) — the one interpolation space this engine
// reads; another space named in the value makes the whole
// color unreadable (nil), never an approximation in srgb
// wearing its name. Because var() substitution is textual
// and runs before any color is parsed, a mix may arrive
// whole from a custom property, and each side of the mix
// is itself parsed by tbParseColor, so mixes nest.
//
// The mixing follows the CSS Color 5 algorithm. The two
// percentages default per the spec — both omitted means
// 50/50, one omitted means 100 minus the other — and are
// clamped to 0...100. When they sum to less than 100 the
// proportions still rule the hue but the result's alpha
// is scaled by sum/100; above 100 the proportions simply
// normalize. The components themselves mix in
// premultiplied-alpha form (each channel weighted by its
// own color's alpha as well as its proportion), then
// divide back out by the mixed alpha — that is what keeps
// a fade toward transparent from darkening through gray
// it never declared.
func tbMixColor(_ v: String) -> NSColor? {
    guard v.hasSuffix(")") else { return nil }
    let inner = String(v.dropFirst("color-mix(".count).dropLast())
    let parts = tbSplitLayers(inner).map {
        $0.trimmingCharacters(in: .whitespaces)
    }
    guard parts.count == 3 else { return nil }
    let space = parts[0].split(whereSeparator: { tbIsSpace($0) })
        .map { String($0).lowercased() }
    guard space == ["in", "srgb"] else { return nil }

    // One side of the mix: a color with an optional
    // percentage trailing it, split at the last space that
    // sits outside parentheses (a nested function's own
    // spaces are all spoken for inside its parens).
    func side(_ raw: String) -> (color: NSColor, percent: Double?)? {
        var colorText = raw
        var percent: Double? = nil
        var depth = 0
        var splitAt: String.Index? = nil
        for i in raw.indices {
            if raw[i] == "(" { depth += 1 }
            else if raw[i] == ")" { depth -= 1 }
            else if raw[i] == " " && depth == 0 { splitAt = i }
        }
        if let split = splitAt {
            let tail = String(raw[raw.index(after: split)...])
            if tail.hasSuffix("%"), let value = Double(tail.dropLast()) {
                percent = min(100, max(0, value))
                colorText = String(raw[..<split])
            }
        }
        guard let color = tbParseColor(colorText) else { return nil }
        return (color, percent)
    }
    guard let first = side(parts[1]), let second = side(parts[2])
    else { return nil }

    var p1 = first.percent
    var p2 = second.percent
    if p1 == nil && p2 == nil { p1 = 50; p2 = 50 }
    else if p1 == nil { p1 = 100 - (p2 ?? 0) }
    else if p2 == nil { p2 = 100 - (p1 ?? 0) }
    let sum = (p1 ?? 0) + (p2 ?? 0)
    guard sum > 0 else {
        return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    }
    let alphaScale = sum < 100 ? CGFloat(sum / 100) : 1
    let w1 = CGFloat((p1 ?? 0) / sum)
    let w2 = CGFloat((p2 ?? 0) / sum)

    func rgba(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
    let c1 = rgba(first.color)
    let c2 = rgba(second.color)
    let mixedAlpha = c1.a * w1 + c2.a * w2
    func channel(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let premixed = a * c1.a * w1 + b * c2.a * w2
        guard mixedAlpha > 0 else { return 0 }
        return min(1, max(0, premixed / mixedAlpha))
    }
    return NSColor(srgbRed: channel(c1.r, c2.r),
                   green: channel(c1.g, c2.g),
                   blue: channel(c1.b, c2.b),
                   alpha: min(1, max(0, mixedAlpha * alphaScale)))
}

// The background color an element's declarations call for:
// background-color itself, or the color layer of the
// `background:` shorthand. In the shorthand, only the final
// layer may carry a color (it paints beneath any images or
// gradients in the earlier layers), so the color is looked
// for there — or in a lone single-layer value.
// Split a CSS value at commas that sit outside parentheses
// (background layers, gradient stops, font stacks).
func tbSplitLayers(_ value: String) -> [String] {
    var layers: [String] = []
    var depth = 0
    var current = ""
    for c in value {
        if c == "(" { depth += 1 }
        else if c == ")" { depth = max(0, depth - 1) }
        if c == "," && depth == 0 {
            layers.append(current)
            current = ""
        } else {
            current.append(c)
        }
    }
    layers.append(current)
    return layers
}

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

// The paint a state resolution contributes (0.23; the
// reduction serves :focus and :active identically since
// 0.26), as a TBHoverStyle — or nil when the resolution
// names nothing the state machinery can paint. Paint
// only, by design: foreground color, the background
// color behind the glyphs (the color layer only —
// tbBackgroundColor, so a shorthand background
// contributes its color; photo and gradient state
// backgrounds are not painted), and the underline /
// strikethrough switches — including `none`, which
// switches one OFF for the state. A state rule that
// changes a font or a size is read and set aside:
// restyling must never move the text.
func tbHoverPaintAttrs(_ decls: [String: String]) -> TBHoverStyle? {
    let style = TBHoverStyle()
    var any = false
    if let color = tbParseColor(decls["color"]) {
        style.foregroundColor = color
        any = true
    }
    if let background = tbBackgroundColor(decls) {
        style.backgroundColor = background
        any = true
    }
    let deco = (decls["text-decoration"] ?? "") + " "
        + (decls["text-decoration-line"] ?? "")
    let decoLow = deco.lowercased()
    if decoLow.contains("none") {
        style.underlineStyle = 0
        style.strikethroughStyle = 0
        any = true
    }
    if decoLow.contains("underline") {
        style.underlineStyle = NSUnderlineStyle.single.rawValue
        any = true
    }
    if decoLow.contains("line-through") {
        style.strikethroughStyle = NSUnderlineStyle.single.rawValue
        any = true
    }
    return any ? style : nil
}

// Stamp an element's hover style onto its text, filling
// only the characters no stamp covers yet: the innermost
// element stamps first (its run finishes first) and keeps
// its ground, its enclosing elements fill around it.
func tbStampHover(_ target: NSMutableAttributedString,
                  range: NSRange, key: NSAttributedString.Key,
                  style: TBHoverStyle) {
    guard range.length > 0,
          range.location != NSNotFound,
          range.location + range.length <= target.length else { return }
    var gaps: [NSRange] = []
    var coveredEnd = range.location
    target.enumerateAttribute(key, in: range,
                              options: []) { _, attrRange, _ in
        if attrRange.location > coveredEnd {
            gaps.append(NSRange(location: coveredEnd,
                                length: attrRange.location - coveredEnd))
        }
        coveredEnd = max(coveredEnd,
                         attrRange.location + attrRange.length)
    }
    if coveredEnd < range.location + range.length {
        gaps.append(NSRange(location: coveredEnd,
                            length: range.location + range.length - coveredEnd))
    }
    for gap in gaps where gap.length > 0 {
        target.addAttribute(key, value: style, range: gap)
    }
}

// The interaction set (0.26): stamp a sticky block's spec
// onto its text — the tbStampHover discipline (the
// innermost stamp keeps its ground) with the sticky
// key, so a sticky nested inside a sticky keeps its own
// spec. The layout manager reads the stamp when it
// paints; the coordinator resolves the spec's shift.
func tbStampSticky(_ target: NSMutableAttributedString,
                   range: NSRange, spec: TBStickySpec) {
    guard range.length > 0,
          range.location != NSNotFound,
          range.location + range.length <= target.length else { return }
    var gaps: [NSRange] = []
    var coveredEnd = range.location
    target.enumerateAttribute(TBStickyKey, in: range,
                              options: []) { _, attrRange, _ in
        if attrRange.location > coveredEnd {
            gaps.append(NSRange(location: coveredEnd,
                                length: attrRange.location - coveredEnd))
        }
        coveredEnd = max(coveredEnd,
                         attrRange.location + attrRange.length)
    }
    if coveredEnd < range.location + range.length {
        gaps.append(NSRange(location: coveredEnd,
                            length: range.location + range.length - coveredEnd))
    }
    for gap in gaps where gap.length > 0 {
        target.addAttribute(TBStickyKey, value: spec, range: gap)
    }
}

// MARK: - Font helpers

func tbFontSizeValue(_ raw: String, relativeTo base: CGFloat,
                     scaled: Bool = false) -> CGFloat? {
    // The reader's text size (0.35), when the
    // caller asks for it: absolute sizes and
    // the named sizes scale; relative sizes
    // (larger, smaller, em, %) ride their
    // base, which is itself already scaled.
    let factor: CGFloat = scaled ? TBSettings.textScale : 1
    let v = raw.trimmingCharacters(in: .whitespaces).lowercased()
    switch v {
    case "xx-small": return 9 * factor
    case "x-small": return 10 * factor
    case "small": return 12 * factor
    case "medium": return 14 * factor
    case "large": return 18 * factor
    case "x-large": return 24 * factor
    case "xx-large": return 32 * factor
    case "larger": return base * 1.2
    case "smaller": return base / 1.2
    default: break
    }
    if v.hasSuffix("rem"), let d = Double(String(v.dropLast(3))) {
        return CGFloat(14 * d) * factor
    }
    if v.hasSuffix("px"), let d = Double(String(v.dropLast(2))) {
        return CGFloat(d) * factor
    }
    if v.hasSuffix("pt"), let d = Double(String(v.dropLast(2))) {
        return CGFloat(d) * factor
    }
    if v.hasSuffix("em"), let d = Double(String(v.dropLast(2))) {
        return base * CGFloat(d)
    }
    if v.hasSuffix("%"), let d = Double(String(v.dropLast(1))) {
        return base * CGFloat(d) / 100
    }
    if let d = Double(v) { return CGFloat(d) * factor }
    return nil
}

// The font a family list names (0.23): the first family in
// the comma list that resolves on this Mac. A named family
// resolves as itself; the generic families map to the
// platform faces CSS expects of them — serif to a Times,
// sans-serif to a Helvetica, monospace to Menlo, cursive
// and fantasy to the Mac's own script and display faces.
// The traits and weight of the incoming font carry across,
// so a bold Georgia stays bold; the size is the caller's
// to settle afterwards, as it always has been.
func tbFontByFamily(_ list: String, like font: NSFont) -> NSFont? {
    let fm = NSFontManager.shared
    let generics: [String: String] = [
        "serif": "Times", "sans-serif": "Helvetica",
        "monospace": "Menlo", "cursive": "Apple Chancery",
        "fantasy": "Papyrus",
    ]
    for rawPart in list.split(separator: ",") {
        var name = rawPart.trimmingCharacters(in: .whitespaces)
        if (name.hasPrefix("\"") && name.hasSuffix("\"") && name.count >= 2)
            || (name.hasPrefix("'") && name.hasSuffix("'") && name.count >= 2) {
            name = String(name.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespaces)
        }
        if name.isEmpty { continue }
        let family = generics[name.lowercased()] ?? name
        if let resolved = fm.font(withFamily: family,
                                  traits: fm.traits(of: font),
                                  weight: fm.weight(of: font),
                                  size: font.pointSize) {
            return resolved
        }
    }
    return nil
}

// Apply one element's own font declarations to a font. Size is
// relative to the incoming font, so ancestors' sizes carry down
// through the font object itself.
func tbFontApplying(_ decls: [String: String], to font: NSFont) -> NSFont {
    var f = font
    let fm = NSFontManager.shared
    // The family first (0.23): the trait and size conversions
    // below then work on the face the page asked for.
    if let family = decls["font-family"],
       let byFamily = tbFontByFamily(family, like: f) {
        f = byFamily
    }
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
    // font-variant (0.23): small-caps is the one variant
    // this engine paints — the font manager trades the face
    // for its small-cap form where the family carries one;
    // a face without small caps simply shows unchanged.
    if let variant = decls["font-variant"]?.lowercased() {
        if variant.contains("small-caps") {
            f = fm.convert(f, toHaveTrait: .smallCapsFontMask)
        } else if variant == "normal" {
            f = fm.convert(f, toNotHaveTrait: .smallCapsFontMask)
        }
    }
    if let fs = decls["font-size"], let size = tbFontSizeValue(fs, relativeTo: f.pointSize, scaled: true) {
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
