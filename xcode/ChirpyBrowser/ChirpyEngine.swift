//
//  ChirpyEngine.swift
//  Chirpy Browser — engine 0.28.0 (Swift)
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
//    * Flexbox (0.24): a block with display:flex (or
//      inline-flex, treated the same) hands its
//      children to the flex layout — each element
//      child an item sub-rendered like a floated box's
//      contents, each run of text and inline children
//      one anonymous item, as the spec requires — and
//      takes its place in the flow as a clear seat,
//      like a multicolumn block, while the view paints
//      the items into the seat's line. flex-direction
//      in all four spellings (the reverses mirror the
//      laid-out boxes in the container's main extent),
//      flex-wrap: wrap, the six justify-content
//      distributions, align-items and align-self
//      (stretch, flex-start, flex-end, center, and
//      baseline — the shared baseline measured from
//      each item's own layout, first fragment and
//      first glyph), row-gap / column-gap / gap,
//      order, and the item properties flex-grow,
//      flex-shrink, flex-basis and the flex shorthand
//      are read, resolved per the spec's own shape:
//      base sizes clamped to hypothetical sizes,
//      lines collected by them, flexible lengths
//      resolved line by line with items freezing at
//      their declared min and max clamps and at
//      their contents' own size under shrink.
//      Percentages resolve against the container's
//      true content size in the layout pass, never a
//      nominal page. Declared sizes read as the whole
//      box, the floated boxes' convention. Flex
//      containers nest — an item that is itself
//      display:flex sub-renders through the same
//      machinery, its spec riding on its seat under
//      TBFlexSpecKey wherever the painted contents
//      carrying it travel, corrected at the finalize
//      to the width it truly stands in — and a flex
//      container inside a floated, positioned or
//      column box works the same way. An absolutely
//      positioned child is no item; it registers with
//      the positioned machinery as usual. Not read:
//      wrap-reverse (its pages get wrap), align-content
//      (wrapped lines pack at the cross start), and a
//      flex container's percentage height. Items are
//      paint, not live text — the floated box's
//      bargain, struck again: their links show their
//      colors but do not click.
//    * Grid (0.25): a block with display:grid (or
//      inline-grid, treated the same) hands its
//      children to the grid layout, built the flex
//      way — each element child an item sub-rendered
//      in a renderer of its own, each run of text and
//      inline children one anonymous item — and takes
//      its place in the flow as a clear seat, the
//      view painting the items into the seat's line.
//      grid-template-columns and grid-template-rows
//      read track lists whole: lengths, percentages,
//      fr shares, minmax() with fixed or fr bounds,
//      repeat() at a fixed count, and repeat() with
//      auto-fill or auto-fit along an axis that has a
//      definite size and repeated tracks with a
//      definite minimum — auto-fit's expansion leaves
//      its empty tracks standing to be collapsed
//      when no item lands in them, as the spec
//      directs. Named lines are parsed past and
//      forgotten; grid-template-areas and placement
//      by name are not read. Track sizing runs the
//      spec's shape: bases from the items' measured
//      contents (an item spanning several tracks
//      shares its excess across the ones it spans),
//      fixed tracks at their lengths, fr tracks
//      sharing what is left with tracks freezing at
//      their minimums, and percentages resolving
//      against the container's true content size —
//      its width for the columns, its declared height
//      for the rows — in the layout pass, never a
//      nominal page. Placement reads grid-column and
//      grid-row in their line and span spellings, the
//      four longhands, and grid-area in its
//      line-number form; auto placement flows by row
//      from a shared cursor, items definite in both
//      axes placed first and row-locked items next,
//      implicit rows growing as the items demand.
//      grid-auto-flow: column is not read — its
//      pages get row flow — and dense packing is not
//      read either: the cursor never backs up.
//      justify-items and align-items, with their self
//      variants (stretch, start, end, center), set an
//      item inside its area; baseline reads as start.
//      justify-content and align-content share out a
//      track set that does not fill its container.
//      Grid nests as flex does — the spec rides on
//      the seat under TBGridSpecKey, a finalize
//      corrects a nested container to the width it
//      truly stands in, and grid-inside-flex and
//      flex-inside-grid travel the one shared
//      finalize path. Items are paint, not live
//      text — the bargain, struck a third time.
//    * The interaction set (0.26): the states and the
//      sticking place. :focus and :active join the
//      selector grammar as states like :hover's —
//      out of the resting cascade, resolved apart
//      and reduced to the same four paint traits
//      (foreground, background color, underline,
//      strikethrough), stamped under their own keys
//      beside hover's. The view wears them in
//      layers — hover under focus under active,
//      each layer's covered paint snapshotted and
//      restored as one stack — for the element the
//      pointer rests on, the link the reader has
//      focused (a press focuses a link, as in a
//      real browser; a live control taking focus
//      releases the text's), and the element being
//      pressed, respectively. Live form controls
//      are styled by the page: a field takes its
//      font, text color, background, border and
//      corner radius from its computed style (the
//      native bezel stands down when the page
//      paints its own), a submit button takes its
//      background as its bezel tint and its color
//      as its title's; a focused control wears its
//      :focus background or border, a declared
//      outline riding as its border ring for the
//      focus's duration; a button being pressed
//      wears its :active colors for the press.
//      Checkbox and radio glyphs take their
//      element's color. Selects and textareas
//      still render as their text — no live
//      control is built for them. position:sticky
//      is read on block boxes: the element flows
//      and reserves its space like a relative box,
//      the renderer records its range and its
//      containing block's, and the view shifts its
//      paint as the page scrolls — held at its
//      top inset once scrolling would carry it
//      past, pushed off by its containing block's
//      bottom edge (bottom mirrors it from below;
//      top wins when both are declared). The shift
//      rides the relative offsets' paint path, so
//      surfaces and glyphs move together and the
//      flow never does. Horizontal sticking is
//      not read (the page does not scroll
//      sideways), a sticky inside a painted box
//      flows plain, and a sticky flex, grid or
//      column container's seat shifts while its
//      items paint at the flow seat.
//    * The paint & motion set (0.27): the decoration
//      and motion traits, all of them paint — layout
//      never moves for any of them. box-shadow paints
//      outer shadows under block surfaces and painted
//      boxes (offset, blur, spread, color; several at
//      once; inset is read and set aside — there is no
//      honest inside clip here); text-shadow rides
//      under the glyphs in every text path. A state's
//      background layers (a :hover gradient or photo)
//      paint through the same layer painter as a
//      resting background and lift away with the state,
//      exactly as its colors do. column-span: all
//      breaks a multicolumn block's flow: the content
//      before a spanner balances into columns, the
//      spanner stands across the full width, and the
//      columns resume below it. text-overflow:
//      ellipsis truncates a nowrap, overflow-hidden
//      block's line at its content edge — in the text
//      itself, so selection and copying see the
//      truncated line and its ellipsis, as the
//      finishing2 test page states. transform applies
//      the 2D functions (translate, rotate, scale,
//      skew, matrix) as a paint-time affine about the
//      element's transform-origin — surfaces, glyphs
//      and painted boxes move together; the flow, and
//      with it link hit-testing, stays at the
//      untransformed place. opacity joins the stamps
//      as a paint trait. transition animates colors,
//      opacity and transforms between the state paints
//      the engine already tracks (hover, focus,
//      active), and @keyframes runs its named rules'
//      paint traits while the page is shown — both
//      from one view-side timer that exists only while
//      something animates and repaints only the
//      animated ranges, and both stand down entirely
//      when the system asks for reduced motion. Timing
//      functions are cubic Béziers (the named easings
//      and cubic-bezier()); steps() reads as ease.
//      What animation never does here: move layout —
//      width, height and font traits in a transition
//      or a keyframe are not read.
//    * The Shield (0.28): the fetcher itself refuses
//      two bundled lists of domains before any
//      network I/O — an ad shield (advertising and
//      tracking networks) and a family filter (adult
//      and gambling sites) — matched when a request's
//      host is a listed domain or sits under one. A
//      refused page load becomes a calm block page
//      generated here; a refused subresource simply
//      never arrives, and its picture or sheet falls
//      back the way a failed fetch always has. The
//      navigation fetcher asks the same question of
//      redirect targets. The family filter has no
//      off switch — Tyler's standing word, promised
//      on the home page. Subresource requests that
//      cross to another site carry no cookies either
//      way and only the asking page's origin as a
//      Referer, and every request sends the Sec-GPC
//      and DNT signals. The lists are curated
//      starters, not any public corpus whole — the
//      README says so plainly.
//  Not yet: JavaScript (the mountain), inset
//  box-shadows, live select and textarea controls,
//  and the outs named in the README.
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
<h2>Thy word is a lamp to my feet</h2>
<p>"Thy word is a lamp to my feet, and a light to my paths."
&mdash; Psalm 118:105 (Douay-Rheims)</p>
<h2>Doors</h2>
<ul>
<li><a href="https://jesuslovestyler.github.io/Catholic-Bible/">Catholic Bible</a></li>
<li><a href="https://jesuslovestyler.github.io/Catholic-Study-Bible/">Catholic Study Bible</a></li>
<li><a href="https://jesuslovestyler.github.io/Library-of-Faith/">Library of Faith</a></li>
<li><a href="https://jesuslovestyler.github.io/Vigil/">Vigil</a></li>
<li><a href="https://jesuslovestyler.com/">Jesus Loves Tyler &mdash; the hub</a></li>
</ul>
<h2>Our promises</h2>
<p>No tracking by us. No selling data. An ad shield against the big
ad and tracking networks, and a family filter against the big adult
and gambling sites — both on on purpose, not buried in a settings
page.</p>
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

