//
//  ChirpyJS.swift
//  Chirpy Browser — engine 0.42 (Swift)
//
//  Chirpy's JavaScript interpreter: its values
//  and rooms, its lexer, its parser, its
//  evaluator, its bridge to the parsed page,
//  and the console's road in. Ours from the
//  ground up, the way the rest of the engine
//  is — no JavaScriptCore, no borrowed engine.
//
//  This file was ChirpyEngine.swift's
//  JavaScript section — everything from
//  `enum TBJSValue` down to the end of
//  tbConsoleEval — until 0.39.1, when it moved
//  here whole: the first step of splitting the
//  engine into files of their own, at Tyler's
//  direction, so each part of the codebase can
//  be fixed and built quicker. Nothing in the
//  move changed a word of the interpreter
//  itself; the section intro that stood over
//  it in the engine file stands below, as it
//  was written. ChirpyEngine.swift keeps a
//  short marker where the section lived,
//  pointing here.
//
//  The interpreter's own account of itself —
//  what each stage built (0.33's first slice,
//  0.38's patterns, templates and guarding,
//  0.39's modern shapes) and the gaps it names
//  on purpose — stays in two places, as it
//  always has: the engine header's bullets in
//  ChirpyEngine.swift, and the README's stage
//  sections. The drills are a suite now, and
//  stay one: js-suite.html opens every stage's
//  page, and no stage is done until the whole
//  suite passes on Tyler's Mac.
//
//  Public domain (Unlicense), like the rest
//  of Chirpy.
//

import Foundation

//
// The interpreter is ours from the ground up, the
// way the rest of the engine is: a lexer, a
// parser, and an evaluator, with a small bridge
// to the parsed page. Its honest scope is in the
// engine header's 0.33 bullet; the drill
// js-test.html promises each piece of it. The
// second stage (0.38) — patterns, templates,
// try/catch, `new` — has its bullet there and
// its own drill, js2-test.html.

enum TBJSValue {
    case undefined
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([TBJSValue])
    case object([String: TBJSValue])
    // JavaScript third stage (0.39): a class
    // instance — its own fields in a reference
    // box, so a write through one name is seen
    // through every name that holds it, and the
    // box carries the class it was built from —
    // and a class itself, a value a name can
    // hold, `new` can build from, and
    // `instanceof` can ask about.
    case instance(TBJSInstanceBox)
    case classDef(TBJSClassBox)
    case function(TBJSFunc)
    case native(String)
    case element(TBNode)
    case document
    case console
    case window
    case location
    // JavaScript sixth stage (0.42): the
    // Math face — one built-in object of
    // constants and reckoning functions,
    // standing in the globals the way the
    // console stands in them.
    case math
    // JavaScript second stage (0.38): a regular
    // expression — its pattern, its flags, and
    // the index its next exec or test starts
    // from under the g or y flag (its lastIndex).
    case regex(String, String, Int)
}

// A value held by reference (0.39): an arrow's
// captured `this` rides in one of these, so the
// function type and the value type stay free of
// each other.
final class TBJSBoxedValue {
    var value: TBJSValue
    init(_ value: TBJSValue) { self.value = value }
}

struct TBJSFunc {
    var params: [TBJSParam]
    var body: [TBJSStmt]
    var env: TBJSEnv
    // JavaScript third stage (0.39): an arrow
    // function keeps the `this` of the room it
    // was written in; a plain function keeps
    // nil here and takes the `this` of its call
    // site, as it always has. The value rides
    // in a small box — a class — because a
    // function value cannot hold another value
    // outright without the two types chasing
    // their own tail.
    var capturedThis: TBJSBoxedValue? = nil
    // An arrow whose body is one expression
    // answers that expression's value without a
    // written return (the body's one statement
    // is an expression statement wearing this).
    var expressionBody = false
    // JavaScript third stage (0.39): the class
    // a method or constructor belongs to, when
    // the function is one. The copies handed
    // out at a call or a member read carry it —
    // it is how `super` knows the room it was
    // written in — while the originals a class
    // box stores keep nil, so no class box ever
    // holds a road back into itself.
    var classHome: TBJSClassBox? = nil
    // A class's own constructor, marked when
    // the building hands it out: `super(...)`
    // may stand only in one of these.
    var isClassConstructor = false
    // JavaScript fifth stage (0.41): a static
    // member — a method or an accessor living
    // on the class's own face — marked when
    // the class face hands it out, so the
    // frame it lays down knows `super` inside
    // it climbs the static road.
    var isStatic = false
}

// JavaScript third stage (0.39): a class as
// the engine keeps it — its name, the class it
// extends (nil for a root class), its
// constructor's function if it declared one,
// and its methods by name. The methods are
// looked up through this box at every read, so
// an instance carries its class, not copies of
// its methods.
final class TBJSClassBox {
    var name: String
    var parent: TBJSClassBox?
    var ctor: TBJSFunc? = nil
    var methods: [String: TBJSFunc] = [:]
    // JavaScript fifth stage (0.41): what
    // lives on the class's own face — its
    // static methods, its static fields (the
    // values themselves, reckoned once when
    // the class is declared), and the
    // accessor pairs of both faces:
    // `accessors` serve the instances,
    // `staticAccessors` the class itself.
    // Reads and writes walk the class road
    // for all of them, the way they always
    // have for methods.
    var statics: [String: TBJSFunc] = [:]
    var staticFields: [String: TBJSValue] = [:]
    var accessors: [String: TBJSAccessor] = [:]
    var staticAccessors: [String: TBJSAccessor] = [:]
    init(name: String, parent: TBJSClassBox? = nil) {
        self.name = name
        self.parent = parent
    }
}

// JavaScript fifth stage (0.41): one
// accessor pair under a single name — a
// getter a read calls, a setter a write
// calls, either standing alone if its
// partner was never written. A read of a
// name whose pair holds no getter answers
// undefined; a write to a name whose pair
// holds no setter is silently set aside —
// the sloppy-mode answers, named in the
// README.
struct TBJSAccessor {
    var getter: TBJSFunc? = nil
    var setter: TBJSFunc? = nil
}

// A class instance's own fields, held by
// reference (0.39): the instance value can be
// copied from hand to hand the way every value
// here is, and every hand still writes the
// same fields — the way an object in the
// language behaves, and the way this engine's
// plain dictionary objects, which are copies,
// do not.
final class TBJSInstanceBox {
    var fields: [String: TBJSValue] = [:]
    var klass: TBJSClassBox
    init(klass: TBJSClassBox) { self.klass = klass }
}

// JavaScript third stage (0.39): one declared
// parameter — a name, an optional default the
// caller may leave unwritten, and whether it
// gathers the road's remaining arguments into
// an array (a rest parameter, always last).
// JavaScript fourth stage (0.40): a parameter
// may instead carry a destructuring pattern,
// which the argument is opened into — the
// name then stands empty and is never read.
struct TBJSParam {
    var name: String = ""
    var pattern: TBJSPattern? = nil
    var `default`: TBJSExpr? = nil
    var isRest = false
}

// JavaScript fifth stage (0.41): an
// accessor as the parser gathers it — a
// getter's shape, a setter's shape, or one
// of each merged under a single name.
struct TBJSAccessorParts {
    var getter: ([TBJSParam], [TBJSStmt])? = nil
    var setter: ([TBJSParam], [TBJSStmt])? = nil
}

// JavaScript fifth stage (0.41): a class
// body as the parser gathers it — the
// constructor and the instance methods, as
// before, and now the class face's own
// members: static methods, static fields
// with the expressions that will reckon
// them once when the class is declared,
// and the accessor pairs of both faces.
struct TBJSClassParts {
    var ctor: ([TBJSParam], [TBJSStmt])? = nil
    var methods: [(String, [TBJSParam], [TBJSStmt])] = []
    var statics: [(String, [TBJSParam], [TBJSStmt])] = []
    var staticFields: [(String, TBJSExpr?)] = []
    var accessors: [(String, TBJSAccessorParts)] = []
    var staticAccessors: [(String, TBJSAccessorParts)] = []
}

// One name, one standing on a class face
// (0.41): when a member is written under a
// name already standing on its face, the
// earlier member is forgotten outright, as
// the language has it — the one exception
// is an accessor's two halves, which merge
// instead (see tbJSMergeAccessor).
func tbJSForgetClassMember(_ parts: inout TBJSClassParts,
                           _ member: String,
                           statics staticFace: Bool) {
    if staticFace {
        parts.statics.removeAll { $0.0 == member }
        parts.staticFields.removeAll { $0.0 == member }
        parts.staticAccessors.removeAll { $0.0 == member }
    } else {
        parts.methods.removeAll { $0.0 == member }
        parts.accessors.removeAll { $0.0 == member }
    }
}

// An accessor's halves merge under their
// name (0.41): a get written after a set (or
// the other way round) joins the pair
// already standing, and a half rewritten
// replaces its own half.
func tbJSMergeAccessor(
    _ list: inout [(String, TBJSAccessorParts)],
    _ member: String, _ word: String,
    _ shape: ([TBJSParam], [TBJSStmt])) {
    var pair = list.first(where: { $0.0 == member })?.1
        ?? TBJSAccessorParts()
    if word == "get" {
        pair.getter = shape
    } else {
        pair.setter = shape
    }
    list.removeAll { $0.0 == member }
    list.append((member, pair))
}

// JavaScript fourth stage (0.40): a
// destructuring pattern — the shape a value is
// opened into, in a declaration, an assignment,
// a parameter, or a for-of head. A name binds;
// a target writes through a member or index
// road (assignments only — a declaration that
// tries to write a member is refused when it
// runs); the two bracket shapes open an array
// or an object piece by piece; and a defaulted
// pattern fills an undefined piece from its
// expression, reckoned where the pattern
// stands, so earlier pieces may be read in it.
indirect enum TBJSPattern {
    case name(String)
    case target(TBJSExpr)
    case array([TBJSPatternItem])
    case object([TBJSPatternProp])
    case defaulted(TBJSPattern, TBJSExpr)
}

// One piece of an array pattern (0.40): a hole
// skips its place, an item opens its piece, and
// a rest — always last — gathers what remains
// into a fresh array for its own pattern.
enum TBJSPatternItem {
    case hole
    case item(TBJSPattern)
    case rest(TBJSPattern)
}

// One piece of an object pattern (0.40): a
// named piece reads that property into its
// pattern, and a rest — always last — gathers
// the properties no named piece took into a
// fresh object for its own pattern.
enum TBJSPatternProp {
    case prop(String, TBJSPattern)
    case rest(TBJSPattern)
}

// One declarator of a let/const list (0.40): a
// plain name with its first value, or a whole
// pattern with the expression it opens — the
// two dresses a lexical list may mix.
enum TBJSLexicalItem {
    case name(String, TBJSExpr?)
    case pattern(TBJSPattern, TBJSExpr)
}

// A for-of head wearing a pattern (0.40): how
// each round's piece is handed out — written
// into bindings that already stand, declared
// with var in the loop's function room, or
// declared with let/const in a fresh room for
// every round, as the plain-name heads do.
enum TBJSForOfKind {
    case assign, declareVar, declareLet, declareConst
}

// How a pattern's names are planted (0.40): an
// assignment writes where the names already
// live; a var declaration plants them in the
// nearest function room; a parameter plants
// them in the call's room; and a let/const
// declaration initializes the bindings its
// room planted when the room opened.
enum TBJSBindMode {
    case assign
    case declareVar
    case declareParam
    case declareLexical(Bool)
}

final class TBJSEnv {
    var vars: [String: TBJSValue] = [:]
    var parent: TBJSEnv?
    // JavaScript third stage (0.39): what kind
    // of binding each name in this room is, and
    // whether a let/const binding has been
    // initialized yet. A name absent from kinds
    // is an ordinary var-shaped binding (the
    // globals, parameters, function names and
    // sloppy globals all predate the distinction
    // and behave as they always have). A lexical
    // binding exists from the moment its block
    // is entered — declareLexical plants it
    // uninitialized — and reading it before its
    // declaration runs is the temporal-dead-zone
    // error, not a silent undefined.
    enum Kind { case flexible, lexical, constant }
    var kinds: [String: Kind] = [:]
    var initialized: [String: Bool] = [:]
    // The nearest enclosing function body's
    // room (or the root): where var declarations
    // and hoisted function declarations land.
    // A fresh environment is its own var scope
    // until marked a mere block — blocks and
    // the try/catch/finally rooms pass the mark
    // down from the room they were opened in.
    var isVarScope = true
    init(parent: TBJSEnv? = nil) { self.parent = parent }
    func get(_ name: String) -> TBJSValue? {
        if let value = vars[name] { return value }
        return parent?.get(name)
    }
    // The same road as get, but a lexical
    // binding still waiting for its declaration
    // stops the walk with the dead-zone error
    // instead of reading as a name nobody holds.
    func lookup(_ name: String) throws -> TBJSValue? {
        if vars[name] != nil || kinds[name] != nil {
            if kinds[name] == .lexical || kinds[name] == .constant,
               initialized[name] != true {
                throw TBJSFlow.error(
                    "cannot use '\(name)' before its declaration")
            }
            return vars[name]
        }
        return try parent?.lookup(name)
    }
    // Whether any room on the road holds a
    // lexical or constant binding of this name
    // (an initialized one still counts: a var
    // may not be declared over it in this nest).
    func hasLexical(_ name: String) -> Bool {
        if kinds[name] == .lexical || kinds[name] == .constant {
            return true
        }
        return parent?.hasLexical(name) ?? false
    }
    // Plant a let/const binding in this room,
    // uninitialized, the moment the room opens.
    func declareLexical(_ name: String, constant: Bool) {
        kinds[name] = constant ? .constant : .lexical
        initialized[name] = false
        vars[name] = nil
    }
    // Run a declaration's own line: the binding
    // takes its value and stands initialized.
    func initializeLexical(_ name: String, _ value: TBJSValue) {
        kinds[name] = kinds[name] ?? .lexical
        initialized[name] = true
        vars[name] = value
    }
    func varScope() -> TBJSEnv {
        if isVarScope { return self }
        return parent?.varScope() ?? self
    }
    // A new room inside this one: a block, a
    // try's guarded room, a catch's, a finally's
    // — never itself a var scope, always under
    // this room's var scope.
    func childBlock() -> TBJSEnv {
        let child = TBJSEnv(parent: self)
        child.isVarScope = false
        return child
    }
    // Open a statement list's lexical bindings
    // in this room before any of it runs: every
    // let/const declared directly in the list
    // stands planted, uninitialized, from the
    // room's first moment — the dead zone.
    func hoistLexical(_ stmts: [TBJSStmt]) {
        for stmt in stmts {
            if case .lexicalDecl(let names, _, let constant) = stmt {
                for name in names where kinds[name] == nil {
                    declareLexical(name, constant: constant)
                }
            }
            // JavaScript fourth stage (0.40): a
            // list carrying patterns plants every
            // name its patterns bind, alongside
            // its plain names.
            if case .lexicalPattern(let items, let constant) = stmt {
                var planted: [String] = []
                for item in items {
                    switch item {
                    case .name(let name, _):
                        planted.append(name)
                    case .pattern(let pattern, _):
                        planted.append(
                            contentsOf: tbJSPatternNames(pattern))
                    }
                }
                for name in planted where kinds[name] == nil {
                    declareLexical(name, constant: constant)
                }
            }
        }
    }
    // Assign where the name already lives; a name
    // nobody holds is defined at the root, the
    // way a browser's sloppy mode makes a global.
    // A constant's room refuses the write, and a
    // lexical binding still in its dead zone
    // refuses it too.
    func set(_ name: String, _ value: TBJSValue) throws {
        if vars[name] != nil || kinds[name] != nil {
            if kinds[name] == .constant {
                if initialized[name] == true {
                    throw TBJSFlow.error(
                        "assignment to a constant '\(name)'")
                }
                throw TBJSFlow.error(
                    "cannot use '\(name)' before its declaration")
            }
            if kinds[name] == .lexical, initialized[name] != true {
                throw TBJSFlow.error(
                    "cannot use '\(name)' before its declaration")
            }
            vars[name] = value
            return
        }
        if let parent = parent {
            try parent.set(name, value)
            return
        }
        vars[name] = value
    }
}

enum TBJSFlow: Error {
    case returnValue(TBJSValue)
    case breakLoop
    case continueLoop
    case error(String)
    // JavaScript second stage (0.38): a value the
    // script itself threw. It rides separately
    // from an engine error so a catch can tell
    // "the page threw this" from "the engine
    // failed" — though a catch can hold either:
    // a thrown value arrives as itself, an engine
    // error arrives as its message string.
    case thrown(TBJSValue)
}

final class TBJSContext {
    var globals = TBJSEnv()
    var logs: [String] = []
    var title: String = ""
    var titleSet = false
    var elementsById: [String: TBNode] = [:]
    // Developer tools (0.35): set when code
    // writes an element's text or the
    // document's title, so the window knows
    // the painted page no longer matches its
    // tree. The JavaScript console clears it
    // before each run and reads it after; a
    // page's own scripts set it too, but a
    // load paints after its scripts anyway.
    var domChanged = false
    // The speed stage (0.36): the script stage's
    // wall-clock budget. tbRunScripts sets the
    // deadline when a page's scripts begin and
    // clears it when they end, so the console
    // (which shares this scope) is never held to
    // it — only a page's own scripts are. The
    // evaluator counts its checks and compares
    // against the deadline as it goes; a loop
    // that never yields still meets the check,
    // because every loop head and every block
    // passes it. When the deadline passes, the
    // run stops and the page keeps its life.
    var budgetDeadline: Date? = nil
    var budgetSteps = 0
    var budgetExceeded = false
    // Script navigation (0.37): the landed
    // page's own address — location.href reads
    // it, and a script's chosen destination is
    // resolved against it — and the destination
    // itself, once a script names one. The
    // render (for a page's scripts) or the
    // console (for the reader's typed words)
    // takes it from here and travels; nothing
    // in the interpreter fetches or paints.
    var pageURL: String = ""
    var navigationTarget: String? = nil
    // A script sends the reader onward: the
    // destination is resolved against the
    // page's address, and only an http, https
    // or file address travels — a script can
    // name no other kind of journey.
    func requestNavigation(_ value: TBJSValue) {
        if let target = tbJSResolveNavigation(value, base: pageURL) {
            navigationTarget = target
        }
    }
    // Mutating array natives (push, pop) set this
    // to the array's new shape; the call site,
    // which knows the expression the array came
    // from, writes it back.
    var mutatedThis: TBJSValue? = nil
    // JavaScript third stage (0.39): the root
    // class every value is asked about by
    // `instanceof Object`, and the stack of
    // class rooms the evaluator is standing in
    // — a method's or constructor's defining
    // class, whether the standing is a
    // constructor's, whether it is a static
    // member's (0.41 — `super` inside one
    // climbs the static road), and, for a
    // constructor of a class that extends
    // another, the fresh instance `super(...)`
    // will build into, held here while the
    // constructor's own `this` still reads
    // unbound.
    let objectClass = TBJSClassBox(name: "Object")
    var classFrames: [(home: TBJSClassBox, isConstructor: Bool,
                       isStatic: Bool,
                       pendingThis: TBJSValue?)] = []
    init() {
        globals.vars["document"] = .document
        globals.vars["window"] = .window
        globals.vars["location"] = .location
        globals.vars["console"] = .console
        globals.vars["this"] = .window
        globals.vars["undefined"] = .undefined
        globals.vars["NaN"] = .number(Double.nan)
        globals.vars["Infinity"] = .number(Double.infinity)
        globals.vars["alert"] = .native("window.alert")
        globals.vars["parseInt"] = .native("global.parseInt")
        globals.vars["parseFloat"] = .native("global.parseFloat")
        globals.vars["isNaN"] = .native("global.isNaN")
        globals.vars["String"] = .native("global.String")
        globals.vars["Number"] = .native("global.Number")
        // JavaScript third stage (0.39): the
        // root class, standing in the globals
        // like any class a page declares, so
        // `instanceof Object` has something to
        // ask about.
        globals.vars["Object"] = .classDef(objectClass)
        // JavaScript second stage (0.38): the
        // RegExp constructor — a call or a `new`
        // with a pattern and optional flags makes
        // a regex value (see tbJSRegexCompile).
        globals.vars["RegExp"] = .native("global.RegExp")
        // JavaScript sixth stage (0.42): the
        // Math global — its constants and
        // reckoning functions stand behind
        // the .math face (see tbJSGetMember
        // and the math.* natives below).
        globals.vars["Math"] = .math
    }
}

// The words of an element: every descendant text
// node, in order — what textContent reads.
func tbJSNodeText(_ node: TBNode) -> String {
    if node.tag == "#text" { return node.text }
    var out = ""
    for child in node.children { out += tbJSNodeText(child) }
    return out
}

// What a textContent (or innerHTML) write does:
// the element's children become the one text.
func tbJSSetNodeText(_ node: TBNode, _ text: String) {
    node.children = []
    if !text.isEmpty {
        let textNode = TBNode(tag: "#text", text: text)
        textNode.parent = node
        node.children.append(textNode)
    }
}

func tbJSNumberString(_ d: Double) -> String {
    if d.isNaN { return "NaN" }
    if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
    if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
    return String(d)
}

