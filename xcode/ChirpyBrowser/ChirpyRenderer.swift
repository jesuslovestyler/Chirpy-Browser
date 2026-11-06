//
//  ChirpyRenderer.swift
//  Chirpy Browser — engine 0.39.6 (Swift)
//
//  The render core: Chirpy's page
//  pipeline. This file takes the parsed
//  document and makes the page the window
//  reads. It holds the renderer's tag
//  sets and base styles, the form
//  controls and their attachments, the
//  form specs, and TBRenderer itself -
//  its stored state, its style
//  resolutions, and its forms - together
//  with the send-on helpers and the page
//  pipeline: tbRenderPage, which runs a
//  page's scripts and walks it to the
//  first paint, and tbRepaintPage, which
//  walks it again when the window asks.
//  TBRenderer's layout regions live in
//  ChirpyLayout.swift and its paint
//  regions in ChirpyPaint.swift, written
//  as extensions of the class declared
//  here - extensions cannot hold stored
//  properties, which is why the class
//  itself waited for a file of its own.
//
//  This file was ChirpyEngine.swift's
//  render country - everything under the
//  render mark, to the end of the file -
//  until 0.39.6, when it moved here
//  whole: the sixth step of splitting the
//  codebase into files of their own, at
//  Tyler's direction, so each part can be
//  fixed and built quicker - and the
//  last. Nothing in the move changed the
//  render core itself; the section intro
//  that stood over it in the engine file
//  stands below, as it was written.
//  ChirpyEngine.swift keeps a short
//  marker where the section lived,
//  pointing here.
//
//  Public domain (Unlicense), like the
//  rest of Chirpy.
//

import Foundation
import AppKit


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
    // The reader's text size (0.35) scales the
    // tag defaults, as it scales the sizes CSS
    // declares absolutely (tbFontApplying);
    // sizes CSS gives relative to a base (em,
    // %, larger and smaller) ride their base,
    // which is itself already scaled.
    let scale = TBSettings.textScale
    switch style {
    case "h1": return NSFont.boldSystemFont(ofSize: 26 * scale)
    case "h2": return NSFont.boldSystemFont(ofSize: 21 * scale)
    case "h3": return NSFont.boldSystemFont(ofSize: 17 * scale)
    case "h4", "h5", "h6": return NSFont.boldSystemFont(ofSize: 15 * scale)
    case "quote":
        return NSFont(name: "Georgia-Italic", size: 14 * scale) ?? NSFont.systemFont(ofSize: 14 * scale)
    default:
        return NSFont.systemFont(ofSize: 14 * scale)
    }
}

// The interaction set (0.26): a live form control's
// style, resolved by the renderer from the element's
// computed declarations and carried on its attachment
// to the view, which dresses the real control with
// it. A class, like TBHoverStyle: attribute and
// attachment values that are Swift dictionaries do
// not survive being read back. Every trait is
// optional — a page that declares nothing gets the
// native control exactly as it stood before 0.26.
// The focus and active traits come from the
// element's :focus and :active resolutions (the
// declarations only, reduced by hand in the
// renderer): a focused control wears the focus
// background or border, a declared outline riding
// as the control's border ring for the focus's
// duration, and a pressed button wears the active
// colors for the press.
final class TBControlStyle {
    var font: NSFont? = nil
    var textColor: NSColor? = nil
    var backgroundColor: NSColor? = nil
    var borderColor: NSColor? = nil
    var borderWidth: CGFloat = 0
    var cornerRadius: CGFloat = 0
    var focusTextColor: NSColor? = nil
    var focusBackgroundColor: NSColor? = nil
    var focusBorderColor: NSColor? = nil
    var outlineColor: NSColor? = nil
    var outlineWidth: CGFloat = 0
    var activeTextColor: NSColor? = nil
    var activeBackgroundColor: NSColor? = nil
}

// Forms (0.13): a text or search input seats an attachment
// in the text, the way an image does — but what belongs
// there is a real, editable field, which the window lays
// over the text (PageTextView's Coordinator in
// ContentView.swift). Pressing Enter submits the form as
// a browser does: its own fields and hidden inputs,
// GET-encoded onto its action.
final class TBFieldAttachment: NSTextAttachment {
    var fieldID = -1
    // The interaction set (0.26): the field's style,
    // as its element's computed declarations resolved
    // it — the view dresses the live control with it.
    var style: TBControlStyle? = nil
}

// An attachment reserves space in the layout only when it
// carries an image (or a cell) — bounds alone reserve
// nothing, which is why 0.13's controls all seated at one
// spot. A clear image the size of the intended box makes
// the glyph advance exactly that box.
func tbClearSeat(width: CGFloat, height: CGFloat) -> NSImage {
    return NSImage(size: NSSize(width: max(width, 1), height: max(height, 1)))
}

final class TBSubmitAttachment: NSTextAttachment {
    var formID = -1
    var label = "Submit"
    // The interaction set (0.26): the button's style,
    // as with the field's.
    var style: TBControlStyle? = nil
}

// Live controls (0.31): one row of a <select>'s
// popup, gathered by the renderer in document
// order. A group row is an <optgroup>'s label: it
// stands in the popup as a disabled row and
// carries no value of its own.
struct TBSelectOption {
    let label: String
    let value: String
    let isGroup: Bool
}

// A <select> seats this attachment; the view builds
// a real popup button over it. The resting choice
// is an index into options — always a real
// option's row, never a group's, or -1 when the
// select holds no option at all.
final class TBSelectAttachment: NSTextAttachment {
    var fieldID = -1
    var options: [TBSelectOption] = []
    var selectedIndex = -1
    // The element's resolved style, as with the
    // field's (0.26).
    var style: TBControlStyle? = nil
}

// A <textarea> seats this attachment; the view
// builds a real multi-line editor over it. The
// seed itself travels as the field's standing
// value in TBFormField, as a field's value does.
final class TBTextAreaAttachment: NSTextAttachment {
    var fieldID = -1
    var style: TBControlStyle? = nil
}

struct TBFormField {
    let id: Int
    let formID: Int        // -1: an input outside any form
    let name: String
    let defaultValue: String
    let placeholder: String
}

struct TBFormSpec {
    let id: Int
    let action: String     // absolute; the page itself when absent
    let method: String     // lowercased; GET submits in 0.13
    var hidden: [(name: String, value: String)] = []
    var submitName: String? = nil
    var submitValue: String? = nil
}