// MARK: - The Shield (0.28)

// The Shield: Chirpy's gate, standing in the fetcher
// itself. Every request this engine issues — a page, a
// form post, a picture, a stylesheet — is built by one
// of the fetch helpers below, and each helper asks the
// Shield before any network I/O happens. Two bundled
// lists of domains, matched by host: a request whose
// host IS a listed domain, or sits under one (any
// subdomain of it), is refused.
//
// A refused page load becomes the block page further
// down — a calm word about what was stopped and why.
// A refused subresource simply never arrives: the
// picture keeps its label, the sheet is skipped, the
// same fallback a failed fetch has always taken.
//
// The lists are data, and plainly commented, so they
// can grow: add a domain on its own line, without a
// scheme and without wildcards. They are curated
// starters — the majors a family browser actually
// meets — not the whole of EasyList or any public
// corpus, and the README says so.
//
// The family filter has NO off switch. That is
// Tyler's standing word, and the home page promises
// it out loud: "on on purpose, not buried in a
// settings page."

enum TBShieldCategory {
    case advertising   // advertising & tracking networks
    case family        // adult & gambling sites
}

// Advertising and tracking: the ad networks, the
// exchanges, the analytics and session-replay
// services, the affiliate and attribution trackers —
// the machinery that follows a reader around the web.
let TBShieldAdDomains: Set<String> = [
    // Google's advertising and measurement
    "doubleclick.net", "googlesyndication.com",
    "googleadservices.com", "googletagservices.com",
    "google-analytics.com", "googletagmanager.com",
    // Social and platform trackers (the parent social
    // sites themselves are NOT listed — only their
    // advertising and pixel hosts)
    "facebook.net", "pixel.facebook.com",
    "ads.twitter.com", "analytics.twitter.com",
    "ads.linkedin.com", "ads.pinterest.com",
    "ct.pinterest.com", "analytics.pinterest.com",
    "ads.tiktok.com", "analytics.tiktok.com",
    "ads.snapchat.com", "tr.snapchat.com",
    "ads.reddit.com", "ads.yahoo.com",
    "bat.bing.com", "clarity.ms",
    // Exchanges, supply and demand platforms
    "adnxs.com", "appnexus.com", "adsrvr.org",
    "rubiconproject.com", "pubmatic.com", "openx.net",
    "criteo.com", "criteo.net", "media.net",
    "amazon-adsystem.com", "smartadserver.com",
    "adform.net", "contextweb.com", "pulsepoint.com",
    "sharethrough.com", "triplelift.com", "gumgum.com",
    "kargo.com", "nativo.com", "sovrn.com", "lijit.com",
    "indexexchange.com", "casalemedia.com",
    "bidswitch.net", "districtm.io", "rtbhouse.com",
    "yieldlab.net", "yieldmo.com", "teads.com",
    "teads.tv", "seedtag.com", "playwire.com",
    "freestar.io", "mediavine.com", "adthrive.com",
    "raptive.com", "snigel.com", "setupad.com",
    "connatix.com", "stackadapt.com", "simpli.fi",
    "basis.net", "choozle.com",
    // Native and content-recommendation networks
    "taboola.com", "outbrain.com", "mgid.com",
    "revcontent.com", "contentad.net", "adnow.com",
    "adskeeper.com", "advertising.com", "adblade.com",
    "plista.com", "ligatus.com", "adyoulike.com",
    // Pop, push and aggressive networks
    "popads.net", "popcash.net", "propellerads.com",
    "adsterra.com", "clickadu.com", "hilltopads.net",
    "adcash.com", "onclickads.net", "onclkds.com",
    "bidvertiser.com", "infolinks.com",
    "vibrantmedia.com", "admarketplace.com",
    "7search.com", "adhitz.com", "a-ads.com",
    "bitmedia.io", "coinzilla.com", "cointraffic.io",
    "evadav.com", "monetag.com", "galaksion.com",
    "mybid.io", "adsupply.com",
    // Adult advertising networks (the ads, here; the
    // destinations themselves are on the family list)
    "exoclick.com", "exosrv.com", "exdynsrv.com",
    "juicyads.com", "plugrush.com", "trafficjunky.com",
    "trafficstars.com", "adxpansion.com",
    "adspyglass.com",
    // Video advertising
    "spotxchange.com", "spotx.tv", "springserve.com",
    "fwmrm.net", "telaria.com", "tremorhub.com",
    "videology.com", "brightroll.com", "innovid.com",
    "flashtalking.com", "sizmek.com", "serving-sys.com",
    "aniview.com", "primis.tech",
    // Mobile advertising and attribution
    "applovin.com", "unityads.com", "ironsource.com",
    "ironsrc.com", "vungle.com", "chartboost.com",
    "mopub.com", "inmobi.com", "startapp.com",
    "airpush.com", "leadbolt.com",
    "millennialmedia.com", "smaato.com", "fyber.com",
    "loopme.com", "adcolony.com", "pangle.io",
    "mintegral.com", "liftoff.io", "moloco.com",
    "ogury.com", "appsflyer.com", "adjust.com",
    "kochava.com", "singular.net", "tune.com",
    "hasoffers.com",
    // Analytics, measurement and session replay
    "scorecardresearch.com", "quantserve.com",
    "quantcast.com", "chartbeat.com", "chartbeat.net",
    "parse.ly", "nr-data.net", "fullstory.com",
    "hotjar.com", "hotjar.io", "mouseflow.com",
    "luckyorange.com", "crazyegg.com", "clicktale.com",
    "clicktale.net", "smartlook.com", "logrocket.com",
    "segment.io", "cdn.segment.com",
    "api.amplitude.com", "api2.amplitude.com",
    "api.mixpanel.com", "heapanalytics.com",
    "woopra.com", "getclicky.com", "statcounter.com",
    "histats.com", "omtrdc.net", "demdex.net",
    "everesttech.net", "2o7.net", "imrworldwide.com",
    "crwdcntrl.net", "exelator.com", "exelate.com",
    "bluekai.com", "bkrtx.com", "mathtag.com",
    "d.turn.com", "addthis.com", "sharethis.com",
    "shareaholic.com", "po.st", "disqusads.com",
    "hs-analytics.net", "track.hubspot.com",
    "mktoresp.com", "marketo.net", "pi.pardot.com",
    "exacttarget.com", "track.customer.io",
    "sendgrid.net", "sessioncam.com",
    "decibelinsight.com", "quantummetric.com",
    "contentsquare.net", "inspectlet.com",
    "optimizely.com", "abtasty.com", "kameleoon.com",
    "dynamicyield.com", "visualwebsiteoptimizer.com",
    "foreseeresults.com", "iperceptions.com",
    "usabilla.com", "kampyle.com", "medallia.com",
    // Push-notification marketing
    "onesignal.com", "pushwoosh.com", "pushengage.com",
    "izooto.com", "aimtell.com", "foxpush.com",
    "pushcrew.com", "subscribers.com",
    // Identity, data brokers and ad verification
    "liveramp.com", "id5.io", "id5-sync.com",
    "tapad.com", "zeotap.com", "lotame.com",
    "agkn.com", "bombora.com", "demandbase.com",
    "rollworks.com", "6sense.com",
    "adsafeprotected.com", "integralads.com",
    "doubleverify.com", "moatads.com", "peer39.com",
    "grapeshot.com", "iesnare.com", "online-metrix.net",
    // Affiliate networks and their tracking domains
    "skimresources.com", "viglink.com", "awin1.com",
    "zanox.com", "tradedoubler.com", "linksynergy.com",
    "shareasale.com", "avantlink.com", "pepperjam.com",
    "impactradius.com", "partnerize.com", "qksrv.net",
    "tkqlhce.com", "dpbolvw.net", "jdoqocy.com",
    "anrdoezrs.net", "kqzyfj.com", "linkconnector.com",
    "adroll.com", "adroll.net", "nextroll.com",
    "perfectaudience.com", "steelhouse.com",
    // Ad servers and long-lived networks
    "zedo.com", "adzerk.net", "buysellads.com",
    "carbonads.net", "adspeed.com", "medialets.com",
    "unicast.com", "eyewonder.com", "pointroll.com",
    "bsserving.com", "undertone.com", "jivox.com",
    "mixpo.com", "adtheorent.com", "dstillery.com",
    "resonate.com", "dataxu.com", "mediamath.com",
    "netmining.com", "owneriq.com", "audiencex.com",
    "adara.com", "sojern.com", "intentmedia.net",
    // Regional majors
    "tanx.com", "mmstat.com", "pos.baidu.com",
    "hm.baidu.com", "mc.yandex.ru", "mc.yandex.com",
    "an.yandex.ru",
]