func tbJSString(_ value: TBJSValue) -> String {
    switch value {
    case .undefined: return "undefined"
    case .null: return "null"
    case .boolean(let b): return b ? "true" : "false"
    case .number(let d): return tbJSNumberString(d)
    case .string(let s): return s
    case .array(let items):
        return items.map { item in
            switch item {
            case .undefined, .null: return ""
            default: return tbJSString(item)
            }
        }.joined(separator: ",")
    case .object: return "[object Object]"
    case .instance: return "[object Object]"
    case .function, .native, .classDef: return "function"
    case .element: return "[object Element]"
    case .document: return "[object HTMLDocument]"
    case .console: return "[object Object]"
    case .math: return "[object Object]"
    case .window: return "[object Window]"
    case .location: return "[object Location]"
    case .regex(let pattern, let flags, _):
        return "/" + pattern + "/" + flags
    }
}

func tbJSNumber(_ value: TBJSValue) -> Double {
    switch value {
    case .undefined: return Double.nan
    case .null: return 0
    case .boolean(let b): return b ? 1 : 0
    case .number(let d): return d
    case .string(let s):
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        if let d = Double(trimmed) { return d }
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X"),
           let v = UInt64(String(trimmed.dropFirst(2)), radix: 16) {
            return Double(v)
        }
        return Double.nan
    case .array(let items): return tbJSNumber(.string(tbJSString(.array(items))))
    case .object, .instance, .classDef, .function, .native, .element,
         .document, .console, .window, .location, .regex, .math:
        return Double.nan
    }
}

func tbJSTruthy(_ value: TBJSValue) -> Bool {
    switch value {
    case .undefined, .null: return false
    case .boolean(let b): return b
    case .number(let d): return d != 0 && !d.isNaN
    case .string(let s): return !s.isEmpty
    default: return true
    }
}

func tbJSTypeName(_ value: TBJSValue) -> String {
    switch value {
    case .undefined: return "undefined"
    case .null: return "object"
    case .boolean: return "boolean"
    case .number: return "number"
    case .string: return "string"
    case .function, .native, .classDef: return "function"
    default: return "object"
    }
}

func tbJSStrictEqual(_ a: TBJSValue, _ b: TBJSValue) -> Bool {
    switch (a, b) {
    case (.undefined, .undefined), (.null, .null): return true
    case (.boolean(let x), .boolean(let y)): return x == y
    case (.number(let x), .number(let y)): return x == y
    case (.string(let x), .string(let y)): return x == y
    case (.element(let x), .element(let y)): return x === y
    case (.instance(let x), .instance(let y)): return x === y
    case (.classDef(let x), .classDef(let y)): return x === y
    case (.location, .location): return true
    case (.math, .math): return true
    case (.regex(let p1, let f1, _), .regex(let p2, let f2, _)):
        // A copy of a pattern is this engine's
        // stand-in for the same object (0.38).
        return p1 == p2 && f1 == f2
    default: return false
    }
}

func tbJSLooseEqual(_ a: TBJSValue, _ b: TBJSValue) -> Bool {
    if tbJSStrictEqual(a, b) { return true }
    switch (a, b) {
    case (.null, .undefined), (.undefined, .null): return true
    case (.number(let x), .string(let y)): return x == tbJSNumber(.string(y))
    case (.string(let x), .number(let y)): return tbJSNumber(.string(x)) == y
    case (.boolean(let x), _): return tbJSLooseEqual(.number(x ? 1 : 0), b)
    case (_, .boolean(let y)): return tbJSLooseEqual(a, .number(y ? 1 : 0))
    case (.array, .string(let y)): return tbJSString(a) == y
    case (.string(let x), .array): return x == tbJSString(b)
    case (.array, .number(let y)): return tbJSNumber(a) == y
    case (.number(let x), .array): return x == tbJSNumber(b)
    default: return false
    }
}

// JavaScript third stage (0.39): whether a
// value is object-shaped at all — the answer
// `instanceof Object` gives for anything that
// is not a primitive.
func tbJSIsObjectLike(_ value: TBJSValue) -> Bool {
    switch value {
    case .undefined, .null, .boolean, .number, .string:
        return false
    default:
        return true
    }
}

// `instanceof` (0.39): against a class, an
// instance answers by walking its own class
// road — itself, its parent, its parent's
// parent — looking for the very box on the
// right. Against the root Object class, every
// object-shaped value answers true. A plain
// function on the right names a constructor
// whose products are this engine's dictionary
// objects, and those carry no class stamp to
// walk — so the honest answer there is false,
// named in the README.
func tbJSInstanceOf(_ value: TBJSValue, _ target: TBJSValue,
                    _ ctx: TBJSContext) -> Bool {
    guard case .classDef(let wanted) = target else { return false }
    if wanted === ctx.objectClass { return tbJSIsObjectLike(value) }
    guard case .instance(let box) = value else { return false }
    var cursor: TBJSClassBox? = box.klass
    while let current = cursor {
        if current === wanted { return true }
        cursor = current.parent
    }
    return false
}

// The `in` operator's question (0.39): does
// this name stand on this value — as a field,
// or, for an instance, as a field or a method
// anywhere on its class road?
func tbJSHasProperty(_ base: TBJSValue, _ name: String,
                     _ ctx: TBJSContext) -> Bool {
    switch base {
    case .object(let obj):
        return obj[name] != nil
    case .instance(let box):
        if box.fields[name] != nil { return true }
        if name == "constructor" { return true }
        var cursor: TBJSClassBox? = box.klass
        while let current = cursor {
            if current.accessors[name] != nil { return true }
            if current.methods[name] != nil { return true }
            cursor = current.parent
        }
        return false
    case .classDef(let box):
        // JavaScript fifth stage (0.41): the
        // class's own face — its name and its
        // constructor's length, and whatever
        // statics, static fields or static
        // accessors stand anywhere on its
        // road. (A static member cannot bear
        // the names name or length here; the
        // reader refuses them.)
        if name == "name" || name == "length" { return true }
        var cursor: TBJSClassBox? = box
        while let current = cursor {
            if current.statics[name] != nil
                || current.staticFields[name] != nil
                || current.staticAccessors[name] != nil {
                return true
            }
            cursor = current.parent
        }
        return false
    case .array(let items):
        if name == "length" || TBJSArrayMethods[name] != nil {
            return true
        }
        if let idx = Int(name) {
            return idx >= 0 && idx < items.count
        }
        return false
    case .string(let s):
        if name == "length" || TBJSStringMethods[name] != nil {
            return true
        }
        if let idx = Int(name) {
            return idx >= 0 && idx < s.count
        }
        return false
    default:
        // The shapes that reach this branch
        // never carry an accessor (0.41), so
        // this read cannot raise; the try? is
        // only the compiler's due.
        if case .undefined = (try? tbJSGetMember(base, name, ctx))
            ?? .undefined {
            return false
        }
        return true
    }
}

let TBJSStringMethods: [String: String] = [
    "charAt": "string.charAt", "indexOf": "string.indexOf",
    "toUpperCase": "string.toUpperCase",
    "toLowerCase": "string.toLowerCase",
    "slice": "string.slice", "split": "string.split",
    "trim": "string.trim", "includes": "string.includes",
    // JavaScript second stage (0.38): the regex
    // companions — match, replace, search.
    "match": "string.match", "replace": "string.replace",
    "search": "string.search",
]
let TBJSArrayMethods: [String: String] = [
    "push": "array.push", "pop": "array.pop",
    "join": "array.join", "indexOf": "array.indexOf",
    "slice": "array.slice", "concat": "array.concat",
]

// Script navigation (0.37): resolve a script's
// chosen destination against the page's own
// address, as a link's address is resolved.
// Only an http, https or file address travels.
func tbJSResolveNavigation(_ value: TBJSValue, base: String) -> String? {
    let raw = tbJSString(value)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty,
          let url = URL(string: raw, relativeTo: URL(string: base)),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" || scheme == "file"
    else { return nil }
    return url.absoluteString
}

// A member read (0.33). JavaScript fifth
// stage (0.41): a read may now be a call —
// an accessor's getter standing on the road
// is invoked where the read finds it — so
// the read raises, like the evaluator it
// serves, and a getter's own error travels
// as catchably as any throw.
func tbJSGetMember(_ base: TBJSValue, _ name: String,
                   _ ctx: TBJSContext) throws -> TBJSValue {
    switch base {
    case .string(let s):
        if name == "length" { return .number(Double(s.count)) }
        if let native = TBJSStringMethods[name] { return .native(native) }
        return .undefined
    case .array(let items):
        if name == "length" { return .number(Double(items.count)) }
        if let native = TBJSArrayMethods[name] { return .native(native) }
        return .undefined
    case .object(let obj):
        return obj[name] ?? .undefined
    case .instance(let box):
        // JavaScript third stage (0.39): an
        // instance reads its own fields first,
        // then its class's methods, then its
        // parent's, and so on up the road. A
        // method is handed out as a copy
        // carrying the class it was found on,
        // so `super` inside it knows its room.
        // JavaScript fifth stage (0.41): an
        // accessor standing on the road is a
        // door, not a value — the read calls
        // its getter with this very instance,
        // and a pair holding no getter answers
        // undefined where it stands.
        if let field = box.fields[name] { return field }
        if name == "constructor" { return .classDef(box.klass) }
        var cursor: TBJSClassBox? = box.klass
        while let current = cursor {
            if let pair = current.accessors[name] {
                guard let stored = pair.getter else {
                    return .undefined
                }
                var getter = stored
                getter.classHome = current
                return try tbJSCall(.function(getter), [],
                                    this: base, ctx)
            }
            if let stored = current.methods[name] {
                var method = stored
                method.classHome = current
                return .function(method)
            }
            cursor = current.parent
        }
        return .undefined
    case .classDef(let box):
        // A class's own face (0.39): its name,
        // and its constructor's length.
        // JavaScript fifth stage (0.41): and
        // now its statics. A read walks the
        // class road the way an instance's read
        // walks for methods: a static accessor
        // is a door whose getter is called with
        // the class this read came through (a
        // subclass reading an inherited door
        // stands in the doorway itself), a
        // static field answers the value it
        // was reckoned with, and a static
        // method is handed out carrying the
        // class it was found on, marked static
        // so its frame knows which road its
        // `super` climbs. The call itself binds
        // `this` to the class the member was
        // read through, as every member call
        // here does — so a static called
        // through a subclass answers with the
        // subclass standing as `this`.
        switch name {
        case "name": return .string(box.name)
        case "length":
            return .number(Double(box.ctor?.params.count ?? 0))
        default: break
        }
        var cursor: TBJSClassBox? = box
        while let current = cursor {
            if let pair = current.staticAccessors[name] {
                guard let stored = pair.getter else {
                    return .undefined
                }
                var getter = stored
                getter.classHome = current
                getter.isStatic = true
                return try tbJSCall(.function(getter), [],
                                    this: base, ctx)
            }
            if let field = current.staticFields[name] {
                return field
            }
            if let stored = current.statics[name] {
                var method = stored
                method.classHome = current
                method.isStatic = true
                return .function(method)
            }
            cursor = current.parent
        }
        return .undefined
    case .element(let node):
        switch name {
        case "textContent", "innerHTML":
            return .string(tbJSNodeText(node))
        case "id": return .string(node.attrs["id"] ?? "")
        case "tagName": return .string(node.tag.uppercased())
        default: return .undefined
        }
    case .document:
        switch name {
        case "title": return .string(ctx.title)
        case "getElementById": return .native("document.getElementById")
        case "location": return .location
        default: return .undefined
        }
    case .console:
        switch name {
        case "log", "info", "warn", "error":
            return .native("console.log")
        default: return .undefined
        }
    case .math:
        // JavaScript sixth stage (0.42): the
        // Math face — its constants stand as
        // numbers, its functions as natives,
        // and a name it does not carry answers
        // undefined, like every other built-in
        // face here. The constants are the
        // language's own values, to the last
        // digit a Double can hold.
        switch name {
        case "E": return .number(2.718281828459045)
        case "PI": return .number(3.141592653589793)
        case "LN2": return .number(0.6931471805599453)
        case "LN10": return .number(2.302585092994046)
        case "LOG2E": return .number(1.4426950408889634)
        case "LOG10E": return .number(0.4342944819032518)
        case "SQRT1_2": return .number(0.7071067811865476)
        case "SQRT2": return .number(1.4142135623730951)
        case "abs", "floor", "ceil", "round", "trunc",
             "sign", "max", "min", "pow", "sqrt", "exp",
             "log", "log2", "log10", "cbrt", "hypot",
             "random":
            return .native("math." + name)
        default: return .undefined
        }
    case .window:
        switch name {
        case "document": return .document
        case "console": return .console
        case "window": return .window
        case "alert": return .native("window.alert")
        // Script navigation (0.37): the window's
        // address, and the window itself under
        // the frame names — a single-frame
        // world, where parent and top are this
        // very window.
        case "location": return .location
        case "parent", "top", "self": return .window
        default: return ctx.globals.get(name) ?? .undefined
        }
    case .location:
        switch name {
        case "href":
            return .string(ctx.navigationTarget ?? ctx.pageURL)
        case "replace": return .native("location.replace")
        case "assign": return .native("location.assign")
        case "toString": return .native("location.toString")
        default: return .undefined
        }
    case .regex(let pattern, let flags, let lastIndex):
        // JavaScript second stage (0.38): a
        // pattern's own face — where it came
        // from, how it is flagged, where its
        // next search starts — and its two
        // working methods.
        switch name {
        case "source": return .string(pattern)
        case "flags": return .string(flags)
        case "lastIndex": return .number(Double(lastIndex))
        case "global": return .boolean(flags.contains("g"))
        case "ignoreCase": return .boolean(flags.contains("i"))
        case "multiline": return .boolean(flags.contains("m"))
        case "sticky": return .boolean(flags.contains("y"))
        case "unicode": return .boolean(flags.contains("u"))
        case "test": return .native("regex.test")
        case "exec": return .native("regex.exec")
        case "toString": return .native("regex.toString")
        default: return .undefined
        }
    default:
        return .undefined
    }
}

// Returns the base's new shape (arrays and objects
// are values here, so a write makes a new one the
// caller writes back); element and document
// writes land in place and return the base.
// JavaScript fifth stage (0.41): a write may
// now be a call — an accessor's setter standing
// on the road is invoked where the write finds
// it — so the write raises, like the read.
func tbJSSetMember(_ base: TBJSValue, _ name: String, _ value: TBJSValue,
                   _ ctx: TBJSContext) throws -> TBJSValue {
    switch base {
    case .object(var obj):
        obj[name] = value
        return .object(obj)
    case .instance(let box):
        // JavaScript third stage (0.39): a
        // write to an instance lands in its
        // box, in place — every hand holding
        // the instance sees it, and the base
        // rides back unchanged. JavaScript
        // fifth stage (0.41): unless an
        // accessor stands on the class road
        // under this name — then the write is
        // a call through the door: the setter
        // is invoked with this very instance,
        // and the name never becomes a plain
        // field. A pair holding no setter
        // swallows the write silently, the
        // sloppy-mode answer. A field already
        // standing under the name is the
        // instance's own, and is simply
        // renewed, door or no door.
        if box.fields[name] != nil {
            box.fields[name] = value
            return base
        }
        var cursor: TBJSClassBox? = box.klass
        while let current = cursor {
            if let pair = current.accessors[name] {
                if let stored = pair.setter {
                    var setter = stored
                    setter.classHome = current
                    _ = try tbJSCall(.function(setter), [value],
                                     this: base, ctx)
                }
                return base
            }
            cursor = current.parent
        }
        box.fields[name] = value
        return base
    case .classDef(let box):
        // JavaScript fifth stage (0.41): a
        // write on a class's own face. A static
        // accessor standing on the road under
        // this name is a door, as it is for an
        // instance — its setter is called with
        // the class this write came through,
        // and a pair holding no setter swallows
        // the write silently. Otherwise the
        // value lands as a static field on this
        // very class: a write through a
        // subclass shadows whatever the parent
        // holds under the name (a field, or a
        // static method's standing) on the
        // subclass alone, and the parent's own
        // face keeps its answer.
        var cursor: TBJSClassBox? = box
        while let current = cursor {
            if let pair = current.staticAccessors[name] {
                if let stored = pair.setter {
                    var setter = stored
                    setter.classHome = current
                    setter.isStatic = true
                    _ = try tbJSCall(.function(setter), [value],
                                     this: base, ctx)
                }
                return base
            }
            cursor = current.parent
        }
        box.staticFields[name] = value
        return base
    case .array(var items):
        if name == "length" {
            let wanted = Int(tbJSNumber(value))
            if wanted >= 0 {
                if wanted < items.count {
                    items.removeSubrange(wanted..<items.count)
                } else {
                    while items.count < wanted { items.append(.undefined) }
                }
            }
            return .array(items)
        }
        if let idx = Int(name), idx >= 0 {
            while items.count <= idx { items.append(.undefined) }
            items[idx] = value
            return .array(items)
        }
        return base
    case .element(let node):
        if name == "textContent" || name == "innerHTML" {
            tbJSSetNodeText(node, tbJSString(value))
            ctx.domChanged = true
        }
        return base
    case .document:
        if name == "title" {
            ctx.title = tbJSString(value)
            ctx.titleSet = true
            ctx.domChanged = true
        }
        if name == "location" {
            ctx.requestNavigation(value)
        }
        return base
    case .window:
        // Script navigation (0.37): writing the
        // window's location is a journey. Any
        // other name written on the window is a
        // global, as the read side already holds.
        if name == "location" {
            ctx.requestNavigation(value)
        } else {
            ctx.globals.vars[name] = value
        }
        return base
    case .location:
        if name == "href" {
            ctx.requestNavigation(value)
        }
        return base
    case .regex(let pattern, let flags, _):
        // JavaScript second stage (0.38): the
        // one writable field a pattern carries.
        if name == "lastIndex" {
            return .regex(pattern, flags,
                          max(0, Int(tbJSNumber(value))))
        }
        return base
    default:
        return base
    }
}

func tbJSGetIndex(_ base: TBJSValue, _ index: TBJSValue,
                  _ ctx: TBJSContext) throws -> TBJSValue {
    switch base {
    case .array(let items):
        if case .number(let d) = index {
            let i = Int(d)
            if d == Double(i) && i >= 0 && i < items.count {
                return items[i]
            }
            return .undefined
        }
        return try tbJSGetMember(base, tbJSString(index), ctx)
    case .string(let s):
        if case .number(let d) = index {
            let i = Int(d)
            let chars = Array(s)
            if d == Double(i) && i >= 0 && i < chars.count {
                return .string(String(chars[i]))
            }
            return .undefined
        }
        return try tbJSGetMember(base, tbJSString(index), ctx)
    case .object, .instance, .element, .document, .console, .window,
         .location, .regex, .math:
        return try tbJSGetMember(base, tbJSString(index), ctx)
    default:
        return .undefined
    }
}

func tbJSSetIndex(_ base: TBJSValue, _ index: TBJSValue, _ value: TBJSValue,
                  _ ctx: TBJSContext) throws -> TBJSValue {
    switch base {
    case .array(var items):
        if case .number(let d) = index {
            let i = Int(d)
            if d == Double(i) && i >= 0 {
                while items.count <= i { items.append(.undefined) }
                items[i] = value
                return .array(items)
            }
            return base
        }
        return try tbJSSetMember(base, tbJSString(index), value, ctx)
    case .object, .instance, .element, .document:
        return try tbJSSetMember(base, tbJSString(index), value, ctx)
    default:
        return base
    }
}

// JavaScript second stage (0.38): the regex
// machinery. A pattern is compiled by
// Foundation's NSRegularExpression — a regex
// library, the same shelf String and URL come
// from, not a borrowed JavaScript engine.
// The spellings mostly agree (\d, \w, \s, the
// anchors, the classes); the gaps this stage
// knows about are named in the 0.38 bullet
// bullet and the README.
func tbJSRegexCompile(_ pattern: String, _ flags: String) throws
    -> NSRegularExpression {
    var options: NSRegularExpression.Options = []
    if flags.contains("i") { options.insert(.caseInsensitive) }
    if flags.contains("m") { options.insert(.anchorsMatchLines) }
    if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
    do {
        return try NSRegularExpression(pattern: pattern,
                                       options: options)
    } catch {
        throw TBJSFlow.error("invalid regular expression: /"
                             + pattern + "/")
    }
}

// One search of a string by a pattern, from a
// starting character offset. Returns the match
// as an array — the whole match, then each
// group, an absent group reading undefined —
// or null; and the lastIndex the pattern
// carries away (only a g or y pattern keeps
// one; a failed search resets it to zero, as
// the language says). The result is a plain
// array: this stage gives it no .index or
// .input properties of its own.
func tbJSRegexExec(_ pattern: String, _ flags: String,
                   _ lastIndex: Int, _ text: String) throws
    -> (TBJSValue, Int) {
    let re = try tbJSRegexCompile(pattern, flags)
    let ns = text as NSString
    let keepsIndex = flags.contains("g") || flags.contains("y")
    var start = keepsIndex ? lastIndex : 0
    if start < 0 { start = 0 }
    if start > ns.length {
        return (.null, keepsIndex ? 0 : lastIndex)
    }
    let range = NSRange(location: start, length: ns.length - start)
    guard let match = re.firstMatch(in: text, options: [],
                                    range: range) else {
        return (.null, keepsIndex ? 0 : lastIndex)
    }
    if flags.contains("y"), match.range.location != start {
        return (.null, 0)
    }
    var items: [TBJSValue] = []
    for group in 0..<match.numberOfRanges {
        let groupRange = match.range(at: group)
        if groupRange.location == NSNotFound {
            items.append(.undefined)
        } else {
            items.append(.string(ns.substring(with: groupRange)))
        }
    }
    var next = lastIndex
    if keepsIndex {
        next = match.range.location + match.range.length
        if match.range.length == 0 { next += 1 }
    }
    return (.array(items), next)
}

