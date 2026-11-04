//
//  ChirpyEngine.swift
//  Chirpy Browser — engine 0.23.0 (Swift)
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
//    * Layout step two (0.7): the page's own centered column
//      is found — a width or max-width cap with auto side
//      margins — and the window centers its text in a column
//      of that width; and block backgrounds are painted by
//      the view as full-width bands across the column
//      instead of hugging their words.
//    * Layout step three (0.8): continuous surfaces — the
//      view bridges the spacing seams between same-colored
//      paragraphs, so a colored container reads as one
//      painted surface instead of separate stripes.
//    * Images (0.9): <img> elements fetch in parallel and
//      render as real pictures in the flow, sized by their
//      CSS/attribute box or their natural size (capped at
//      the nominal page width); a failed image falls back
//      to its labelled placeholder. srcset and inline
//      <svg> are not read yet.
//    * Background photos (0.10; paint order fixed in 0.11 —
//      the view now paints layers AFTER AppKit's own
//      background pass, which had been repainting the
//      surface color over them): background-image layers
//      paint on a block's surface over its color — url()
//      photos, fetched or decoded from data: URIs, drawn
//      per background-size (cover/contain/lengths),
//      background-position, and background-repeat; and
//      linear-gradient overlays painted from their color
//      stops. Layers belonging to inline elements, radial
//      and conic gradients are not read yet.
//    * Layout step four (0.17): positioned layout. float:
//      left/right lifts an image or a block box out of the
//      vertical stack; the renderer records it as a layout
//      event and the view packs floats against the column's
//      edges (consecutive floats share a band until the
//      width runs out, then drop to a new one), gives the
//      text exclusion paths to wrap around them, and paints
//      each float — its background, photo layers, picture,
//      or its own rendered contents — in the surface pass.
//      clear: left/right/both starts a block below the
//      floats it names, and a container that establishes
//      containment (overflow other than visible, flow-root,
//      a float itself — or, the float-era reality, simply a
//      painted surface) is extended to contain the floats
//      anchored inside it. position: relative shifts a
//      box's paint by its offsets without disturbing the
//      flow position. position: absolute/fixed and the
//      multi-column properties are NOT read — honestly out.
//    * Load progress (0.18): the main document fetch is
//      delegate-driven and reports the bytes received
//      against the response's expected length; the window
//      shows them as a progress bar under the address bar
//      — indeterminate when the server declares no length,
//      and while the fetched page renders its styles and
//      pictures. An HTML file dropped on the window opens
//      through the same load path.
//    * Parallel loading (0.19): a page's external
//      stylesheets fetch concurrently and join the
//      cascade strictly in document order; images,
//      background photos and floated pictures fetch with
//      bounded concurrency — at most six in flight —
//      with every result collected before the pass that
//      seats them runs. Block floats still finish one
//      float at a time. Nothing paints until the page is
//      whole: first paint, caching and prefetching are
//      future steps, not this one.
//    * First paint (0.20): the walked page reaches the
//      window before its pictures — the text paints with
//      declared picture boxes reserved, and the fetched
//      pixels fill their boxes as they land; floated
//      pictures are placed from their declared geometry
//      at first paint and painted when they arrive. The
//      view resolves a page's floats in a few whole
//      passes instead of one layout per float.
//    * Positioned layout (0.21): position:absolute lifts
//      a box out of the flow altogether — no exclusion,
//      no wrap; it overlays, resolved by the view against
//      its containing block: the nearest positioned
//      ancestor's painted surface (the renderer records
//      the ancestor's range in the text as it walks), or
//      the page column. position:fixed answers to the
//      viewport instead: the box becomes a real overlay
//      view the window keeps glued to the visible area
//      while the page scrolls beneath it. Insets are
//      lengths or percentages of the containing block;
//      left+right (or top+bottom) with no declared size
//      derives that size; z-index orders the overlays,
//      document order breaking ties. Declared geometry
//      places at first paint; boxes measured from their
//      contents place at arrivals, like block floats.
//      position: sticky and transforms are not read.
//    * Multi-column and color-mix (0.22): a block with
//      column-count or column-width lays its contents
//      out in balanced columns — sub-rendered like a
//      floated box, measured across as many text
//      containers as it has columns (the height binary-
//      searched until the content just fills them), its
//      height reserved in the flow by a clear seat, and
//      the columns and their rules painted into that
//      space by the layout manager. column-gap and
//      column-rule are read; column-span and the break
//      properties are not, and a multicolumn block's own
//      contents are paint, not live text — the floated
//      box's bargain. color-mix(in srgb, …) is read
//      anywhere a color is: premultiplied-alpha mixing
//      per the spec, percentages defaulting and scaling
//      alpha as the spec directs, nested mixes included;
//      other color spaces are not read.
//    * The finishing set (0.23): the font: shorthand is
//      read whole — style, variant, weight and stretch
//      before the size, an optional /line-height, then
//      the family — and expands into its longhands at
//      its own place in the cascade, unmentioned
//      components resetting to normal as the shorthand
//      demands; a font: arriving through var() expands
//      after substitution. font-family is honored (the
//      first family in the list that resolves on this
//      Mac; the generic families map to platform
//      faces), and font-variant paints small-caps.
//      The system-font keywords (font: menu and kin)
//      and font-stretch are read and set aside.
//      @media grows past prefers-color-scheme:
//      min-width / max-width / width against the text
//      area's width as the load began,
//      prefers-reduced-motion from the system's own
//      accessibility setting, hover / pointer answered
//      as the constants they are on a Mac; unknown
//      features keep their old answer — the block does
//      not apply — and a sheet's media rules no longer
//      leak into its plain cascade. Structural
//      pseudo-classes join matching: :first-child,
//      :last-child, :nth-child() and :nth-of-type()
//      in every An+B spelling, :first-of-type,
//      :last-of-type, :not() around a compound, and
//      :empty. :link and :visited divide a page's
//      anchors by this window's session — the URLs it
//      has loaded; nothing is kept between launches.
//      :hover is paint, never layout: each element's
//      hover traits (color, background color, the
//      underline and strikethrough switches) are
//      stamped onto its text, and the view lifts the
//      text into them while the pointer rests on it.
//      :focus and :active are not read, and a hover
//      background's photo or gradient layers are not
//      painted — its color is.
//  Not yet: position: sticky, :focus and :active,
//  JavaScript (the mountain).
//