// The family filter: the major adult destinations
// and the major gambling destinations. On by
// default, on always — see the note at the top.
let TBShieldFamilyDomains: Set<String> = [
    // Adult video and photo destinations
    "pornhub.com", "xvideos.com", "xhamster.com",
    "xnxx.com", "redtube.com", "youporn.com",
    "tube8.com", "spankbang.com", "spankwire.com",
    "keezmovies.com", "extremetube.com",
    "pornerbros.com", "drtuber.com", "4tube.com",
    "fux.com", "alohatube.com", "porn300.com",
    "hclips.com", "sunporno.com", "hqporner.com",
    "porntrex.com", "porndoe.com", "porn.com",
    "sex.com", "motherless.com", "efukt.com",
    "pornpics.com", "pornhd.com", "youjizz.com",
    "empflix.com", "tnaflix.com", "eporner.com",
    "porndig.com", "thisvid.com", "boyfriendtv.com",
    "imagefap.com", "redgifs.com", "scrolller.com",
    "fapello.com",
    // Adult studios and membership sites
    "brazzers.com", "bangbros.com", "realitykings.com",
    "naughtyamerica.com", "digitalplayground.com",
    "twistys.com", "babes.com", "mofos.com",
    "teamskeet.com", "mylf.com", "fakehub.com",
    "pornpros.com", "blacked.com", "vixen.com",
    "tushy.com", "deeper.com", "slayed.com",
    "kink.com", "evilangel.com", "julesjordan.com",
    "metart.com", "x-art.com", "playboy.com",
    "penthouse.com", "hustler.com", "dorcel.com",
    "sexlikereal.com", "vrporn.com",
    // Live cams
    "chaturbate.com", "livejasmin.com", "stripchat.com",
    "bongacams.com", "myfreecams.com", "cam4.com",
    "imlive.com", "streamate.com", "xlovecam.com",
    "camsoda.com", "xcams.com", "flirt4free.com",
    "jerkmate.com", "liveprivates.com",
    "camcontacts.com",
    // Creator and clip platforms (adult)
    "onlyfans.com", "fansly.com", "manyvids.com",
    "clips4sale.com", "iwantclips.com", "loyalfans.com",
    "fancentro.com", "justfor.fans",
    // Drawn and written adult content
    "hanime.tv", "hentaihaven.xxx", "nhentai.net",
    "nhentai.com", "e-hentai.org", "exhentai.org",
    "hentai-foundry.com", "rule34.xxx", "paheal.net",
    "gelbooru.com", "danbooru.donmai.us", "xbooru.com",
    "sankakucomplex.com", "fakku.com", "hitomi.la",
    "tsumino.com", "pururin.io", "asmhentai.com",
    "hentaifox.com", "luscious.net", "8muses.com",
    "hentai2read.com", "simply-hentai.com",
    "doujins.com", "hentaihand.com", "3hentai.net",
    "hentaiera.com", "myhentaigallery.com",
    "literotica.com", "asstr.org", "sexstories.com",
    "nifty.org", "bdsmlibrary.com", "storiesonline.net",
    "lushstories.com",
    // Hookup, escort and adult personals
    "adultfriendfinder.com", "ashleymadison.com",
    "benaughty.com", "xdating.com", "freechatnow.com",
    "eros.com", "bedpage.com", "skipthegames.eu",
    "skipthegames.com", "rubmaps.ch",
    "theeroticreview.com", "eccie.net", "slixa.com",
    "tryst.link", "babepedia.com", "adamandeve.com",
    // Sportsbooks and bookmakers
    "bet365.com", "williamhill.com", "ladbrokes.com",
    "coral.co.uk", "paddypower.com", "skybet.com",
    "betfair.com", "betfred.com", "unibet.com",
    "unibet.co.uk", "betway.com", "betsson.com",
    "betsafe.com", "leovegas.com", "mrgreen.com",
    "rizk.com", "casumo.com", "videoslots.com",
    "comeon.com", "betclic.com", "winamax.com",
    "winamax.fr", "expekt.com", "nordicbet.com",
    "coolbet.com", "888.com", "888casino.com",
    "888poker.com", "draftkings.com", "fanduel.com",
    "betmgm.com", "caesars.com", "pointsbet.com",
    "espnbet.com", "betrivers.com",
    "playsugarhouse.com", "wynnbet.com",
    "hardrockbet.com", "betparx.com",
    "goldennuggetcasino.com", "borgatacasino.com",
    "palacasino.com", "resortscasino.com",
    "hardrockcasino.com",
    // Offshore and crypto books and casinos
    "bovada.lv", "betonline.ag", "sportsbetting.ag",
    "mybookie.ag", "bookmaker.eu", "betus.com",
    "xbet.ag", "superslots.ag", "wildcasino.ag",
    "slots.lv", "cafecasino.lv", "ignitioncasino.eu",
    "stake.com", "stake.us", "rollbit.com", "bc.game",
    "duelbits.com", "roobet.com", "cloudbet.com",
    "sportsbet.io", "bitsler.com", "primedice.com",
    "freebitco.in", "fortunejack.com", "bitstarz.com",
    "playamo.com", "gamdom.com", "csgoempire.com",
    "hellcase.com", "key-drop.com", "skinclub.com",
    "csgo500.com", "thunderpick.io", "ggbet.com",
    "loot.bet", "1xbet.com", "melbet.com",
    "mostbet.com", "parimatch.com", "22bet.com",
    "betwinner.com", "pin-up.bet", "leon.bet",
    // Poker
    "pokerstars.com", "partypoker.com", "ggpoker.com",
    "americascardroom.com", "blackchippoker.eu",
    "natural8.com", "wsop.com", "clubwpt.com",
    "globalpoker.com",
    // Online casinos
    "jackpotcitycasino.com", "royalvegascasino.com",
    "europacasino.com", "casinoeuro.com",
    "karamba.com", "playojo.com",
    "allbritishcasino.com", "casinogods.com",
    "guts.com", "dunder.com", "kaboo.com",
    "thrills.com", "superlenny.com", "nextcasino.com",
    "viks.com", "shadowbet.com", "ikibu.com",
    "codeta.com", "playfrank.com", "instacasino.com",
    "casinoheroes.com", "suomicasino.com",
    "coolcatcasino.com", "slotsofvegas.com",
    "slotsempire.com", "redstagcasino.com",
    "miamiclubcasino.com", "lincolncasino.eu",
    "libertyslots.eu", "everygame.eu",
    "dreamvegas.com",
    // Sweepstakes casinos and pick'em games
    "chumbacasino.com", "luckylandslots.com",
    "mcluck.com", "pulsz.com", "wowvegas.com",
    "fortunecoins.com", "sportzino.com", "modo.us",
    "crowncoins.com", "high5casino.com",
    "dingdingding.com", "prizepicks.com",
    "underdogfantasy.com",
    // Racing, lotteries, bingo, prediction markets
    "twinspires.com", "tvg.com", "xpressbet.com",
    "nyrabets.com", "powerball.com",
    "megamillions.com", "national-lottery.co.uk",
    "thelotter.com", "lottoland.com", "jackpot.com",
    "foxybingo.co.uk", "galabingo.com",
    "tombola.co.uk", "meccabingo.com", "buzzbingo.com",
    "polymarket.com",
]

// A host is held by a list when it is a listed
// domain or sits under one: the walk tries the whole
// host, then drops the first label and tries again,
// down to the bare domain.
func tbShieldMatch(host: String, in domains: Set<String>) -> Bool {
    var candidate = host
    while true {
        if domains.contains(candidate) { return true }
        guard let dot = candidate.firstIndex(of: ".") else { return false }
        candidate = String(candidate[candidate.index(after: dot)...])
    }
}

// Why a host is refused, if it is. The family filter
// is asked first — the stronger refusal wins the
// wording of the block page.
func tbShieldCategory(host: String?) -> TBShieldCategory? {
    guard let host = host?.lowercased(), !host.isEmpty else { return nil }
    if tbShieldMatch(host: host, in: TBShieldFamilyDomains) { return .family }
    if tbShieldMatch(host: host, in: TBShieldAdDomains) { return .advertising }
    return nil
}

func tbShieldCategory(urlString: String) -> TBShieldCategory? {
    return tbShieldCategory(host: URL(string: urlString)?.host)
}

// Escape a string for HTML — the block page prints
// the refused address, and an address is the reader's
// own typing, so it goes in as text, never as markup.
func tbShieldEscapeHTML(_ s: String) -> String {
    var out = s.replacingOccurrences(of: "&", with: "&amp;")
    out = out.replacingOccurrences(of: "<", with: "&lt;")
    out = out.replacingOccurrences(of: ">", with: "&gt;")
    out = out.replacingOccurrences(of: "\"", with: "&quot;")
    return out
}

// The block page: generated here, like the home page,
// in Chirpy's own voice. It says what was stopped and
// why, and it is honest about the way back — there is
// no script in this engine to walk history from a
// page, so the way back is the Back button the window
// already has, and the page says so.
func tbBlockedPageHTML(urlString: String, category: TBShieldCategory) -> String {
    let heading: String
    let why: String
    switch category {
    case .family:
        heading = "Stopped by the family filter"
        why = "This address is on the family filter's list — the adult "
            + "and gambling sites Chirpy will not open. The filter is on "
            + "on purpose, and there is no switch for it: that is the "
            + "promise on the home page, kept."
    case .advertising:
        heading = "Stopped by the ad shield"
        why = "This address belongs to an advertising and tracking "
            + "network — the kind of address other pages load quietly "
            + "behind a reader's back, not a place anyone goes on "
            + "purpose. The ad shield refused it."
    }
    return """
    <!DOCTYPE html>
    <html>
    <head><title>\(heading)</title></head>
    <body>
    <h1>Chirpy Browser</h1>
    <h2>\(heading)</h2>
    <p>Chirpy did not load <b>\(tbShieldEscapeHTML(urlString))</b>.</p>
    <p>\(why)</p>
    <p>Nothing was fetched from that address — the refusal happened
    here, on this Mac, before any request left it.</p>
    <p>Press the Back button above to return to the page you were on,
    or go <a href="chirpy://home">home</a>.</p>
    <h2>Thy word is a lamp to my feet</h2>
    <p>"Thy word is a lamp to my feet, and a light to my paths."
    &mdash; Psalm 118:105 (Douay-Rheims)</p>
    </body>
    </html>
    """
}