// The replacement side of replace: a template
// read against one match — $$ is a dollar,
// $& the whole match, $` and $' the text
// before and after it, $1..$99 a group (an
// absent group reads empty, a number past the
// last group stays literal). With no match in
// hand (the plain-string form of replace),
// $& is the needle itself and every $n stays
// literal, as the language has it.
func tbJSRegexExpandReplacement(_ template: String, _ text: NSString,
                                _ match: NSTextCheckingResult?,
                                _ needle: String) -> String {
    let whole: String
    let groupCount: Int
    if let match = match {
        whole = text.substring(with: match.range)
        groupCount = match.numberOfRanges - 1
    } else {
        whole = needle
        groupCount = 0
    }
    func groupText(_ index: Int) -> String? {
        guard let match = match, index <= groupCount else {
            return nil
        }
        let groupRange = match.range(at: index)
        if groupRange.location == NSNotFound { return "" }
        return text.substring(with: groupRange)
    }
    let chars = Array(template)
    var out = ""
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c != "$" || i + 1 >= chars.count {
            out.append(c)
            i += 1
            continue
        }
        let next = chars[i + 1]
        switch next {
        case "$":
            out.append("$")
            i += 2
        case "&":
            out.append(whole)
            i += 2
        case "`":
            if let match = match {
                out += text.substring(to: match.range.location)
            } else {
                out.append("$`")
            }
            i += 2
        case "'":
            if let match = match {
                out += text.substring(
                    from: match.range.location + match.range.length)
            } else {
                out.append("$'")
            }
            i += 2
        default:
            if next >= "1" && next <= "9" {
                var digits = String(next)
                var width = 1
                if i + 2 < chars.count, chars[i + 2] >= "0",
                   chars[i + 2] <= "9",
                   let two = Int(digits + String(chars[i + 2])),
                   two <= groupCount {
                    digits = String(two)
                    width = 2
                }
                if let group = groupText(Int(digits) ?? 0) {
                    out.append(group)
                    i += 1 + width
                } else {
                    out.append("$")
                    i += 1
                }
            } else {
                out.append("$")
                i += 1
            }
        }
    }
    return out
}

// MARK: - JavaScript lexer and parser (0.33)

enum TBJSTemplatePart {
    // A template literal under construction
    // (0.38): plain words, or the source of one
    // ${…} interpolation, which the parser reads
    // as an expression of its own.
    case text(String)
    case exprSource(String)
}

enum TBJSToken {
    case number(Double)
    case string(String)
    case regex(String, String)
    case template([TBJSTemplatePart])
    case ident(String)
    case punct(String)
    case eof
}


func tbJSLex(_ source: String) throws -> [TBJSToken] {
    let chars = Array(source)
    let n = chars.count
    var i = 0
    var tokens: [TBJSToken] = []
    func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    func isIdentStart(_ c: Character) -> Bool {
        c.isLetter || c == "_" || c == "$"
    }
    func isIdentPart(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$"
    }
    // JavaScript second stage (0.38): whether a
    // "/" here opens a pattern or divides. A
    // pattern can only stand where a value can
    // begin — at the start, after an operator or
    // an opener, after a keyword that expects a
    // value; after a value (a number, a string,
    // a template, a pattern, a name, a closer)
    // the same stroke is division. The keyword
    // list is the honest heuristic every small
    // lexer keeps.
    func regexCanOpen() -> Bool {
        guard let last = tokens.last else { return true }
        switch last {
        case .number, .string, .template, .regex:
            return false
        case .ident(let name):
            return ["typeof", "return", "case", "in", "of",
                    "new", "delete", "void", "throw",
                    "instanceof", "else", "do"].contains(name)
        case .punct(let p):
            return p != ")" && p != "]" && p != "}"
        case .eof:
            return true
        }
    }
    while i < n {
        let c = chars[i]
        if c == " " || c == "\t" || c == "\n" || c == "\r" {
            i += 1
            continue
        }
        if c == "/" && i + 1 < n && chars[i + 1] == "/" {
            while i < n && chars[i] != "\n" { i += 1 }
            continue
        }
        if c == "/" && i + 1 < n && chars[i + 1] == "*" {
            i += 2
            while i + 1 < n && !(chars[i] == "*" && chars[i + 1] == "/") {
                i += 1
            }
            i = min(i + 2, n)
            continue
        }
        if c == "/" && regexCanOpen() {
            // A pattern (0.38): read to the
            // closing stroke, honoring backslash
            // escapes and character classes (a
            // "/" inside […] closes nothing), then
            // the flag letters that follow. If no
            // closing stroke stands on this line,
            // it was division after all and the
            // ordinary road below takes the "/".
            var j = i + 1
            var pattern = ""
            var inClass = false
            var closed = false
            while j < n {
                let ch = chars[j]
                if ch == "\\" && j + 1 < n {
                    pattern.append(ch)
                    pattern.append(chars[j + 1])
                    j += 2
                    continue
                }
                if ch == "\n" { break }
                if ch == "[" { inClass = true }
                if ch == "]" { inClass = false }
                if ch == "/" && !inClass { closed = true; break }
                pattern.append(ch)
                j += 1
            }
            if closed {
                var flags = ""
                var k = j + 1
                while k < n && chars[k].isLetter {
                    flags.append(chars[k])
                    k += 1
                }
                tokens.append(.regex(pattern, flags))
                i = k
                continue
            }
        }
        if c == "`" {
            // A template literal (0.38): words
            // and ${…} workings woven together.
            // Each working's source is captured
            // whole — braces counted, strings and
            // nested templates stepped over, so
            // the parser can read it as an
            // expression. One known limit: a
            // pattern inside ${…} whose text holds
            // a "}" would end the working early.
            var parts: [TBJSTemplatePart] = []
            var words = ""
            var j = i + 1
            var closed = false
            while j < n {
                let ch = chars[j]
                if ch == "\\" && j + 1 < n {
                    let esc = chars[j + 1]
                    switch esc {
                    case "n": words.append("\n")
                    case "t": words.append("\t")
                    case "r": words.append("\r")
                    case "`": words.append("`")
                    case "$": words.append("$")
                    case "\\": words.append("\\")
                    default: words.append(esc)
                    }
                    j += 2
                    continue
                }
                if ch == "`" { closed = true; j += 1; break }
                if ch == "$" && j + 1 < n && chars[j + 1] == "{" {
                    parts.append(.text(words))
                    words = ""
                    var depth = 1
                    var k = j + 2
                    var quote: Character? = nil
                    var inTemplate = false
                    // A stack of the modes this
                    // working stepped out of, one
                    // per open ${ — a nested
                    // template's ${ returns to the
                    // template, not to plain code,
                    // when its brace closes.
                    var modes: [Bool] = []
                    while k < n && depth > 0 {
                        let inner = chars[k]
                        if let q = quote {
                            if inner == "\\" { k += 2; continue }
                            if inner == q { quote = nil }
                            k += 1
                            continue
                        }
                        if inTemplate {
                            if inner == "\\" { k += 2; continue }
                            if inner == "`" {
                                inTemplate = false
                                k += 1
                                continue
                            }
                            if inner == "$" && k + 1 < n
                                && chars[k + 1] == "{" {
                                depth += 1
                                modes.append(true)
                                inTemplate = false
                                k += 2
                                continue
                            }
                            k += 1
                            continue
                        }
                        if inner == "'" || inner == "\"" {
                            quote = inner
                            k += 1
                            continue
                        }
                        if inner == "`" {
                            inTemplate = true
                            k += 1
                            continue
                        }
                        if inner == "/" && k + 1 < n
                            && chars[k + 1] == "/" {
                            while k < n && chars[k] != "\n" {
                                k += 1
                            }
                            continue
                        }
                        if inner == "{" { depth += 1 }
                        if inner == "}" {
                            depth -= 1
                            if depth == 0 { break }
                            if let wasTemplate = modes.popLast(),
                               wasTemplate {
                                inTemplate = true
                            }
                        }
                        k += 1
                    }
                    if depth != 0 {
                        throw TBJSFlow.error(
                            "unterminated template literal")
                    }
                    parts.append(.exprSource(
                        String(chars[(j + 2)..<k])))
                    j = k + 1
                    continue
                }
                words.append(ch)
                j += 1
            }
            if !closed {
                throw TBJSFlow.error("unterminated template literal")
            }
            parts.append(.text(words))
            tokens.append(.template(parts))
            i = j
            continue
        }
        if isDigit(c) || (c == "." && i + 1 < n && isDigit(chars[i + 1])) {
            var text = ""
            if c == "0" && i + 1 < n
                && (chars[i + 1] == "x" || chars[i + 1] == "X") {
                i += 2
                var hex = ""
                while i < n && chars[i].isHexDigit {
                    hex.append(chars[i])
                    i += 1
                }
                tokens.append(.number(Double(UInt64(hex, radix: 16) ?? 0)))
                continue
            }
            while i < n && (isDigit(chars[i]) || chars[i] == ".") {
                text.append(chars[i])
                i += 1
            }
            if i < n && (chars[i] == "e" || chars[i] == "E") {
                var j = i + 1
                if j < n && (chars[j] == "+" || chars[j] == "-") { j += 1 }
                if j < n && isDigit(chars[j]) {
                    text.append(chars[i])
                    i += 1
                    if i < n && (chars[i] == "+" || chars[i] == "-") {
                        text.append(chars[i])
                        i += 1
                    }
                    while i < n && isDigit(chars[i]) {
                        text.append(chars[i])
                        i += 1
                    }
                }
            }
            tokens.append(.number(Double(text) ?? Double.nan))
            continue
        }
        if c == "\"" || c == "'" {
            let quote = c
            i += 1
            var text = ""
            var closed = false
            while i < n {
                let ch = chars[i]
                if ch == quote { closed = true; i += 1; break }
                if ch == "\\" && i + 1 < n {
                    let esc = chars[i + 1]
                    switch esc {
                    case "n": text.append("\n")
                    case "t": text.append("\t")
                    case "r": text.append("\r")
                    case "0": text.append("\0")
                    case "u":
                        var hex = ""
                        var k = i + 2
                        while k < n && hex.count < 4 && chars[k].isHexDigit {
                            hex.append(chars[k])
                            k += 1
                        }
                        if let v = UInt32(hex, radix: 16),
                           let scalar = Unicode.Scalar(v) {
                            text.append(Character(scalar))
                        }
                        i = k
                        continue
                    default: text.append(esc)
                    }
                    i += 2
                    continue
                }
                text.append(ch)
                i += 1
            }
            if !closed { throw TBJSFlow.error("unterminated string") }
            tokens.append(.string(text))
            continue
        }
        if isIdentStart(c) {
            var name = ""
            while i < n && isIdentPart(chars[i]) {
                name.append(chars[i])
                i += 1
            }
            tokens.append(.ident(name))
            continue
        }
        let rest = String(chars[i..<min(i + 3, n)])
        var matched: String? = nil
        for op in ["===", "!==", "==", "!=", "<=", ">=", "&&", "||",
                   "++", "--", "+=", "-=", "*=", "/=", "%=",
                   // JavaScript third stage (0.39):
                   // the arrow's joining stroke, and
                   // spread's three dots.
                   "=>", "..."] {
            if rest.hasPrefix(op) { matched = op; break }
        }
        if let op = matched {
            tokens.append(.punct(op))
            i += op.count
            continue
        }
        if "(){}[];,.?:+-*/%<>=!".contains(c) {
            tokens.append(.punct(String(c)))
            i += 1
            continue
        }
        if c == "#" {
            // JavaScript fifth stage (0.41):
            // outside a string or a pattern, a
            // hash opens only one thing in the
            // language — a private name — and
            // private members are refused by
            // name rather than as a stray mark.
            throw TBJSFlow.error(
                "private fields and methods (#name)"
                + " are not in this stage")
        }
        throw TBJSFlow.error("unexpected character '\(c)'")
    }
    tokens.append(.eof)
    return tokens
}

indirect enum TBJSExpr {
    case literal(TBJSValue)
    case ident(String)
    case arrayLit([TBJSExpr])
    case objectLit([(String, TBJSExpr)])
    case member(TBJSExpr, String)
    case index(TBJSExpr, TBJSExpr)
    case call(TBJSExpr, [TBJSExpr])
    case unary(String, TBJSExpr)
    case prefix(String, TBJSExpr)
    case postfix(String, TBJSExpr)
    case binary(String, TBJSExpr, TBJSExpr)
    case assign(TBJSExpr, TBJSExpr)
    case opAssign(String, TBJSExpr, TBJSExpr)
    // JavaScript fourth stage (0.40): a
    // destructuring assignment — the pattern
    // the value is opened into, and the
    // expression the value comes from. The
    // value is reckoned whole before any
    // piece is handed out, which is what
    // makes [a, b] = [b, a] a swap.
    case patternAssign(TBJSPattern, TBJSExpr)
    case ternary(TBJSExpr, TBJSExpr, TBJSExpr)
    case funcExpr([TBJSParam], [TBJSStmt])
    // JavaScript second stage (0.38): building
    // with `new` — the thing built, and the
    // arguments it is built with.
    case newExpr(TBJSExpr, [TBJSExpr])
    // JavaScript third stage (0.39): an arrow
    // function — the shared parameter road and
    // its body. When the body is one expression
    // the flag says so, and the body holds that
    // expression as a lone expression statement.
    case arrowExpr([TBJSParam], [TBJSStmt], Bool)
    // Spread (0.39): stands inside a call's
    // arguments and an array literal's pieces,
    // and opens into the values it holds.
    case spread(TBJSExpr)
    // JavaScript third stage (0.39): `super`
    // in a class's rooms — a call of the
    // parent class's constructor, standing
    // only in a constructor; and a read of a
    // name on the parent class, whose call
    // keeps the child's `this`.
    case superCall([TBJSExpr])
    case superMember(String)
}

indirect enum TBJSStmt {
    case empty
    case expr(TBJSExpr)
    case decl(String, TBJSExpr?)
    // JavaScript third stage (0.39): a let or
    // const declaration — every declarator's
    // name and first value together, and
    // whether the bindings are constants. The
    // names are planted in whatever room the
    // list stands in when that room opens.
    case lexicalDecl([String], [TBJSExpr?], Bool)
    // JavaScript fourth stage (0.40): a let or
    // const list that carries at least one
    // destructuring pattern — every declarator
    // as an item, plain names and patterns
    // mixed, so the room can plant every name
    // the list binds before the block runs.
    case lexicalPattern([TBJSLexicalItem], Bool)
    // JavaScript fourth stage (0.40): a var
    // declaration wearing a pattern — the
    // pattern and the expression it opens.
    // (A pattern declaration always carries a
    // value; the reader refuses one without.)
    case patternVar(TBJSPattern, TBJSExpr)
    // A for head wearing let/const (0.39): the
    // head runs in a room of its own, and the
    // loop copies the head's bindings into a
    // fresh room for every round, so a closure
    // made in one round keeps that round's
    // counter. (kind: true = const.)
    case forLexical([String], [TBJSExpr?], Bool,
                    TBJSExpr?, TBJSExpr?, TBJSStmt)
    case block([TBJSStmt])
    case ifElse(TBJSExpr, TBJSStmt, TBJSStmt?)
    case whileLoop(TBJSExpr, TBJSStmt)
    case doWhile(TBJSStmt, TBJSExpr)
    case forLoop(TBJSStmt?, TBJSExpr?, TBJSExpr?, TBJSStmt)
    // JavaScript third stage (0.39): for-of —
    // the thing walked, and the target each
    // piece is handed to (a name being
    // declared with var when the flag stands,
    // or an existing name, member or index).
    // The let/const form keeps its name apart:
    // every round is a fresh binding.
    case forOf(TBJSExpr, TBJSExpr, TBJSStmt, Bool)
    case forOfLexical(String, Bool, TBJSExpr, TBJSStmt)
    // JavaScript fourth stage (0.40): for-of
    // with a pattern in its head — the pattern,
    // how each round's piece is handed out,
    // the thing walked, and the body.
    case forOfPattern(TBJSPattern, TBJSForOfKind,
                      TBJSExpr, TBJSStmt)
    // JavaScript third stage (0.39): a class
    // declaration — its name, the name of the
    // class it extends if it names one, and
    // its body as the parser gathered it.
    // JavaScript fifth stage (0.41): the body
    // now carries the class face's own
    // members too — statics, static fields,
    // and the accessor pairs of both faces.
    case classDecl(String, String?, TBJSClassParts)
    case funcDecl(String, [TBJSParam], [TBJSStmt])
    case returnStmt(TBJSExpr?)
    case breakStmt
    case continueStmt
    // JavaScript second stage (0.38): throw,
    // and try with its catch name and body and
    // its finally body — either companion may
    // be absent, never both.
    case throwStmt(TBJSExpr)
    case tryStmt([TBJSStmt], String?, [TBJSStmt]?, [TBJSStmt]?)
}

struct TBJSParser {
    var tokens: [TBJSToken]
    var pos = 0

    func peek() -> TBJSToken { tokens[min(pos, tokens.count - 1)] }
    func peekIdent() -> String? {
        if case .ident(let name) = peek() { return name }
        return nil
    }
    func peekPunct() -> String? {
        if case .punct(let p) = peek() { return p }
        return nil
    }
    mutating func advance() { pos += 1 }
    mutating func acceptPunct(_ p: String) -> Bool {
        if peekPunct() == p { advance(); return true }
        return false
    }
    mutating func acceptIdent(_ name: String) -> Bool {
        if peekIdent() == name { advance(); return true }
        return false
    }
    mutating func expectPunct(_ p: String) throws {
        if !acceptPunct(p) {
            throw TBJSFlow.error("expected '\(p)'")
        }
    }
    mutating func expectIdent() throws -> String {
        if case .ident(let name) = peek() {
            advance()
            return name
        }
        throw TBJSFlow.error("expected a name")
    }
    mutating func skipSemicolons() {
        while acceptPunct(";") {}
    }

    mutating func parseProgram() throws -> [TBJSStmt] {
        var stmts: [TBJSStmt] = []
        while true {
            if case .eof = peek() { break }
            stmts.append(try parseStatement())
        }
        return stmts
    }

    mutating func parseBlock() throws -> [TBJSStmt] {
        try expectPunct("{")
        var stmts: [TBJSStmt] = []
        while peekPunct() != "}" {
            if case .eof = peek() {
                throw TBJSFlow.error("unterminated block")
            }
            stmts.append(try parseStatement())
        }
        try expectPunct("}")
        return stmts
    }

    // var/let/const with any number of declarators.
    mutating func parseDeclList() throws -> [TBJSStmt] {
        advance()  // the keyword itself
        var stmts: [TBJSStmt] = []
        while true {
            // JavaScript fourth stage (0.40): a
            // declarator may wear a pattern; a
            // pattern declaration must carry the
            // value it opens.
            if peekPunct() == "[" || peekPunct() == "{" {
                let pattern = try parsePattern()
                guard acceptPunct("=") else {
                    throw TBJSFlow.error(
                        "a destructuring declaration needs"
                        + " a value to open")
                }
                stmts.append(.patternVar(pattern,
                                         try parseAssign()))
                if !acceptPunct(",") { break }
                continue
            }
            let name = try expectIdent()
            var initial: TBJSExpr? = nil
            if acceptPunct("=") { initial = try parseAssign() }
            stmts.append(.decl(name, initial))
            if !acceptPunct(",") { break }
        }
        return stmts
    }

    // A let/const declaration (0.39): the whole
    // list as one statement, every declarator's
    // name and first value together, so the
    // room the list stands in can plant all the
    // names — uninitialized — before the block
    // runs, which is what makes reading one
    // early an error rather than a shrug.
    mutating func parseLexicalDeclList() throws -> TBJSStmt {
        let constant = peekIdent() == "const"
        advance()  // the keyword itself
        var names: [String] = []
        var initials: [TBJSExpr?] = []
        // JavaScript fourth stage (0.40): the
        // list may carry patterns among its
        // names; then the whole list rides as
        // items, so every name — plain or
        // patterned — is planted before the
        // block runs, and the dead zone covers
        // them all alike.
        var items: [TBJSLexicalItem] = []
        var sawPattern = false
        while true {
            if peekPunct() == "[" || peekPunct() == "{" {
                sawPattern = true
                let pattern = try parsePattern()
                guard acceptPunct("=") else {
                    throw TBJSFlow.error(
                        "a destructuring declaration needs"
                        + " a value to open")
                }
                items.append(.pattern(pattern,
                                      try parseAssign()))
            } else {
                let name = try expectIdent()
                var initial: TBJSExpr? = nil
                if acceptPunct("=") {
                    initial = try parseAssign()
                }
                names.append(name)
                initials.append(initial)
                items.append(.name(name, initial))
            }
            if !acceptPunct(",") { break }
        }
        if sawPattern {
            return .lexicalPattern(items, constant)
        }
        return .lexicalDecl(names, initials, constant)
    }

