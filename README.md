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

## Status — Engine 0.2

What works today:

- Fetching real pages over HTTPS and rendering them as readable,
  clickable documents (headings, paragraphs, lists, links that
  navigate, back/forward history).
- **CSS step one**: `<style>` blocks and inline styles — element,
  class, and id selectors in proper cascade order — for color,
  background color, bold, italic, font size, text alignment,
  underlines, and `display: none`.

Honest limits, for now:

- No JavaScript. (This is the mountain every engine climbs last;
  JavaScript-heavy sites will look bare.)
- No box layout yet — no margins, floats, or columns; pages are
  words-first. CSS step two (descendant selectors, external
  stylesheets) is next on the road, then images, tabs, and forms.
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