// The registrable domain of a host — its last two
// labels (example.com for www.example.com). An
// approximation, honestly: two-part public suffixes
// (co.uk and kin) read as the domain itself, which
// only ever makes two of their subdomains count as
// one site. It is the "same site" test the privacy
// dressing below is allowed to make.
func tbRegistrableDomain(_ host: String) -> String {
    let labels = host.lowercased().split(separator: ".")
    if labels.count <= 2 { return labels.joined(separator: ".") }
    return labels.suffix(2).joined(separator: ".")
}

// Privacy dressing for a subresource request — the
// fetches a page makes behind its reader's back.
// Against the page that asked (pageURLString):
//   same site — the request is left exactly as it
//     was built; today's behavior, untouched.
//   cross site — the request carries no cookies in
//     either direction (the session neither sends
//     stored cookies with it nor keeps any the reply
//     tries to set), and its Referer is the asking
//     page's origin only — scheme and host, never
//     the page's path.
// With no asking page to judge against, the request
// is left as built. Page loads themselves are not
// dressed here: they are the reader's own going,
// and Chirpy has never sent a Referer on one.
func tbShieldPrivacy(_ request: inout URLRequest, pageURLString: String?) {
    guard let pageURLString = pageURLString,
          let pageURL = URL(string: pageURLString),
          let pageHost = pageURL.host,
          let requestHost = request.url?.host else { return }
    if tbRegistrableDomain(pageHost) == tbRegistrableDomain(requestHost) {
        return
    }
    request.httpShouldHandleCookies = false
    if let scheme = pageURL.scheme {
        var origin = scheme + "://" + pageHost
        if let port = pageURL.port { origin += ":\(port)" }
        request.setValue(origin, forHTTPHeaderField: "Referer")
    }
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
    // The Shield (0.28): a listed host is refused here,
    // before any request leaves the Mac — the load
    // becomes the block page instead.
    if let category = tbShieldCategory(host: url.host) {
        return (urlString, tbBlockedPageHTML(urlString: urlString,
                                             category: category))
    }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.28.0 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    request.setValue("1", forHTTPHeaderField: "DNT")
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
    // The Shield (0.28): a form sent to a listed host
    // is refused the same way — the block page answers.
    if let category = tbShieldCategory(host: url.host) {
        return (urlString, tbBlockedPageHTML(urlString: urlString,
                                             category: category))
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("ChirpyBrowser/0.28.0 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    request.setValue("1", forHTTPHeaderField: "DNT")
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
    // The Shield (0.28): set when a redirect's target
    // was refused; the completion then answers with
    // the block page instead of the redirect's reply.
    private var redirectBlock: (url: String, html: String)? = nil

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
        // The Shield (0.28): the navigation gate. A
        // listed host never reaches the session at
        // all — the load returns the block page at
        // once, and the window renders it like any
        // other page.
        if let category = tbShieldCategory(host: url.host) {
            return (finalURL: urlString,
                    html: tbBlockedPageHTML(urlString: urlString,
                                            category: category))
        }
        var request = URLRequest(url: url)
        if let postBody = postBody {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = postBody.data(using: .utf8)
        }
        request.setValue("ChirpyBrowser/0.28.0 (Swift; our own engine)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Sec-GPC")
        request.setValue("1", forHTTPHeaderField: "DNT")
        redirectBlock = nil
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
        } else if let redirectBlock = redirectBlock {
            done?.resume(returning: (finalURL: redirectBlock.url,
                                     html: redirectBlock.html))
        } else {
            let html = String(data: received, encoding: .utf8)
                ?? String(decoding: received, as: UTF8.self)
            done?.resume(returning: (finalURL: landedURL, html: html))
        }
    }

    // The Shield at the redirect (0.28): following a
    // redirect is a fresh going, so its target is
    // asked the same question as any address the
    // reader types. A listed target is not followed —
    // the task completes with the redirect's own
    // response, and the completion above hands the
    // window the block page instead of that reply.
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let category = tbShieldCategory(host: request.url?.host) {
            let target = request.url?.absoluteString ?? ""
            redirectBlock = (url: target,
                             html: tbBlockedPageHTML(urlString: target,
                                                     category: category))
            completionHandler(nil)
            return
        }
        completionHandler(request)
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
func tbFetchData(urlString: String, pageURLString: String? = nil) async -> Data? {
    guard let url = URL(string: urlString) else { return nil }
    // The Shield (0.28): a listed host is refused
    // before any network I/O — the picture falls back
    // to its label, exactly as a failed fetch does.
    if tbShieldCategory(host: url.host) != nil { return nil }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.28.0 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
    request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    request.setValue("1", forHTTPHeaderField: "DNT")
    tbShieldPrivacy(&request, pageURLString: pageURLString)
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
// they never touch the caller's state. The page that
// asked rides along (0.28) so the Shield can judge
// each request's site against its page.
func tbFetchDataBatch(_ jobs: [(index: Int, url: String)],
                      limit: Int = 6,
                      pageURL: String? = nil) async -> [Int: Data] {
    if jobs.isEmpty { return [:] }
    var results: [Int: Data] = [:]
    await withTaskGroup(of: (Int, Data?).self) { group in
        var next = 0
        let window = min(limit, jobs.count)
        while next < window {
            let job = jobs[next]
            group.addTask { (job.index, await tbFetchData(urlString: job.url, pageURLString: pageURL)) }
            next += 1
        }
        for await (index, data) in group {
            if let data = data { results[index] = data }
            if next < jobs.count {
                let job = jobs[next]
                group.addTask { (job.index, await tbFetchData(urlString: job.url, pageURLString: pageURL)) }
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

// The interaction set (0.26): :focus and :active wear
// the same paint as :hover — the same TBHoverStyle
// traits, reduced by the same hand — stamped under
// their own keys, element and block, exactly as
// hover's are. The view keeps the three states as
// layers (hover under focus under active) over the
// same characters and puts the covered paint back
// as one stack when they lift.
let TBFocusAttrsKey = NSAttributedString.Key("TBFocusAttrs")
let TBFocusBlockAttrsKey = NSAttributedString.Key("TBFocusBlockAttrs")
let TBActiveAttrsKey = NSAttributedString.Key("TBActiveAttrs")
let TBActiveBlockAttrsKey = NSAttributedString.Key("TBActiveBlockAttrs")

// The paint & motion set (0.27): the stamps the new
// paint traits ride on — shadows on a block's range,
// text shadows on a paragraph, a paint transform and
// an opacity on a block's or an element's range, and
// the transition and animation specs the view's timer
// works from. All class values, for the hover stamps'
// reason.
let TBBoxShadowKey = NSAttributedString.Key("TBBoxShadow")
let TBTextShadowKey = NSAttributedString.Key("TBTextShadow")
let TBTransformKey = NSAttributedString.Key("TBTransform")
let TBOpacityKey = NSAttributedString.Key("TBOpacity")
let TBTransitionKey = NSAttributedString.Key("TBTransition")
let TBAnimationKey = NSAttributedString.Key("TBAnimation")

// The interaction set (0.26): position:sticky. A sticky
// block's paragraphs carry its spec under this key;
// the layout manager shifts the runs' paint by the
// amount the view's coordinator last resolved for
// that spec (its stickyShifts), through the same
// paint path the relative offsets travel. The flow
// position never changes — a form control seated in
// a sticky element stays at its flow seat, exactly
// as it does inside a relative offset.
let TBStickyKey = NSAttributedString.Key("TBSticky")

final class TBHoverStyle {
    var foregroundColor: NSColor? = nil
    var backgroundColor: NSColor? = nil
    var underlineStyle: Int? = nil
    var strikethroughStyle: Int? = nil
    // The paint & motion set (0.27): the part of a state
    // style the four traits above cannot hold — its
    // background layers, its opacity, its paint
    // transform. The view paints the layers through the
    // ordinary layer painter while the state is worn and
    // lifts them with it, and the opacity and transform
    // ride its effects table.
    var backgroundBox: TBBackgroundBox? = nil
    var opacityValue: CGFloat? = nil
    var transformSpec: TBTransformSpec? = nil
}

// The paint & motion set (0.27): one box shadow —
// offsets in points (y down, as the page reads), a
// blur radius, a spread, and a color. Inset shadows
// never reach this struct: the parser sets them
// aside, because the painters draw a shadow under a
// box and have no honest way to clip one inside it.
struct TBBoxShadow {
    var dx: CGFloat
    var dy: CGFloat
    var blur: CGFloat
    var spread: CGFloat
    var color: NSColor
}

final class TBBoxShadowSet {
    var shadows: [TBBoxShadow] = []
}

// One text shadow: an offset, a blur, a color — a
// text shadow has no spread and no inset in CSS.
struct TBTextShadow {
    var dx: CGFloat
    var dy: CGFloat
    var blur: CGFloat
    var color: NSColor
}

final class TBTextShadowSet {
    var shadows: [TBTextShadow] = []
}

// A transform's numbers before a box is known: a
// plain number (scale factors, matrix entries), a
// length (points, or a percentage of the element's
// own box), and an angle already in radians.
enum TBTransformValue {
    case number(CGFloat)
    case length(TBInsetValue)
    case angle(CGFloat)
}

// The standard product of two affine transforms in
// the (a, b, c, d, tx, ty) layout both CSS's matrix()
// and CGAffineTransform share: the result applies b
// to a point first, then a — the order CSS's
// transform list reads in.
func tbMatrixMultiply(_ a: CGAffineTransform,
                      _ b: CGAffineTransform) -> CGAffineTransform {
    CGAffineTransform(
        a: a.a * b.a + a.c * b.b,
        b: a.b * b.a + a.d * b.b,
        c: a.a * b.c + a.c * b.d,
        d: a.b * b.c + a.d * b.d,
        tx: a.a * b.tx + a.c * b.ty + a.tx,
        ty: a.b * b.tx + a.d * b.ty + a.ty)
}

func tbTransformLength(_ value: TBTransformValue,
                       base: CGFloat) -> CGFloat {
    switch value {
    case .number(let n): return n
    case .length(.points(let p)): return p
    case .length(.percent(let pct)): return base * pct / 100
    case .angle(let r): return r
    }
}

// One transform function resolved against a concrete
// box: percentages in translates mean part of the
// box's own size on that axis, as the spec directs.
func tbTransformMatrix(
    _ function: (name: String, values: [TBTransformValue]),
    in box: NSRect) -> CGAffineTransform {
    let v = function.values
    func number(_ i: Int) -> CGFloat {
        guard i < v.count, case .number(let n) = v[i] else { return 0 }
        return n
    }
    func length(_ i: Int, _ base: CGFloat) -> CGFloat {
        guard i < v.count else { return 0 }
        return tbTransformLength(v[i], base: base)
    }
    func angle(_ i: Int) -> CGFloat {
        guard i < v.count, case .angle(let r) = v[i] else { return 0 }
        return r
    }
    switch function.name {
    case "translate":
        return CGAffineTransform(
            translationX: length(0, box.width),
            y: v.count > 1 ? length(1, box.height) : 0)
    case "translatex":
        return CGAffineTransform(translationX: length(0, box.width), y: 0)
    case "translatey":
        return CGAffineTransform(translationX: 0, y: length(0, box.height))
    case "scale":
        let sx = number(0)
        return CGAffineTransform(scaleX: sx,
                                 y: v.count > 1 ? number(1) : sx)
    case "scalex":
        return CGAffineTransform(scaleX: number(0), y: 1)
    case "scaley":
        return CGAffineTransform(scaleX: 1, y: number(0))
    case "rotate":
        return CGAffineTransform(rotationAngle: angle(0))
    case "skewx":
        return CGAffineTransform(a: 1, b: 0, c: tan(angle(0)),
                                 d: 1, tx: 0, ty: 0)
    case "skewy":
        return CGAffineTransform(a: 1, b: tan(angle(0)), c: 0,
                                 d: 1, tx: 0, ty: 0)
    case "skew":
        return CGAffineTransform(
            a: 1, b: tan(v.count > 1 ? angle(1) : 0),
            c: tan(angle(0)), d: 1, tx: 0, ty: 0)
    case "matrix":
        guard v.count == 6 else { return .identity }
        return CGAffineTransform(a: number(0), b: number(1),
                                 c: number(2), d: number(3),
                                 tx: number(4), ty: number(5))
    default:
        return .identity
    }
}

// A 2D transform as the page declared it: the
// function list, kept unresolved — a percentage
// translate means part of the element's OWN box,
// which only the painter knows — plus the
// transform-origin as two inset values against the
// box, defaulting to its center. matrix(in:) resolves
// the list against a concrete box. A painter already
// holding a resolved matrix (the view, interpolating
// between two transforms mid-flight) may set
// resolvedMatrix, and matrix(in:) then answers it as
// it stands.
final class TBTransformSpec {
    var functions: [(name: String, values: [TBTransformValue])] = []
    var originX: TBInsetValue = .percent(50)
    var originY: TBInsetValue = .percent(50)
    var resolvedMatrix: CGAffineTransform? = nil

    func matrix(in box: NSRect) -> CGAffineTransform {
        if let resolved = resolvedMatrix { return resolved }
        var result = CGAffineTransform.identity
        for function in functions {
            result = tbMatrixMultiply(
                result, tbTransformMatrix(function, in: box))
        }
        return result
    }
}

// A CSS timing function as a cubic Bézier: the two
// control points between (0, 0) and (1, 1).
// evaluate() answers eased progress for linear
// progress — the x(t) inversion every browser does,
// solved by Newton-Raphson with a bisection fallback.
struct TBTimingFunction {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    static let linear = TBTimingFunction(x1: 0, y1: 0, x2: 1, y2: 1)
    static let ease = TBTimingFunction(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeIn = TBTimingFunction(x1: 0.42, y1: 0, x2: 1, y2: 1)
    static let easeOut = TBTimingFunction(x1: 0, y1: 0, x2: 0.58, y2: 1)
    static let easeInOut = TBTimingFunction(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    func evaluate(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if x1 == 0, y1 == 0, x2 == 1, y2 == 1 { return x }
        var t = x
        for _ in 0..<8 {
            let xt = cubic(t, x1, x2) - x
            if abs(xt) < 0.000001 { break }
            let slope = cubicSlope(t, x1, x2)
            if abs(slope) < 0.000001 { break }
            t -= xt / slope
        }
        if t < 0 || t > 1 || abs(cubic(t, x1, x2) - x) > 0.0001 {
            var lo = 0.0
            var hi = 1.0
            t = x
            for _ in 0..<24 {
                if cubic(t, x1, x2) < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
        }
        return cubic(t, y1, y2)
    }

    private func cubic(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    private func cubicSlope(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * p1 + 6 * u * t * (p2 - p1) + 3 * t * t * (1 - p2)
    }
}

// A timing word or a cubic-bezier() — steps() is not
// read (it answers ease, as the header says).
func tbTimingFunction(_ token: String) -> TBTimingFunction {
    let t = token.trimmingCharacters(in: .whitespaces).lowercased()
    switch t {
    case "linear": return .linear
    case "ease": return .ease
    case "ease-in": return .easeIn
    case "ease-out": return .easeOut
    case "ease-in-out": return .easeInOut
    default:
        if t.hasPrefix("cubic-bezier("), t.hasSuffix(")") {
            let parts = t.dropFirst(13).dropLast()
                .split(separator: ",")
                .map { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 4, let a = parts[0], let b = parts[1],
               let c = parts[2], let d = parts[3] {
                return TBTimingFunction(x1: a, y1: b, x2: c, y2: d)
            }
        }
        return .ease
    }
}

struct TBTransitionEntry {
    var property: String
    var duration: Double
    var delay: Double
    var timing: TBTimingFunction
}

// A transition as the page declared it, ready for the
// view's timer: entries by property, "all" answering
// for any property no entry names.
final class TBTransitionSpec {
    var entries: [TBTransitionEntry] = []
    func entry(for property: String) -> TBTransitionEntry? {
        entries.first { $0.property == property && $0.duration > 0 }
            ?? entries.first { $0.property == "all" && $0.duration > 0 }
    }
}

// The paint traits one keyframe stop can carry —
// colors, opacity and a transform; never a layout
// trait, by the set's founding rule.
struct TBAnimTraits {
    var foreground: NSColor? = nil
    var background: NSColor? = nil
    var opacity: CGFloat? = nil
    var transform: TBTransformSpec? = nil
}

// A resolved @keyframes animation on an element: the
// rule's stops reduced to paint traits, with the
// element's own duration, delay, iteration count
// (.infinity plays forever), direction and timing.
final class TBAnimationSpec {
    var stops: [(offset: Double, traits: TBAnimTraits)] = []
    var duration: Double = 0
    var delay: Double = 0
    var iterations: Double = 1
    var direction: String = "normal"
    var timing: TBTimingFunction = .ease
}

// An element's declared opacity, boxed for stamping.
final class TBOpacitySpec {
    var value: CGFloat
    init(_ value: CGFloat) { self.value = value }
}

// One segment of a multicolumn block's contents
// (0.27): either a run of columns (isSpanner false)
// or a column-span: all element standing across the
// block's full width. The view paints the parts in
// order, each in its own slice of the seat.
final class TBColumnPart {
    var content: NSAttributedString? = nil
    var height: CGFloat = 0
    var isSpanner: Bool = false
}

// Flexbox (0.24): a flex container's spec rides on its
// seat character under this key, as a class (attribute
// values that are Swift dictionaries do not survive
// being read back — the hover stamps' lesson). A
// top-level container ALSO records a .flex layout
// event, and the view resolves its seat from the event
// like a multicolumn block's; but a container nested
// inside a painted box — a floated box's contents, a
// column block, another flex item — has no event of its
// own (its renderer records none), so the stamp is what
// carries it: wherever the box's contents travel, the
// seat and its spec travel together, and the view finds
// the stamp when it paints the box and lays the flex
// items into the seat's place, recursively.
let TBFlexSpecKey = NSAttributedString.Key("TBFlexSpec")

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
    // A declared percentage width (0.25.0): the raw
    // percent, kept unresolved because a percentage
    // belongs to the containing block, whose real
    // width only the view knows — the view resolves
    // it at placement time, as it already does a
    // positioned box's percentage insets (0.21).
    // borderWidth meanwhile holds a provisional size
    // resolved against the nominal containing width,
    // which the renderer's own height measurement
    // uses until the view's resolution lands.
    var widthPercent: CGFloat? = nil
    // The horizontal padding of this float's
    // containing block and its block ancestors, in
    // points: how far the containing block's content
    // box is inset within the column. Padding is an
    // absolute length, so this much the renderer can
    // state exactly; the view subtracts it from the
    // real column width before resolving widthPercent.
    var containingPaddingH: CGFloat = 0
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
    // The paint & motion set (0.27): the box's shadows,
    // paint transform and opacity, painted with it.
    var boxShadows: TBBoxShadowSet? = nil
    var transformSpec: TBTransformSpec? = nil
    var opacityValue: CGFloat = 1
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
    case flex(TBFlexSpec)
    case grid(TBGridSpec)
    case sticky(TBStickySpec)
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
    // The paint & motion set (0.27): the box's shadows,
    // paint transform and opacity, painted with it.
    var boxShadows: TBBoxShadowSet? = nil
    var transformSpec: TBTransformSpec? = nil
    var opacityValue: CGFloat = 1
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

// The interaction set (0.26): a block lifted by
// position:sticky — lifted in paint only, never in
// the flow: it stands where the walk put it and
// reserves its space like any block, and the view
// shifts its paint as the page scrolls. The spec
// carries the element's own character range and its
// containing block's (the nearest block ancestor's
// range, recorded the same way — nil when the
// parent is the page itself, whose extent is the
// whole text), and the insets it sticks by: top
// holds it below the viewport's top edge once
// scrolling would carry it above, until the
// containing block's bottom edge pushes it off;
// bottom mirrors that from below. Left and right
// are not read — the page does not scroll sideways.
final class TBStickySpec {
    let rangeBlock: TBContainingBlock
    let containingBlock: TBContainingBlock?
    var top: TBInsetValue? = nil
    var bottom: TBInsetValue? = nil

    init(rangeBlock: TBContainingBlock,
         containingBlock: TBContainingBlock?) {
        self.rangeBlock = rangeBlock
        self.containingBlock = containingBlock
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
    // The segments the block's contents were cut into
    // at its column-span: all children (0.27) — one
    // part when there is no spanner.
    var parts: [TBColumnPart] = []
    // The paint & motion set (0.27): the container's
    // shadows, paint transform and opacity — its seat's
    // surface reads the stamps for the shadow; the item
    // and content painters wrap in the transform and
    // opacity so the whole container moves together.
    var boxShadows: TBBoxShadowSet? = nil
    var transformSpec: TBTransformSpec? = nil
    var opacityValue: CGFloat = 1
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

// Flexbox (0.24): the seat that reserves a flex
// container's height in the flow — a clear-seat
// attachment like the multicolumn block's, one
// character wide in the text and the whole block
// tall — and the spec the walk records for the view:
// the container's flex parameters and its items, each
// item sub-rendered and cleaned like a floated box's
// contents, with every item's border box resolved by
// the renderer's layout pass into the container's
// content-box coordinates. The view paints the items
// into the seat's line.
final class TBFlexSeatAttachment: NSTextAttachment {}

enum TBFlexDirection { case row, rowReverse, column, columnReverse }

// One flex item: its flex properties as the page
// declared them (lengths kept as points-or-percent
// until the layout pass resolves them against the
// container's true size — a percentage resolved
// against a nominal page is the 0.25.0 float bug, and
// flex does not repeat it), its margins and padding,
// its backgrounds, its rendered contents, and — after
// the layout pass — its border box in the container's
// content-box coordinates.
final class TBFlexItem {
    var order: Int = 0
    var grow: Double = 0
    var shrink: Double = 1
    // flex-basis: nil is auto (the item's width or
    // height property, else its contents); basisContent
    // is the `content` keyword (its contents, always).
    var basis: TBInsetValue? = nil
    var basisContent = false
    // align-self: nil is auto — the container's
    // align-items answers.
    var alignSelf: String? = nil
    var marginTop: CGFloat = 0
    var marginRight: CGFloat = 0
    var marginBottom: CGFloat = 0
    var marginLeft: CGFloat = 0
    var paddingTop: CGFloat = 0
    var paddingRight: CGFloat = 0
    var paddingBottom: CGFloat = 0
    var paddingLeft: CGFloat = 0
    var widthDecl: TBInsetValue? = nil
    var heightDecl: TBInsetValue? = nil
    var minWidth: TBInsetValue? = nil
    var maxWidth: TBInsetValue? = nil
    var minHeight: TBInsetValue? = nil
    var maxHeight: TBInsetValue? = nil
    var backgroundColor: NSColor? = nil
    var backgroundBox: TBBackgroundBox? = nil
    // The paint & motion set (0.27): the box's shadows,
    // paint transform and opacity, painted with it.
    var boxShadows: TBBoxShadowSet? = nil
    var transformSpec: TBTransformSpec? = nil
    var opacityValue: CGFloat = 1
    // The item's own rendered contents, painted by the
    // view inside the item's padding — paint, not live
    // text: the floated box's bargain, struck again.
    var content: NSAttributedString? = nil
    // The border box the layout pass resolved.
    var rect: NSRect = .zero

    // The margins along an axis, summed.
    func marginMain(horizontal: Bool) -> CGFloat {
        horizontal ? marginLeft + marginRight : marginTop + marginBottom
    }
    func marginCross(horizontal: Bool) -> CGFloat {
        horizontal ? marginTop + marginBottom : marginLeft + marginRight
    }
    func paddingMain(horizontal: Bool) -> CGFloat {
        horizontal ? paddingLeft + paddingRight : paddingTop + paddingBottom
    }
    func paddingCross(horizontal: Bool) -> CGFloat {
        horizontal ? paddingTop + paddingBottom : paddingLeft + paddingRight
    }
}

final class TBFlexSpec {
    // The paint & motion set (0.27): the container's
    // shadows, paint transform and opacity — its seat's
    // surface reads the stamps for the shadow; the item
    // and content painters wrap in the transform and
    // opacity so the whole container moves together.
    var boxShadows: TBBoxShadowSet? = nil
    var transformSpec: TBTransformSpec? = nil
    var opacityValue: CGFloat = 1
    // Where the seat sits in the text; the view hangs
    // the container from the top of the line that
    // holds it.
    var anchorCharIndex: Int = 0
    let direction: TBFlexDirection
    var wraps: Bool = false
    var justify: String = "flex-start"
    var alignItems: String = "stretch"
    // The gaps as declared, resolved by the layout
    // pass: column-gap percentages belong to the
    // container's width, row-gap percentages to its
    // height when the page declared one (an indefinite
    // height resolves a percentage row-gap to zero, as
    // the spec directs).
    var gapRow: TBInsetValue? = nil
    var gapColumn: TBInsetValue? = nil
    // The container's content-box width — the seat's
    // width, and the span row-direction items share.
    // A variable, not a constant: a container nested in
    // a painted box is first walked against the page's
    // nominal width, and the box's finalize corrects it
    // to the width it truly stands in (see
    // correctFlexSeats).
    var totalWidth: CGFloat
    // The content-box height the page declared, when
    // it declared one; nil is an indefinite height —
    // the container stands as tall as its lines.
    var declaredHeight: CGFloat? = nil
    // The content-box width a declared width or
    // max-width capped the container at, when one did:
    // a finalize correcting a nested container may
    // narrow it to the width it stands in, but never
    // widen it past what the page declared.
    var declaredContentWidth: CGFloat? = nil
    // The container's own min-height / max-height,
    // resolved to content-box points at spec time
    // (percentage heights are not read — there is no
    // definite height above a flow block to resolve
    // them against).
    var minHeightClamp: CGFloat? = nil
    var maxHeightClamp: CGFloat? = nil
    // The laid-out height of the whole container:
    // what the seat reserves.
    var totalHeight: CGFloat = 0
    var items: [TBFlexItem] = []
    // The seat in the page's text, whose bounds the
    // arrivals finish corrects to the final height.
    var seat: TBFlexSeatAttachment? = nil
    // This container's own flow indents (its margins
    // and padding as the flow folded them), recorded
    // so a finalize correcting a nested container can
    // find the content width inside its seat's line.
    var flowIndent: CGFloat = 0
    var flowTailIndent: CGFloat = 0

    init(direction: TBFlexDirection, totalWidth: CGFloat) {
        self.direction = direction
        self.totalWidth = totalWidth
    }
}

// Grid (0.25): a grid container's spec rides on its
// seat character under this key, exactly as a flex
// container's does — a class, for the same reason the
// hover stamps taught: attribute values that are
// Swift dictionaries do not survive being read back.
// A top-level container also records a .grid layout
// event, from which the view resolves its seat; a
// container nested inside a painted box has no event
// of its own, and the stamp is what carries it —
// wherever the box's contents travel, the seat and
// its spec travel together, and the view finds the
// stamp when it paints the box and lays the grid
// items into the seat's place, recursively. One
// finalize path serves both layout systems: the
// corrections each performs scan for both stamps.
let TBGridSpecKey = NSAttributedString.Key("TBGridSpec")

// The seat that reserves a grid container's height
// in the flow — a clear-seat attachment like the
// flex container's, one character wide in the text
// and the whole block tall.
final class TBGridSeatAttachment: NSTextAttachment {}

// One track of a grid template, as the page declared
// it: a minimum and a maximum, each a length (points,
// or a percentage kept raw until the layout pass
// resolves it against the container's true size on
// that axis), or the contents themselves, or — the
// maximum only — a share of the leftover in fr. A
// plain length sets both ends to itself; a bare fr
// sets no minimum, its content floor answering, as a
// minmax() fr minimum also does: neither is read.
// fromAutoFit marks the tracks a repeat(auto-fit)
// produced, the ones the layout may collapse when no
// item lands in them.
struct TBGridTrack {
    var minLength: TBInsetValue? = nil
    var maxLength: TBInsetValue? = nil
    var maxFr: Double? = nil
    var maxContent = false
    var fromAutoFit = false
}

// One grid item: its placement as dressed (a resolved
// 1-based start line per axis, or nil where that axis
// is automatic, and a span per axis), its alignment
// within its area, its sizes, margins and padding,
// its backgrounds, its rendered contents, and — after
// the layout pass — its border box in the container's
// content-box coordinates.
final class TBGridItem {
    var colLine: Int? = nil
    var colSpan: Int = 1
    var rowLine: Int? = nil
    var rowSpan: Int = 1
    // justify-self / align-self: nil is auto — the
    // container's justify-items / align-items answers.
    var justifySelf: String? = nil
    var alignSelf: String? = nil
    var marginTop: CGFloat = 0
    var marginRight: CGFloat = 0
    var marginBottom: CGFloat = 0
    var marginLeft: CGFloat = 0
    var paddingTop: CGFloat = 0
    var paddingRight: CGFloat = 0
    var paddingBottom: CGFloat = 0
    var paddingLeft: CGFloat = 0
    var widthDecl: TBInsetValue? = nil
    var heightDecl: TBInsetValue? = nil
    var backgroundColor: NSColor? = nil
    var backgroundBox: TBBackgroundBox? = nil
    // The paint & motion set (0.27): the box's shadows,
    // paint transform and opacity, painted with it.
    var boxShadows: TBBoxShadowSet? = nil
    var transformSpec: TBTransformSpec? = nil
    var opacityValue: CGFloat = 1
    // The item's own rendered contents, painted by the
    // view inside its padding — paint, not live text:
    // the floated box's bargain, struck a third time.
    var content: NSAttributedString? = nil
    // The border box the layout pass resolved.
    var rect: NSRect = .zero
}

// A grid container: its templates, alignment and
// distribution words, gaps, and the widths and
// heights the flex container's own spec taught this
// one to keep — the content-box width a variable
// (a nested container is walked at the nominal width
// and corrected to the width it truly stands in),
// the declared content height when the page declared
// one, the declared width cap, the height clamps, and
// the laid-out height the seat reserves.
final class TBGridSpec {
    // The paint & motion set (0.27): the container's
    // shadows, paint transform and opacity — its seat's
    // surface reads the stamps for the shadow; the item
    // and content painters wrap in the transform and
    // opacity so the whole container moves together.
    var boxShadows: TBBoxShadowSet? = nil
    var transformSpec: TBTransformSpec? = nil
    var opacityValue: CGFloat = 1
    // Where the seat sits in the text; the view hangs
    // the container from the top of the line that
    // holds it.
    var anchorCharIndex: Int = 0
    var columnTracks: [TBGridTrack] = []
    var rowTracks: [TBGridTrack] = []
    // Normalized words: stretch, start, end, center.
    var justifyItems: String = "stretch"
    var alignItems: String = "stretch"
    // Normalized: start, end, center, space-between,
    // space-around, space-evenly.
    var justifyContent: String = "start"
    var alignContent: String = "start"
    // The gaps as declared, resolved by the layout
    // pass: column-gap percentages belong to the
    // container's width, row-gap percentages to its
    // declared height (an indefinite height resolves a
    // percentage row-gap to zero, as the spec directs).
    var gapRow: TBInsetValue? = nil
    var gapColumn: TBInsetValue? = nil
    var totalWidth: CGFloat
    var declaredHeight: CGFloat? = nil
    var declaredContentWidth: CGFloat? = nil
    var minHeightClamp: CGFloat? = nil
    var maxHeightClamp: CGFloat? = nil
    var totalHeight: CGFloat = 0
    var items: [TBGridItem] = []
    // The seat in the page's text, whose bounds the
    // arrivals finish corrects to the final height.
    var seat: TBGridSeatAttachment? = nil
    // This container's own flow indents, recorded so a
    // finalize correcting a nested container can find
    // the content width inside its seat's line.
    var flowIndent: CGFloat = 0
    var flowTailIndent: CGFloat = 0

    init(totalWidth: CGFloat) {
        self.totalWidth = totalWidth
    }
}

// One side of a grid placement, as written: a line
// number (negative until dress resolves it against
// the explicit grid), a span, or nothing — auto,
// which is also where a line name lands, names being
// parsed past and forgotten.
enum TBGridSide {
    case line(Int)
    case span(Int)
    case auto
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
func tbFetchText(urlString: String, pageURLString: String? = nil) async -> String? {
    guard let url = URL(string: urlString) else { return nil }
    // The Shield (0.28): a listed host is refused
    // before any network I/O — the page renders
    // without that sheet, as it does when one fails.
    if tbShieldCategory(host: url.host) != nil { return nil }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.28.0 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue("text/css,*/*", forHTTPHeaderField: "Accept")
    request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    request.setValue("1", forHTTPHeaderField: "DNT")
    tbShieldPrivacy(&request, pageURLString: pageURLString)
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
        let have = (node.attrs["class"] ?? "")
            .split(whereSeparator: { tbIsSpace($0) }).map(String.init)
        for wanted in compound.classes where !have.contains(wanted) {
            return false
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
    var matched: [TBCSSRule] = []
    for rule in rules where tbSelectorHasState(rule.selector, flag)
        && tbSelectorMatches(rule.selector, node: node,
                             hoverSatisfied: flag == .hover,
                             focusSatisfied: flag == .focus,
                             activeSatisfied: flag == .active) {
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

// The hover resolution (0.23): the declarations an element
// wears while the pointer is over it.
func tbResolveHoverStyle(node: TBNode, rules: [TBCSSRule]) -> [String: String] {
    tbResolveStateStyle(node: node, rules: rules, flag: .hover)
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
    // Percentage float widths (0.25.0): the horizontal
    // padding of the block ancestors currently open,
    // accumulated by walkBlock the way the relative
    // offsets above are — a floated child's containing
    // block is its parent block's content box, which
    // sits this far inside the column.
    private var ancestorPaddingH: CGFloat = 0

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

    // The interaction set (0.26): every block's own
    // character range, open while the block is walked —
    // the stack a sticky element reads its containing
    // block (its parent block) from. Blocks inside a
    // painted box record none, as they record no layout
    // events: a sticky there flows plain.
    private var blockRanges: [TBContainingBlock] = []

    // Multi-column layout (0.22): the multicolumn blocks
    // the walk met, each with the sub-renderer holding
    // its contents, waiting for the arrivals finish to
    // clean and re-balance them, as block floats wait.
    private var pendingColumns: [(spec: TBMultiColumnSpec,
                                  subs: [(part: TBColumnPart, sub: TBRenderer)])] = []

    // The paint & motion set (0.27): the walk's running
    // paint state — the text shadows in force (inherited,
    // as CSS inherits them), whether the block being
    // walked clips its lines unwrapped (white-space:
    // nowrap), the content width an ellipsis block
    // truncates at when the block qualifies, and the
    // child filter a segmented columns sub-renderer
    // walks under, consumed by its first walkBlock.
    private var textShadowSetCurrent: TBTextShadowSet? = nil
    private var nowrapClips = false
    private var ellipsisWidth: CGFloat? = nil
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
    private var pendingFlex: [(spec: TBFlexSpec, subs: [TBRenderer])] = []
    private var flexCount = 0

    // Grid (0.25): the grid containers the walk met,
    // each with the sub-renderers holding its items'
    // contents, waiting for the arrivals finish beside
    // the flex containers — the same two-stage life,
    // and the same nesting through painted boxes, the
    // seat's attribute stamp carrying the spec where
    // no layout event is recorded.
    private var pendingGrid: [(spec: TBGridSpec, subs: [TBRenderer])] = []
    private var gridCount = 0

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

    // One state's declarations (0.23; all three states
    // since 0.26), var()-resolved like the resting style.
    // What the view paints from them is
    // tbHoverPaintAttrs' paint — never layout; what a
    // live form control wears from them is read by
    // controlStyle below.
    func resolvedStateStyle(node: TBNode, flag: TBStateFlag) -> [String: String] {
        let raw = tbResolveStateStyle(node: node, rules: rules, flag: flag)
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
    // in — when it put none. An inset shadow is
    // skipped whole: inset is named out for this
    // engine, whose painters draw a shadow under a
    // box and cannot clip one inside it.
    private func boxShadowSet(_ decls: [String: String],
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
            guard valid, !inset, lengths.count >= 2 else { continue }
            let blur = lengths.count > 2 ? lengths[2] : 0
            guard blur >= 0 else { continue }
            set.shadows.append(TBBoxShadow(
                dx: lengths[0], dy: lengths[1], blur: blur,
                spread: lengths.count > 3 ? lengths[3] : 0,
                color: shadowColor ?? color ?? .black))
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
    private func transformSpec(_ decls: [String: String],
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
    private func opacityValue(_ decls: [String: String]) -> CGFloat? {
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
    private func transitionSpec(_ decls: [String: String]) -> TBTransitionSpec? {
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
    private func animationSpec(_ decls: [String: String],
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
                    || word.hasPrefix("cubic-bezier(") {
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
    private func columnSpanner(_ child: TBNode) -> Bool {
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
        let savedAncestorPaddingH = ancestorPaddingH
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
        var tookFlex = false
        if node.tag != "document", flexCount < 60,
           let flexSpec = flexContainerSpec(own, fontSize: effFont.pointSize,
                                            metrics: metrics) {
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
        var tookGrid = false
        if !tookFlex, node.tag != "document", gridCount < 60,
           let gridSpec = gridContainerSpec(own, fontSize: effFont.pointSize,
                                            metrics: metrics) {
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
        textShadowSetCurrent = savedTextShadows
        nowrapClips = savedNowrapClips
        ellipsisWidth = savedEllipsisWidth

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
    // sticky stays in the flow too and is read in
    // walkBlock (0.26) — it is never an answer here.
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
        spec.boxShadows = boxShadowSet(own, color: nil,
                                       fontSize: ownFont.pointSize)
        spec.transformSpec = transformSpec(own,
                                           fontSize: ownFont.pointSize)
        spec.opacityValue = opacityValue(own) ?? 1
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
    private func controlStyle(node: TBNode, own: [String: String],
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

    // MARK: - Flexbox (0.24)

    // One length as flex reads it: a plain percentage
    // is kept as a percentage (its base is the flex
    // container's own size, which only the layout pass
    // knows); anything else resolves to points through
    // the ordinary length reader. "auto" and the
    // unreadable yield nil.
    private func flexLength(_ raw: String?,
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
    private func resolveFlexLength(_ value: TBInsetValue?,
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
    // percentage height is not read, there being no
    // definite height above a flow block to resolve
    // it against.
    private func flexContainerSpec(_ own: [String: String],
                                   fontSize: CGFloat,
                                   metrics: TBBlockMetrics)
        -> TBFlexSpec? {
        let display = (own["display"] ?? "")
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard display == "flex" || display == "inline-flex"
        else { return nil }
        var direction: TBFlexDirection = .row
        var wraps = false
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
            case "wrap": wraps = true
            case "nowrap": wraps = false
            // wrap-reverse is not read: its lines stack
            // from the cross end, which a seat in a text
            // flow cannot honestly express; the page
            // gets wrap, and the header says so.
            case "wrap-reverse": wraps = true
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
        var declaredHeight: CGFloat? = nil
        if let declared = flexLength(own["height"], fontSize: fontSize),
           case .points(let v) = declared {
            declaredHeight = max(v - padV, 0)
        }
        var minHeightClamp: CGFloat? = nil
        var maxHeightClamp: CGFloat? = nil
        if let declared = flexLength(own["min-height"], fontSize: fontSize),
           case .points(let v) = declared {
            minHeightClamp = max(v - padV, 0)
        }
        if let declared = flexLength(own["max-height"], fontSize: fontSize),
           case .points(let v) = declared {
            maxHeightClamp = max(v - padV, 0)
        }
        let spec = TBFlexSpec(direction: direction, totalWidth: contentW)
        spec.wraps = wraps
        spec.justify = justify
        spec.alignItems = alignItems
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
    private func renderFlex(node: TBNode, spec: TBFlexSpec,
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
        var crossCursor: CGFloat = 0
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
            // expects. Wrapped lines keep their items'
            // sizes and pack at the cross start:
            // align-content is not read.
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

            // Place the items across the line.
            for i in line {
                let item = items[i]
                let mCrossStart = horizontal ? item.marginTop
                    : item.marginLeft
                let mCrossEnd = horizontal ? item.marginBottom
                    : item.marginRight
                let align = alignOf(i)
                var box = cross[i]
                var pos: CGFloat
                if let offset = baselines[i], align == "baseline" {
                    pos = crossCursor + ascent - offset
                } else if align == "stretch", !crossDeclared[i] {
                    box = max(lineCross - mCrossStart - mCrossEnd, 0)
                    pos = crossCursor + mCrossStart
                } else if align == "flex-end" {
                    pos = crossCursor + lineCross - mCrossEnd - box
                } else if align == "center" {
                    pos = crossCursor
                        + (lineCross - box - mCrossStart - mCrossEnd) / 2
                        + mCrossStart
                } else {
                    // flex-start — and baseline across a
                    // column container, whose items stand
                    // one above another with no shared
                    // line of text to align to.
                    pos = crossCursor + mCrossStart
                }
                crossAt[i] = pos
                crossBox[i] = box
            }
            lineCrosses.append(lineCross)
            crossCursor += lineCross + crossGap
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
                                    range: NSRange(location: 0,
                                                   length: cleaned.length))
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

    // Drop what a template may carry besides track
    // sizes: the bracketed line names and the quoted
    // area strings of grid-template. Names are parsed
    // past and forgotten — placement by name is not
    // read — but they must not reach the track parser
    // as sizes.
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
    // number, a span, or auto — which is also where a
    // line name lands, and where a written zero lands,
    // zero being no line at all in CSS.
    private func gridSide(_ raw: String) -> TBGridSide {
        let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty || t == "auto" { return .auto }
        if t.hasPrefix("span") {
            let rest = String(t.dropFirst(4))
                .trimmingCharacters(in: .whitespaces)
            if let n = Int(rest), n > 0 { return .span(n) }
            return .auto
        }
        if let n = Int(t), n != 0 { return .line(n) }
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
    // and a percentage height is not read, there being
    // no definite height above a flow block to resolve
    // it against. The grid-template shorthand (its
    // rows, a slash, its columns) is read first, the
    // template longhands over it — the order this
    // engine reads every shorthand in.
    private func gridContainerSpec(_ own: [String: String],
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
        var declaredHeight: CGFloat? = nil
        if let declared = flexLength(own["height"], fontSize: fontSize),
           case .points(let v) = declared {
            declaredHeight = max(v - padV, 0)
        }
        var minHeightClamp: CGFloat? = nil
        var maxHeightClamp: CGFloat? = nil
        if let declared = flexLength(own["min-height"], fontSize: fontSize),
           case .points(let v) = declared {
            minHeightClamp = max(v - padV, 0)
        }
        if let declared = flexLength(own["max-height"], fontSize: fontSize),
           case .points(let v) = declared {
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
            spec.rowTracks = gridTrackList(own["grid-template-rows"],
                                           fontSize: fontSize,
                                           mainSize: declaredHeight,
                                           mainGap: gapRowPts)
        }
        if own["grid-template-columns"] != nil {
            spec.columnTracks = gridTrackList(own["grid-template-columns"],
                                              fontSize: fontSize,
                                              mainSize: contentW,
                                              mainGap: gapColumnPts)
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
                               explicitCols: Int, explicitRows: Int) {
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
            let parts = area.split(separator: "/",
                                   omittingEmptySubsequences: false)
                .map { gridSide(String($0)) }
            if parts.count > 0 { rowStart = parts[0] }
            if parts.count > 1 { colStart = parts[1] }
            if parts.count > 2 { rowEnd = parts[2] }
            if parts.count > 3 { colEnd = parts[3] }
        }
        if let raw = own["grid-row"] { (rowStart, rowEnd) = sides(of: raw) }
        if let raw = own["grid-column"] { (colStart, colEnd) = sides(of: raw) }
        if let raw = own["grid-row-start"] { rowStart = gridSide(raw) }
        if let raw = own["grid-row-end"] { rowEnd = gridSide(raw) }
        if let raw = own["grid-column-start"] { colStart = gridSide(raw) }
        if let raw = own["grid-column-end"] { colEnd = gridSide(raw) }
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
    private func renderGrid(node: TBNode, spec: TBGridSpec,
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
                          explicitRows: spec.rowTracks.count)
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
        pendingGrid.append((spec: spec, subs: subs))
        gridCount += 1
        return true
    }

    // Lay a grid container out: place every item,
    // size the tracks, and resolve every item's
    // border box in the container's content-box
    // coordinates, with the container's own height.
    // Placement first, in the spec's order — items
    // definite in both axes, then items locked to a
    // row at the first free run in it, then the rest
    // from a shared cursor that only moves forward
    // (dense packing is not read: the cursor never
    // backs up into a hole it passed). Then the
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

        // Placement.
        var colCount = max(spec.columnTracks.count, 1)
        for item in items {
            if let line = item.colLine {
                colCount = max(colCount, line - 1 + item.colSpan)
            }
            colCount = max(colCount, item.colSpan)
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
        var placedRow = [Int](repeating: -1, count: items.count)
        var placedCol = [Int](repeating: -1, count: items.count)
        for i in items.indices {
            guard let rl = items[i].rowLine, let cl = items[i].colLine
            else { continue }
            placedRow[i] = rl - 1
            placedCol[i] = cl - 1
            markArea(rl - 1, cl - 1, items[i].rowSpan, items[i].colSpan)
        }
        for i in items.indices where placedRow[i] < 0 {
            guard let rl = items[i].rowLine, items[i].colLine == nil
            else { continue }
            let r = rl - 1
            var c = 0
            while !areaFree(r, c, items[i].rowSpan, items[i].colSpan) {
                c += 1
            }
            placedRow[i] = r
            placedCol[i] = c
            markArea(r, c, items[i].rowSpan, items[i].colSpan)
            colCount = max(colCount, c + items[i].colSpan)
        }
        var cursorRow = 0
        var cursorCol = 0
        for i in items.indices where placedRow[i] < 0 {
            let item = items[i]
            if let cl = item.colLine {
                let c = cl - 1
                if c < cursorCol { cursorRow += 1 }
                var r = cursorRow
                while !areaFree(r, c, item.rowSpan, item.colSpan) {
                    r += 1
                }
                placedRow[i] = r
                placedCol[i] = c
                markArea(r, c, item.rowSpan, item.colSpan)
                cursorRow = r
                cursorCol = c
            } else {
                var r = cursorRow
                var c = cursorCol
                while true {
                    if c + item.colSpan > colCount {
                        r += 1
                        c = 0
                        continue
                    }
                    if areaFree(r, c, item.rowSpan, item.colSpan) { break }
                    c += 1
                }
                placedRow[i] = r
                placedCol[i] = c
                markArea(r, c, item.rowSpan, item.colSpan)
                cursorRow = r
                cursorCol = c
            }
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
                                    range: NSRange(location: 0,
                                                   length: cleaned.length))
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