    // JavaScript fourth stage (0.40): a
    // destructuring pattern. The bracket shapes
    // open piece by piece; anything else is a
    // target — a plain name, or a road into a
    // held thing (o.x, arr[0]) that only an
    // assignment may write through. A computed
    // key in an object pattern is refused by
    // name, here at the reading, rather than
    // read as something it is not.
    mutating func parsePattern() throws -> TBJSPattern {
        if peekPunct() == "[" { return try parseArrayPattern() }
        if peekPunct() == "{" { return try parseObjectPattern() }
        return try parsePatternTarget()
    }

    mutating func parsePatternTarget() throws -> TBJSPattern {
        let name = try expectIdent()
        var expr: TBJSExpr = .ident(name)
        var chained = false
        while true {
            if acceptPunct(".") {
                expr = .member(expr, try expectIdent())
                chained = true
            } else if acceptPunct("[") {
                let index = try parseExpr()
                try expectPunct("]")
                expr = .index(expr, index)
                chained = true
            } else {
                break
            }
        }
        return chained ? .target(expr) : .name(name)
    }

    mutating func parseArrayPattern() throws -> TBJSPattern {
        advance()  // the opening bracket
        var items: [TBJSPatternItem] = []
        if !acceptPunct("]") {
            while true {
                if peekPunct() == "]" { break }
                if acceptPunct(",") {
                    items.append(.hole)
                    continue
                }
                if acceptPunct("...") {
                    let inner = try parsePattern()
                    if peekPunct() == "=" {
                        throw TBJSFlow.error(
                            "a rest element takes no default")
                    }
                    items.append(.rest(inner))
                    try expectPunct("]")
                    return .array(items)
                }
                var item = try parsePattern()
                if acceptPunct("=") {
                    item = .defaulted(item, try parseAssign())
                }
                items.append(.item(item))
                if !acceptPunct(",") { break }
                if peekPunct() == "]" { break }
            }
            try expectPunct("]")
        }
        return .array(items)
    }

    mutating func parseObjectPattern() throws -> TBJSPattern {
        advance()  // the opening brace
        var props: [TBJSPatternProp] = []
        if !acceptPunct("}") {
            while true {
                if peekPunct() == "}" { break }
                if acceptPunct("...") {
                    // A rest gathers into a name or
                    // a member road — never a
                    // bracket shape of its own.
                    let inner = try parsePatternTarget()
                    if peekPunct() == "=" {
                        throw TBJSFlow.error(
                            "an object rest takes no default")
                    }
                    props.append(.rest(inner))
                    try expectPunct("}")
                    return .object(props)
                }
                if peekPunct() == "[" {
                    throw TBJSFlow.error(
                        "computed keys in a destructuring"
                        + " pattern are not in this stage")
                }
                let key: String
                var plainName = false
                switch peek() {
                case .ident(let name):
                    key = name
                    plainName = true
                    advance()
                case .string(let s):
                    key = s
                    advance()
                case .number(let d):
                    key = tbJSNumberString(d)
                    advance()
                default:
                    throw TBJSFlow.error(
                        "bad name in a destructuring pattern")
                }
                var value: TBJSPattern
                if acceptPunct(":") {
                    value = try parsePattern()
                } else {
                    guard plainName else {
                        throw TBJSFlow.error(
                            "a destructuring shorthand"
                            + " must be a plain name")
                    }
                    value = .name(key)
                }
                if acceptPunct("=") {
                    value = .defaulted(value, try parseAssign())
                }
                props.append(.prop(key, value))
                if !acceptPunct(",") { break }
                if peekPunct() == "}" { break }
            }
            try expectPunct("}")
        }
        return .object(props)
    }

    // The one road for parameter lists (0.39):
    // declarations, function expressions, and
    // arrows all read their parameters here —
    // plain names, names with defaults whose
    // expressions are read whole (commas inside
    // them belong to the expression, so the
    // default is read at the ternary's level),
    // and a closing rest that gathers the rest.
    mutating func parseParams() throws -> [TBJSParam] {
        try expectPunct("(")
        var params: [TBJSParam] = []
        if peekPunct() != ")" {
            while true {
                if acceptPunct("...") {
                    // JavaScript fourth stage
                    // (0.40): the gathered rest may
                    // itself be opened by a pattern.
                    if peekPunct() == "[" || peekPunct() == "{" {
                        params.append(TBJSParam(
                            pattern: try parsePattern(),
                            isRest: true))
                    } else {
                        params.append(TBJSParam(
                            name: try expectIdent(), isRest: true))
                    }
                    break
                }
                // JavaScript fourth stage (0.40):
                // a parameter may be a pattern,
                // opened from its argument when
                // the call is made; a default
                // behind the whole pattern fills a
                // missing or undefined argument,
                // read at the ternary's level like
                // every default on this road.
                if peekPunct() == "[" || peekPunct() == "{" {
                    let pattern = try parsePattern()
                    var fallback: TBJSExpr? = nil
                    if acceptPunct("=") {
                        fallback = try parseTernary()
                    }
                    params.append(TBJSParam(
                        pattern: pattern, default: fallback))
                    if !acceptPunct(",") { break }
                    if peekPunct() == ")" { break }
                    continue
                }
                let name = try expectIdent()
                var fallback: TBJSExpr? = nil
                if acceptPunct("=") {
                    fallback = try parseTernary()
                }
                params.append(TBJSParam(name: name, default: fallback))
                if !acceptPunct(",") { break }
                if peekPunct() == ")" { break }
            }
        }
        try expectPunct(")")
        return params
    }

    mutating func parseFunctionTail() throws
        -> ([TBJSParam], [TBJSStmt]) {
        let params = try parseParams()
        let body = try parseBlock()
        return (params, body)
    }

    // A class declaration (0.39): the name, an
    // optional `extends` naming one other
    // class, and a body of methods — the one
    // named constructor, and the rest by name.
    // JavaScript fifth stage (0.41): the body
    // holds the class face's own members too —
    // static methods, static fields, and
    // accessor pairs (get/set) standing on
    // either face. What this stage still does
    // not hold is named where it stands:
    // static initialization blocks, computed
    // member names, and instance fields.
    mutating func parseClassDecl() throws -> TBJSStmt {
        advance()  // the word class itself
        let name = try expectIdent()
        var parentName: String? = nil
        if acceptIdent("extends") {
            parentName = try expectIdent()
        }
        try expectPunct("{")
        var parts = TBJSClassParts()
        while peekPunct() != "}" {
            if case .eof = peek() {
                throw TBJSFlow.error("unterminated class body")
            }
            skipSemicolons()
            if peekPunct() == "}" { break }
            if peekPunct() == "[" {
                throw TBJSFlow.error(
                    "computed member names in a class body"
                    + " are not in this stage")
            }
            // A static initialization block —
            // `static`, then the body's own
            // brace — is named and refused.
            if peekIdent() == "static",
               case .punct("{") = tokens[min(pos + 1,
                                             tokens.count - 1)] {
                throw TBJSFlow.error(
                    "static initialization blocks"
                    + " are not in this stage")
            }
            var isStatic = false
            // `static` is a modifier only when a
            // member's name follows it; a method
            // merely named static (its name, then
            // its parameters) is an ordinary
            // method, read as one below.
            if peekIdent() == "static",
               case .ident = tokens[min(pos + 1,
                                        tokens.count - 1)] {
                isStatic = true
                advance()
            }
            if isStatic, peekPunct() == "[" {
                throw TBJSFlow.error(
                    "computed member names in a class body"
                    + " are not in this stage")
            }
            // An accessor: get or set, then the
            // member's name, then its parameters.
            // A method merely named get or set
            // (the name, then its parameters)
            // falls through and is read as an
            // ordinary method below.
            if let word = peekIdent(),
               word == "get" || word == "set",
               case .ident = tokens[min(pos + 1,
                                        tokens.count - 1)],
               case .punct("(") = tokens[min(pos + 2,
                                             tokens.count - 1)] {
                advance()  // the word get or set
                let memberName = try expectIdent()
                if isStatic {
                    if memberName == "constructor" {
                        throw TBJSFlow.error(
                            "a constructor cannot be static")
                    }
                    if memberName == "prototype"
                        || memberName == "name"
                        || memberName == "length" {
                        throw TBJSFlow.error(
                            "a static member cannot be named '"
                            + memberName + "' in this stage")
                    }
                } else if memberName == "constructor" {
                    throw TBJSFlow.error(
                        "an accessor cannot be named"
                        + " 'constructor' in this stage")
                }
                let (params, body) = try parseFunctionTail()
                if word == "get", !params.isEmpty {
                    throw TBJSFlow.error(
                        "a getter takes no parameters")
                }
                if word == "set", params.count != 1 {
                    throw TBJSFlow.error(
                        "a setter takes exactly one parameter")
                }
                let alreadyPaired = isStatic
                    ? parts.staticAccessors.contains {
                        $0.0 == memberName }
                    : parts.accessors.contains {
                        $0.0 == memberName }
                if !alreadyPaired {
                    tbJSForgetClassMember(&parts, memberName,
                                          statics: isStatic)
                }
                if isStatic {
                    tbJSMergeAccessor(&parts.staticAccessors,
                                      memberName, word,
                                      (params, body))
                } else {
                    tbJSMergeAccessor(&parts.accessors,
                                      memberName, word,
                                      (params, body))
                }
                skipSemicolons()
                continue
            }
            let memberName = try expectIdent()
            // A field: the name, then a value's
            // opening stroke, the member's own
            // ending, or the body's end. Only
            // the class face's fields are in
            // this stage.
            if peekPunct() == "=" || peekPunct() == ";"
                || peekPunct() == "}" {
                guard isStatic else {
                    throw TBJSFlow.error(
                        "instance fields are not in this stage")
                }
                if memberName == "constructor" {
                    throw TBJSFlow.error(
                        "a constructor cannot be static")
                }
                if memberName == "prototype"
                    || memberName == "name"
                    || memberName == "length" {
                    throw TBJSFlow.error(
                        "a static member cannot be named '"
                        + memberName + "' in this stage")
                }
                var first: TBJSExpr? = nil
                if acceptPunct("=") {
                    first = try parseAssign()
                }
                tbJSForgetClassMember(&parts, memberName,
                                      statics: true)
                parts.staticFields.append((memberName, first))
                skipSemicolons()
                continue
            }
            let (params, body) = try parseFunctionTail()
            if memberName == "constructor" {
                if isStatic {
                    throw TBJSFlow.error(
                        "a constructor cannot be static")
                }
                if parts.ctor != nil {
                    throw TBJSFlow.error(
                        "a class holds one constructor")
                }
                parts.ctor = (params, body)
            } else if isStatic {
                if memberName == "prototype"
                    || memberName == "name"
                    || memberName == "length" {
                    throw TBJSFlow.error(
                        "a static member cannot be named '"
                        + memberName + "' in this stage")
                }
                tbJSForgetClassMember(&parts, memberName,
                                      statics: true)
                parts.statics.append((memberName, params, body))
            } else {
                tbJSForgetClassMember(&parts, memberName,
                                      statics: false)
                parts.methods.append((memberName, params, body))
            }
            skipSemicolons()
        }
        try expectPunct("}")
        return .classDecl(name, parentName, parts)
    }

    mutating func parseStatement() throws -> TBJSStmt {
        skipSemicolons()
        if peekPunct() == "{" {
            return .block(try parseBlock())
        }
        if let word = peekIdent() {
            switch word {
            case "var":
                let decls = try parseDeclList()
                skipSemicolons()
                return decls.count == 1 ? decls[0] : .block(decls)
            case "let", "const":
                // JavaScript third stage (0.39):
                // one statement carrying the whole
                // list, so the room can plant every
                // name before anything runs.
                let stmt = try parseLexicalDeclList()
                skipSemicolons()
                return stmt
            case "function":
                advance()
                let name = try expectIdent()
                let (params, body) = try parseFunctionTail()
                return .funcDecl(name, params, body)
            case "class":
                // JavaScript third stage (0.39).
                let stmt = try parseClassDecl()
                skipSemicolons()
                return stmt
            case "if":
                advance()
                try expectPunct("(")
                let cond = try parseExpr()
                try expectPunct(")")
                let thenBranch = try parseStatement()
                var elseBranch: TBJSStmt? = nil
                if acceptIdent("else") {
                    elseBranch = try parseStatement()
                }
                return .ifElse(cond, thenBranch, elseBranch)
            case "while":
                advance()
                try expectPunct("(")
                let cond = try parseExpr()
                try expectPunct(")")
                return .whileLoop(cond, try parseStatement())
            case "do":
                advance()
                let body = try parseStatement()
                if !acceptIdent("while") {
                    throw TBJSFlow.error("expected 'while' after do")
                }
                try expectPunct("(")
                let cond = try parseExpr()
                try expectPunct(")")
                skipSemicolons()
                return .doWhile(body, cond)
            case "for":
                advance()
                try expectPunct("(")
                // JavaScript third stage (0.39):
                // for-of, first in its let/const
                // dress — one name, no first
                // value, and the word `of` right
                // behind it, where the counted
                // loop would ask for a semicolon.
                if let w = peekIdent(), w == "let" || w == "const" {
                    let nameToken = tokens[min(pos + 1,
                                                tokens.count - 1)]
                    let ofToken = tokens[min(pos + 2,
                                              tokens.count - 1)]
                    if case .ident(let oneName) = nameToken,
                       case .ident(let ofWord) = ofToken,
                       ofWord == "of" {
                        let constant = w == "const"
                        advance()  // let or const
                        advance()  // the name
                        advance()  // of
                        let walked = try parseExpr()
                        try expectPunct(")")
                        return .forOfLexical(
                            oneName, constant, walked,
                            try parseStatement())
                    }
                    // JavaScript fourth stage
                    // (0.40): the same walk with a
                    // pattern in the head — told
                    // apart by the bracket behind
                    // the keyword.
                    let headToken = tokens[min(pos + 1,
                                               tokens.count - 1)]
                    if case .punct(let bracket) = headToken,
                       bracket == "[" || bracket == "{" {
                        let constant = w == "const"
                        advance()  // let or const
                        let pattern = try parsePattern()
                        guard acceptIdent("of") else {
                            throw TBJSFlow.error(
                                "destructuring in a counted"
                                + " for-loop head is not in"
                                + " this stage")
                        }
                        let walked = try parseExpr()
                        try expectPunct(")")
                        return .forOfPattern(
                            pattern,
                            constant ? .declareConst
                                : .declareLet,
                            walked, try parseStatement())
                    }
                }
                // The same walk in its var dress.
                if peekIdent() == "var" {
                    let nameToken = tokens[min(pos + 1,
                                                tokens.count - 1)]
                    let ofToken = tokens[min(pos + 2,
                                              tokens.count - 1)]
                    if case .ident(let oneName) = nameToken,
                       case .ident(let ofWord) = ofToken,
                       ofWord == "of" {
                        advance()  // var
                        advance()  // the name
                        advance()  // of
                        let walked = try parseExpr()
                        try expectPunct(")")
                        return .forOf(.ident(oneName), walked,
                                      try parseStatement(), true)
                    }
                    // JavaScript fourth stage
                    // (0.40): the var walk with a
                    // pattern in its head.
                    let headToken = tokens[min(pos + 1,
                                               tokens.count - 1)]
                    if case .punct(let bracket) = headToken,
                       bracket == "[" || bracket == "{" {
                        advance()  // var
                        let pattern = try parsePattern()
                        guard acceptIdent("of") else {
                            throw TBJSFlow.error(
                                "destructuring in a counted"
                                + " for-loop head is not in"
                                + " this stage")
                        }
                        let walked = try parseExpr()
                        try expectPunct(")")
                        return .forOfPattern(
                            pattern, .declareVar, walked,
                            try parseStatement())
                    }
                }
                // JavaScript third stage (0.39): a
                // let or const in the head makes
                // the loop keep its own bindings,
                // fresh for every round.
                if let w = peekIdent(), w == "let" || w == "const" {
                    let headDecl = try parseLexicalDeclList()
                    guard case .lexicalDecl(let names, let initials,
                                             let constant) = headDecl
                    else {
                        // JavaScript fourth stage
                        // (0.40): a pattern in a
                        // counted head is refused by
                        // name — patterns stand in
                        // for-of heads and plain
                        // declarations in this stage.
                        throw TBJSFlow.error(
                            "destructuring in a counted"
                            + " for-loop head is not in"
                            + " this stage")
                    }
                    try expectPunct(";")
                    var lexCond: TBJSExpr? = nil
                    if peekPunct() != ";" {
                        lexCond = try parseExpr()
                    }
                    try expectPunct(";")
                    var lexStep: TBJSExpr? = nil
                    if peekPunct() != ")" {
                        lexStep = try parseExpr()
                    }
                    try expectPunct(")")
                    return .forLexical(names, initials, constant,
                                       lexCond, lexStep,
                                       try parseStatement())
                }
                var initial: TBJSStmt? = nil
                if peekPunct() != ";" {
                    if peekIdent() == "var" {
                        let decls = try parseDeclList()
                        initial = decls.count == 1 ? decls[0]
                            : .block(decls)
                    } else {
                        // JavaScript fourth stage
                        // (0.40): the head may be a
                        // for-of over a pattern —
                        // tried on a copy of the
                        // reader, since the same
                        // brackets open an array
                        // literal on the counted road.
                        if peekPunct() == "["
                            || peekPunct() == "{" {
                            let saved = pos
                            if let pattern = try? parsePattern(),
                               acceptIdent("of") {
                                let walked = try parseExpr()
                                try expectPunct(")")
                                return .forOfPattern(
                                    pattern, .assign, walked,
                                    try parseStatement())
                            }
                            pos = saved
                        }
                        // JavaScript third stage
                        // (0.39): the head may be a
                        // for-of over an existing
                        // name, member or index —
                        // the word `of` where the
                        // counted loop asks for its
                        // first semicolon.
                        let target = try parseExpr()
                        if acceptIdent("of") {
                            switch target {
                            case .ident, .member, .index:
                                let walked = try parseExpr()
                                try expectPunct(")")
                                return .forOf(
                                    target, walked,
                                    try parseStatement(), false)
                            default:
                                throw TBJSFlow.error(
                                    "for-of walks into a name,"
                                    + " a member or an index")
                            }
                        }
                        initial = .expr(target)
                    }
                }
                try expectPunct(";")
                var cond: TBJSExpr? = nil
                if peekPunct() != ";" { cond = try parseExpr() }
                try expectPunct(";")
                var step: TBJSExpr? = nil
                if peekPunct() != ")" { step = try parseExpr() }
                try expectPunct(")")
                return .forLoop(initial, cond, step,
                                try parseStatement())
            case "return":
                advance()
                var value: TBJSExpr? = nil
                // A value follows unless the next
                // token is ";" or "}" (or the end of
                // the script, checked inside). The
                // 0.33 code also required the next
                // token to be punctuation — but a
                // value can begin with a name, a
                // number or a string, whose next
                // token is not punctuation at all,
                // so "return x", "return 5" and above
                // all "return function() {...}" were
                // read as bare returns. The closure's
                // orphaned "function() {...}" was then
                // parsed as a statement and died on
                // "expected a name" — one bad line
                // silencing a page's whole script
                // (the js-test drill, Nov 5, 2026;
                // the repair is 0.34).
                if peekPunct() != ";" && peekPunct() != "}" {
                    if case .eof = peek() {
                        // No value; the return ends the script.
                    } else {
                        value = try parseExpr()
                    }
                }
                skipSemicolons()
                return .returnStmt(value)
            case "break":
                advance()
                skipSemicolons()
                return .breakStmt
            case "continue":
                advance()
                skipSemicolons()
                return .continueStmt
            case "throw":
                // JavaScript second stage (0.38).
                advance()
                let value = try parseExpr()
                skipSemicolons()
                return .throwStmt(value)
            case "try":
                // JavaScript second stage (0.38):
                // the guarded block, then a catch
                // that names what it caught, a
                // finally that always runs, or
                // both — the language asks for at
                // least one of the two.
                advance()
                let guarded = try parseBlock()
                var catchName: String? = nil
                var catchBody: [TBJSStmt]? = nil
                var finallyBody: [TBJSStmt]? = nil
                if acceptIdent("catch") {
                    try expectPunct("(")
                    catchName = try expectIdent()
                    try expectPunct(")")
                    catchBody = try parseBlock()
                }
                if acceptIdent("finally") {
                    finallyBody = try parseBlock()
                }
                if catchBody == nil && finallyBody == nil {
                    throw TBJSFlow.error(
                        "try without catch or finally")
                }
                return .tryStmt(guarded, catchName, catchBody,
                                finallyBody)
            default:
                break
            }
        }
        let expr = try parseExpr()
        skipSemicolons()
        return .expr(expr)
    }

    mutating func parseExpr() throws -> TBJSExpr {
        return try parseAssign()
    }