import Foundation
import AppKit

let TB_HOME_HTML = """
<!DOCTYPE html>
<html>
<head><title>Chirpy Home</title></head>
<body>
<h1>Chirpy Browser</h1>
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
    if urlString == "chirpy://home" {
        return (urlString, TB_HOME_HTML)
    }
    guard let url = URL(string: urlString) else {
        throw NSError(domain: "ChirpyBrowser", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "That address could not be understood."])
    }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.23.0 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    let final = response.url?.absoluteString ?? urlString
    let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    return (final, html)
}

// Fetch a page by form POST: the fields travel in the
// body, form-encoded, as a browser sends them.
func tbFetchPOST(urlString: String, body: String) async throws -> (finalURL: String, html: String) {
    guard let url = URL(string: urlString) else {
        throw NSError(domain: "ChirpyBrowser", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "That address could not be understood."])
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("ChirpyBrowser/0.23.0 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue("application/x-www-form-urlencoded",
                     forHTTPHeaderField: "Content-Type")
    request.httpBody = body.data(using: .utf8)
    let (data, response) = try await URLSession.shared.data(for: request)
    let final = response.url?.absoluteString ?? urlString
    let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    return (final, html)
}

// Load progress (0.18): the main document fetch, delegate-
// driven so the window gets a progress bar. The helpers
// above deliver a page all at once; this one also reports,
// as the bytes arrive, how much of the page has come in —
// the fraction of the response's expected length, or nil
// when the server declares no length (a chunked reply),
// which the window shows as an indeterminate bar. Only
// http(s) pages come through here; local pages (Chirpy
// home, dropped files) are instant and keep the plain
// helpers. A redirect restarts the count with the new
// response, and the count is of the bytes as delivered —
// on a compressed page it can reach the top of its band
// early and wait there, which the README says plainly.
final class TBProgressFetcher: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var received = Data()
    private var expected: Int64 = -1
    private var landedURL = ""
    private var continuation: CheckedContinuation<(finalURL: String, html: String), Error>?
    private var progressHandler: ((Double?) -> Void)?
    private var lastReported: Double = -1

    // Stop an in-flight fetch (a newer load supersedes it).
    func cancel() {
        dataTask?.cancel()
    }

    func fetch(urlString: String, postBody: String?,
               onProgress: @escaping (Double?) -> Void)
        async throws -> (finalURL: String, html: String) {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ChirpyBrowser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "That address could not be understood."])
        }
        var request = URLRequest(url: url)
        if let postBody = postBody {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = postBody.data(using: .utf8)
        }
        request.setValue("ChirpyBrowser/0.23.0 (Swift; our own engine)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        landedURL = urlString
        progressHandler = onProgress
        let session = URLSession(configuration: .default,
                                 delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.dataTask(with: request)
            self.dataTask = task
            task.resume()
        }
    }

    // A response begins — again after a redirect, when the
    // byte count and the expected length start over with it.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        received = Data()
        expected = response.expectedContentLength
        lastReported = -1
        reportProgress()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        received.append(data)
        reportProgress()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        let done = continuation
        continuation = nil
        if let response = task.response {
            landedURL = response.url?.absoluteString ?? landedURL
        }
        session.finishTasksAndInvalidate()
        if let error = error {
            done?.resume(throwing: error)
        } else {
            let html = String(data: received, encoding: .utf8)
                ?? String(decoding: received, as: UTF8.self)
            done?.resume(returning: (finalURL: landedURL, html: html))
        }
    }

    // The delegate queue is this fetcher's own serial
    // queue, so the state above needs no locking. Report
    // when the fraction moves a visible step, and whenever
    // the answer changes between a fraction and "unknown".
    private func reportProgress() {
        guard let progressHandler = progressHandler else { return }
        if expected <= 0 {
            if lastReported != -2 {
                lastReported = -2
                progressHandler(nil)
            }
            return
        }
        let fraction = min(Double(received.count) / Double(expected), 1)
        if fraction - lastReported >= 0.01
            || (fraction >= 1 && lastReported < 1) {
            lastReported = fraction
            progressHandler(fraction)
        }
    }
}

// Fetch a binary resource (an image). Failures return nil:
// the image falls back to its label.
func tbFetchData(urlString: String) async -> Data? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.23.0 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 20
    guard let (data, response) = try? await URLSession.shared.data(for: request) else {
        return nil
    }
    if let http = response as? HTTPURLResponse, http.statusCode >= 400 { return nil }
    return data
}

// Fetch a batch of binary resources with bounded
// concurrency (0.19): at most `limit` requests in flight
// at once — six, the browsers' classic per-host number —
// where a pass that lets everything fly at once can swamp
// a small server, and one that queues behind a single
// file makes the page wait on every round trip in turn.
// Every result is collected before the caller proceeds,
// keyed by the job's index in the batch, so the consuming
// pass walks its jobs in their original order whatever
// order the replies landed in. All of it goes through
// tbFetchData and the one shared session, so connections
// are reused; a failed fetch is simply absent from the
// results. Child tasks only fetch and hand values back —
// they never touch the caller's state.
func tbFetchDataBatch(_ jobs: [(index: Int, url: String)],
                      limit: Int = 6) async -> [Int: Data] {
    if jobs.isEmpty { return [:] }
    var results: [Int: Data] = [:]
    await withTaskGroup(of: (Int, Data?).self) { group in
        var next = 0
        let window = min(limit, jobs.count)
        while next < window {
            let job = jobs[next]
            group.addTask { (job.index, await tbFetchData(urlString: job.url)) }
            next += 1
        }
        for await (index, data) in group {
            if let data = data { results[index] = data }
            if next < jobs.count {
                let job = jobs[next]
                group.addTask { (job.index, await tbFetchData(urlString: job.url)) }
                next += 1
            }
        }
    }
    return results
}

// Decode a data: URI in place (base64 or plain text payload).
func tbDecodeDataURI(_ uri: String) -> Data? {
    guard let comma = uri.firstIndex(of: ",") else { return nil }
    let header = uri[uri.startIndex..<comma].lowercased()
    let payload = String(uri[uri.index(after: comma)...])
    if header.contains(";base64") {
        return Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
    }
    return payload.data(using: .utf8)
}

// Background-image layers (0.10): one layer is a photo
// (url) or a linear gradient (its inner specification).
// The view paints them over the surface color; photos are
// fetched by the renderer into `image`, gradients paint
// straight from their specification.
final class TBBackgroundLayer {
    enum Kind {
        case image(String)     // absolute URL (or a data: URI)
        case gradient(String)  // the text inside linear-gradient(…)
    }
    let kind: Kind
    var image: NSImage? = nil
    init(kind: Kind) { self.kind = kind }
}

// All the layers one element declares, with the sizing,
// position, and repeat that govern them — one value each,
// serving every layer (the common authoring; gradients
// ignore all three anyway).
final class TBBackgroundBox {
    let layers: [TBBackgroundLayer]
    let sizeSpec: String
    let positionSpec: String
    let repeatSpec: String
    init(layers: [TBBackgroundLayer], sizeSpec: String,
         positionSpec: String, repeatSpec: String) {
        self.layers = layers
        self.sizeSpec = sizeSpec
        self.positionSpec = positionSpec
        self.repeatSpec = repeatSpec
    }
}

// The attribute key that carries a TBBackgroundBox on a
// paragraph's closing newline, where the layout manager
// reads a surface's layers.
let TBBackgroundKey = NSAttributedString.Key("TBBackgroundLayers")

// Surface edges (0.15): how far a surface's paint extends
// above its first paragraph's first line and below its
// last paragraph's last line — the inside space (a padded
// container's own padding, the spacing of what it holds)
// that belongs to the surface but to no line of text. The
// renderer stamps these on the edge paragraphs; the
// layout manager reads them when it paints the surface.
let TBExtTopKey = NSAttributedString.Key("TBExtTop")
let TBExtBottomKey = NSAttributedString.Key("TBExtBottom")

// Layout step four (0.17): positioned layout. The renderer
// records floats and clears as events in document order,
// anchored at character offsets in the rendered text; the
// view resolves them into exclusion paths and painted
// boxes once it knows the column's real width. A relative
// offset travels on the text itself, under this key, as an
// NSValue(NSPoint): the layout manager shifts that run's
// glyphs and backgrounds when it paints, while the flow —
// and everything seated in it, like form controls — stays
// where the text put it.
let TBRelOffsetKey = NSAttributedString.Key("TBRelOffset")

// The finishing set (0.23): hover. A hovered element's
// paint-level style rides on its text under these keys, as
// a TBHoverStyle — a class, like TBBackgroundBox, because
// attribute values that are Swift dictionaries do not
// survive being read back. Two keys because two stamps land
// on the same characters: an element's own (stamped as its
// run finishes) and its enclosing block's (stamped as the
// block closes), and the view merges them block-under-
// element when the pointer arrives. The view finds the
// style under the glyph, lifts the element's characters
// into it, and puts the original characters back when the
// pointer leaves — hover never touches layout.
let TBHoverAttrsKey = NSAttributedString.Key("TBHoverAttrs")
let TBHoverBlockAttrsKey = NSAttributedString.Key("TBHoverBlockAttrs")

final class TBHoverStyle {
    var foregroundColor: NSColor? = nil
    var backgroundColor: NSColor? = nil
    var underlineStyle: Int? = nil
    var strikethroughStyle: Int? = nil
}

enum TBFloatSide { case left, right }
enum TBClearSide { case left, right, both }

final class TBFloatSpec {
    // Where the float was met in the text; the view hangs
    // the box from the top of the line that starts there.
    let anchorCharIndex: Int
    let side: TBFloatSide
    let isImage: Bool
    // The border box the view packs and paints. For image
    // floats the renderer's finish pass replaces the
    // provisional size with the picture's real one.
    var borderWidth: CGFloat
    var borderHeight: CGFloat
    var widthDeclared = false
    var heightDeclared = false
    var marginTop: CGFloat = 0
    var marginRight: CGFloat = 0
    var marginBottom: CGFloat = 0
    var marginLeft: CGFloat = 0
    var paddingTop: CGFloat = 0
    var paddingRight: CGFloat = 0
    var paddingBottom: CGFloat = 0
    var paddingLeft: CGFloat = 0
    var backgroundColor: NSColor? = nil
    var backgroundBox: TBBackgroundBox? = nil
    // An image float's picture (nil until fetched).
    var image: NSImage? = nil
    var imageFailed = false
    var alt = ""
    // A block float's own rendered contents, painted by
    // the view inside the box's padding.
    var content: NSAttributedString? = nil

    init(anchorCharIndex: Int, side: TBFloatSide, isImage: Bool,
         borderWidth: CGFloat, borderHeight: CGFloat) {
        self.anchorCharIndex = anchorCharIndex
        self.side = side
        self.isImage = isImage
        self.borderWidth = borderWidth
        self.borderHeight = borderHeight
    }
}

final class TBClearSpec {
    // Patches to the cleared paragraph's first character
    // when that paragraph is flushed (see TBRenderer.flush).
    var anchorCharIndex: Int
    let side: TBClearSide
    // nil: an author's clear — every earlier float counts.
    // Non-nil: the renderer's own containment clear for a
    // container — only floats anchored in [rangeStart,
    // anchorCharIndex) count.
    let rangeStart: Int?
    init(anchorCharIndex: Int, side: TBClearSide, rangeStart: Int?) {
        self.anchorCharIndex = anchorCharIndex
        self.side = side
        self.rangeStart = rangeStart
    }
}

enum TBLayoutEvent {
    case float(TBFloatSpec)
    case clear(TBClearSpec)
    case positioned(TBPositionedSpec)
    case columns(TBMultiColumnSpec)
}

// Positioned layout (0.21): an element with position
// other than static establishes the containing block for
// its absolutely positioned descendants. The renderer
// tracks those ancestors as character ranges in the
// rendered text — the start is known when the block
// opens, the end is patched when it closes (the same
// trick TBClearSpec's anchors play) — and the view turns
// the range into the ancestor's painted surface rect:
// full column width, from its surface's top edge stamp
// to its bottom edge stamp, shifted by any relative
// offset the ancestor itself carries.
final class TBContainingBlock {
    let startCharIndex: Int
    var endCharIndex: Int
    init(startCharIndex: Int) {
        self.startCharIndex = startCharIndex
        self.endCharIndex = startCharIndex
    }
}

// One inset of a positioned box (top/right/bottom/left):
// a length in points, or a percentage kept as its raw
// number (50 for 50%) until the view knows the
// containing block it resolves against. A missing or
// "auto" inset is nil.
enum TBInsetValue {
    case points(CGFloat)
    case percent(CGFloat)
}

enum TBPositionKind { case absolute, fixed }

// A box lifted out of the flow by position:absolute or
// position:fixed (0.21). Like a float it is recorded at
// the walk and resolved by the view — but it makes no
// exclusion and no text wraps it: it overlays. Its size
// is final at first paint when the page declares it;
// a box measured from its contents is sized by the
// arrivals finish, as block floats are. Which dimension
// the insets themselves must decide (left+right with no
// width, top+bottom with no height) only the view can
// settle, against the true containing block — the flags
// carry that; the renderer leaves those sizes at zero.
final class TBPositionedSpec {
    // Where the box was met in the text; an inset left
    // auto on an axis falls back to the position the
    // box would have had in the flow, measured from here.
    let anchorCharIndex: Int
    let kind: TBPositionKind
    // Absolute only: the nearest positioned ancestor's
    // range in the text, or nil for the page column.
    // Fixed boxes answer to the viewport instead.
    let containingBlock: TBContainingBlock?
    var top: TBInsetValue? = nil
    var right: TBInsetValue? = nil
    var bottom: TBInsetValue? = nil
    var left: TBInsetValue? = nil
    var zIndex: Int = 0
    let isImage: Bool
    var borderWidth: CGFloat
    var borderHeight: CGFloat
    var widthDeclared = false
    var heightDeclared = false
    var widthFromInsets = false
    var heightFromInsets = false
    var marginTop: CGFloat = 0
    var marginRight: CGFloat = 0
    var marginBottom: CGFloat = 0
    var marginLeft: CGFloat = 0
    var paddingTop: CGFloat = 0
    var paddingRight: CGFloat = 0
    var paddingBottom: CGFloat = 0
    var paddingLeft: CGFloat = 0
    var backgroundColor: NSColor? = nil
    var backgroundBox: TBBackgroundBox? = nil
    // An image box's picture (nil until fetched).
    var image: NSImage? = nil
    var imageFailed = false
    var alt = ""
    // A block box's own rendered contents, painted by
    // the view inside the box's padding.
    var content: NSAttributedString? = nil

    init(anchorCharIndex: Int, kind: TBPositionKind,
         containingBlock: TBContainingBlock?, isImage: Bool,
         borderWidth: CGFloat, borderHeight: CGFloat) {
        self.anchorCharIndex = anchorCharIndex
        self.kind = kind
        self.containingBlock = containingBlock
        self.isImage = isImage
        self.borderWidth = borderWidth
        self.borderHeight = borderHeight
    }
}

// Multi-column layout (0.22): the seat that reserves a
// multicolumn block's height in the flow — a clear-seat
// attachment like a form control's, one character wide
// in the text and the whole block tall — and the spec
// the walk records for the view: the block's contents,
// sub-rendered and cleaned like a floated box's, with
// the column geometry the renderer's balancing measured.
// The view paints the columns into the seat's line.
final class TBColumnSeatAttachment: NSTextAttachment {}

final class TBMultiColumnSpec {
    // Where the seat sits in the text; the view hangs the
    // columns from the top of the line that holds it.
    var anchorCharIndex: Int = 0
    let columnCount: Int
    // The used width of one column (its text container's
    // width) and the balanced height every column stands.
    var columnWidth: CGFloat
    var columnHeight: CGFloat = 0
    let gap: CGFloat
    // The block's content-box width — the seat's width,
    // and the span the columns and gaps together fill.
    let totalWidth: CGFloat
    var totalHeight: CGFloat = 0
    // The rule painted in each gap: its width (0 or a
    // style of none/hidden paints nothing), style and
    // color (the element's own text color when the page
    // declares none — currentColor, as the spec directs).
    var ruleWidth: CGFloat = 0
    var ruleStyle: String = "none"
    var ruleColor: NSColor? = nil
    // The block's rendered contents, painted by the view
    // across the columns (paint, not live text — the
    // floated box's bargain, struck in finalizeColumns).
    var content: NSAttributedString? = nil
    // The seat in the page's text, whose bounds the
    // arrivals finish corrects to the final height.
    var seat: TBColumnSeatAttachment? = nil

    init(columnCount: Int, columnWidth: CGFloat, gap: CGFloat,
         totalWidth: CGFloat) {
        self.columnCount = columnCount
        self.columnWidth = columnWidth
        self.gap = gap
        self.totalWidth = totalWidth
    }
}

// Parse an element's background-image into a box of
// layers. The longhand is the primary path; the
// `background` shorthand is mined for layer chunks that
// carry a url() or a linear-gradient() (their position
// and size tokens in the shorthand are not read).
func tbBackgroundSpec(_ decls: [String: String], base: String)
    -> (key: String, box: TBBackgroundBox)? {
    var layerTexts: [String] = []
    var key = ""
    if let image = decls["background-image"] {
        layerTexts = tbSplitLayers(image)
        key = "img:" + image
    } else if let shorthand = decls["background"] {
        for chunk in tbSplitLayers(shorthand) {
            if chunk.contains("url(") || chunk.contains("linear-gradient(") {
                layerTexts.append(chunk)
            }
        }
        if layerTexts.isEmpty { return nil }
        key = "short:" + shorthand
    } else {
        return nil
    }
    var layers: [TBBackgroundLayer] = []
    for text in layerTexts {
        let layer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if layer.hasPrefix("url(") {
            guard let open = layer.firstIndex(of: "("),
                  let close = layer.lastIndex(of: ")"), close > open else { continue }
            var url = String(layer[layer.index(after: open)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if (url.hasPrefix("\"") && url.hasSuffix("\""))
                || (url.hasPrefix("'") && url.hasSuffix("'")) {
                url = String(url.dropFirst().dropLast())
            }
            if url.isEmpty { continue }
            let absolute = url.hasPrefix("data:")
                ? url
                : (URL(string: url, relativeTo: URL(string: base))?.absoluteString ?? url)
            layers.append(TBBackgroundLayer(kind: .image(absolute)))
        } else if layer.hasPrefix("linear-gradient(") {
            guard let open = layer.firstIndex(of: "("),
                  let close = layer.lastIndex(of: ")"), close > open else { continue }
            let inner = String(layer[layer.index(after: open)..<close])
            layers.append(TBBackgroundLayer(kind: .gradient(inner)))
        }
        // "none" layers and other gradient kinds (radial,
        // conic) are not read yet.
    }
    if layers.isEmpty { return nil }
    let size = tbSplitLayers(decls["background-size"] ?? "auto").first ?? "auto"
    let position = tbSplitLayers(decls["background-position"] ?? "0% 0%").first ?? "0% 0%"
    let repeatSpec = tbSplitLayers(decls["background-repeat"] ?? "repeat").first ?? "repeat"
    let box = TBBackgroundBox(layers: layers, sizeSpec: size,
                              positionSpec: position, repeatSpec: repeatSpec)
    return (key + "|" + size + "|" + position + "|" + repeatSpec, box)
}

// Fetch a plain text resource (used for external stylesheets).
// Failures return nil: a page must still render without its CSS.
func tbFetchText(urlString: String) async -> String? {
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.23.0 (Swift; our own engine)",
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
    // The finishing set (0.23): for an <a> element, whether
    // its target is in this session's visited set — the
    // renderer stamps it as it resolves the element's
    // style, and :link / :visited matching reads it. The
    // set itself is the window's, passed to each render;
    // nothing persists between launches.
    var linkVisited = false
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
// :hover. :focus and :active stay outside the grammar, so a
// selector using them does not parse and its rule never applies.
struct TBCompound {
    var tag: String? = nil
    var classes: [String] = []
    var id: String? = nil
    var isRoot = false   // :root — matches the <html> element
    var isHover = false  // :hover — matches only in a hover resolution
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
                return nil   // :focus, :active, :lang, … — not read
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
                       hoverSatisfied: Bool = false) -> Bool {
    if node.tag == "#text" || node.tag == "document" { return false }
    // :hover is a state, not a shape: in an ordinary match it
    // is never true (so hover rules stay out of the resting
    // cascade), and in a hover resolution it is treated as
    // satisfied for whichever element the compound binds to —
    // the hovered element itself, or an ancestor of it in a
    // selector like `.card:hover .title`.
    if compound.isHover && !hoverSatisfied { return false }
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
    if let notBox = compound.notBox,
       tbCompoundMatches(notBox.compound, node: node,
                         hoverSatisfied: hoverSatisfied) {
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
        let siblings = tbElementSiblings(node)
        guard let own = siblings.firstIndex(where: { $0 === node }) else {
            return false
        }
        let index = own + 1   // CSS counts from 1
        if compound.firstChild && index != 1 { return false }
        if compound.lastChild && index != siblings.count { return false }
        if let nth = compound.nthChild, !tbNthMatches(nth, index: index) {
            return false
        }
        if compound.firstOfType || compound.lastOfType
            || compound.nthOfType != nil {
            let ofType = siblings.filter { $0.tag == node.tag }
            guard let ownType = ofType.firstIndex(where: { $0 === node })
            else { return false }
            let typeIndex = ownType + 1
            if compound.firstOfType && typeIndex != 1 { return false }
            if compound.lastOfType && typeIndex != ofType.count {
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
                       hoverSatisfied: Bool = false) -> Bool {
    func matchFrom(_ index: Int, _ current: TBNode) -> Bool {
        guard tbCompoundMatches(selector.compounds[index], node: current,
                                hoverSatisfied: hoverSatisfied) else {
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
    var matched: [TBCSSRule] = []
    for rule in rules where tbSelectorMatches(rule.selector, node: node) {
        matched.append(rule)
    }
    matched.sort {
        ($0.selector.specificity, $0.order) < ($1.selector.specificity, $1.order)
    }
    var out: [String: String] = [:]
    for rule in matched {
        tbMergeDeclarations(rule.declarations, into: &out)
    }
    if let inlineStyle = node.attrs["style"] {
        tbMergeDeclarations(tbParseDeclarations(inlineStyle), into: &out)
    }
    return out
}

// Does any compound in this selector carry :hover?
func tbSelectorHasHover(_ selector: TBSelector) -> Bool {
    selector.compounds.contains { $0.isHover }
}

// The hover resolution (0.23): the declarations an element
// wears while the pointer is over it — only rules carrying
// :hover, matched with the state treated as satisfied, in
// the same cascade order as the resting resolution. What
// the view does with them is paint, not layout: see
// tbHoverPaintAttrs.
func tbResolveHoverStyle(node: TBNode, rules: [TBCSSRule]) -> [String: String] {
    if node.tag == "#text" { return [:] }
    var matched: [TBCSSRule] = []
    for rule in rules where tbSelectorHasHover(rule.selector)
        && tbSelectorMatches(rule.selector, node: node, hoverSatisfied: true) {
        matched.append(rule)
    }
    matched.sort {
        ($0.selector.specificity, $0.order) < ($1.selector.specificity, $1.order)
    }
    var out: [String: String] = [:]
    for rule in matched {
        tbMergeDeclarations(rule.declarations, into: &out)
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

// The paint a :hover resolution contributes (0.23), as a
// TBHoverStyle — or nil when the resolution names nothing
// the hover machinery can paint. Paint only, by design:
// foreground color, the background color behind the
// glyphs (the color layer only — tbBackgroundColor, so a
// shorthand background contributes its color; photo and
// gradient hover backgrounds are not painted), and the
// underline / strikethrough switches — including `none`,
// which switches one OFF for the hover. A hover rule that
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

// Forms (0.13): a text or search input seats an attachment
// in the text, the way an image does — but what belongs
// there is a real, editable field, which the window lays
// over the text (PageTextView's Coordinator in
// ContentView.swift). Pressing Enter submits the form as
// a browser does: its own fields and hidden inputs,
// GET-encoded onto its action.
final class TBFieldAttachment: NSTextAttachment {
    var fieldID = -1
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
    private var spaceCarry: CGFloat = 0
    private struct TBSurfaceEdge {
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
    private var surfaceEdges: [TBSurfaceEdge] = []

    // Layout step four (0.17): the floats and clears the
    // walk met, in document order, for the view to resolve;
    // the floats still waiting on pictures or measuring;
    // and the relative-offset accumulation of the blocks
    // currently open (offsets sum through nesting, as CSS
    // positions them). A renderer inside a float records
    // no events of its own — nested floats simply flow.
    var layoutEvents: [TBLayoutEvent] = []
    private var insideFloat = false
    private var pendingClears: [TBClearSpec] = []
    private var floatCount = 0
    private var floatImageJobs: [(spec: TBFloatSpec, url: String)] = []
    private var pendingBlockFloats: [(spec: TBFloatSpec, sub: TBRenderer)] = []
    private var relDX: CGFloat = 0
    private var relDY: CGFloat = 0
    private var lastFlushRange: NSRange? = nil
    var nominalWidth: CGFloat = 1000

    // Positioned layout (0.21): the positioned boxes the
    // walk met and what they still wait on — pictures to
    // fetch, contents to measure — and the stack of
    // positioned ancestors currently open, whose ranges
    // an absolutely positioned descendant resolves
    // against. A block-level relative ancestor pushes in
    // walkBlock; a relative span pushes in inline().
    private var positionedCount = 0
    private var positionedImageJobs: [(spec: TBPositionedSpec, url: String)] = []
    private var pendingPositioned: [(spec: TBPositionedSpec, sub: TBRenderer)] = []
    private var containingBlocks: [TBContainingBlock] = []

    // Multi-column layout (0.22): the multicolumn blocks
    // the walk met, each with the sub-renderer holding
    // its contents, waiting for the arrivals finish to
    // clean and re-balance them, as block floats wait.
    private var pendingColumns: [(spec: TBMultiColumnSpec, sub: TBRenderer)] = []

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
    private func noteSurfaceParagraph(range: NSRange, color: NSColor?,
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

    private var currentFormID: Int { openForms.last ?? -1 }

    private func enterForm(_ node: TBNode) {
        let raw = (node.attrs["action"] ?? "").trimmingCharacters(in: .whitespaces)
        let action = raw.isEmpty ? base
            : (URL(string: raw, relativeTo: URL(string: base))?.absoluteString ?? base)
        let method = (node.attrs["method"] ?? "get").lowercased()
        forms.append(TBFormSpec(id: forms.count, action: action, method: method))
        openForms.append(forms.count - 1)
    }

    private func exitForm() {
        if !openForms.isEmpty { openForms.removeLast() }
    }

    // A form remembers its first named submit control: a
    // browser sends that button's name and value along
    // when the form is submitted from the keyboard.
    private func noteSubmit(_ node: TBNode) {
        guard currentFormID >= 0, forms[currentFormID].submitName == nil,
              let name = node.attrs["name"], !name.isEmpty else { return }
        forms[currentFormID].submitName = name
        forms[currentFormID].submitValue = node.attrs["value"] ?? ""
    }

    private func descendantText(_ node: TBNode) -> String {
        if node.tag == "#text" { return node.text }
        return node.children.map { descendantText($0) }.joined()
    }

    // One <input>, rendered. Text-like inputs seat a field
    // attachment; hidden inputs register silently against
    // their form; submits seat a button attachment;
    // checkboxes and radios draw their state; the rest
    // render as their label until a later step.
    private func formControl(_ node: TBNode, font: NSFont,
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
                let box = CGRect(x: 0, y: 0,
                                 width: CGFloat(label.count) * 8 + 30,
                                 height: 26)
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
            return NSAttributedString(string: " \(glyph) ",
                                      attributes: [.font: font])
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
            var width = tbLengthValue(own["width"] ?? node.attrs["width"],
                                      fontSize: font.pointSize)
            if width == nil, let sizeText = node.attrs["size"],
               let size = Double(sizeText) {
                width = CGFloat(size) * 7.5 + 16
            }
            let box = CGRect(x: 0, y: 0,
                             width: min(max(width ?? 240, 90), 560),
                             height: 26)
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

    // The background layers this element declares, if any.
    func backgroundBox(decls: [String: String]) -> TBBackgroundBox? {
        guard let spec = tbBackgroundSpec(decls, base: base) else { return nil }
        if let cached = backgroundBoxes[spec.key] { return cached }
        backgroundBoxes[spec.key] = spec.box
        return spec.box
    }

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
        // A font: that arrived through var() expands now
        // that its value is concrete (0.23).
        return tbExpandDeferredFont(out)
    }

    // The element's hover declarations (0.23), var()-resolved
    // like the resting style. What the view paints from them
    // is tbHoverPaintAttrs' paint — never layout.
    func resolvedHoverStyle(node: TBNode) -> [String: String] {
        let raw = tbResolveHoverStyle(node: node, rules: rules)
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
        return tbHoverPaintAttrs(decls)
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
        let fetched = await tbFetchDataBatch(fetchJobs)
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
        let fetched = await tbFetchDataBatch(fetchJobs)
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
            await withTaskGroup(of: (Int, String?).self) { group in
                for job in sheetJobs {
                    group.addTask { (job.index, await tbFetchText(urlString: job.url)) }
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
            || !pendingColumns.isEmpty { return true }
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
            let blockRange = NSRange(location: 0, length: buffer.length)
            if align != .left || metrics.hasAny || spaceCarry > 0 {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = align
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
    private func appendJoined(_ buffer: NSMutableAttributedString,
                              _ piece: NSAttributedString, isElement: Bool) {
        if isElement, piece.length > 0,
           let last = buffer.string.last, let first = piece.string.first,
           !last.isWhitespace, !first.isWhitespace, !first.isPunctuation {
            buffer.append(NSAttributedString(string: " "))
        }
        buffer.append(piece)
    }

    private func walkBlock(node: TBNode, style: String, baseFont: NSFont,
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
        var flushedOwn = false
        let linkStart = out.length   // for block-level anchors, below
        let isForm = node.tag == "form"
        if isForm { enterForm(node) }

        var buffer = NSMutableAttributedString()
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
        if !insideFloat, node.tag != "document",
           let columnSpec = multiColumnSpec(
               own, fontSize: effFont.pointSize,
               totalWidth: nominalWidth - metrics.indent - metrics.tailIndent) {
            if columnSpec.ruleColor == nil {
                columnSpec.ruleColor = effColor
            }
            tookColumns = renderColumns(
                node: node, spec: columnSpec, font: effFont,
                color: color, align: align, background: effBackground,
                backgroundBox: effBox, metrics: metrics,
                ownSurface: declaresSurface)
            flushedOwn = tookColumns
        }
        for child in tookColumns ? [] : node.children {
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

        // A block-level anchor (a card styled display:grid, say)
        // never passes through inline(), where links are made —
        // so make the whole block clickable here, keeping the
        // colors its own CSS gave it, and give it its [n] marker.
        if node.tag == "a", let href = node.attrs["href"], !href.isEmpty,
           out.length > linkStart {
            let absolute = URL(string: href, relativeTo: URL(string: base))?.absoluteString ?? href
            links.append(absolute)
            out.addAttribute(.link, value: absolute,
                             range: NSRange(location: linkStart,
                                            length: out.length - linkStart))
            let marker = NSAttributedString(
                string: " [\(links.count)]",
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

        // Positioned layout (0.21): this block's range as a
        // containing block ends where its content did.
        if let block = openedContainingBlock {
            block.endCharIndex = out.length
            containingBlocks.removeLast()
        }
    }

    // MARK: - Positioned layout (0.17)

    private func floatSide(_ raw: String?) -> TBFloatSide? {
        switch (raw ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
        case "left": return .left
        case "right": return .right
        default: return nil
        }
    }

    private func clearSide(_ raw: String?) -> TBClearSide? {
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
    private func relativeOffset(_ decls: [String: String], fontSize: CGFloat)
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
    // sticky is not read.
    private func positionKind(_ raw: String?) -> TBPositionKind? {
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
    private func insetValue(_ raw: String?, fontSize: CGFloat) -> TBInsetValue? {
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
    private func boxLengths(_ decls: [String: String], _ property: String,
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
    private func establishesContainment(_ own: [String: String]) -> Bool {
        for key in ["overflow", "overflow-x", "overflow-y"] {
            if let value = own[key]?.lowercased(),
               ["hidden", "auto", "scroll", "clip"].contains(value) { return true }
        }
        let display = (own["display"] ?? "").lowercased()
        if display == "flow-root" || display == "table" { return true }
        if floatSide(own["float"]) != nil { return true }
        return tbBackgroundColor(own) != nil || backgroundBox(decls: own) != nil
    }

    private func registerImageFloat(_ node: TBNode, own: [String: String],
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
        layoutEvents.append(.float(spec))
        floatCount += 1
        floatImageJobs.append((spec: spec, url: absolute))
    }

    private func registerBlockFloat(_ node: TBNode, own: [String: String],
                                    side: TBFloatSide, font: NSFont,
                                    color: NSColor?, align: NSTextAlignment) {
        let childFont = tbFontApplying(own, to: font)
        let fontSize = childFont.pointSize
        let margins = boxLengths(own, "margin", fontSize: fontSize)
        let padding = boxLengths(own, "padding", fontSize: fontSize)
        let declaredW = tbLengthValue(own["width"], fontSize: fontSize)
        let declaredH = tbLengthValue(own["height"], fontSize: fontSize)
        let spec = TBFloatSpec(anchorCharIndex: out.length, side: side, isImage: false,
                               borderWidth: declaredW ?? 0,
                               borderHeight: declaredH ?? 0)
        spec.widthDeclared = declaredW != nil
        spec.heightDeclared = declaredH != nil
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
    private func measureText(_ string: NSAttributedString, width: CGFloat) -> CGSize {
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
    // fetched, its failures labelled): strip what cannot
    // work inside a painted box — the link targets and
    // their [n] markers (the markers point into the page's
    // link list, which this box is not part of), and the
    // form controls, for which bracketed labels stand in —
    // then size the box: a declared width wins, else the
    // box shrinks to its contents' natural width, capped
    // at the column; a declared height wins, else the
    // measured height of the contents at the final width.
    // Links inside a floated box keep their colors in 0.17
    // but are not clickable — the box is paint, not text.
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
        cleaned.removeAttribute(.link,
                                range: NSRange(location: 0, length: cleaned.length))
        spec.content = cleaned
        let padH = spec.paddingLeft + spec.paddingRight
        let padV = spec.paddingTop + spec.paddingBottom
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

    // MARK: - Multi-column layout (0.22)

    // Split a declaration value at spaces outside
    // parentheses — the token walk tbBoxValues does for
    // box values, needed again here because a shorthand's
    // color may be a function with spaces of its own (a
    // color-mix, an rgb()).
    private func valueTokens(_ raw: String) -> [String] {
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

    // A block's column declarations, resolved to the
    // geometry the columns will stand in — or nil when
    // the block declares no columns, or they resolve to
    // a single column: one column is just the flow, and
    // the painted-box bargain (below) is not worth
    // striking for it.
    private func multiColumnSpec(_ own: [String: String],
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
    private func renderColumns(node: TBNode, spec: TBMultiColumnSpec,
                               font: NSFont, color: NSColor?,
                               align: NSTextAlignment,
                               background: NSColor?,
                               backgroundBox: TBBackgroundBox?,
                               metrics: TBBlockMetrics,
                               ownSurface: Bool) -> Bool {
        let sub = TBRenderer(base: base)
        sub.rules = rules
        sub.visitedURLs = visitedURLs
        sub.insideFloat = true
        sub.nominalWidth = nominalWidth
        sub.walkBlock(node: node, style: tbStyle(for: node.tag),
                      baseFont: font, color: color, align: align,
                      inheritedBackground: nil, inheritedBackgroundBox: nil)
        let visible = (sub.out.string as NSString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visible.isEmpty else { return false }
        spec.content = sub.out
        spec.columnHeight = balanceColumns(sub.out, count: spec.columnCount,
                                           columnWidth: spec.columnWidth)
        spec.totalHeight = spec.columnHeight
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
        pendingColumns.append((spec: spec, sub: sub))
        return true
    }

    // A multicolumn block's contents are finished (its
    // pictures fetched, its failures labelled): strip
    // what cannot work inside a painted box — the link
    // targets and their [n] markers, and the form
    // controls, for which bracketed labels stand in —
    // exactly the cleaning a floated box's contents get —
    // then balance the columns again on the finished
    // text and correct the seat in the page to the final
    // height, so the re-installed page reserves the truth.
    private func finalizeColumns(spec: TBMultiColumnSpec, sub: TBRenderer) {
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
        cleaned.removeAttribute(.link,
                                range: NSRange(location: 0, length: cleaned.length))
        spec.content = cleaned
        spec.columnHeight = balanceColumns(cleaned, count: spec.columnCount,
                                           columnWidth: spec.columnWidth)
        spec.totalHeight = spec.columnHeight
        if let seat = spec.seat {
            seat.image = tbClearSeat(width: spec.totalWidth,
                                     height: spec.totalHeight)
            seat.bounds = CGRect(x: 0, y: 0, width: spec.totalWidth,
                                 height: spec.totalHeight)
        }
    }

    // Arrivals for the multicolumn blocks (0.22): each
    // block's own pictures and backgrounds land first,
    // then its contents are cleaned and re-balanced —
    // the same two-stage life the block floats lead.
    func finishColumns() async {
        for pending in pendingColumns {
            await pending.sub.finishImages()
            await pending.sub.finishBackgrounds()
            finalizeColumns(spec: pending.spec, sub: pending.sub)
        }
        pendingColumns = []
    }

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
        spec.widthFromInsets = !spec.widthDeclared
            && spec.left != nil && spec.right != nil
        spec.heightFromInsets = !spec.heightDeclared
            && spec.top != nil && spec.bottom != nil
    }

    private func registerPositionedImage(_ node: TBNode, own: [String: String],
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

    private func registerPositionedBlock(_ node: TBNode, own: [String: String],
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
        cleaned.removeAttribute(.link,
                                range: NSRange(location: 0, length: cleaned.length))
        spec.content = cleaned
        let padH = spec.paddingLeft + spec.paddingRight
        let padV = spec.paddingTop + spec.paddingBottom
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
            let fetched = await tbFetchDataBatch(fetchJobs)
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
            let fetched = await tbFetchDataBatch(fetchJobs)
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
            finalizeBlockFloat(spec: pending.spec, sub: pending.sub)
        }
        pendingBlockFloats = []
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
                let box = CGRect(x: 0, y: 0,
                                 width: CGFloat(label.count) * 8 + 30,
                                 height: 26)
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
                linked.append(NSAttributedString(string: " [\(links.count)]", attributes: linkAttrs))
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
        return result
    }
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
}

// Render a page in two stages: onFirstPaint is called
// (on the main actor) with the walked page as soon as
// it exists, and the same value is returned once every
// arrival has landed in it. The finishing set (0.23)
// hands the renderer two things only the window knows:
// the session's visited URLs (for :link / :visited) and
// the text area's width as the load began (for @media).
func tbRenderPage(html: String, base: String,
                  visited: Set<String> = [],
                  mediaWidth: CGFloat? = nil,
                  onFirstPaint: (TBFirstPaint) -> Void) async -> TBFirstPaint {
    return await tbRenderFollowingRefresh(html: html, base: base, depth: 0,
                                          visited: visited,
                                          mediaWidth: mediaWidth,
                                          onFirstPaint: onFirstPaint)
}

private func tbRenderFollowingRefresh(html: String, base: String, depth: Int,
                                      visited: Set<String>,
                                      mediaWidth: CGFloat?,
                                      onFirstPaint: (TBFirstPaint) -> Void)
    async -> TBFirstPaint {
    let title = tbExtractTitle(html: html)
    let tree = tbParse(html: html)
    if depth < 3, let target = tbMetaRefreshTarget(root: tree, base: base),
       target != base,
       let (newBase, newHTML) = try? await tbFetch(urlString: target) {
        return await tbRenderFollowingRefresh(html: newHTML, base: newBase,
                                              depth: depth + 1,
                                              visited: visited,
                                              mediaWidth: mediaWidth,
                                              onFirstPaint: onFirstPaint)
    }
    let renderer = TBRenderer(base: base)
    renderer.visitedURLs = visited
    renderer.mediaWidth = mediaWidth
    let body = await renderer.renderFirstPaint(root: tree)
    // A script-only send-on (a search engine's click
    // bounce, say) renders as a black void. When the walk
    // found no words at all, offer the destinations the
    // page's own code names, plainly labelled — an honest
    // door instead of an empty room.
    let visible = (body.string as NSString)
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
                string: "Chirpy doesn't speak JavaScript yet. The destination written in this page's code is:\n\n",
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
            let paint = TBFirstPaint(
                title: title.isEmpty ? "This page needs JavaScript" : title,
                body: notice, pageBackground: nil, columnWidth: nil,
                forms: [], fields: [], landedURL: base, layoutEvents: [],
                arrivalsPending: false)
            await MainActor.run { onFirstPaint(paint) }
            return paint
        }
    }
    let paint = TBFirstPaint(
        title: title.isEmpty ? base : title,
        body: body,
        pageBackground: renderer.pageBackground,
        columnWidth: renderer.columnTextWidth(root: tree),
        forms: renderer.forms,
        fields: renderer.fields,
        landedURL: base,
        layoutEvents: renderer.layoutEvents,
        arrivalsPending: renderer.hasPendingArrivals)
    // The page goes to the window now, on the main
    // actor; the arrivals fetch on behind it.
    await MainActor.run { onFirstPaint(paint) }
    await renderer.finishArrivals()
    return paint
}