final class TBRenderer {
    let base: String
    var links: [String] = []
    var rules: [TBCSSRule] = []
    // The speed stage (0.36): resolved styles are
    // remembered per element for the life of this
    // walk — the tree and the rules do not change
    // under a walk, and the walk was asking for the
    // same element's style again and again (the
    // block walk, its inline children, its state
    // paints). And the cascade is offered only the
    // rules that could match: an index by the
    // rightmost compound's plainest key (its tag,
    // its id, or its first class; a compound with
    // none of those stands in the universal
    // bucket). The index can only over-include —
    // tbSelectorMatches still has the last word —
    // so the styles it yields are the full scan's
    // styles, reached faster. Measured on the
    // Wikipedia article: the resting cascade's
    // per-element full scan was 2.0s of a walk
    // that repeated it many times over.
    private var styleCache: [ObjectIdentifier: [String: String]] = [:]
    private var stateCache: [String: [String: String]] = [:]
    // The variable environment, remembered (0.37.3):
    // an element's custom-property environment is a
    // function of its ancestor chain and the rule set,
    // neither of which changes during a walk — yet it
    // was rebuilt for every resolution that needed it:
    // the resting resolution once per element, and each
    // of the three state resolutions again for the same
    // element (41,313 state calls on the measured
    // article, 13.5s of environment building, though
    // the raw state cascades themselves cost ~0s).
    // One build per element now serves all four.
    private var envCache: [ObjectIdentifier: [String: String]] = [:]
    // The custom-property rules of the current rule
    // set, filtered once — the environment builder
    // used to re-filter the whole sheet per call.
    private var customRulesCache: [TBCSSRule] = []
    private var customRulesCacheCount = -1

    // The element's variable environment, from the
    // remembered copy when there is one.
    func variableEnvironment(node: TBNode) -> [String: String] {
        let key = ObjectIdentifier(node)
        if let kept = envCache[key] { return kept }
        if customRulesCacheCount != rules.count {
            customRulesCache = rules.filter { rule in
                rule.declarations.contains { $0.key.hasPrefix("--") }
            }
            customRulesCacheCount = rules.count
        }
        let env = tbVariableEnvironment(node: node,
                                        customRules: customRulesCache,
                                        rules: rules)
        envCache[key] = env
        return env
    }
    private var ruleIndex: [String: [TBCSSRule]] = [:]
    private var ruleIndexRuleCount = -1

    // The rules that could match this element:
    // every bucket its rightmost-compound key
    // could have filed it under.
    func candidateRules(node: TBNode) -> [TBCSSRule] {
        if ruleIndexRuleCount != rules.count {
            ruleIndex = [:]
            for rule in rules {
                guard let subject = rule.selector.compounds.last
                else { continue }
                let key: String
                if let id = subject.id {
                    key = "i:" + id
                } else if let tag = subject.tag {
                    key = "t:" + tag
                } else if let first = subject.classes.first {
                    key = "c:" + first
                } else {
                    key = "u:"
                }
                ruleIndex[key, default: []].append(rule)
            }
            ruleIndexRuleCount = rules.count
        }
        var out = ruleIndex["u:"] ?? []
        out += ruleIndex["t:" + node.tag] ?? []
        if let id = node.attrs["id"], !id.isEmpty {
            out += ruleIndex["i:" + id] ?? []
        }
        if let classes = node.attrs["class"] {
            for name in classes.split(whereSeparator: { $0.isWhitespace }) {
                out += ruleIndex["c:" + name] ?? []
            }
        }
        return out
    }
    // The second speed repair (0.37.2): the state
    // resolution's candidates. tbResolveStateStyle
    // matches ONLY rules carrying its state flag, so
    // offer it only those rules, by the same index
    // bargain — the flag's own census first (a cached
    // filter of the whole sheet), then the index's
    // buckets, and tbResolveStateStyle still filters
    // by the flag itself, so the offered set only
    // over-includes, never under-includes. The state
    // resolutions were measured doing the full
    // census scan per element instead: against the
    // real Wikipedia "Jesus" article the filtered
    // :hover census is 4 rules of 1,204, and the
    // unfiltered offer made every one of the walk's
    // 41,313 state calls scan them all — 23.78s of
    // one 79.1s first paint in the harness, against
    // 33.17s for the entire resting cascade, which
    // had the index all along.
    private var stateRuleCensus: [TBStateFlag: [TBCSSRule]] = [:]
    private var stateCensusRuleCount = -1
    func stateCandidateRules(node: TBNode) -> [TBCSSRule] {
        if stateCensusRuleCount != rules.count {
            stateRuleCensus = [:]
            stateCensusRuleCount = rules.count
        }
        var out: [TBCSSRule] = []
        for flag in [TBStateFlag.hover, .focus, .active] {
            if let census = stateRuleCensus[flag] {
                out += census
                continue
            }
            let census = candidateRules(node: node).filter {
                tbSelectorHasState($0.selector, flag)
            }
            stateRuleCensus[flag] = census
            out += census
        }
        return out
    }
    var pageBackground: NSColor? = nil
    let out = NSMutableAttributedString()

    // Images (0.9): an <img> seats an attachment in the text
    // as it renders; the pictures are fetched together at
    // the end (finishImages), so the page arrives whole.
    struct TBImageJob {
        let attachment: NSTextAttachment
        let url: String
        let alt: String
        let preferredWidth: CGFloat?
        let preferredHeight: CGFloat?
    }
    var imageJobs: [TBImageJob] = []

    // Background boxes by declaration key, so identical
    // declarations share one box — and one photo fetch.
    var backgroundBoxes: [String: TBBackgroundBox] = [:]

    // Forms (0.13): every form on the page, every typable
    // field, and the stack of forms open at this point of
    // the walk. (HTML forms do not nest, but the walk is
    // recursive, so a stack keeps the bookkeeping honest.)
    var forms: [TBFormSpec] = []
    var fields: [TBFormField] = []
    private var openForms: [Int] = []
    private var nextFieldID = 0