    // An arrow function, tried on a copy of the
    // reader (0.39). The tent reads a parameter
    // list — or one bare name — and demands the
    // arrow right behind; if the shape is not an
    // arrow the main reader simply never heard
    // of it, so grouped sums, calls, and plain
    // parentheses walk their old roads untouched.
    mutating func tryParseArrow() -> TBJSExpr? {
        // One bare name: `a => …`.
        if case .ident(let one) = tokens[pos] {
            if case .punct(let p) = tokens[min(pos + 1, tokens.count - 1)],
               p == "=>" {
                let saved = pos
                pos += 2
                if let arrow = parseArrowBody(
                    params: [TBJSParam(name: one)]) {
                    return arrow
                }
                pos = saved
                return nil
            }
            return nil
        }
        guard peekPunct() == "(" else { return nil }
        var depth = 0
        var scan = pos
        while scan < tokens.count {
            if case .punct(let p) = tokens[scan] {
                if p == "(" { depth += 1 }
                if p == ")" {
                    depth -= 1
                    if depth == 0 { break }
                }
            }
            scan += 1
        }
        guard depth == 0, scan + 1 < tokens.count,
              case .punct(let next) = tokens[scan + 1], next == "=>"
        else { return nil }
        let saved = pos
        do {
            let params = try parseParams()
            pos += 1  // the arrow itself
            if let arrow = parseArrowBody(params: params) {
                return arrow
            }
        } catch {
            // Not an arrow after all — the main
            // reader walks its own road.
        }
        pos = saved
        return nil
    }

    // The arrow's body, once the parameters and
    // the arrow are behind us: a block of
    // statements, or one expression carried as
    // a lone expression statement with its flag.
    mutating func parseArrowBody(params: [TBJSParam]) -> TBJSExpr? {
        if peekPunct() == "{" {
            guard let body = try? parseBlock() else {
                return nil
            }
            return .arrowExpr(params, body, false)
        }
        guard let body = try? parseAssign() else {
            return nil
        }
        return .arrowExpr(params, [.expr(body)], true)
    }

    mutating func parseAssign() throws -> TBJSExpr {
        // JavaScript third stage (0.39): an
        // arrow may stand where an assignment
        // stands — tried first, on a copy.
        if let arrow = tryParseArrow() { return arrow }
        // JavaScript fourth stage (0.40): a
        // pattern may stand on an assignment's
        // left — tried on a copy of the reader,
        // since the same brackets open an array
        // or object literal everywhere else. The
        // shape is a pattern only when a lone
        // equals sign stands right behind it;
        // otherwise the reader never heard of
        // it, and literals walk their old road.
        if peekPunct() == "[" || peekPunct() == "{" {
            let saved = pos
            if let pattern = try? parsePattern(),
               peekPunct() == "=" {
                advance()
                return .patternAssign(pattern,
                                      try parseAssign())
            }
            pos = saved
        }
        let lhs = try parseTernary()
        if acceptPunct("=") {
            return .assign(lhs, try parseAssign())
        }
        for op in ["+=", "-=", "*=", "/=", "%="] {
            if peekPunct() == op {
                advance()
                return .opAssign(String(op.dropLast()),
                                 lhs, try parseAssign())
            }
        }
        return lhs
    }

    mutating func parseTernary() throws -> TBJSExpr {
        let cond = try parseOr()
        if acceptPunct("?") {
            let yes = try parseAssign()
            try expectPunct(":")
            let no = try parseAssign()
            return .ternary(cond, yes, no)
        }
        return cond
    }

    mutating func parseBinaryLevel(_ ops: [String],
                                   _ next: (inout TBJSParser) throws
                                       -> TBJSExpr) throws -> TBJSExpr {
        var lhs = try next(&self)
        while let p = peekPunct(), ops.contains(p) {
            advance()
            let rhs = try next(&self)
            lhs = .binary(p, lhs, rhs)
        }
        return lhs
    }

    mutating func parseOr() throws -> TBJSExpr {
        return try parseBinaryLevel(["||"]) { try $0.parseAnd() }
    }
    mutating func parseAnd() throws -> TBJSExpr {
        return try parseBinaryLevel(["&&"]) { try $0.parseEquality() }
    }
    mutating func parseEquality() throws -> TBJSExpr {
        return try parseBinaryLevel(["==", "!=", "===", "!=="]) {
            try $0.parseRelational()
        }
    }
    mutating func parseRelational() throws -> TBJSExpr {
        // JavaScript third stage (0.39): the
        // comparison strokes, and the two word
        // operators — instanceof and in — which
        // ride at this same level, read as
        // identifiers rather than strokes.
        var lhs = try parseAdditive()
        while true {
            if let p = peekPunct(),
               ["<", "<=", ">", ">="].contains(p) {
                advance()
                let rhs = try parseAdditive()
                lhs = .binary(p, lhs, rhs)
                continue
            }
            if let word = peekIdent(),
               word == "instanceof" || word == "in" {
                advance()
                let rhs = try parseAdditive()
                lhs = .binary(word, lhs, rhs)
                continue
            }
            break
        }
        return lhs
    }
    mutating func parseAdditive() throws -> TBJSExpr {
        return try parseBinaryLevel(["+", "-"]) {
            try $0.parseMultiplicative()
        }
    }
    mutating func parseMultiplicative() throws -> TBJSExpr {
        return try parseBinaryLevel(["*", "/", "%"]) {
            try $0.parseUnary()
        }
    }

    mutating func parseUnary() throws -> TBJSExpr {
        if let p = peekPunct(), p == "!" || p == "-" || p == "+" {
            advance()
            return .unary(p, try parseUnary())
        }
        if peekIdent() == "typeof" {
            advance()
            return .unary("typeof", try parseUnary())
        }
        if let p = peekPunct(), p == "++" || p == "--" {
            advance()
            return .prefix(p, try parseUnary())
        }
        return try parsePostfix()
    }

    mutating func parsePostfix() throws -> TBJSExpr {
        var expr = try parseCallMember()
        if let p = peekPunct(), p == "++" || p == "--" {
            advance()
            expr = .postfix(p, expr)
        }
        return expr
    }

    mutating func parseCallMember() throws -> TBJSExpr {
        var expr = try parsePrimary()
        while true {
            if acceptPunct(".") {
                let name = try expectIdent()
                expr = .member(expr, name)
            } else if acceptPunct("[") {
                let index = try parseExpr()
                try expectPunct("]")
                expr = .index(expr, index)
            } else if peekPunct() == "(" {
                advance()
                var args: [TBJSExpr] = []
                if peekPunct() != ")" {
                    while true {
                        // Spread (0.39): an opened
                        // list standing among the
                        // arguments.
                        if acceptPunct("...") {
                            args.append(.spread(try parseAssign()))
                        } else {
                            args.append(try parseAssign())
                        }
                        if !acceptPunct(",") { break }
                    }
                }
                try expectPunct(")")
                expr = .call(expr, args)
            } else {
                break
            }
        }
        return expr
    }

    mutating func parsePrimary() throws -> TBJSExpr {
        switch peek() {
        case .number(let d):
            advance()
            return .literal(.number(d))
        case .string(let s):
            advance()
            return .literal(.string(s))
        case .ident(let name):
            switch name {
            case "true":
                advance()
                return .literal(.boolean(true))
            case "false":
                advance()
                return .literal(.boolean(false))
            case "null":
                advance()
                return .literal(.null)
            case "undefined":
                advance()
                return .literal(.undefined)
            case "function":
                advance()
                if peekIdent() != nil { advance() }  // a name, unused
                let (params, body) = try parseFunctionTail()
                return .funcExpr(params, body)
            case "super":
                // JavaScript third stage (0.39):
                // a constructor call of the
                // parent class, or a name read on
                // the parent class. Anything else
                // `super` might stand for is not
                // in this stage.
                advance()
                if acceptPunct("(") {
                    var args: [TBJSExpr] = []
                    if peekPunct() != ")" {
                        while true {
                            if acceptPunct("...") {
                                args.append(
                                    .spread(try parseAssign()))
                            } else {
                                args.append(try parseAssign())
                            }
                            if !acceptPunct(",") { break }
                        }
                    }
                    try expectPunct(")")
                    return .superCall(args)
                }
                if acceptPunct(".") {
                    return .superMember(try expectIdent())
                }
                throw TBJSFlow.error(
                    "super stands only as super(...)"
                    + " or super.name in this stage")
            case "new":
                // JavaScript second stage (0.38):
                // what is built is a primary with
                // its member road (no calls — a
                // call in the road belongs to the
                // road, not the building), then
                // the building's own arguments,
                // which may be absent entirely.
                advance()
                var target = try parsePrimary()
                while true {
                    if acceptPunct(".") {
                        target = .member(target, try expectIdent())
                    } else if acceptPunct("[") {
                        let index = try parseExpr()
                        try expectPunct("]")
                        target = .index(target, index)
                    } else {
                        break
                    }
                }
                var args: [TBJSExpr] = []
                if acceptPunct("(") {
                    if peekPunct() != ")" {
                        while true {
                            // Spread (0.39): the
                            // building's arguments
                            // open lists too.
                            if acceptPunct("...") {
                                args.append(.spread(try parseAssign()))
                            } else {
                                args.append(try parseAssign())
                            }
                            if !acceptPunct(",") { break }
                        }
                    }
                    try expectPunct(")")
                }
                return .newExpr(target, args)
            default:
                advance()
                return .ident(name)
            }
        case .regex(let pattern, let flags):
            // JavaScript second stage (0.38): a
            // pattern is a value from birth.
            advance()
            return .literal(.regex(pattern, flags, 0))
        case .template(let parts):
            // JavaScript second stage (0.38): a
            // template is weaving — its words
            // and workings folded together with
            // +, left to right, which is exactly
            // what the evaluator's + does to a
            // string and a value. Each working's
            // source is lexed and read on the
            // spot as its own expression.
            advance()
            var woven: TBJSExpr? = nil
            for part in parts {
                let piece: TBJSExpr
                switch part {
                case .text(let words):
                    piece = .literal(.string(words))
                case .exprSource(let workings):
                    var sub = TBJSParser(
                        tokens: try tbJSLex(workings))
                    piece = try sub.parseExpr()
                }
                if let soFar = woven {
                    woven = .binary("+", soFar, piece)
                } else {
                    woven = piece
                }
            }
            return woven ?? .literal(.string(""))
        case .punct("("):
            advance()
            let expr = try parseExpr()
            try expectPunct(")")
            return expr
        case .punct("["):
            advance()
            var elements: [TBJSExpr] = []
            if peekPunct() != "]" {
                while true {
                    // JavaScript third stage (0.39):
                    // spread is gathered here too —
                    // an opened array's values land
                    // in this one, in order.
                    if acceptPunct("...") {
                        elements.append(.spread(try parseAssign()))
                    } else if peekPunct() == "," {
                        elements.append(.literal(.undefined))
                    } else {
                        elements.append(try parseAssign())
                    }
                    if !acceptPunct(",") { break }
                    if peekPunct() == "]" { break }
                }
            }
            try expectPunct("]")
            return .arrayLit(elements)
        case .punct("{"):
            advance()
            var pairs: [(String, TBJSExpr)] = []
            if peekPunct() != "}" {
                while true {
                    let key: String
                    switch peek() {
                    case .ident(let name):
                        key = name
                        advance()
                    case .string(let s):
                        key = s
                        advance()
                    case .number(let d):
                        key = tbJSNumberString(d)
                        advance()
                    default:
                        throw TBJSFlow.error("bad object key")
                    }
                    // JavaScript fifth stage
                    // (0.41): an accessor in an
                    // object literal — get or set,
                    // then a name that is not a
                    // colon — is refused by name.
                    // A plain object here is a
                    // dictionary of values; it has
                    // no doors to stand in it. (A
                    // key merely named get or set,
                    // with its colon after it, is
                    // an ordinary key.)
                    if key == "get" || key == "set",
                       peekPunct() != ":" {
                        throw TBJSFlow.error(
                            "getters and setters in object"
                            + " literals are not in this stage")
                    }
                    try expectPunct(":")
                    pairs.append((key, try parseAssign()))
                    if !acceptPunct(",") { break }
                    if peekPunct() == "}" { break }
                }
            }
            try expectPunct("}")
            return .objectLit(pairs)
        default:
            throw TBJSFlow.error("unexpected token")
        }
    }
}

// MARK: - JavaScript evaluator (0.33)

// The script budget's check (0.36): counted, so
// the clock is read once in a while rather than
// at every statement; thrown as an ordinary
// script error whose message the runner
// recognizes and reports in its own plain words.
func tbJSCheckBudget(_ ctx: TBJSContext) throws {
    guard ctx.budgetDeadline != nil else { return }
    ctx.budgetSteps += 1
    if ctx.budgetSteps % 256 == 0, let deadline = ctx.budgetDeadline,
       Date() > deadline {
        ctx.budgetExceeded = true
        throw TBJSFlow.error("script budget reached")
    }
}

func tbJSExec(_ stmts: [TBJSStmt], _ env: TBJSEnv,
              _ ctx: TBJSContext) throws {
    // Function declarations are hoisted: they
    // exist before the first statement runs.
    for stmt in stmts {
        if case .funcDecl(let name, let params, let body) = stmt {
            env.vars[name] = .function(TBJSFunc(params: params,
                                                body: body, env: env))
        }
    }
    // JavaScript third stage (0.39): the list's
    // let and const names are planted in this
    // room — present but uninitialized — before
    // anything runs. That planting is the whole
    // of the temporal dead zone: the name is
    // found, and the error is honest.
    env.hoistLexical(stmts)
    for stmt in stmts {
        try tbJSCheckBudget(ctx)
        try tbJSExecStmt(stmt, env, ctx)
    }
}

