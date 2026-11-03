# Turtle Browser

A web browser with **its own engine**, written from scratch.

Turtle Browser fetches pages itself, parses the HTML with its own
parser, works out the styles with its own CSS code, and paints the
page itself. There is no WebKit, no Chromium, and no Gecko inside —
when Turtle shows you a page, our engine did every step.

It is a browser **for Catholics, by Catholics**: it opens on a
Catholic home page (a verse, and doors to a free Catholic Bible,
a study Bible, and a library of classic Christian books), and it
is built on three promises — no tracking, no ads, no selling data.
Turtle Browser is an independent project; it is not affiliated
with or endorsed by the Catholic Church.

## Status — Engine 0.13.7 (diagnostic)
Forms are real: text and search inputs render as live, editable fields seated in the page where the markup puts them (each attachment carries a clear seat image, because bounds alone reserve no width in the layout), submit buttons chain immediately after their form's field, and Enter (or a click) submits GET and POST forms the way a browser does — hidden inputs, current values, first named submit. Meta-refresh send-ons are followed up to three hops, and a page whose body is only a JavaScript send-on (a search engine's click bounce, say) shows an honest notice offering the destination written in its code instead of a black void. DuckDuckGo's HTML search works end to end; Google's form submits correctly but Google gates its results behind JavaScript for engines it does not know.
What works today:

- Fetching real pages over HTTPS and rendering them as readable,
  clickable documents (headings, paragraphs, lists, links that
  navigate, back/forward history).
- **CSS steps one through four**: `<style>` blocks, inline
  styles, and external stylesheets fetched from
  `<link rel="stylesheet">`, woven into one cascade in document
  order. Selectors: element, class, id, compound (`a.card`,
  `.banner.intro`), descendant (`.banner h1`), child (`ul > li`),
  universal (`*`), and `:root`, matched against the real ancestor
  chain with proper specificity. **CSS variables**: custom
  properties are inherited down the tree and `var()` references
  (with fallbacks) are resolved before painting; when the Mac is
  in dark mode, rules inside `@media (prefers-color-scheme:
  dark)` join the cascade, as in a real browser. **Box
  backgrounds**: a container's background paints behind
  everything inside it (nearest background wins), the color
  layer of the `background:` shorthand is honored, and the
  page's own background becomes the window's canvas color.
  **Layout step one**: computed `display` steers the flow (an
  element styled block, flex, or grid stands as its own block —
  link cards stand apart instead of running together), margins
  and padding become paragraph spacing and indents, and
  line-height is honored, with `clamp()`/`min()`/`max()`
  lengths understood. (0.6.1: block-level links — the cards —
  stay clickable, with their `[n]` markers, keeping the colors
  their own CSS gives them. 0.6.2: link appearance is the
  engine's alone — the text view's default blue no longer
  repaints linked text — each marker sits at its own card's
  end, and sibling spans gain the space a layout's gap would
  give them. 0.6.3: a build fix — the span-join helper no
  longer asks for `inout`, which a constant buffer cannot
  give.) **Layout step two**: the page's own centered column
  is found (a width or max-width cap with auto side margins)
  and the window centers its text in a column of that width,
  and block backgrounds paint as full-width bands across the
  column instead of hugging their words. **Layout step
  three**: continuous surfaces — the spacing seams between
  same-colored paragraphs are bridged, so a colored section
  reads as one painted surface rather than separate stripes.
  (0.8.1: a build fix — the band fill uses `NSRect.fill()`;
  the old C `NSRectFill` is not in scope on current SDKs.)
  **Images**: `<img>` elements fetch in parallel and render
  as real pictures in the flow, sized by their CSS or
  attribute box or their natural size (capped at the page
  width); a failed image falls back to its labelled
  placeholder. `srcset` and inline `<svg>` are not read
  yet. **Background photos**: `background-image` layers
  paint on a block's surface over its color — `url()`
  photos (fetched, or decoded in place from `data:` URIs)
  drawn per `background-size` (cover/contain/lengths),
  `background-position`, and `background-repeat`, with
  `linear-gradient` overlays painted from their color
  stops. Layers belonging to inline elements, and radial
  or conic gradients, are not read yet. The properties:
  color, background color, bold,
  italic, font size, text alignment, underlines, spacing,
  and `display`.

Honest limits, for now:

- No JavaScript. (This is the mountain every engine climbs last;
  JavaScript-heavy sites will look bare.)
- No true box positioning yet — no columns or floats; those
  want a richer paint surface than a text view. Images, tabs,
  and forms are further down the road. Pseudo-classes
  (`:hover`), other `@media` queries, and `color-mix()` are
  not read yet.
- One window, one page at a time.

## The two engines

- **`xcode/`** — the Mac app. The Turtle Engine in Swift
  (Foundation + AppKit only), with a SwiftUI browser window.
  Open `TurtleBrowser.xcodeproj`, choose "My Mac", press Run.
  Release builds are Universal (Apple Silicon + Intel).
- **`python/`** — the original prototype the Swift engine was
  ported from. Pure standard-library Python, no installs:
  `python3 turtle_browser.py` opens the window;
  `python3 turtle_browser.py --dump <url>` prints what the
  engine makes of a page.

## Public domain

This software is released into the **public domain** under the
Unlicense (see `LICENSE`). It is a gift: copy it, modify it,
ship it, sell it, learn from it — no permission needed, no
royalties, forever.

One request, in the spirit of honesty rather than law: the code
belongs to everyone, but the name *Turtle Browser* identifies
this project's own builds. If you make your own browser from
this code, please give your build its own name, so people are
never confused about which browser they are running.

## Why

The web's browsers all descend from a handful of engines owned
by the largest companies on earth. Turtle Browser is a small
proof that an ordinary person can still build one — slowly,
honestly, and in the open.