    // Surface edges (0.15): spaceCarry moves a block's
    // before-spacing down to the first paragraph actually
    // flushed beneath it — a container holding only blocks
    // flushes nothing itself, and until now its spacing
    // (a padded wrapper's padding included) vanished from
    // the flow, so surfaces began at their first line of
    // text instead of at their true top edge. The edge
    // stack tracks, per open background-declaring element,
    // the inside space at its surface's top and bottom.
    var spaceCarry: CGFloat = 0
    struct TBSurfaceEdge {
        var color: NSColor?
        var box: TBBackgroundBox?
        var padTop: CGFloat = 0
        var padBottom: CGFloat = 0
        var topCarry: CGFloat = 0
        var topStamped = false
        var bottomCarry: CGFloat = 0
        var lastParaRange: NSRange? = nil
        var lastParaAfter: CGFloat = 0
    }
    var surfaceEdges: [TBSurfaceEdge] = []

    // Layout step four (0.17): the floats and clears the
    // walk met, in document order, for the view to resolve;
    // the floats still waiting on pictures or measuring;
    // and the relative-offset accumulation of the blocks
    // currently open (offsets sum through nesting, as CSS
    // positions them). A renderer inside a float records
    // no events of its own — nested floats simply flow.
    var layoutEvents: [TBLayoutEvent] = []
    // The seat containers whose own node is an
    // anchor (0.37.3), in document order: the
    // render's nested seat specs carry no layout
    // event of their own, so the finished page
    // reports them separately and seat-shaped
    // renderers (sub-renders inside floats and
    // positioned boxes) can hand theirs up.
    var containerLinkSeats: [(kind: String, link: String)] = []
    var insideFloat = false
    var pendingClears: [TBClearSpec] = []
    var floatCount = 0
    var floatImageJobs: [(spec: TBFloatSpec, url: String)] = []
    var pendingBlockFloats: [(spec: TBFloatSpec, sub: TBRenderer)] = []
    var relDX: CGFloat = 0
    var relDY: CGFloat = 0
    var lastFlushRange: NSRange? = nil
    var nominalWidth: CGFloat = 1000
    // Percentage float widths (0.25.0): the horizontal
    // padding of the block ancestors currently open,
    // accumulated by walkBlock the way the relative
    // offsets above are — a floated child's containing
    // block is its parent block's content box, which
    // sits this far inside the column.
    var ancestorPaddingH: CGFloat = 0

    // Percentage container heights (0.30): the
    // definite content height of the block ancestor
    // currently open, when it declared one — a height
    // in points, or a percentage itself resolved
    // against the ancestor above it, the chain CSS
    // keeps. walkBlock pushes each block's own as it
    // opens and restores the parent's at the close;
    // a block declaring no height pushes nil, for
    // its children's percentages have nothing
    // definite to stand on.
    var definiteAncestorHeight: CGFloat? = nil

    // Positioned layout (0.21): the positioned boxes the
    // walk met and what they still wait on — pictures to
    // fetch, contents to measure — and the stack of
    // positioned ancestors currently open, whose ranges
    // an absolutely positioned descendant resolves
    // against. A block-level relative ancestor pushes in
    // walkBlock; a relative span pushes in inline().
    var positionedCount = 0
    var positionedImageJobs: [(spec: TBPositionedSpec, url: String)] = []
    var pendingPositioned: [(spec: TBPositionedSpec, sub: TBRenderer)] = []
    var containingBlocks: [TBContainingBlock] = []

    // The interaction set (0.26): every block's own
    // character range, open while the block is walked —
    // the stack a sticky element reads its containing
    // block (its parent block) from. Blocks inside a
    // painted box record none, as they record no layout
    // events: a sticky there flows plain.
    var blockRanges: [TBContainingBlock] = []

    // Multi-column layout (0.22): the multicolumn blocks
    // the walk met, each with the sub-renderer holding
    // its contents, waiting for the arrivals finish to
    // clean and re-balance them, as block floats wait.
    var pendingColumns: [(spec: TBMultiColumnSpec,
                                  subs: [(part: TBColumnPart, sub: TBRenderer)])] = []

    // The paint & motion set (0.27): the walk's running
    // paint state — the text shadows in force (inherited,
    // as CSS inherits them), whether the block being
    // walked clips its lines unwrapped (white-space:
    // nowrap), the content width an ellipsis block
    // truncates at when the block qualifies, and the
    // child filter a segmented columns sub-renderer
    // walks under, consumed by its first walkBlock.
    var textShadowSetCurrent: TBTextShadowSet? = nil
    var nowrapClips = false
    var ellipsisWidth: CGFloat? = nil
    var columnChildFilter: Set<ObjectIdentifier>? = nil

    // @keyframes rules collected from the page's sheets
    // at the first paint (0.27), by name.
    var keyframes: [String: TBKeyframesRule] = [:]

    // Flexbox (0.24): the flex containers the walk met,
    // each with the sub-renderers holding its items'
    // contents, waiting for the arrivals finish to
    // clean, correct and re-lay them, as block floats
    // wait. Unlike floats and columns, flex containers
    // are also met inside sub-renderers — an item that
    // is itself a flex container, a flex box inside a
    // floated box — where no layout event is recorded
    // and the seat's own attribute stamp carries the
    // spec into the painted contents.
    var pendingFlex: [(spec: TBFlexSpec, subs: [TBRenderer])] = []
    var flexCount = 0

    // Grid (0.25): the grid containers the walk met,
    // each with the sub-renderers holding its items'
    // contents, waiting for the arrivals finish beside
    // the flex containers — the same two-stage life,
    // and the same nesting through painted boxes, the
    // seat's attribute stamp carrying the spec where
    // no layout event is recorded.
    var pendingGrid: [(spec: TBGridSpec, subs: [TBRenderer])] = []
    var gridCount = 0

    // MARK: - Surface edges - live in ChirpyPaint.swift

    // The surface-edge machinery stood here -
    // edgeIndex, noteSurfaceParagraph and
    // closeSurfaceEdges - from the painted
    // boxes' first stage until 0.39.5, when
    // they moved into ChirpyPaint.swift as
    // extensions of TBRenderer, whole and
    // word for word. The split's fifth step -
    // see ChirpyPaint.swift.

    var currentFormID: Int { openForms.last ?? -1 }

    func enterForm(_ node: TBNode) {
        let raw = (node.attrs["action"] ?? "").trimmingCharacters(in: .whitespaces)
        let action = raw.isEmpty ? base
            : (URL(string: raw, relativeTo: URL(string: base))?.absoluteString ?? base)
        let method = (node.attrs["method"] ?? "get").lowercased()
        forms.append(TBFormSpec(id: forms.count, action: action, method: method))
        openForms.append(forms.count - 1)
    }