func tbJSExecStmt(_ stmt: TBJSStmt, _ env: TBJSEnv,
                  _ ctx: TBJSContext) throws {
    switch stmt {
    case .empty:
        return
    case .expr(let expr):
        _ = try tbJSEval(expr, env, ctx)
    case .decl(let name, let initial):
        // JavaScript third stage (0.39): var
        // belongs to the nearest function or
        // global room, however deep in blocks the
        // declaration stands — the old flexible
        // behavior, kept whole.
        let home = env.varScope()
        if let initial = initial {
            home.vars[name] = try tbJSEval(initial, env, ctx)
        } else if home.vars[name] == nil {
            home.vars[name] = .undefined
        }
    case .lexicalDecl(let names, let initials, let constant):
        // JavaScript third stage (0.39): the
        // names stand planted in this room by the
        // list's opening; each declarator now
        // gives its name its value, in order, so
        // a later declarator may read an earlier
        // one — and may NOT read its own name or
        // a later one, which are still planted
        // and uninitialized. A const declaration
        // must carry a value, as the standard
        // requires.
        for index in names.indices {
            let value: TBJSValue
            if let initial = initials[index] {
                value = try tbJSEval(initial, env, ctx)
            } else if constant {
                throw TBJSFlow.error(
                    "a constant '"
                    + names[index]
                    + "' must be given a value")
            } else {
                value = .undefined
            }
            env.initializeLexical(names[index], value)
        }
    case .patternVar(let pattern, let source):
        // JavaScript fourth stage (0.40): a var
        // declaration wearing a pattern — the
        // value is reckoned whole, then opened
        // into the nearest function room.
        let value = try tbJSEval(source, env, ctx)
        try tbJSBindPattern(pattern, value, env,
                            .declareVar, ctx)
    case .lexicalPattern(let items, let constant):
        // JavaScript fourth stage (0.40): a let
        // or const list carrying patterns. The
        // names stand planted in this room by
        // the list's opening — patterns' names
        // alongside plain ones — and each
        // declarator now gives its names their
        // values, in order, so a later one may
        // read an earlier, and none may read a
        // name still waiting, its own included.
        for item in items {
            switch item {
            case .name(let name, let initial):
                let value: TBJSValue
                if let initial = initial {
                    value = try tbJSEval(initial, env, ctx)
                } else if constant {
                    throw TBJSFlow.error(
                        "a constant '"
                        + name
                        + "' must be given a value")
                } else {
                    value = .undefined
                }
                env.initializeLexical(name, value)
            case .pattern(let pattern, let source):
                let value = try tbJSEval(source, env, ctx)
                try tbJSBindPattern(
                    pattern, value, env,
                    .declareLexical(constant), ctx)
            }
        }
    case .block(let stmts):
        // JavaScript third stage (0.39): a block
        // is a room of its own — its let and
        // const live and die inside it.
        try tbJSExec(stmts, env.childBlock(), ctx)
    case .funcDecl:
        return  // Hoisted by tbJSExec.
    case .ifElse(let cond, let thenBranch, let elseBranch):
        if tbJSTruthy(try tbJSEval(cond, env, ctx)) {
            try tbJSExecStmt(thenBranch, env, ctx)
        } else if let elseBranch = elseBranch {
            try tbJSExecStmt(elseBranch, env, ctx)
        }
    case .whileLoop(let cond, let body):
        while tbJSTruthy(try tbJSEval(cond, env, ctx)) {
            // The budget check rides the loop head
            // too (0.36): a loop whose body is one
            // bare statement never passes tbJSExec,
            // and an empty body still spins here.
            try tbJSCheckBudget(ctx)
            do {
                try tbJSExecStmt(body, env, ctx)
            } catch let flow as TBJSFlow {
                switch flow {
                case .breakLoop: return
                case .continueLoop: continue
                default: throw flow
                }
            }
        }
    case .doWhile(let body, let cond):
        while true {
            try tbJSCheckBudget(ctx)
            do {
                try tbJSExecStmt(body, env, ctx)
            } catch let flow as TBJSFlow {
                switch flow {
                case .breakLoop: return
                case .continueLoop: break
                default: throw flow
                }
            }
            if !tbJSTruthy(try tbJSEval(cond, env, ctx)) { break }
        }
    case .forLoop(let initial, let cond, let step, let body):
        if let initial = initial {
            try tbJSExecStmt(initial, env, ctx)
        }
        while true {
            try tbJSCheckBudget(ctx)
            if let cond = cond,
               !tbJSTruthy(try tbJSEval(cond, env, ctx)) {
                break
            }
            do {
                try tbJSExecStmt(body, env, ctx)
            } catch let flow as TBJSFlow {
                switch flow {
                case .breakLoop: return
                case .continueLoop: break
                default: throw flow
                }
            }
            if let step = step {
                _ = try tbJSEval(step, env, ctx)
            }
        }
    case .forLexical(let names, let initials, let constant,
                     let cond, let step, let body):
        // JavaScript third stage (0.39): the
        // head's declarations live in their own
        // room under the loop's room. The head
        // runs once there; then, for every round,
        // the bindings are copied into a fresh
        // room — the standard's own dance — so a
        // closure made in one round keeps that
        // round's counter, while the step belongs
        // to the round to come. A const head
        // whose step writes to it fails honestly,
        // as the standard says it must.
        let head = env.childBlock()
        head.hoistLexical([.lexicalDecl(names, initials, constant)])
        try tbJSExecStmt(.lexicalDecl(names, initials, constant),
                         head, ctx)
        // The first round gets a fresh room of
        // its own, copied from the head — never
        // the head itself — and every later
        // round is copied from the round before
        // it before the step runs in the new
        // room. No room a body ran in is ever
        // written again, so a closure made in a
        // round keeps that round's values whole.
        func freshRound(from source: TBJSEnv) -> TBJSEnv {
            let room = env.childBlock()
            for name in names {
                room.declareLexical(name, constant: constant)
                if let value = try? source.lookup(name) {
                    room.initializeLexical(name, value)
                }
            }
            return room
        }
        var roundEnv = freshRound(from: head)
        while true {
            try tbJSCheckBudget(ctx)
            if let cond = cond,
               !tbJSTruthy(try tbJSEval(cond, roundEnv, ctx)) {
                break
            }
            do {
                try tbJSExecStmt(body, roundEnv, ctx)
            } catch let flow as TBJSFlow {
                switch flow {
                case .breakLoop: return
                case .continueLoop: break
                default: throw flow
                }
            }
            // The bindings' present values ride
            // into the next round's fresh room,
            // and the step belongs to that room.
            let next = freshRound(from: roundEnv)
            if let step = step {
                _ = try tbJSEval(step, next, ctx)
            }
            roundEnv = next
        }
    case .forOf(let target, let walked, let body, let declaresVar):
        // JavaScript third stage (0.39): walk
        // an array's values, or a string's
        // letters, handing each to the target
        // in turn. Anything else is not walked
        // in this stage, and says so.
        let iterable = try tbJSEval(walked, env, ctx)
        let items: [TBJSValue]
        switch iterable {
        case .array(let values):
            items = values
        case .string(let s):
            items = s.map { .string(String($0)) }
        default:
            throw TBJSFlow.error(
                "for-of can only walk an array or a string"
                + " in this stage")
        }
        if declaresVar, case .ident(let name) = target {
            let home = env.varScope()
            if home.vars[name] == nil {
                home.vars[name] = .undefined
            }
        }
        for item in items {
            try tbJSCheckBudget(ctx)
            try tbJSAssign(target, item, env, ctx)
            do {
                try tbJSExecStmt(body, env, ctx)
            } catch let flow as TBJSFlow {
                switch flow {
                case .breakLoop: return
                case .continueLoop: continue
                default: throw flow
                }
            }
        }
    case .forOfLexical(let name, let constant, let walked,
                       let body):
        // JavaScript third stage (0.39): the
        // same walk, with a let or const name —
        // a fresh room for every round, so a
        // closure made in one round keeps that
        // round's piece, as the language has it.
        let iterable = try tbJSEval(walked, env, ctx)
        let items: [TBJSValue]
        switch iterable {
        case .array(let values):
            items = values
        case .string(let s):
            items = s.map { .string(String($0)) }
        default:
            throw TBJSFlow.error(
                "for-of can only walk an array or a string"
                + " in this stage")
        }
        for item in items {
            try tbJSCheckBudget(ctx)
            let round = env.childBlock()
            round.declareLexical(name, constant: constant)
            round.initializeLexical(name, item)
            do {
                try tbJSExecStmt(body, round, ctx)
            } catch let flow as TBJSFlow {
                switch flow {
                case .breakLoop: return
                case .continueLoop: continue
                default: throw flow
                }
            }
        }
    case .forOfPattern(let pattern, let kind, let walked,
                       let body):
        // JavaScript fourth stage (0.40): the
        // same walk, with a pattern in the
        // head. Each round's piece is opened
        // into the pattern by the head's own
        // dress: written into bindings that
        // stand, declared with var in the
        // function room, or — let and const —
        // declared in a fresh room for the
        // round, so a closure made in one round
        // keeps that round's pieces.
        let iterable = try tbJSEval(walked, env, ctx)
        let items: [TBJSValue]
        switch iterable {
        case .array(let values):
            items = values
        case .string(let s):
            items = s.map { .string(String($0)) }
        default:
            throw TBJSFlow.error(
                "for-of can only walk an array or a string"
                + " in this stage")
        }
        for item in items {
            try tbJSCheckBudget(ctx)
            switch kind {
            case .assign:
                try tbJSBindPattern(pattern, item, env,
                                    .assign, ctx)
                do {
                    try tbJSExecStmt(body, env, ctx)
                } catch let flow as TBJSFlow {
                    switch flow {
                    case .breakLoop: return
                    case .continueLoop: continue
                    default: throw flow
                    }
                }
            case .declareVar:
                try tbJSBindPattern(pattern, item, env,
                                    .declareVar, ctx)
                do {
                    try tbJSExecStmt(body, env, ctx)
                } catch let flow as TBJSFlow {
                    switch flow {
                    case .breakLoop: return
                    case .continueLoop: continue
                    default: throw flow
                    }
                }
            case .declareLet, .declareConst:
                let constant = kind == .declareConst
                let round = env.childBlock()
                for name in tbJSPatternNames(pattern) {
                    round.declareLexical(name,
                                         constant: constant)
                }
                try tbJSBindPattern(
                    pattern, item, round,
                    .declareLexical(constant), ctx)
                do {
                    try tbJSExecStmt(body, round, ctx)
                } catch let flow as TBJSFlow {
                    switch flow {
                    case .breakLoop: return
                    case .continueLoop: continue
                    default: throw flow
                    }
                }
            }
        }
    case .classDecl(let name, let parentName, let parts):
        // JavaScript third stage (0.39): the
        // class is made where its declaration
        // stands — a box holding its name, its
        // parent, its constructor and methods —
        // and the name is bound in this room.
        // The functions are made in this room,
        // so a class declared inside a function
        // closes over that function's world. The
        // box's stored functions keep no road
        // back to the box; the road is written
        // onto the copies handed out at a build
        // or a member read. JavaScript fifth
        // stage (0.41): the box now also holds
        // the class face's own members, made
        // the same way, and its static fields
        // reckon once, here, in the order they
        // were written — each in a room whose
        // `this` is the class itself, so a
        // later field may read an earlier one
        // through the class's name or through
        // `this`, as the language has it. A
        // field with no written value stands
        // as undefined, present under its name.
        var parent: TBJSClassBox? = nil
        if let parentName = parentName {
            let found = try env.lookup(parentName) ?? .undefined
            guard case .classDef(let parentBox) = found else {
                throw TBJSFlow.error(
                    "class " + name + " extends something"
                    + " that is not a class")
            }
            parent = parentBox
        }
        let box = TBJSClassBox(name: name, parent: parent)
        if let ctor = parts.ctor {
            box.ctor = TBJSFunc(params: ctor.0, body: ctor.1,
                                env: env)
        }
        for (methodName, params, body) in parts.methods {
            box.methods[methodName] = TBJSFunc(
                params: params, body: body, env: env)
        }
        for (methodName, params, body) in parts.statics {
            box.statics[methodName] = TBJSFunc(
                params: params, body: body, env: env)
        }
        for (memberName, pair) in parts.accessors {
            box.accessors[memberName] = TBJSAccessor(
                getter: pair.getter.map {
                    TBJSFunc(params: $0.0, body: $0.1, env: env)
                },
                setter: pair.setter.map {
                    TBJSFunc(params: $0.0, body: $0.1, env: env)
                })
        }
        for (memberName, pair) in parts.staticAccessors {
            box.staticAccessors[memberName] = TBJSAccessor(
                getter: pair.getter.map {
                    TBJSFunc(params: $0.0, body: $0.1, env: env)
                },
                setter: pair.setter.map {
                    TBJSFunc(params: $0.0, body: $0.1, env: env)
                })
        }
        env.vars[name] = .classDef(box)
        if !parts.staticFields.isEmpty {
            let fieldRoom = env.childBlock()
            fieldRoom.vars["this"] = .classDef(box)
            for (fieldName, first) in parts.staticFields {
                if let first = first {
                    box.staticFields[fieldName] =
                        try tbJSEval(first, fieldRoom, ctx)
                } else {
                    box.staticFields[fieldName] = .undefined
                }
            }
        }
    case .returnStmt(let value):
        if let value = value {
            throw TBJSFlow.returnValue(try tbJSEval(value, env, ctx))
        }
        throw TBJSFlow.returnValue(.undefined)
    case .breakStmt:
        throw TBJSFlow.breakLoop
    case .continueStmt:
        throw TBJSFlow.continueLoop
    case .throwStmt(let value):
        // JavaScript second stage (0.38): what
        // the script throws is a value, and it
        // travels as one until a catch holds it.
        throw TBJSFlow.thrown(try tbJSEval(value, env, ctx))
    case .tryStmt(let guarded, let catchName, let catchBody,
                  let finallyBody):
        // JavaScript second stage (0.38). The
        // guarded block runs in its own scope.
        // Whatever leaves it early — a thrown
        // value, an engine error, a return, a
        // break, a continue — is set aside; the
        // catch, if one stands and the leaving
        // was a throw or an error, holds it (a
        // thrown value as itself, an error as
        // its message); the finally, if one
        // stands, then runs on every road; and
        // whatever was set aside rides on —
        // unless the catch or the finally left
        // early itself, and that leaving wins.
        var pending: TBJSFlow? = nil
        do {
            try tbJSExec(guarded, env.childBlock(), ctx)
        } catch let flow as TBJSFlow {
            switch flow {
            case .error(let message):
                if let catchName = catchName, let catchBody = catchBody {
                    let catchEnv = env.childBlock()
                    catchEnv.vars[catchName] = .string(message)
                    do {
                        try tbJSExec(catchBody, catchEnv, ctx)
                    } catch let inner as TBJSFlow {
                        pending = inner
                    }
                } else {
                    pending = flow
                }
            case .thrown(let value):
                if let catchName = catchName, let catchBody = catchBody {
                    let catchEnv = env.childBlock()
                    catchEnv.vars[catchName] = value
                    do {
                        try tbJSExec(catchBody, catchEnv, ctx)
                    } catch let inner as TBJSFlow {
                        pending = inner
                    }
                } else {
                    pending = flow
                }
            case .returnValue, .breakLoop, .continueLoop:
                pending = flow
            }
        }
        if let finallyBody = finallyBody {
            do {
                try tbJSExec(finallyBody, env.childBlock(), ctx)
            } catch let inner as TBJSFlow {
                pending = inner
            }
        }
        if let pending = pending { throw pending }
    }
}

// JavaScript third stage (0.39): carries a renewed
// value back to the name its walk bottomed out at.
// The value is threaded down the member/index chain
// by re-entering the setters with the chain's own
// nested values, and lands in the name's room
// directly — a renewal of what the binding holds,
// never a rebinding of the name itself. Returns
// false when the chain bottoms out at something
// that is not a name, leaving the caller its old
// road.
func tbJSStoreValue(_ target: TBJSExpr, _ value: TBJSValue,
                    _ env: TBJSEnv, _ ctx: TBJSContext) -> Bool {
    switch target {
    case .ident(let name):
        guard env.get(name) != nil else { return false }
        env.vars[name] = value
        return true
    case .member(let baseExpr, let name):
        let base = (try? tbJSEval(baseExpr, env, ctx)) ?? .undefined
        let renewed = (try? tbJSSetMember(base, name, value,
                                          ctx)) ?? base
        return tbJSStoreValue(baseExpr, renewed, env, ctx)
    case .index(let baseExpr, let indexExpr):
        let base = (try? tbJSEval(baseExpr, env, ctx)) ?? .undefined
        let index = (try? tbJSEval(indexExpr, env, ctx)) ?? .undefined
        let renewed = (try? tbJSSetIndex(base, index, value,
                                         ctx)) ?? base
        return tbJSStoreValue(baseExpr, renewed, env, ctx)
    default:
        return false
    }
}

// JavaScript fourth stage (0.40): every name a
// pattern binds, in the order it binds them —
// the rooms plant these before a list runs, and
// a for-of head plants them for every round.
func tbJSPatternNames(_ pattern: TBJSPattern) -> [String] {
    switch pattern {
    case .name(let name):
        return [name]
    case .target:
        return []
    case .defaulted(let inner, _):
        return tbJSPatternNames(inner)
    case .array(let items):
        var names: [String] = []
        for item in items {
            switch item {
            case .hole:
                continue
            case .item(let inner), .rest(let inner):
                names.append(contentsOf: tbJSPatternNames(inner))
            }
        }
        return names
    case .object(let props):
        var names: [String] = []
        for prop in props {
            switch prop {
            case .prop(_, let inner):
                names.append(contentsOf: tbJSPatternNames(inner))
            case .rest(let inner):
                names.append(contentsOf: tbJSPatternNames(inner))
            }
        }
        return names
    }
}

// JavaScript fourth stage (0.40): plant one
// name with its value, by the road the
// pattern's home prescribes.
func tbJSBindName(_ name: String, _ value: TBJSValue,
                  _ env: TBJSEnv, _ mode: TBJSBindMode,
                  _ ctx: TBJSContext) throws {
    switch mode {
    case .assign:
        try tbJSAssign(.ident(name), value, env, ctx)
    case .declareVar:
        // A var declarator's own road: the name
        // takes its value in the function room.
        env.varScope().vars[name] = value
    case .declareParam:
        env.vars[name] = value
    case .declareLexical:
        env.initializeLexical(name, value)
    }
}

// JavaScript fourth stage (0.40): open a value
// into a pattern. Pieces are handed out left
// to right; a default fills only an undefined
// piece, reckoned where the pattern stands, so
// it may read the pieces already handed out.
// Null and undefined cannot be opened at all —
// the error is an ordinary script error, and a
// catch can hold it. An array pattern opens an
// array or a string, as for-of walks them; an
// object pattern reads its pieces through the
// same member road every read walks.
func tbJSBindPattern(_ pattern: TBJSPattern, _ value: TBJSValue,
                     _ env: TBJSEnv, _ mode: TBJSBindMode,
                     _ ctx: TBJSContext) throws {
    switch pattern {
    case .name(let name):
        try tbJSBindName(name, value, env, mode, ctx)
    case .target(let expr):
        // A member road may only be written by
        // an assignment; a declaration wearing
        // one is refused honestly, here where
        // it runs.
        guard case .assign = mode else {
            throw TBJSFlow.error(
                "a destructuring declaration cannot"
                + " write a member")
        }
        try tbJSAssign(expr, value, env, ctx)
    case .defaulted(let inner, let fallback):
        if case .undefined = value {
            let filled = try tbJSEval(fallback, env, ctx)
            try tbJSBindPattern(inner, filled, env, mode, ctx)
        } else {
            try tbJSBindPattern(inner, value, env, mode, ctx)
        }
    case .array(let items):
        let values: [TBJSValue]
        switch value {
        case .array(let opened):
            values = opened
        case .string(let s):
            values = s.map { .string(String($0)) }
        case .null, .undefined:
            throw TBJSFlow.error(
                "cannot destructure null or undefined")
        default:
            throw TBJSFlow.error(
                "an array pattern can only open an array"
                + " or a string in this stage")
        }
        for (index, item) in items.enumerated() {
            switch item {
            case .hole:
                continue
            case .item(let inner):
                let piece = index < values.count
                    ? values[index] : .undefined
                try tbJSBindPattern(inner, piece, env, mode, ctx)
            case .rest(let inner):
                let remaining = Array(values.dropFirst(index))
                try tbJSBindPattern(inner, .array(remaining),
                                    env, mode, ctx)
            }
        }
    case .object(let props):
        if case .null = value {
            throw TBJSFlow.error(
                "cannot destructure null or undefined")
        }
        if case .undefined = value {
            throw TBJSFlow.error(
                "cannot destructure null or undefined")
        }
        var taken: Set<String> = []
        var restTarget: TBJSPattern? = nil
        for prop in props {
            switch prop {
            case .prop(let key, let inner):
                taken.insert(key)
                let piece = try tbJSGetMember(value, key, ctx)
                try tbJSBindPattern(inner, piece, env, mode, ctx)
            case .rest(let inner):
                restTarget = inner
            }
        }
        if let restTarget = restTarget {
            // The rest gathers what no named
            // piece took, from a plain object's
            // own properties or an instance's own
            // fields — the two shapes whose whole
            // contents this engine can honestly
            // enumerate.
            let gathered: TBJSValue
            switch value {
            case .object(let obj):
                var rest: [String: TBJSValue] = [:]
                for (key, held) in obj where !taken.contains(key) {
                    rest[key] = held
                }
                gathered = .object(rest)
            case .instance(let box):
                var rest: [String: TBJSValue] = [:]
                for (key, held) in box.fields
                where !taken.contains(key) {
                    rest[key] = held
                }
                gathered = .object(rest)
            default:
                throw TBJSFlow.error(
                    "an object rest can only gather an"
                    + " object in this stage")
            }
            try tbJSBindPattern(restTarget, gathered,
                                env, mode, ctx)
        }
    }
}

func tbJSAssign(_ target: TBJSExpr, _ value: TBJSValue, _ env: TBJSEnv,
                _ ctx: TBJSContext) throws {
    switch target {
    case .ident(let name):
        // Script navigation (0.37): while the name
        // still holds the page's own location,
        // assigning it is a journey, not a
        // variable — every browser reads
        // location = "…" as travel.
        if name == "location", let held = env.get(name),
           case .location = held,
           tbJSResolveNavigation(value, base: ctx.pageURL) != nil {
            ctx.requestNavigation(value)
            return
        }
        try env.set(name, value)
    case .member(let baseExpr, let name):
        let base = try tbJSEval(baseExpr, env, ctx)
        let newBase = try tbJSSetMember(base, name, value, ctx)
        // JavaScript third stage (0.39): when the
        // chain bottoms out at a name, the whole
        // renewed value is carried back through the
        // tree and stored by this function's own
        // road — straight into the name's room —
        // never through env.set. A member write is
        // a renewal of what the binding holds, not
        // a rebinding of the name, so it never asks
        // the const question; env.set remains the
        // road, and stays strict, only for true
        // rebindings. Element and document writes
        // already landed in place and never reach
        // this road at all.
        if tbJSStoreValue(baseExpr, newBase, env, ctx) {
            return
        }
        switch baseExpr {
        case .ident, .member, .index:
            try tbJSAssign(baseExpr, newBase, env, ctx)
        default:
            break  // Element writes already landed in place.
        }
    case .index(let baseExpr, let indexExpr):
        let base = try tbJSEval(baseExpr, env, ctx)
        let index = try tbJSEval(indexExpr, env, ctx)
        let newBase = try tbJSSetIndex(base, index, value, ctx)
        // JavaScript third stage (0.39): an index
        // write into a name-held value is the same
        // renewal as a member write — carried back
        // through tbJSStoreValue, never through the
        // rebinding road.
        if tbJSStoreValue(baseExpr, newBase, env, ctx) {
            return
        }
        switch baseExpr {
        case .ident, .member, .index:
            try tbJSAssign(baseExpr, newBase, env, ctx)
        default:
            break
        }
    default:
        break  // Not an assignable shape; let the page go on.
    }
}

func tbJSEval(_ expr: TBJSExpr, _ env: TBJSEnv,
              _ ctx: TBJSContext) throws -> TBJSValue {
    switch expr {
    case .literal(let value):
        return value
    case .ident(let name):
        // JavaScript third stage (0.39): a name
        // planted in this block but not yet
        // declared reads as an error — the
        // temporal dead zone — never as silence.
        // A name nobody planted anywhere keeps
        // the old leniency: undefined, not a halt.
        return try env.lookup(name) ?? .undefined
    case .arrayLit(let elements):
        var values: [TBJSValue] = []
        for element in elements {
            // Spread (0.39): an opened list lays
            // its values into this one, in order.
            if case .spread(let inner) = element {
                let opened = try tbJSEval(inner, env, ctx)
                guard case .array(let items) = opened else {
                    throw TBJSFlow.error(
                        "only an array can be spread here")
                }
                values.append(contentsOf: items)
            } else {
                values.append(try tbJSEval(element, env, ctx))
            }
        }
        return .array(values)
    case .objectLit(let pairs):
        var obj: [String: TBJSValue] = [:]
        for (key, valueExpr) in pairs {
            obj[key] = try tbJSEval(valueExpr, env, ctx)
        }
        return .object(obj)
    case .member(let baseExpr, let name):
        let base = try tbJSEval(baseExpr, env, ctx)
        return try tbJSGetMember(base, name, ctx)
    case .index(let baseExpr, let indexExpr):
        let base = try tbJSEval(baseExpr, env, ctx)
        let index = try tbJSEval(indexExpr, env, ctx)
        return try tbJSGetIndex(base, index, ctx)
    case .call(let callee, let argExprs):
        var args: [TBJSValue] = []
        for argExpr in argExprs {
            // Spread (0.39): an opened list
            // gives its values into the call,
            // in order.
            if case .spread(let inner) = argExpr {
                let opened = try tbJSEval(inner, env, ctx)
                guard case .array(let items) = opened else {
                    throw TBJSFlow.error(
                        "only an array can be spread here")
                }
                args.append(contentsOf: items)
            } else {
                args.append(try tbJSEval(argExpr, env, ctx))
            }
        }
        switch callee {
        case .member(let baseExpr, let name):
            let base = try tbJSEval(baseExpr, env, ctx)
            let fn = try tbJSGetMember(base, name, ctx)
            ctx.mutatedThis = nil
            let result = try tbJSCall(fn, args, this: base, ctx)
            if let mutated = ctx.mutatedThis {
                ctx.mutatedThis = nil
                switch baseExpr {
                case .ident, .member, .index:
                    try tbJSAssign(baseExpr, mutated, env, ctx)
                default:
                    break
                }
            }
            return result
        case .index(let baseExpr, let indexExpr):
            let base = try tbJSEval(baseExpr, env, ctx)
            let index = try tbJSEval(indexExpr, env, ctx)
            let fn = try tbJSGetIndex(base, index, ctx)
            return try tbJSCall(fn, args, this: base, ctx)
        case .superMember:
            // JavaScript third stage (0.39): a
            // parent class's method, called with
            // this very `this` — the road
            // super.method() walks.
            let fn = try tbJSEval(callee, env, ctx)
            return try tbJSCall(fn, args,
                                this: env.get("this") ?? .undefined,
                                ctx)
        default:
            let fn = try tbJSEval(callee, env, ctx)
            return try tbJSCall(fn, args, this: .undefined, ctx)
        }
    case .unary(let op, let inner):
        switch op {
        case "!":
            return .boolean(!tbJSTruthy(try tbJSEval(inner, env, ctx)))
        case "-":
            return .number(-tbJSNumber(try tbJSEval(inner, env, ctx)))
        case "+":
            return .number(tbJSNumber(try tbJSEval(inner, env, ctx)))
        case "typeof":
            return .string(tbJSTypeName(try tbJSEval(inner, env, ctx)))
        default:
            throw TBJSFlow.error("unknown operator \(op)")
        }
    case .prefix(let op, let target):
        let old = try tbJSEval(target, env, ctx)
        let new = tbJSNumber(old) + (op == "++" ? 1 : -1)
        try tbJSAssign(target, .number(new), env, ctx)
        return .number(new)
    case .postfix(let op, let target):
        let old = try tbJSEval(target, env, ctx)
        let oldNumber = tbJSNumber(old)
        try tbJSAssign(target, .number(oldNumber + (op == "++" ? 1 : -1)),
                       env, ctx)
        return .number(oldNumber)
    case .binary(let op, let lhs, let rhs):
        if op == "&&" {
            let left = try tbJSEval(lhs, env, ctx)
            return tbJSTruthy(left) ? try tbJSEval(rhs, env, ctx) : left
        }
        if op == "||" {
            let left = try tbJSEval(lhs, env, ctx)
            return tbJSTruthy(left) ? left : try tbJSEval(rhs, env, ctx)
        }
        let left = try tbJSEval(lhs, env, ctx)
        let right = try tbJSEval(rhs, env, ctx)
        switch op {
        case "+":
            if case .string = left { return .string(tbJSString(left) + tbJSString(right)) }
            if case .string = right { return .string(tbJSString(left) + tbJSString(right)) }
            return .number(tbJSNumber(left) + tbJSNumber(right))
        case "-":
            return .number(tbJSNumber(left) - tbJSNumber(right))
        case "*":
            return .number(tbJSNumber(left) * tbJSNumber(right))
        case "/":
            return .number(tbJSNumber(left) / tbJSNumber(right))
        case "%":
            return .number(tbJSNumber(left)
                .truncatingRemainder(dividingBy: tbJSNumber(right)))
        case "==": return .boolean(tbJSLooseEqual(left, right))
        case "!=": return .boolean(!tbJSLooseEqual(left, right))
        case "===": return .boolean(tbJSStrictEqual(left, right))
        case "!==": return .boolean(!tbJSStrictEqual(left, right))
        case "instanceof":
            // JavaScript third stage (0.39).
            return .boolean(tbJSInstanceOf(left, right, ctx))
        case "in":
            // JavaScript third stage (0.39).
            return .boolean(tbJSHasProperty(right, tbJSString(left),
                                            ctx))
        case "<", "<=", ">", ">=":
            if case .string(let a) = left, case .string(let b) = right {
                switch op {
                case "<": return .boolean(a < b)
                case "<=": return .boolean(a <= b)
                case ">": return .boolean(a > b)
                default: return .boolean(a >= b)
                }
            }
            let a = tbJSNumber(left)
            let b = tbJSNumber(right)
            switch op {
            case "<": return .boolean(a < b)
            case "<=": return .boolean(a <= b)
            case ">": return .boolean(a > b)
            default: return .boolean(a >= b)
            }
        default:
            throw TBJSFlow.error("unknown operator \(op)")
        }
    case .assign(let target, let valueExpr):
        let value = try tbJSEval(valueExpr, env, ctx)
        try tbJSAssign(target, value, env, ctx)
        return value
    case .patternAssign(let pattern, let valueExpr):
        // JavaScript fourth stage (0.40): the
        // value is reckoned whole before any
        // piece is handed out — the reckoning
        // is what makes a swap a swap — and the
        // assignment answers the value, like
        // every assignment here.
        let value = try tbJSEval(valueExpr, env, ctx)
        try tbJSBindPattern(pattern, value, env, .assign, ctx)
        return value
    case .opAssign(let op, let target, let valueExpr):
        let current = try tbJSEval(target, env, ctx)
        let operand = try tbJSEval(valueExpr, env, ctx)
        let value: TBJSValue
        switch op {
        case "+":
            if case .string = current {
                value = .string(tbJSString(current) + tbJSString(operand))
            } else if case .string = operand {
                value = .string(tbJSString(current) + tbJSString(operand))
            } else {
                value = .number(tbJSNumber(current) + tbJSNumber(operand))
            }
        case "-":
            value = .number(tbJSNumber(current) - tbJSNumber(operand))
        case "*":
            value = .number(tbJSNumber(current) * tbJSNumber(operand))
        case "/":
            value = .number(tbJSNumber(current) / tbJSNumber(operand))
        case "%":
            value = .number(tbJSNumber(current)
                .truncatingRemainder(dividingBy: tbJSNumber(operand)))
        default:
            throw TBJSFlow.error("unknown operator \(op)=")
        }
        try tbJSAssign(target, value, env, ctx)
        return value
    case .ternary(let cond, let yes, let no):
        if tbJSTruthy(try tbJSEval(cond, env, ctx)) {
            return try tbJSEval(yes, env, ctx)
        }
        return try tbJSEval(no, env, ctx)
    case .funcExpr(let params, let body):
        return .function(TBJSFunc(params: params, body: body, env: env))
    case .arrowExpr(let params, let body, let isExpression):
        // JavaScript third stage (0.39): the
        // arrow is born holding two things from
        // the room where it stands — its scope,
        // and that room's `this`, which no later
        // call can take from it.
        return .function(TBJSFunc(
            params: params, body: body, env: env,
            capturedThis: TBJSBoxedValue(
                env.get("this") ?? .undefined),
            expressionBody: isExpression))
    case .superCall(let argExprs):
        // JavaScript third stage (0.39): build
        // this instance through the parent
        // class's constructor. Only a class
        // constructor may stand here, and only
        // one whose class has a parent. The
        // fresh instance rides in the frame the
        // constructor's call laid down, because
        // the constructor's own `this` reads
        // unbound until this call binds it.
        guard let frame = ctx.classFrames.last,
              frame.isConstructor else {
            throw TBJSFlow.error(
                "super(...) stands only in a class constructor")
        }
        guard let parent = frame.home.parent else {
            throw TBJSFlow.error(
                "this class has no parent to build through")
        }
        var args: [TBJSValue] = []
        for argExpr in argExprs {
            if case .spread(let inner) = argExpr {
                let opened = try tbJSEval(inner, env, ctx)
                guard case .array(let items) = opened else {
                    throw TBJSFlow.error(
                        "only an array can be spread here")
                }
                args.append(contentsOf: items)
            } else {
                args.append(try tbJSEval(argExpr, env, ctx))
            }
        }
        let startThis = frame.pendingThis
            ?? (env.get("this") ?? .undefined)
        let boundThis = try tbJSInvokeClassConstructor(
            parent, args, this: startThis, ctx)
        try env.set("this", boundThis)
        return boundThis
    case .superMember(let name):
        // JavaScript third stage (0.39): a name
        // read on the parent of the class the
        // standing method was written in. The
        // method is handed out carrying the
        // class it was found on, so a `super`
        // inside it looks one road further up.
        // JavaScript fifth stage (0.41): the
        // read may also find a door — an
        // accessor standing on the parent's
        // road is called with this very `this`
        // — and inside a static member the
        // whole read climbs the static road
        // instead: the parent's static
        // accessors, fields and methods.
        guard let frame = ctx.classFrames.last else {
            throw TBJSFlow.error(
                "super stands only in a class method"
                + " or constructor")
        }
        let standingThis = env.get("this") ?? .undefined
        var cursor = frame.home.parent
        while let current = cursor {
            if frame.isStatic {
                if let pair = current.staticAccessors[name] {
                    guard let stored = pair.getter else {
                        return .undefined
                    }
                    var getter = stored
                    getter.classHome = current
                    getter.isStatic = true
                    return try tbJSCall(.function(getter), [],
                                        this: standingThis, ctx)
                }
                if let field = current.staticFields[name] {
                    return field
                }
                if let stored = current.statics[name] {
                    var method = stored
                    method.classHome = current
                    method.isStatic = true
                    return .function(method)
                }
            } else {
                if let pair = current.accessors[name] {
                    guard let stored = pair.getter else {
                        return .undefined
                    }
                    var getter = stored
                    getter.classHome = current
                    return try tbJSCall(.function(getter), [],
                                        this: standingThis, ctx)
                }
                if let stored = current.methods[name] {
                    var method = stored
                    method.classHome = current
                    return .function(method)
                }
            }
            cursor = current.parent
        }
        return .undefined
    case .spread:
        // Spread (0.39) is opened where it
        // stands — in a call's arguments, a
        // building's arguments, or an array
        // literal — and never read as a value.
        throw TBJSFlow.error("spread outside its place")
    case .newExpr(let target, let argExprs):
        // JavaScript second stage (0.38):
        // building. RegExp is the one native
        // constructor; a reader's own function
        // builds a plain object, is called with
        // the object as its `this`, and the
        // object is the result — unless the
        // function returns an object-shaped
        // value of its own, which wins, as the
        // language has it. The function's final
        // `this` is read back through the same
        // mutatedThis road the array helpers use,
        // because here values are copies: a
        // constructor's `this.x = …` writes land
        // on its scope's binding, and the built
        // thing is that binding at the end.
        var args: [TBJSValue] = []
        for argExpr in argExprs {
            // Spread (0.39): an opened list
            // gives its values into the building,
            // in order; anything else that is
            // spread here is an honest error.
            if case .spread(let inner) = argExpr {
                let opened = try tbJSEval(inner, env, ctx)
                guard case .array(let items) = opened else {
                    throw TBJSFlow.error(
                        "only an array can be spread here")
                }
                args.append(contentsOf: items)
            } else {
                args.append(try tbJSEval(argExpr, env, ctx))
            }
        }
        let built = try tbJSEval(target, env, ctx)
        switch built {
        case .native(let name) where name == "global.RegExp":
            return try tbJSNative(name, args, this: .undefined, ctx)
        case .classDef(let box):
            // JavaScript third stage (0.39): a
            // class builds an instance of its
            // own — fields in a fresh box, the
            // class riding with it.
            return try tbJSConstructClass(box, args, ctx)
        case .function:
            // JavaScript third stage (0.39): an
            // arrow cannot be built with — the
            // standard says so plainly, and the
            // error is catchable like any throw.
            if case .function(let fn) = built, fn.capturedThis != nil {
                throw TBJSFlow.error(
                    "an arrow function cannot be used with new")
            }
            let fresh = TBJSValue.object([:])
            ctx.mutatedThis = nil
            let result = try tbJSCall(built, args, this: fresh, ctx)
            let finalThis = ctx.mutatedThis ?? fresh
            ctx.mutatedThis = nil
            switch result {
            case .object, .array, .function, .native, .regex,
                 .element, .instance, .classDef:
                return result
            default:
                return finalThis
            }
        default:
            throw TBJSFlow.error(
                "tried to construct with something"
                + " that is not a constructor")
        }
    }
}

// JavaScript third stage (0.39): building an
// instance of a class. A fresh box is made,
// the class's constructor runs with the box as
// its `this`, and the box is the result —
// unless a constructor returns an
// object-shaped value of its own, which wins,
// as the language has it.
func tbJSConstructClass(_ box: TBJSClassBox, _ args: [TBJSValue],
                        _ ctx: TBJSContext) throws -> TBJSValue {
    let fresh = TBJSValue.instance(TBJSInstanceBox(klass: box))
    return try tbJSInvokeClassConstructor(box, args, this: fresh,
                                          ctx)
}

// Run one class's constructor on an instance
// already in hand (0.39) — the road both `new`
// and `super(...)` walk. A class with no
// written constructor hands the building to
// its parent with the same arguments, the
// language's default; a root class with none
// simply gives the instance back. A derived
// class's written constructor must call
// super(...) before it ends — its `this`
// reads unbound until it does, and ending
// still unbound is an honest error.
func tbJSInvokeClassConstructor(_ box: TBJSClassBox,
                                _ args: [TBJSValue],
                                this: TBJSValue,
                                _ ctx: TBJSContext) throws
    -> TBJSValue {
    if let stored = box.ctor {
        var fn = stored
        fn.classHome = box
        fn.isClassConstructor = true
        ctx.mutatedThis = nil
        let result = try tbJSCall(.function(fn), args, this: this,
                                  ctx)
        let finalThis = ctx.mutatedThis ?? this
        ctx.mutatedThis = nil
        switch result {
        case .object, .array, .function, .native, .regex,
             .element, .instance, .classDef:
            return result
        default:
            if box.parent != nil, case .undefined = finalThis {
                throw TBJSFlow.error(
                    "a constructor for a class that extends"
                    + " another must call super(...) first")
            }
            return finalThis
        }
    }
    if let parent = box.parent {
        return try tbJSInvokeClassConstructor(parent, args,
                                              this: this, ctx)
    }
    return this
}

func tbJSCall(_ fn: TBJSValue, _ args: [TBJSValue], this: TBJSValue,
              _ ctx: TBJSContext) throws -> TBJSValue {
    switch fn {
    case .function(let fn):
        // JavaScript third stage (0.39): the
        // receiver is chosen honestly — an arrow
        // keeps the `this` of the room where it
        // was born, whatever it is called on; an
        // ordinary function takes the call's own
        // receiver, as it always has.
        var receiver = fn.capturedThis?.value ?? this
        // A class's method or constructor lays
        // its frame on the context's stack for
        // the length of the call, so `super`
        // knows the class it was written in. A
        // derived class's constructor starts
        // with its `this` unbound: the fresh
        // instance rides in the frame until
        // super(...) binds it.
        let pushedFrame = fn.classHome != nil
        if let home = fn.classHome {
            if fn.isClassConstructor, home.parent != nil {
                ctx.classFrames.append(
                    (home: home, isConstructor: true,
                     isStatic: fn.isStatic,
                     pendingThis: receiver))
                receiver = .undefined
            } else {
                ctx.classFrames.append(
                    (home: home,
                     isConstructor: fn.isClassConstructor,
                     isStatic: fn.isStatic,
                     pendingThis: nil))
            }
        }
        defer {
            if pushedFrame { ctx.classFrames.removeLast() }
        }
        let callEnv = TBJSEnv(parent: fn.env)
        callEnv.vars["this"] = receiver
        // The parameters bind in order (0.39):
        // each takes its argument; an explicit
        // undefined wakes a default just as a
        // missing argument does; the defaults
        // reckon in this very room, so a later
        // one may read an earlier parameter; and
        // a rest gathers whatever arguments
        // remain into a true array. A pattern
        // parameter (0.40) is opened from its
        // argument — after its own default, if
        // it carries one, has filled an
        // undefined — and its names plant in
        // this room like any parameter's.
        var taken = 0
        for param in fn.params {
            if param.isRest {
                let gathered: TBJSValue =
                    .array(Array(args.dropFirst(taken)))
                if let pattern = param.pattern {
                    try tbJSBindPattern(pattern, gathered,
                                        callEnv, .declareParam,
                                        ctx)
                } else {
                    callEnv.vars[param.name] = gathered
                }
                continue
            }
            var value: TBJSValue = taken < args.count
                ? args[taken] : .undefined
            taken += 1
            if case .undefined = value, let fallback = param.default {
                value = try tbJSEval(fallback, callEnv, ctx)
            }
            if let pattern = param.pattern {
                try tbJSBindPattern(pattern, value, callEnv,
                                    .declareParam, ctx)
            } else {
                callEnv.vars[param.name] = value
            }
        }
        if fn.expressionBody {
            // An arrow whose body is one
            // expression: its value is the answer.
            if case .expr(let bodyExpr)? = fn.body.first {
                return try tbJSEval(bodyExpr, callEnv, ctx)
            }
            return .undefined
        }
        do {
            try tbJSExec(fn.body, callEnv, ctx)
        } catch let flow as TBJSFlow {
            switch flow {
            case .returnValue(let value):
                // The function's last word on its
                // `this` rides back (0.38): a
                // method's — or a constructor's —
                // writes to it are writes of copies
                // here, and the call site restores
                // them to the thing it called on.
                ctx.mutatedThis = callEnv.vars["this"]
                return value
            case .breakLoop, .continueLoop:
                throw TBJSFlow.error("break or continue outside a loop")
            case .error, .thrown:
                throw flow
            }
        }
        ctx.mutatedThis = callEnv.vars["this"]
        return .undefined
    case .classDef(let box):
        // JavaScript third stage (0.39): a
        // class is built with `new`, never
        // called bare — the language says so,
        // and the error is catchable.
        throw TBJSFlow.error(
            "class " + box.name + " cannot be called"
            + " without new")
    case .native(let name):
        return try tbJSNative(name, args, this: this, ctx)
    default:
        throw TBJSFlow.error("tried to call something that is not a function")
    }
}