    func exitForm() {
        if !openForms.isEmpty { openForms.removeLast() }
    }

    // A form remembers its first named submit control: a
    // browser sends that button's name and value along
    // when the form is submitted from the keyboard.
    func noteSubmit(_ node: TBNode) {
        guard currentFormID >= 0, forms[currentFormID].submitName == nil,
              let name = node.attrs["name"], !name.isEmpty else { return }
        forms[currentFormID].submitName = name
        forms[currentFormID].submitValue = node.attrs["value"] ?? ""
    }

    func descendantText(_ node: TBNode) -> String {
        if node.tag == "#text" { return node.text }
        return node.children.map { descendantText($0) }.joined()
    }

    // One <input>, rendered. Text-like inputs seat a field
    // attachment; hidden inputs register silently against
    // their form; submits seat a button attachment;
    // checkboxes and radios draw their state; the rest
    // render as their label until a later step.
    func formControl(_ node: TBNode, font: NSFont,
                             own: [String: String]) -> NSAttributedString {
        let type = (node.attrs["type"] ?? "text").lowercased()
        let name = node.attrs["name"] ?? ""
        let value = node.attrs["value"] ?? ""
        if type == "hidden" {
            if currentFormID >= 0 && !name.isEmpty {
                forms[currentFormID].hidden.append((name: name, value: value))
            }
            return NSAttributedString(string: "")
        }
        if type == "submit" {
            if currentFormID >= 0 {
                noteSubmit(node)
                let label = value.isEmpty ? "Submit" : value
                let attachment = TBSubmitAttachment()
                attachment.formID = currentFormID
                attachment.label = label
                // The interaction set (0.26): the button's
                // style rides on its attachment, and a
                // declared size replaces the label's
                // measure, as a field's declared width does.
                attachment.style = controlStyle(node: node, own: own,
                                                font: font)
                let width = tbLengthValue(own["width"], fontSize: font.pointSize)
                    ?? (CGFloat(label.count) * 8 + 30)
                let height = tbLengthValue(own["height"], fontSize: font.pointSize)
                    ?? 26
                let box = CGRect(x: 0, y: 0,
                                 width: min(max(width, 40), 560),
                                 height: min(max(height, 20), 120))
                attachment.bounds = box
                attachment.image = tbClearSeat(width: box.width, height: box.height)
                return NSAttributedString(attachment: attachment)
            }
            return NSAttributedString(
                string: " [\(value.isEmpty ? "Submit" : value)] ",
                attributes: [.font: font,
                             .foregroundColor: NSColor.secondaryLabelColor])
        }
        if type == "checkbox" || type == "radio" {
            let on = node.attrs["checked"] != nil
            let glyph = type == "checkbox" ? (on ? "\u{2611}" : "\u{2610}")
                                           : (on ? "\u{25C9}" : "\u{25CB}")
            // The interaction set (0.26): the glyph wears
            // its element's color, as its text would.
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if let color = tbParseColor(own["color"]) {
                attrs[.foregroundColor] = color
            }
            return NSAttributedString(string: " \(glyph) ", attributes: attrs)
        }
        if ["text", "search", "password", "email", "url", "tel",
            "number", ""].contains(type) {
            let id = nextFieldID
            nextFieldID += 1
            fields.append(TBFormField(
                id: id, formID: currentFormID, name: name,
                defaultValue: value,
                placeholder: node.attrs["placeholder"] ?? ""))
            let attachment = TBFieldAttachment()
            attachment.fieldID = id
            // The interaction set (0.26): the field's
            // style rides on its attachment, and a
            // declared height replaces the standing
            // field height.
            attachment.style = controlStyle(node: node, own: own,
                                            font: font)
            var width = tbLengthValue(own["width"] ?? node.attrs["width"],
                                      fontSize: font.pointSize)
            if width == nil, let sizeText = node.attrs["size"],
               let size = Double(sizeText) {
                width = CGFloat(size) * 7.5 + 16
            }
            let height = tbLengthValue(own["height"], fontSize: font.pointSize)
                ?? 26
            let box = CGRect(x: 0, y: 0,
                             width: min(max(width ?? 240, 90), 560),
                             height: min(max(height, 20), 120))
            attachment.bounds = box
            attachment.image = tbClearSeat(width: box.width, height: box.height)
            return NSAttributedString(attachment: attachment)
        }
        let label = value.isEmpty ? type : value
        return NSAttributedString(
            string: " [\(label)] ",
            attributes: [.font: font,
                         .foregroundColor: NSColor.secondaryLabelColor])
    }

    // One <option>'s own words (0.31): its text with
    // any nested option or optgroup left out — the
    // parser nests a following <option> inside the
    // one before it, there being no implied close,
    // so a nested option's words belong to its own
    // row — folded the way a browser folds a
    // label's whitespace.
    private func optionLabel(_ node: TBNode) -> String {
        func own(_ n: TBNode) -> String {
            if n.tag == "#text" { return n.text }
            if n.tag == "option" || n.tag == "optgroup" { return "" }
            return n.children.map { own($0) }.joined()
        }
        return own(node)
            .split(whereSeparator: { $0 == " " || $0 == "\n"
                                     || $0 == "\t" || $0 == "\r" })
            .joined(separator: " ")
    }

    // A <select>'s rows (0.31), in document order:
    // options flatten out of whatever nesting the
    // parser left them in, and an <optgroup> first
    // lays down its label as a group row, then its
    // own options. The resting choice is the last
    // option carrying `selected` — the choice a
    // browser's parser leaves standing — or, for a
    // `multiple` select, its first chosen one; with
    // none chosen, the first real option rests.
    private func selectRows(_ node: TBNode)
        -> (rows: [TBSelectOption], selected: Int) {
        var rows: [TBSelectOption] = []
        var marked: [Int] = []
        func collect(_ n: TBNode) {
            for child in n.children {
                if child.tag == "optgroup" {
                    let label = (child.attrs["label"] ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty {
                        rows.append(TBSelectOption(label: label, value: "",
                                                   isGroup: true))
                    }
                    collect(child)
                } else if child.tag == "option" {
                    let label = optionLabel(child)
                    rows.append(TBSelectOption(
                        label: label,
                        value: child.attrs["value"] ?? label,
                        isGroup: false))
                    if child.attrs["selected"] != nil {
                        marked.append(rows.count - 1)
                    }
                    collect(child)
                } else {
                    collect(child)
                }
            }
        }
        collect(node)
        var selected = node.attrs["multiple"] != nil
            ? marked.first : marked.last
        if selected == nil {
            selected = rows.firstIndex { !$0.isGroup }
        }
        return (rows, selected ?? -1)
    }

    // One <select>, rendered (0.31): it registers
    // as a form field whose standing value is its
    // resting choice's, and seats a popup
    // attachment the view makes live. Its width is
    // its widest row's measure in the element's
    // font, with room for the popup's own chrome,
    // unless a size is declared.
    func formSelect(_ node: TBNode, font: NSFont,
                            own: [String: String]) -> NSAttributedString {
        let name = node.attrs["name"] ?? ""
        let (rows, selected) = selectRows(node)
        let id = nextFieldID
        nextFieldID += 1
        fields.append(TBFormField(
            id: id, formID: currentFormID, name: name,
            defaultValue: selected >= 0 ? rows[selected].value : "",
            placeholder: ""))
        let attachment = TBSelectAttachment()
        attachment.fieldID = id
        attachment.options = rows
        attachment.selectedIndex = selected
        attachment.style = controlStyle(node: node, own: own,
                                        font: font)
        var width = tbLengthValue(own["width"] ?? node.attrs["width"],
                                  fontSize: font.pointSize)
        if width == nil {
            let widest = rows.map { $0.label }
                .max(by: { $0.count < $1.count }) ?? ""
            width = CGFloat(widest.count) * (font.pointSize * 0.55) + 44
        }
        let height = tbLengthValue(own["height"], fontSize: font.pointSize)
            ?? 26
        let box = CGRect(x: 0, y: 0,
                         width: min(max(width ?? 120, 60), 560),
                         height: min(max(height, 20), 120))
        attachment.bounds = box
        attachment.image = tbClearSeat(width: box.width, height: box.height)
        return NSAttributedString(attachment: attachment)
    }

    // One <textarea>, rendered (0.31): a form field
    // whose standing value is its seed — the
    // element's own text, decoded once here (the
    // parser kept it raw), with the one leading
    // newline HTML drops — seating an editor
    // attachment the view makes live. rows and
    // cols size the seat by the element's font
    // cells, a declared size winning, as a
    // field's does.
    func formTextArea(_ node: TBNode, font: NSFont,
                              own: [String: String]) -> NSAttributedString {
        let name = node.attrs["name"] ?? ""
        var seed = tbDecodeEntities(descendantText(node))
        if seed.hasPrefix("\r\n") { seed = String(seed.dropFirst(2)) }
        else if seed.hasPrefix("\n") { seed = String(seed.dropFirst()) }
        let id = nextFieldID
        nextFieldID += 1
        fields.append(TBFormField(
            id: id, formID: currentFormID, name: name,
            defaultValue: seed,
            placeholder: node.attrs["placeholder"] ?? ""))
        let attachment = TBTextAreaAttachment()
        attachment.fieldID = id
        attachment.style = controlStyle(node: node, own: own,
                                        font: font)
        let rows = max(Int(node.attrs["rows"] ?? "") ?? 2, 1)
        let cols = max(Int(node.attrs["cols"] ?? "") ?? 20, 4)
        var width = tbLengthValue(own["width"] ?? node.attrs["width"],
                                  fontSize: font.pointSize)
        if width == nil {
            width = CGFloat(cols) * (font.pointSize * 0.6) + 28
        }
        var height = tbLengthValue(own["height"] ?? node.attrs["height"],
                                   fontSize: font.pointSize)
        if height == nil {
            height = CGFloat(rows) * (font.pointSize * 1.45) + 18
        }
        let box = CGRect(x: 0, y: 0,
                         width: min(max(width ?? 240, 90), 700),
                         height: min(max(height ?? 60, 34), 480))
        attachment.bounds = box
        attachment.image = tbClearSeat(width: box.width, height: box.height)
        return NSAttributedString(attachment: attachment)
    }

    // The background box stood here - the
    // element's declared background layers,
    // read into a TBBackgroundBox - until
    // 0.39.5, when it moved into
    // ChirpyPaint.swift with the rest of the
    // paint system, whole and word for word.
    // The split's fifth step - see
    // ChirpyPaint.swift.

    init(base: String) { self.base = base }

    // The Mac's own appearance decides prefers-color-scheme,
    // exactly as it does for a real browser on this machine.
    var darkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // The finishing set (0.23): the render's wider knowledge.
    // visitedURLs is the session's — the URLs this window has
    // loaded, handed down by the model; mediaWidth is the
    // window's text width as the load began. Sub-renderers
    // inherit both, as they inherit the rules.
    var visitedURLs: Set<String> = []
    var mediaWidth: CGFloat? = nil

    // The system's Reduce Motion setting, read from
    // NSWorkspace's accessibility values — the same source
    // the Finder and Dock honor.
    var reducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // Whether any rule in this sheet carries :hover at all —
    // computed once; most pages have none, and the walk then
    // does no hover work for them.
    lazy var hoverRulePresent: Bool = rules.contains {
        tbSelectorHasHover($0.selector)
    }

    // The interaction set (0.26): the same census for
    // :focus and :active — most pages have neither, and
    // the walk then does no state work for them.
    lazy var focusRulePresent: Bool = rules.contains {
        tbSelectorHasState($0.selector, .focus)
    }

    lazy var activeRulePresent: Bool = rules.contains {
        tbSelectorHasState($0.selector, .active)
    }

    // Layout step two: find the page's own centered column —
    // the shallowest element capped by width or max-width
    // whose side margins are auto (the classic
    // `width: min(100% - 36px, 1120px); margin: 0 auto`), and
    // return the text width inside it (the cap less its own
    // horizontal padding, pages here being border-box).
    // Nil when the page simply flows full-width.
    func columnTextWidth(root: TBNode) -> CGFloat? {
        var best: (depth: Int, width: CGFloat)? = nil
        func visit(_ node: TBNode, depth: Int) {
            if node.tag != "#text" && node.tag != "document" {
                let decls = resolvedStyle(node: node)
                var cap: CGFloat? = nil
                for prop in ["max-width", "width"] {
                    if let raw = decls[prop], let value = tbFixedCap(raw) {
                        cap = value
                        break
                    }
                }
                if let cap = cap, cap >= 480 {
                    let margins = tbBoxValues(decls, "margin")
                    let inlineAuto = (decls["margin-inline"] ?? "")
                        .lowercased().contains("auto")
                    if (margins[1].lowercased() == "auto"
                            && margins[3].lowercased() == "auto") || inlineAuto {
                        let padding = tbBoxValues(decls, "padding")
                        let padL = tbLengthValue(padding[3], fontSize: 14) ?? 0
                        let padR = tbLengthValue(padding[1], fontSize: 14) ?? 0
                        let textWidth = cap - padL - padR
                        if textWidth >= 240 {
                            if let current = best {
                                if depth < current.depth
                                    || (depth == current.depth && textWidth > current.width) {
                                    best = (depth, textWidth)
                                }
                            } else {
                                best = (depth, textWidth)
                            }
                        }
                    }
                }
            }
            for child in node.children {
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return best?.width
    }

    // An element's declarations with var() references resolved
    // against its inherited custom properties.
    func resolvedStyle(node: TBNode) -> [String: String] {
        // :link / :visited (0.23): stamp the anchor's visited
        // state before the cascade reads it — the window's
        // session set, resolved against this page's base.
        if node.tag == "a", let href = node.attrs["href"], !href.isEmpty {
            let absolute = URL(string: href, relativeTo: URL(string: base))?
                .absoluteString ?? href
            node.linkVisited = visitedURLs.contains(absolute)
        }
        // The speed stage (0.36): a walk asks for an
        // element's style many times; the answer
        // cannot change while the walk stands, so
        // it is remembered. The visited stamp above
        // still lands first, every time.
        let cacheKey = ObjectIdentifier(node)
        if let remembered = styleCache[cacheKey] { return remembered }
        let raw = tbResolveStyle(node: node, rules: candidateRules(node: node))
        if raw.isEmpty {
            styleCache[cacheKey] = raw
            return raw
        }
        let env = variableEnvironment(node: node)
        var out: [String: String] = [:]
        for (name, value) in raw {
            if name.hasPrefix("--") { continue }
            if let resolved = tbSubstituteVars(value, env: env) {
                out[name] = resolved
            }
        }
        // A font: that arrived through var() expands now
        // that its value is concrete (0.23).
        let resolved = tbExpandDeferredFont(out)
        styleCache[cacheKey] = resolved
        return resolved
    }

    // One state's declarations (0.23; all three states
    // since 0.26), var()-resolved like the resting style.
    // What the view paints from them is
    // tbHoverPaintAttrs' paint — never layout; what a
    // live form control wears from them is read by
    // controlStyle below.
    func resolvedStateStyle(node: TBNode, flag: TBStateFlag) -> [String: String] {
        // Remembered like the resting style (0.36),
        // under the state beside the element.
        let cacheKey = "\(ObjectIdentifier(node))|\(flag)"
        if let remembered = stateCache[cacheKey] { return remembered }
        let raw = tbResolveStateStyle(node: node,
                                      rules: stateCandidateRules(node: node),
                                      flag: flag)
        if raw.isEmpty {
            stateCache[cacheKey] = raw
            return raw
        }
        let env = variableEnvironment(node: node)
        var out: [String: String] = [:]
        for (name, value) in raw {
            if name.hasPrefix("--") { continue }
            if let resolved = tbSubstituteVars(value, env: env) {
                out[name] = resolved
            }
        }
        stateCache[cacheKey] = out
        return out
    }

    // The element's hover declarations (0.23), var()-resolved
    // like the resting style.
    func resolvedHoverStyle(node: TBNode) -> [String: String] {
        resolvedStateStyle(node: node, flag: .hover)
    }

    // The element's focus declarations (0.26).
    func resolvedFocusStyle(node: TBNode) -> [String: String] {
        resolvedStateStyle(node: node, flag: .focus)
    }

    // The element's active declarations (0.26).
    func resolvedActiveStyle(node: TBNode) -> [String: String] {
        resolvedStateStyle(node: node, flag: .active)
    }

    // MARK: - Paint & motion - lives in ChirpyPaint.swift

    // TBRenderer's paint & motion country
    // stood here - the shadow, transform,
    // opacity, transition and animation
    // parsing, the hover, focus and active
    // paint styles, the image and background
    // finishes, the first paint and the
    // arrivals finish, and the walk itself -
    // from 0.27's stage until 0.39.5, when it
    // moved into ChirpyPaint.swift as
    // extensions of TBRenderer, whole and
    // word for word. The split's fifth step -
    // see ChirpyPaint.swift.


    // MARK: - Layout regions - live in ChirpyLayout.swift

    // TBRenderer's layout regions stood here -
    // positioned layout (0.17), multi-column
    // layout (0.22), flexbox (0.24), grid
    // (0.25), and positioned layout (0.21) -
    // from their stages until 0.39.4, when
    // they moved into ChirpyLayout.swift as
    // extensions of TBRenderer, whole and word
    // for word. The split's fourth step - see
    // ChirpyLayout.swift.
}

// A <meta http-equiv="refresh"> sends the reader onward
// after a pause — many sites (Google's search stub among
// them) are nothing but that send-on. Return the resolved
// target, or nil when the page stays put.
func tbMetaRefreshTarget(root: TBNode, base: String) -> String? {
    if root.tag == "meta",
       (root.attrs["http-equiv"] ?? "").lowercased() == "refresh",
       let content = root.attrs["content"] {
        for part in content.split(separator: ";") {
            let piece = part.trimmingCharacters(in: .whitespaces)
            if piece.lowercased().hasPrefix("url=") {
                var target = String(piece.dropFirst(4))
                    .trimmingCharacters(in: .whitespaces)
                if (target.hasPrefix("'") && target.hasSuffix("'"))
                    || (target.hasPrefix("\"") && target.hasSuffix("\"")) {
                    target = String(target.dropFirst().dropLast())
                }
                if !target.isEmpty {
                    return URL(string: target, relativeTo: URL(string: base))?.absoluteString
                }
            }
        }
    }
    for child in root.children {
        if let found = tbMetaRefreshTarget(root: child, base: base) {
            return found
        }
    }
    return nil
}

// The noscript door (0.37): a page that sends
// scriptless readers onward folds its refresh
// inside <noscript> — DuckDuckGo's redirector
// is exactly that shape. The parser sets
// noscript subtrees aside whole, so the folded
// tag never enters the tree the scan above
// walks. Here each noscript span's raw text is
// parsed on its own and asked the same
// question. The render asks only after the
// page's own scripts have had their say:
// noscript is the fallback for a reader
// without scripts, not a rival to them.
func tbNoscriptRefreshTarget(html: String, base: String) -> String? {
    var searchFrom = html.startIndex
    while let open = html.range(of: "<noscript",
                                options: .caseInsensitive,
                                range: searchFrom..<html.endIndex) {
        guard let close = html.range(of: "</noscript",
                                     options: .caseInsensitive,
                                     range: open.upperBound..<html.endIndex)
        else { return nil }
        let span = String(html[open.upperBound..<close.lowerBound])
        if let found = tbMetaRefreshTarget(root: tbParse(html: span),
                                           base: base) {
            return found
        }
        searchFrom = close.upperBound
    }
    return nil
}

func tbScriptBounceTargets(html: String, base: String) -> [String] {
    var found: [String] = []
    func offer(_ raw: String) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("http") else { return }
        let absolute = URL(string: value, relativeTo: URL(string: base))?.absoluteString ?? value
        if !found.contains(absolute) { found.append(absolute) }
    }
    if let mark = html.range(of: "uddg=") {
        let tail = html[mark.upperBound...]
        var raw = ""
        for ch in tail {
            if ch == "&" || ch == "\"" || ch == "'" || ch == "<" || ch.isWhitespace { break }
            raw.append(ch)
        }
        if let decoded = raw.removingPercentEncoding { offer(decoded) }
    }
    for marker in ["location.replace(", "location.href =", "location.href=",
                   "location = ", "location="] {
        var searchFrom = html.startIndex
        while let hit = html.range(of: marker, range: searchFrom..<html.endIndex) {
            let rest = html[hit.upperBound...]
            if let quote = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                let after = rest.index(after: quote)
                if after < rest.endIndex,
                   let close = rest[after...].firstIndex(of: rest[quote]) {
                    offer(String(rest[after..<close]))
                }
            }
            searchFrom = hit.upperBound
        }
    }
    return Array(found.prefix(3))
}

// First paint (0.20): everything the window needs to
// show a page the moment it is walked — and, in
// arrivalsPending, whether pieces of it are still out
// fetching. The body is the renderer's own string: the
// finish passes keep working on it after the hand-off,
// which is how the window's re-install at arrivals time
// sees the finished page.
struct TBFirstPaint {
    let title: String
    let body: NSAttributedString
    let pageBackground: NSColor?
    let columnWidth: CGFloat?
    let forms: [TBFormSpec]
    let fields: [TBFormField]
    let landedURL: String
    let layoutEvents: [TBLayoutEvent]
    let arrivalsPending: Bool
    // JavaScript (0.33): what the page's scripts
    // said to the console, and their errors — the
    // window shows them on the status line.
    let consoleLines: [String]
    // Developer tools (0.35): the landed page
    // itself, kept for the console and the
    // Inspector — its tree, its scope, and (once
    // the walk below has run) its renderer.
    let session: TBPageSession
}

// Render a page in two stages: onFirstPaint is called
// (on the main actor) with the walked page as soon as
// it exists, and the same value is returned once every
// arrival has landed in it. The finishing set (0.23)
// hands the renderer two things only the window knows:
// the session's visited URLs (for :link / :visited) and
// the text area's width as the load began (for @media).
// The speed stage (0.36) adds the window's own fetch
// time, so the load's timing entry can speak of the
// whole road.
func tbRenderPage(html: String, base: String,
                  visited: Set<String> = [],
                  mediaWidth: CGFloat? = nil,
                  fetchSeconds: Double = 0,
                  onFirstPaint: (TBFirstPaint) -> Void) async -> TBFirstPaint {
    return await tbRenderFollowingRefresh(html: html, base: base, depth: 0,
                                          visited: visited,
                                          mediaWidth: mediaWidth,
                                          fetchSeconds: fetchSeconds,
                                          onFirstPaint: onFirstPaint)
}

// The JavaScript console's repaint (0.35):
// walk the landed page's kept tree again after
// console code changed it, and hand the window
// a fresh paint of the same page — no fetch,
// no re-parse, no second run of the page's
// scripts; the scope the console worked in is
// the scope that stays. Arrivals work as they
// do for a load: the walked page now, the
// finished page when its pictures have landed.
func tbRepaintPage(session: TBPageSession,
                   visited: Set<String> = [],
                   mediaWidth: CGFloat? = nil,
                   onFirstPaint: (TBFirstPaint) -> Void) async -> TBFirstPaint {
    let renderer = TBRenderer(base: session.base)
    renderer.visitedURLs = visited
    renderer.mediaWidth = mediaWidth
    let body = await renderer.renderFirstPaint(root: session.root)
    session.renderer = renderer
    let title = session.shownTitle
    let paint = TBFirstPaint(
        title: title.isEmpty ? session.base : title,
        body: body,
        pageBackground: renderer.pageBackground,
        columnWidth: renderer.columnTextWidth(root: session.root),
        forms: renderer.forms,
        fields: renderer.fields,
        landedURL: session.base,
        layoutEvents: renderer.layoutEvents,
        arrivalsPending: renderer.hasPendingArrivals,
        consoleLines: [],
        session: session)
    await MainActor.run { onFirstPaint(paint) }
    await renderer.finishArrivals()
    return paint
}

private func tbRenderFollowingRefresh(html: String, base: String, depth: Int,
                                      visited: Set<String>,
                                      mediaWidth: CGFloat?,
                                      fetchSeconds: Double,
                                      onFirstPaint: (TBFirstPaint) -> Void)
    async -> TBFirstPaint {
    var title = tbExtractTitle(html: html)
    let parseStart = Date()
    let tree = tbParse(html: html)
    let parseSeconds = Date().timeIntervalSince(parseStart)
    if depth < 3, let target = tbMetaRefreshTarget(root: tree, base: base),
       target != base {
        let hopStart = Date()
        if let (newBase, newHTML) = try? await tbFetch(urlString: target) {
            // The refresh hop's fetch joins the
            // load's fetch time, and the deeper
            // render speaks for the page that
            // finally lands.
            return await tbRenderFollowingRefresh(
                html: newHTML, base: newBase,
                depth: depth + 1,
                visited: visited,
                mediaWidth: mediaWidth,
                fetchSeconds: fetchSeconds
                    + Date().timeIntervalSince(hopStart),
                onFirstPaint: onFirstPaint)
        }
    }
    // Scripts before the walk (0.37.1): the session
    // exists from the start, and the page's scripts
    // run against the kept tree BEFORE anything is
    // painted, so a page whose scripts send the
    // reader onward — or rewrite the page — is
    // never handed to the window as a settled page
    // first. The paint-first order (0.36) handed
    // the doorway over first: the window installed
    // its address in the bar, cleared the progress
    // and stood the load down as finished, and only
    // then did the script's send-on begin its fetch.
    // On a slow destination the reader sat on the
    // white doorway of a load the app itself called
    // done, and any touch there began a new load
    // whose generation guard silently discarded
    // the destination when it finally landed. That
    // is how a live DuckDuckGo result click settled
    // on the white /l/ page. The script stage keeps
    // its honest budget (3s, 0.36), so the wait
    // before paint is bounded the way a real
    // browser's parser-blocking scripts bound it,
    // and the single walk below paints the page
    // the scripts left behind — the order this
    // renderer kept from 0.33 to 0.35, restored.
    let session = tbMakeSession(root: tree, base: base, initialTitle: title)
    let scriptStart = Date()
    let js = await tbRunScripts(session: session)
    let scriptSeconds = Date().timeIntervalSince(scriptStart)
    // Script navigation (0.37): a script that
    // sends the reader onward — DuckDuckGo's
    // window.parent.location.replace is the
    // shape that named the need — is followed
    // the way the refresh above is followed:
    // the same hop limit, the same Shield-
    // checked fetch, the hop's fetch time
    // joining the load's account, and the
    // deeper render speaking for the page that
    // finally lands, so the address bar and
    // the history name the destination, never
    // the doorway.
    if depth < 3, let target = js.navigationTarget, target != base {
        let hopStart = Date()
        if let (newBase, newHTML) = try? await tbFetch(urlString: target) {
            return await tbRenderFollowingRefresh(
                html: newHTML, base: newBase,
                depth: depth + 1,
                visited: visited,
                mediaWidth: mediaWidth,
                fetchSeconds: fetchSeconds
                    + Date().timeIntervalSince(hopStart),
                onFirstPaint: onFirstPaint)
        }
    }
    // The noscript door (0.37): the scripts had
    // their say and the reader is still here —
    // now the folded refresh inside <noscript>
    // is asked, and followed down the same road.
    if depth < 3,
       let target = tbNoscriptRefreshTarget(html: html, base: base),
       target != base {
        let hopStart = Date()
        if let (newBase, newHTML) = try? await tbFetch(urlString: target) {
            return await tbRenderFollowingRefresh(
                html: newHTML, base: newBase,
                depth: depth + 1,
                visited: visited,
                mediaWidth: mediaWidth,
                fetchSeconds: fetchSeconds
                    + Date().timeIntervalSince(hopStart),
                onFirstPaint: onFirstPaint)
        }
    }
    if let override = js.titleOverride { title = override }
    // One walk, one hand-off (0.37.1): the tree
    // the scripts left behind is walked once, and
    // the single paint carries the script stage's
    // console lines and the load's timing with it,
    // so the console receives each exactly once.
    // (The 0.36 shape walked twice when scripts
    // changed the page; that second walk is gone
    // with the paint-first order it served.)
    let renderer = TBRenderer(base: base)
    renderer.visitedURLs = visited
    renderer.mediaWidth = mediaWidth
    let layoutStart = Date()
    let body = await renderer.renderFirstPaint(root: tree)
    let layoutSeconds = Date().timeIntervalSince(layoutStart)
    session.renderer = renderer
    let timingLine = "Timing: " + [
        String(format: "fetch %.2fs", fetchSeconds),
        String(format: "parse %.2fs", parseSeconds),
        String(format: "style+layout %.2fs", layoutSeconds),
        String(format: "scripts %.2fs", scriptSeconds),
        String(format: "total %.2fs",
               fetchSeconds + parseSeconds + layoutSeconds
                + scriptSeconds),
    ].joined(separator: " \u{00B7} ")
    let paint = TBFirstPaint(
        title: title.isEmpty ? base : title,
        body: body,
        pageBackground: renderer.pageBackground,
        columnWidth: renderer.columnTextWidth(root: tree),
        forms: renderer.forms,
        fields: renderer.fields,
        landedURL: base,
        layoutEvents: renderer.layoutEvents,
        arrivalsPending: renderer.hasPendingArrivals,
        consoleLines: js.consoleLines + [timingLine],
        session: session)
    // A script-only send-on (a search engine's click
    // bounce, say) renders as a black void. When the
    // final walk found no words at all, offer the
    // destinations the page's own code names, plainly
    // labelled — an honest door instead of an empty
    // room. The check stands after the scripts, as
    // it did when they ran before the walk: a page
    // whose scripts write its words is no bounce.
    let visible = (paint.body.string as NSString)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if visible.isEmpty {
        let targets = tbScriptBounceTargets(html: html, base: base)
        if !targets.isEmpty {
            let notice = NSMutableAttributedString()
            notice.append(NSAttributedString(
                string: "This page needs JavaScript to move on\n\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 17),
                             .foregroundColor: NSColor.labelColor]))
            notice.append(NSAttributedString(
                string: "Chirpy's JavaScript is a first slice — it runs a page's own code, but it has no event handlers, timers, or network calls yet, so a page that moves only through those can still strand it. The destination written in this page's code is:\n\n",
                attributes: [.font: NSFont.systemFont(ofSize: 14),
                             .foregroundColor: NSColor.labelColor]))
            for target in targets {
                notice.append(NSAttributedString(
                    string: target + "\n",
                    attributes: [.font: NSFont.systemFont(ofSize: 14),
                                 .link: target,
                                 .foregroundColor: NSColor.linkColor,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue]))
            }
            let noticePaint = TBFirstPaint(
                title: title.isEmpty ? "This page needs JavaScript" : title,
                body: notice, pageBackground: nil, columnWidth: nil,
                forms: [], fields: [], landedURL: base, layoutEvents: [],
                arrivalsPending: false,
                consoleLines: paint.consoleLines,
                session: session)
            await MainActor.run { onFirstPaint(noticePaint) }
            return noticePaint
        }
    }
    await MainActor.run { onFirstPaint(paint) }
    await renderer.finishArrivals()
    return paint
}