func tbJSNative(_ name: String, _ args: [TBJSValue], this: TBJSValue,
                _ ctx: TBJSContext) throws -> TBJSValue {
    func arg(_ index: Int) -> TBJSValue {
        index < args.count ? args[index] : .undefined
    }
    switch name {
    case "console.log":
        ctx.logs.append(args.map { tbJSString($0) }
            .joined(separator: " "))
        return .undefined
    case "window.alert":
        ctx.logs.append("Alert: " + tbJSString(arg(0)))
        return .undefined
    case "location.replace", "location.assign":
        // Script navigation (0.37): the journey is
        // recorded, not taken — the render follows
        // it through the Shield-checked fetch, the
        // way a meta refresh is followed, so a
        // script can send the reader nowhere the
        // address bar could not.
        ctx.requestNavigation(arg(0))
        return .undefined
    case "location.toString":
        return .string(ctx.navigationTarget ?? ctx.pageURL)
    case "document.getElementById":
        let id = tbJSString(arg(0))
        if let node = ctx.elementsById[id] {
            return .element(node)
        }
        return .null
    case "global.parseInt":
        let text = tbJSString(arg(0))
            .trimmingCharacters(in: .whitespaces)
        var digits = ""
        var i = text.startIndex
        if i < text.endIndex && (text[i] == "-" || text[i] == "+") {
            digits.append(text[i])
            i = text.index(after: i)
        }
        while i < text.endIndex && text[i] >= "0" && text[i] <= "9" {
            digits.append(text[i])
            i = text.index(after: i)
        }
        if let d = Double(digits) { return .number(d) }
        return .number(Double.nan)
    case "global.parseFloat":
        let text = tbJSString(arg(0))
        var prefix = ""
        for c in text {
            if c.isNumber || c == "." || c == "-" || c == "+"
                || c == "e" || c == "E" {
                prefix.append(c)
            } else {
                break
            }
        }
        if let d = Double(prefix) { return .number(d) }
        return .number(Double.nan)
    case "global.isNaN":
        return .boolean(tbJSNumber(arg(0)).isNaN)
    case "global.String":
        return .string(tbJSString(arg(0)))
    case "global.Number":
        return .number(tbJSNumber(arg(0)))
    case "global.RegExp":
        // JavaScript second stage (0.38): the
        // RegExp constructor, by call or by
        // `new` — the same making either way.
        // A pattern in hand lends its own
        // pattern (and its flags, unless new
        // ones are named); a string is read as
        // a pattern; the making validates the
        // pattern now, as a constructor does.
        if case .regex(let pattern, let flags, _) = arg(0) {
            if args.count > 1 {
                let newFlags = tbJSString(arg(1))
                _ = try tbJSRegexCompile(pattern, newFlags)
                return .regex(pattern, newFlags, 0)
            }
            return .regex(pattern, flags, 0)
        }
        let pattern = args.isEmpty ? "" : tbJSString(arg(0))
        let flags = args.count > 1 ? tbJSString(arg(1)) : ""
        _ = try tbJSRegexCompile(pattern, flags)
        return .regex(pattern, flags, 0)
    case "math.abs":
        // JavaScript sixth stage (0.42): the
        // Math reckonings. Every argument is
        // read as a number first, the way the
        // language reads it — a missing one is
        // NaN, a string is reckoned by its
        // digits — and the answers follow the
        // language at the edges: NaN and the
        // infinities land where JavaScript
        // puts them, named case by case where
        // the library underneath differs.
        return .number(abs(tbJSNumber(arg(0))))
    case "math.floor":
        return .number(tbJSNumber(arg(0)).rounded(.down))
    case "math.ceil":
        return .number(tbJSNumber(arg(0)).rounded(.up))
    case "math.round":
        // The language rounds half toward
        // +Infinity — round(-2.5) is -2, not
        // -3 — which floor(x + 0.5) says
        // exactly.
        return .number((tbJSNumber(arg(0)) + 0.5).rounded(.down))
    case "math.trunc":
        return .number(tbJSNumber(arg(0)).rounded(.towardZero))
    case "math.sign":
        let reckoned = tbJSNumber(arg(0))
        if reckoned.isNaN { return .number(Double.nan) }
        if reckoned > 0 { return .number(1) }
        if reckoned < 0 { return .number(-1) }
        return .number(reckoned)
    case "math.max":
        // The greatest of however many are
        // handed in: none at all answers
        // -Infinity, one NaN anywhere poisons
        // the whole reckoning, and +0 stands
        // greater than -0.
        var greatest = -Double.infinity
        for value in args {
            let n = tbJSNumber(value)
            if n.isNaN { return .number(Double.nan) }
            if n > greatest || (n == 0 && greatest == 0
                && greatest.sign == .minus
                && n.sign == .plus) {
                greatest = n
            }
        }
        return .number(greatest)
    case "math.min":
        // The least, mirrored: none at all
        // answers +Infinity, one NaN poisons,
        // and -0 stands less than +0.
        var least = Double.infinity
        for value in args {
            let n = tbJSNumber(value)
            if n.isNaN { return .number(Double.nan) }
            if n < least || (n == 0 && least == 0
                && least.sign == .plus
                && n.sign == .minus) {
                least = n
            }
        }
        return .number(least)
    case "math.pow":
        let base = tbJSNumber(arg(0))
        let power = tbJSNumber(arg(1))
        // The language's edge law, where the
        // library underneath answers
        // differently: anything to the power
        // 0 is 1, even NaN; a NaN power
        // poisons every base, even 1; and a
        // base of ±1 to an infinite power is
        // NaN.
        if power == 0 { return .number(1) }
        if power.isNaN { return .number(Double.nan) }
        if abs(base) == 1 && power.isInfinite {
            return .number(Double.nan)
        }
        return .number(pow(base, power))
    case "math.sqrt":
        return .number(sqrt(tbJSNumber(arg(0))))
    case "math.exp":
        return .number(exp(tbJSNumber(arg(0))))
    case "math.log":
        return .number(log(tbJSNumber(arg(0))))
    case "math.log2":
        return .number(log2(tbJSNumber(arg(0))))
    case "math.log10":
        return .number(log10(tbJSNumber(arg(0))))
    case "math.cbrt":
        // The library's cbrt can miss a
        // perfect cube by one digit in the
        // last place (27 comes back a hair
        // over 3). When a neighbor of its
        // answer cubes to the very value
        // handed in, that neighbor is the
        // true root, and it stands.
        let handed = tbJSNumber(arg(0))
        let rough = cbrt(handed)
        if rough * rough * rough == handed {
            return .number(rough)
        }
        let below = rough.nextDown
        if below * below * below == handed {
            return .number(below)
        }
        let above = rough.nextUp
        if above * above * above == handed {
            return .number(above)
        }
        return .number(rough)
    case "math.hypot":
        // However many legs are handed in,
        // folded two at a time. An infinite
        // leg answers +Infinity outright —
        // even beside a NaN, as the language
        // has it — and no legs at all
        // answers 0.
        var sawInfinite = false
        var sawNaN = false
        var joined = 0.0
        for value in args {
            let n = tbJSNumber(value)
            if n.isInfinite { sawInfinite = true }
            else if n.isNaN { sawNaN = true }
            else { joined = hypot(joined, n) }
        }
        if sawInfinite { return .number(Double.infinity) }
        if sawNaN { return .number(Double.nan) }
        return .number(joined)
    case "math.random":
        // Non-deterministic by the language's
        // own definition: a fresh draw from
        // the system's entropy at every call,
        // in [0, 1). Never seeded, never
        // faked to a fixed answer.
        return .number(Double.random(in: 0..<1))
    case "regex.test":
        // JavaScript second stage (0.38).
        guard case .regex(let pattern, let flags, let lastIndex) = this
        else { return .boolean(false) }
        let (result, next) = try tbJSRegexExec(
            pattern, flags, lastIndex, tbJSString(arg(0)))
        if flags.contains("g") || flags.contains("y") {
            ctx.mutatedThis = .regex(pattern, flags, next)
        }
        if case .null = result { return .boolean(false) }
        return .boolean(true)
    case "regex.exec":
        // JavaScript second stage (0.38).
        guard case .regex(let pattern, let flags, let lastIndex) = this
        else { return .null }
        let (result, next) = try tbJSRegexExec(
            pattern, flags, lastIndex, tbJSString(arg(0)))
        if flags.contains("g") || flags.contains("y") {
            ctx.mutatedThis = .regex(pattern, flags, next)
        }
        return result
    case "regex.toString":
        guard case .regex(let pattern, let flags, _) = this
        else { return .string("") }
        return .string("/" + pattern + "/" + flags)
    case "string.charAt":
        guard case .string(let s) = this else { return .string("") }
        let chars = Array(s)
        let i = Int(tbJSNumber(arg(0)))
        if i >= 0 && i < chars.count { return .string(String(chars[i])) }
        return .string("")
    case "string.indexOf":
        guard case .string(let s) = this else { return .number(-1) }
        let sub = tbJSString(arg(0))
        if sub.isEmpty { return .number(0) }
        let ns = s as NSString
        let found = ns.range(of: sub)
        if found.location == NSNotFound { return .number(-1) }
        return .number(Double(ns.substring(to: found.location).count))
    case "string.toUpperCase":
        guard case .string(let s) = this else { return .undefined }
        return .string(s.uppercased())
    case "string.toLowerCase":
        guard case .string(let s) = this else { return .undefined }
        return .string(s.lowercased())
    case "string.slice":
        guard case .string(let s) = this else { return .undefined }
        let chars = Array(s)
        var start = Int(tbJSNumber(arg(0)))
        if start < 0 { start = max(0, chars.count + start) }
        var end = chars.count
        if args.count > 1 {
            end = Int(tbJSNumber(arg(1)))
            if end < 0 { end = max(0, chars.count + end) }
        }
        start = min(start, chars.count)
        end = min(max(end, start), chars.count)
        return .string(String(chars[start..<end]))
    case "string.split":
        guard case .string(let s) = this else { return .undefined }
        if args.isEmpty { return .array([.string(s)]) }
        // JavaScript second stage (0.38): a
        // pattern splits where it matches, and
        // its groups join the pieces, as the
        // language has it; a limit, when one is
        // named, trims the pieces for both forms.
        if case .regex(let pattern, let flags, _) = arg(0) {
            let re = try tbJSRegexCompile(pattern, flags)
            let ns = s as NSString
            let matches = re.matches(
                in: s, options: [],
                range: NSRange(location: 0, length: ns.length))
            var pieces: [TBJSValue] = []
            var cursor = 0
            for match in matches {
                pieces.append(.string(ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor))))
                for group in 1..<match.numberOfRanges {
                    let groupRange = match.range(at: group)
                    if groupRange.location == NSNotFound {
                        pieces.append(.undefined)
                    } else {
                        pieces.append(
                            .string(ns.substring(with: groupRange)))
                    }
                }
                cursor = match.range.location + match.range.length
            }
            pieces.append(.string(ns.substring(from: cursor)))
            if args.count > 1, case .number(let limit) = arg(1) {
                pieces = Array(pieces.prefix(max(0, Int(limit))))
            }
            return .array(pieces)
        }
        let sep = tbJSString(arg(0))
        if sep.isEmpty {
            return .array(s.map { .string(String($0)) })
        }
        var pieces = s.components(separatedBy: sep)
            .map { TBJSValue.string($0) }
        if args.count > 1, case .number(let limit) = arg(1) {
            pieces = Array(pieces.prefix(max(0, Int(limit))))
        }
        return .array(pieces)
    case "string.match":
        // JavaScript second stage (0.38). A
        // pattern with the g flag gathers every
        // match's whole text; without it, one
        // exec — groups and all — or null. A
        // plain string argument is read as a
        // pattern, as the language reads it.
        guard case .string(let s) = this else { return .undefined }
        if case .regex(let pattern, let flags, _) = arg(0) {
            if flags.contains("g") {
                let re = try tbJSRegexCompile(pattern, flags)
                let ns = s as NSString
                let matches = re.matches(
                    in: s, options: [],
                    range: NSRange(location: 0, length: ns.length))
                if matches.isEmpty { return .null }
                return .array(matches.map {
                    .string(ns.substring(with: $0.range))
                })
            }
            let (result, _) = try tbJSRegexExec(pattern, flags, 0, s)
            return result
        }
        let (result, _) = try tbJSRegexExec(
            args.isEmpty ? "" : tbJSString(arg(0)), "", 0, s)
        return result
    case "string.search":
        // JavaScript second stage (0.38): the
        // character position of the first match,
        // or -1. A plain string is a pattern here
        // too.
        guard case .string(let s) = this else { return .number(-1) }
        let pattern: String
        let flags: String
        if case .regex(let p, let f, _) = arg(0) {
            pattern = p
            flags = f
        } else {
            pattern = args.isEmpty ? "" : tbJSString(arg(0))
            flags = ""
        }
        let re = try tbJSRegexCompile(pattern, flags)
        let ns = s as NSString
        guard let match = re.firstMatch(
            in: s, options: [],
            range: NSRange(location: 0, length: ns.length)) else {
            return .number(-1)
        }
        return .number(Double(ns.substring(
            to: match.range.location).count))
    case "string.replace":
        // JavaScript second stage (0.38):
        // replacing with a pattern (the first
        // match, or every match under g) or with
        // a plain string (its first standing).
        // The replacement's $ words — $$, $&,
        // $`, $', $1..$99 — are expanded against
        // each match. A function for a
        // replacement is not in this stage.
        guard case .string(let s) = this else { return .undefined }
        if args.count < 2 { return .string(s) }
        if case .function = arg(1) {
            throw TBJSFlow.error(
                "replace with a function is not in this stage")
        }
        if case .native = arg(1) {
            throw TBJSFlow.error(
                "replace with a function is not in this stage")
        }
        let replacement = tbJSString(arg(1))
        let ns = s as NSString
        if case .regex(let pattern, let flags, _) = arg(0) {
            let re = try tbJSRegexCompile(pattern, flags)
            let all = re.matches(
                in: s, options: [],
                range: NSRange(location: 0, length: ns.length))
            let chosen = flags.contains("g")
                ? all : Array(all.prefix(1))
            var out = ""
            var cursor = 0
            for match in chosen {
                out += ns.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor))
                out += tbJSRegexExpandReplacement(
                    replacement, ns, match, "")
                cursor = match.range.location + match.range.length
            }
            out += ns.substring(from: cursor)
            return .string(out)
        }
        let needle = tbJSString(arg(0))
        if needle.isEmpty {
            return .string(tbJSRegexExpandReplacement(
                replacement, ns, nil, needle) + s)
        }
        let found = (s as NSString).range(of: needle)
        if found.location == NSNotFound { return .string(s) }
        let before = ns.substring(to: found.location)
        let after = ns.substring(
            from: found.location + found.length)
        return .string(before + tbJSRegexExpandReplacement(
            replacement, ns, nil, needle) + after)
    case "string.trim":
        guard case .string(let s) = this else { return .undefined }
        return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
    case "string.includes":
        guard case .string(let s) = this else { return .boolean(false) }
        return .boolean(s.contains(tbJSString(arg(0))))
    case "array.push":
        guard case .array(var items) = this else { return .undefined }
        items.append(contentsOf: args)
        ctx.mutatedThis = .array(items)
        return .number(Double(items.count))
    case "array.pop":
        guard case .array(var items) = this else { return .undefined }
        if items.isEmpty { return .undefined }
        let last = items.removeLast()
        ctx.mutatedThis = .array(items)
        return last
    case "array.join":
        guard case .array(let items) = this else { return .undefined }
        let sep = args.isEmpty ? "," : tbJSString(arg(0))
        return .string(items.map { item in
            switch item {
            case .undefined, .null: return ""
            default: return tbJSString(item)
            }
        }.joined(separator: sep))
    case "array.indexOf":
        guard case .array(let items) = this else { return .number(-1) }
        for (index, item) in items.enumerated() {
            if tbJSLooseEqual(item, arg(0)) {
                return .number(Double(index))
            }
        }
        return .number(-1)
    case "array.slice":
        guard case .array(let items) = this else { return .undefined }
        var start = args.isEmpty ? 0 : Int(tbJSNumber(arg(0)))
        if start < 0 { start = max(0, items.count + start) }
        var end = items.count
        if args.count > 1 {
            end = Int(tbJSNumber(arg(1)))
            if end < 0 { end = max(0, items.count + end) }
        }
        start = min(start, items.count)
        end = min(max(end, start), items.count)
        return .array(Array(items[start..<end]))
    case "array.concat":
        guard case .array(var items) = this else { return .undefined }
        for extra in args {
            if case .array(let more) = extra {
                items.append(contentsOf: more)
            } else {
                items.append(extra)
            }
        }
        return .array(items)
    default:
        throw TBJSFlow.error("unknown native \(name)")
    }
}

// Collect the page's scripts in document order,
// and its elements by id (first bearer wins, as
// in a browser).
func tbCollectScripts(_ node: TBNode, into list: inout [TBNode]) {
    if node.tag == "script" {
        list.append(node)
        return
    }
    for child in node.children {
        tbCollectScripts(child, into: &list)
    }
}

func tbCollectIds(_ node: TBNode, into map: inout [String: TBNode]) {
    if let id = node.attrs["id"], !id.isEmpty, map[id] == nil {
        map[id] = node
    }
    for child in node.children {
        tbCollectIds(child, into: &map)
    }
}

struct TBJSRun {
    var titleOverride: String? = nil
    var consoleLines: [String] = []
    // Script navigation (0.37): the destination
    // a script named, if it named one — the
    // render follows it like a meta refresh.
    var navigationTarget: String? = nil
}

// Developer tools (0.35): a landed page, kept
// whole for the console — its parsed tree, its
// base address, and the very scope its scripts
// ran in, so what the JavaScript console asks
// is asked of the page the reader is looking
// at, in the state its scripts left it in. The
// renderer that painted the page rides along:
// the Inspector reads an element's resolved
// declarations from it — the cascade that
// actually painted the page, not a re-derivation.
final class TBPageSession {
    let root: TBNode
    let base: String
    let ctx: TBJSContext
    let landedTitle: String
    var renderer: TBRenderer? = nil
    init(root: TBNode, base: String, ctx: TBJSContext,
         landedTitle: String) {
        self.root = root
        self.base = base
        self.ctx = ctx
        self.landedTitle = landedTitle
    }
    // The title the window shows: a script's
    // word (or the console's) over the landed
    // one.
    var shownTitle: String {
        ctx.titleSet ? ctx.title : landedTitle
    }
}

// Make the landed page's session (0.36): its
// scope exists before anything paints, so the
// walk can go to the window first and the
// page's scripts can run against the kept tree
// afterwards — the paint-first order below.
func tbMakeSession(root: TBNode, base: String,
                   initialTitle: String) -> TBPageSession {
    let ctx = TBJSContext()
    ctx.title = initialTitle
    ctx.pageURL = base
    tbCollectIds(root, into: &ctx.elementsById)
    return TBPageSession(root: root, base: base,
                         ctx: ctx, landedTitle: initialTitle)
}

// Run the landed page's scripts, in document
// order, on its kept scope — inline code,
// and external files fetched the way style
// sheets are (the Shield is asked first, then
// the fetcher, cache and all). Writes land on
// the parsed tree itself. Since 0.36 the walk
// has already painted once when this runs, so
// what the scripts change is repainted after.
// The script budget (0.36): the whole stage —
// fetches and execution together — gets three
// seconds of wall clock. Past it, no further
// script runs, one plain line says so in the
// console, and the page lives its life.
func tbRunScripts(session: TBPageSession) async -> TBJSRun {
    let root = session.root
    let base = session.base
    let ctx = session.ctx
    var scripts: [TBNode] = []
    tbCollectScripts(root, into: &scripts)
    if scripts.isEmpty {
        return TBJSRun()
    }
    ctx.budgetDeadline = Date().addingTimeInterval(3.0)
    // The console shares this scope after the
    // load; the deadline is the page's alone.
    defer { ctx.budgetDeadline = nil }
    var budgetLogged = false
    func noteBudget() {
        if !budgetLogged {
            budgetLogged = true
            ctx.logs.append("Script budget reached"
                + " \u{2014} the rest of this page's scripts were skipped")
        }
    }
    for script in scripts {
        if ctx.budgetExceeded {
            noteBudget()
            break
        }
        if let deadline = ctx.budgetDeadline, Date() > deadline {
            ctx.budgetExceeded = true
            noteBudget()
            break
        }
        var source = script.children
            .filter { $0.tag == "#text" }.map { $0.text }
            .joined()
        if let src = script.attrs["src"],
           !src.trimmingCharacters(in: .whitespaces).isEmpty {
            let resolved: String
            if let url = URL(string: src, relativeTo: URL(string: base)) {
                resolved = url.absoluteString
            } else {
                resolved = src
            }
            if tbShieldCategory(urlString: resolved) != nil {
                let host = URL(string: resolved)?.host ?? resolved
                ctx.logs.append("Shield: script refused from " + host)
                continue
            }
            if let fetched = await tbFetchText(urlString: resolved,
                                               pageURLString: base) {
                source = fetched
            } else {
                ctx.logs.append("Script did not load: " + src)
                continue
            }
        }
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            continue
        }
        do {
            let tokens = try tbJSLex(source)
            var parser = TBJSParser(tokens: tokens)
            let program = try parser.parseProgram()
            try tbJSExec(program, ctx.globals, ctx)
        } catch let flow as TBJSFlow {
            if ctx.budgetExceeded {
                noteBudget()
                break
            }
            switch flow {
            case .error(let message):
                ctx.logs.append("Script error: " + message)
            case .thrown(let value):
                // JavaScript second stage (0.38):
                // a throw nothing caught ends this
                // script, in its own words.
                ctx.logs.append("Script error: uncaught throw: "
                                + tbJSString(value))
            case .returnValue:
                break  // A top-level return just ends the script.
            case .breakLoop, .continueLoop:
                ctx.logs.append("Script error: break or continue outside a loop")
            }
        } catch {
            if ctx.budgetExceeded {
                noteBudget()
                break
            }
            ctx.logs.append("Script error: \(error)")
        }
        // Script navigation (0.37): a script that
        // sends the reader onward ends the stage.
        // The page is leaving; its remaining
        // scripts belong to a room being vacated.
        if ctx.navigationTarget != nil {
            break
        }
    }
    let navigation = ctx.navigationTarget
    ctx.navigationTarget = nil
    return TBJSRun(titleOverride: ctx.titleSet ? ctx.title : nil,
                   consoleLines: ctx.logs,
                   navigationTarget: navigation)
}

// What one trip through the JavaScript
// console produced: the lines the code spoke
// while it ran (console words, alerts and
// errors ride among them in their usual
// prefixed forms; the window sorts them as it
// does a page's), the value to show, and
// whether the page's face changed underneath.
struct TBConsoleEvalOutcome {
    var newLogs: [String] = []
    var valueText: String? = nil
    var errorText: String? = nil
    var pageChanged = false
    // Script navigation (0.37): a destination
    // the typed words named — the window takes
    // it through its own load, like any journey.
    var navigationTarget: String? = nil
}

// The JavaScript console (0.35): run what the
// reader typed through the same lexer, parser
// and evaluator a page's scripts use, in the
// landed page's own scope — or a bare scope,
// with an empty document, when no page is
// landed. A program is accepted whole; when
// its last statement is an expression, that
// expression's value is the console's answer,
// as in a browser's console; otherwise the
// answer is undefined. An error stops the run
// and stands as the run's error line.
func tbConsoleEval(session: TBPageSession?,
                   source: String) -> TBConsoleEvalOutcome {
    let ctx = session?.ctx ?? TBJSContext()
    var outcome = TBConsoleEvalOutcome()
    let logCountBefore = ctx.logs.count
    ctx.domChanged = false
    do {
        let tokens = try tbJSLex(source)
        var parser = TBJSParser(tokens: tokens)
        var program = try parser.parseProgram()
        var lastExpr: TBJSExpr? = nil
        if let last = program.last, case .expr(let expr) = last {
            lastExpr = expr
            program.removeLast()
        }
        if !program.isEmpty {
            try tbJSExec(program, ctx.globals, ctx)
        }
        if let expr = lastExpr {
            let value = try tbJSEval(expr, ctx.globals, ctx)
            outcome.valueText = tbJSInspect(value)
        } else {
            outcome.valueText = "undefined"
        }
    } catch let flow as TBJSFlow {
        switch flow {
        case .error(let message):
            outcome.errorText = message
        case .thrown(let value):
            // JavaScript second stage (0.38): in
            // the console a throw nothing caught
            // is the run's error line, in the
            // thrown value's own words.
            outcome.errorText = "uncaught throw: "
                + tbJSString(value)
        case .returnValue(let value):
            // A top-level return in console
            // code: its value is the answer, as
            // though the console were the body
            // of a function wrapped around it.
            outcome.valueText = tbJSInspect(value)
        case .breakLoop, .continueLoop:
            outcome.errorText = "break or continue outside a loop"
        }
    } catch {
        outcome.errorText = "\(error)"
    }
    outcome.newLogs = Array(ctx.logs.dropFirst(logCountBefore))
    outcome.pageChanged = ctx.domChanged
    ctx.domChanged = false
    outcome.navigationTarget = ctx.navigationTarget
    ctx.navigationTarget = nil
    return outcome
}

// A console's rendering of a value (0.35):
// strings wear their quotes, so they cannot
// be mistaken for numbers; arrays and objects
// open one level; an element names its tag
// and id.
func tbJSInspect(_ value: TBJSValue) -> String {
    switch value {
    case .string(let s):
        return "\"" + s + "\""
    case .array(let items):
        if items.isEmpty { return "[]" }
        return "[ " + items.map { tbJSInspectShallow($0) }
            .joined(separator: ", ") + " ]"
    case .object(let obj):
        if obj.isEmpty { return "{}" }
        let parts = obj.keys.sorted().map { key in
            key + ": " + tbJSInspectShallow(obj[key] ?? .undefined)
        }
        return "{ " + parts.joined(separator: ", ") + " }"
    case .instance(let box):
        // JavaScript third stage (0.39): an
        // instance opens like an object — its
        // own fields, one level.
        if box.fields.isEmpty { return "{}" }
        let parts = box.fields.keys.sorted().map { key in
            key + ": "
                + tbJSInspectShallow(box.fields[key] ?? .undefined)
        }
        return "{ " + parts.joined(separator: ", ") + " }"
    case .element(let node):
        if let id = node.attrs["id"], !id.isEmpty {
            return "<" + node.tag + " id=\"" + id + "\">"
        }
        return "<" + node.tag + ">"
    default:
        return tbJSString(value)
    }
}

private func tbJSInspectShallow(_ value: TBJSValue) -> String {
    switch value {
    case .array: return "[...]"
    case .object: return "{...}"
    case .instance: return "{...}"
    default: return tbJSInspect(value)
    }
}
