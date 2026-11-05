CHIRPY BROWSER — Xcode project
===============================
Chirpy Browser (formerly Turtle Browser) as a Mac app project:
our own engine, written from scratch in Swift. It fetches
pages itself, parses the HTML with its own parser, and paints
the page itself. No WebKit anywhere in it. Public domain
(Unlicense); the source lives in the Chirpy-Browser GitHub
repo (renamed from Turtle-Browser).

WHAT'S NEW IN 0.37.1 — THE REPAIR BENCH
------------------------------------------------------
Two live failures came back from the Mac,
and both were measured before they were
touched.

* The white doorway. A live DuckDuckGo
  result click settled on the /l/ page —
  white, with the doorway's own address in
  the bar and on the status line, as though
  the load had finished there. It had, in
  a sense: the paint-first order (0.36)
  handed the doorway to the window BEFORE
  its scripts ran. The window installed
  it, cleared the progress and stood the
  load down as finished; only then did the
  script's send-on begin fetching the real
  destination — a 2.7 MB article, seconds
  away. Any touch on that "finished" white
  page began a new load, and the new
  load's generation guard silently
  discarded the destination when it
  landed. The plain refresh chase never
  had this fault — it never paints its
  doorway — which is why a Google
  meta-refresh stub chase followed live
  while the script door seemed shut, and
  why the local file drills passed: a file
  destination paints in a blink, leaving
  no gap to fall into. The fix restores
  the order of 0.33–0.35: scripts run
  first, against the kept tree, and ONE
  walk paints the page they leave behind.
  A doorway is never presented as a
  settled page again. Honest trade, named
  plainly: a page's scripts now run before
  its first paint, bounded by the same
  three-second budget as ever — the way
  a real browser's parser-blocking
  scripts bound it — and the console's
  Timing line loses the repaint member
  the two-walk shape needed. The harness
  witness: fed the verbatim live
  interstitial, through the real progress
  fetcher, the render now hands over
  exactly one paint — the destination.

* The pointer knows a link now. Hovering
  Wikipedia's links showed only the text
  selector. Two things were true: the
  seats (floated boxes, grid and flex
  items, columns, positioned boxes, fixed
  overlays) were never consulted at hover
  at all, and no link cursor was ever set
  anywhere — a seat's link wore the I-beam
  like any word. The point is now asked
  both ways — the text's own link stamp,
  then the seats' — and the pointing hand
  shows where either answers. One
  suspicion was measured and cleared on
  the way: Wikipedia's article body is
  NOT swallowed by any seat. This
  engine's own cascade, run against the
  live "Jesus" article and Wikipedia's
  real stylesheets, resolves every
  ancestor of its paragraphs — page
  container, content container, the body
  main, the parser output — to plain
  block flow: no grid, no flex, no float.
  The article's links are flow links, the
  kind that already navigate from a
  DuckDuckGo results page.

The drill: build and run — the status
line should read "Chirpy Engine 0.37.1
(Swift)". First the errand that failed:
search DuckDuckGo and click a result —
you should land on the real site, and
the doorway should never appear as a
finished page on the way. Then
Wikipedia: open an article, hover a
paragraph link (the hand should show),
and click it; try an infobox link too.
Then the local witness,
wiki-shape-test.html: five links in five
homes — plain flow, a floated box (the
infobox nesting: float, inner div,
paragraph, anchor), a grid item, a flex
item, a positioned box. Hover each for
the hand, click each for its named
landing. Whichever number fails is the
whole report — that shape is where the
remaining trouble lives. And js-test
still keeps its eleven promises, and
interstitial-test still walks through
both its doors.

WHAT'S NEW IN 0.37.0 — THE ONWARD DOORS
------------------------------------------------------
First: this build repairs the 0.36 build
failure. Xcode refused 0.36 with two errors
— "Call to main actor-isolated instance
method 'load' in a synchronous nonisolated
context" — both in the painted-box link
wiring (the seat-link handler and the fixed-
box link handler), which called the model's
load synchronously from inside stored
closures. Both now hop to the main actor
the way this file's own frame observer
already did, and a sweep of the whole file
found no other call like them. Build once:
the repair and everything below arrive
together. (The Linux checker that guards
these builds only parses — it cannot see
actor isolation — which is how the fault
shipped; the diagnosis here was proven by
reproducing your exact error from the 0.36
code's shape, and the fix mirrors the call
site in this same file that has compiled
since before 0.35.)

Then the doors. DuckDuckGo told on us next:
search for anything, click a result, and
you landed on a page that merely showed
the destination's address as a link to tap
by hand. The mechanism, measured: the
result's address is a redirector, and the
redirector answers not with a redirect but
with a scrap of a page carrying two
send-ons — a line of JavaScript,
window.parent.location.replace(url), and a
meta refresh folded inside <noscript>.
Chirpy opened neither: its window object
was a shell with no location, no parent,
no top, so the script's road walked into
undefined and died; and the parser sets
noscript subtrees aside whole, so the
refresh hunt, which walks the parsed tree,
never saw the folded tag.

* Scripts can send the reader onward now.
  window carries a location — the same
  object at window.location,
  document.location, and the bare name —
  with href to read and to write, and
  replace and assign. window.parent,
  window.top and window.self are the window
  itself: a single-frame world. A script's
  chosen destination is resolved against
  the page's own address (http, https and
  file travel; nothing else does), ends
  the script stage, and is followed the
  way a meta refresh is followed — the
  same three-hop limit, the same
  Shield-checked fetch — so the address
  bar and the history name the
  destination, never the doorway, and a
  send-on to a listed host lands on the
  Shield's block page, exactly as typing
  that address would. The JavaScript
  console honors a typed location the
  same way, through the window's own load.

* The folded refresh is read too. When a
  page's scripts have had their say and
  the reader is still standing there, the
  raw text inside <noscript> is parsed
  and asked for a refresh of its own, and
  a send-on found there is followed down
  the same road — the fallback door, in
  its proper order: scripts first, as
  noscript has always meant.

The drill: build and run — the status line
should read "Chirpy Engine 0.37.0 (Swift)"
and name "script navigation" among the
features. First, the errand that named the
need: type a word in the address bar, open
the DuckDuckGo results, and click any
result — you should land on the real site,
not on a page of addresses. Then the local
witness, interstitial-test.html (its four
small companions beside it): step through
the script door and you should land on a
page that begins "You came through the
SCRIPT door"; go back, step through the
noscript door, and its page begins "You
came through the NOSCRIPT door". And
js-test still keeps its eleven promises.

WHAT'S NEW IN 0.36.0 — THE SPEED STAGE, AND LINKS THAT ANSWER
------------------------------------------------------
Wikipedia told on us: a real article took so
long we went and measured before we touched
anything. The numbers (our own engine's code,
run headless against the real "Cardinal
(bird)" article — 220 KB of HTML, 2,818
elements, 607 stylesheet rules):

* Parsing was never the problem: the whole
  article parses in about a tenth of a
  second, its CSS in about the same.

* The style stage was the mountain. One pass
  resolving every element's style took about
  49 seconds — and almost all of it was the
  CSS custom-property environment, which
  matched all 607 rules against every
  ancestor of every element (about 87
  seconds when isolated), though only 4 of
  the 607 rules define a --property at all.
  It matches only those now. The resting
  cascade's own full scan (about 2 seconds a
  pass, and the walk asked for the same
  elements again and again) is answered from
  an index by each selector's simplest key,
  and each element's resolved style is
  remembered for the walk's life. The same
  pass, same article, same output — verified
  element for element against the old way —
  now takes about a second and a half (and the
  walk's repeat questions are answered from
  memory, not recomputed).

* Scripts no longer stand in front of the
  painting. A page paints first; its scripts
  run afterwards against the kept page, and
  if they change anything the page repaints
  a beat later (the console's repaint, doing
  double duty). Wikipedia's own scripts die
  in our young interpreter in about 0.02
  seconds — they were never the wall — but
  on a page whose scripts do run, you now
  see the page while they work.

* A script budget. The whole script stage —
  fetches and execution together — gets
  three seconds. Past it, no more of that
  page's scripts run, and the console says
  so in plain words: "Script budget reached
  — the rest of this page's scripts were
  skipped". One misbehaving page can no
  longer hold the browser hostage.

* A Timing entry for every load, standing
  in the console as a Note: fetch, parse,
  style+layout, scripts, and the total (and
  a repaint time, when the scripts changed
  the page). Your Mac is now the profiler:
  these are the numbers to watch, cold and
  warm.

And the links. On real pages, clicking a
link inside the page's words did nothing
but select — while Chirpy Home's links
worked. The mechanism, found: links inside
painted boxes — floated boxes, grid and
flex items, columns, positioned boxes —
had their targets stripped when the box was
finished, because the box is paint, not the
text view's text, and the native click path
only ever sees text. Chirpy Home has no
such boxes, so its links lived. Now the
boxes keep their targets, and the view
hit-tests a click inside a painted box
against the same layout that painted it:
a click on a link in a box follows it. (A
container nested inside a box's own
contents is not followed yet — that is the
named remainder, not a silent one.)

The drill: build and run — the status line
should read "Chirpy Engine 0.36.0 (Swift)"
and name "the speed stage, painted-box
links" among the features. Open js-test
(helper beside it): all eleven promises
still filled, the title still the script's
own, the console and the alert still in
the drawer — the promises land a beat
after the page paints now, which is the
paint-first bargain made visible. Open a
Wikipedia article cold, press Console, and
read the Timing entry (a Note). Open the
SAME article again — the cache is warm —
and compare: fetch should fall away and
the total with it. Then the links: on
Wikipedia's main page, click a link in the
"Featured article" area, and on an article
page click one of the blue links in the
article's words and one inside the
infobox — every one should navigate. On
the hub, click a card. Plain clicks, no
dragging: a drag still selects, as it
should.

WHAT'S NEW IN 0.35.0 — DEVELOPER TOOLS AND SETTINGS
------------------------------------------------------
You asked for what every browser has: a
console for the page — its HTML, its CSS,
its JavaScript — and a place to debug our
own engine with. And you could not see the
alert, even full-screen. Both are answered
here.

* A console drawer. Press Console on the
  bar and a drawer opens under the page, with
  two faces. The Console face holds what a
  page said — its console words, its script
  errors, its alerts, the Shield's refusals —
  as readable entries, in the order they
  came. They no longer live only at the
  status line's tail, which the window cut
  out of sight; that is where the alert was
  hiding. An alert also raises a banner
  under the bar until you dismiss it. While
  the drawer is shut, the Console button
  counts what arrived.

* A JavaScript console. At the foot of the
  Console face, a field: type JavaScript,
  press Return, and it runs through our own
  interpreter in the landed page's own scope.
  The page is kept after it paints — its
  tree, its scope, the renderer that painted
  it — so a function a fetched helper left
  behind is still there to call, an element's
  text can be read, and a write repaints the
  page from its kept tree so you see the
  change. Debugging our engine, with our
  engine's own machinery.

* The Inspector. The drawer's second face:
  the landed page's tree — tags, ids,
  classes, its text — and, for the element
  you choose, the declarations our engine
  itself resolved for it, plus the rules
  that matched it, in cascade order. When a
  page looks wrong in Chirpy, this is where
  the reason stands. Read-only for now;
  editing a style live is the next step.

* A white page. A page that paints no
  background of its own is now laid on
  white, as real browsers lay it. The canvas
  used to fall back to the Mac's system
  text background, which follows the dark
  appearance — so js-test, a plain unstyled
  page, showed black words on a near-black
  ground. A page that paints its own
  background, in its styles or in its own
  color-scheme rules, keeps it untouched:
  the hub and hub-shape-test look exactly
  as they did.

* Settings. A Settings button opens a
  sheet: the homepage the Home button and a
  launch open; the cache's cap (50, 100, 200
  or 500 MB); the page text size (90% to
  125%), which reloads the page so you can
  see it; and whether links carry their [n]
  numbers. Every one is honored by the
  engine and kept between launches. The
  Shield stands there as fact — its lists'
  sizes — and never as a switch: there is no
  setting that turns it off, on purpose.

* The mark. The singing cardinal in stained
  glass — your choice — now stands on Chirpy
  Home and at the head of the repo's README.
  The app icon is the named remainder: the
  project carries no asset catalog yet, so
  the icon set is cut and waiting in the
  workspace's assets, not yet wired in.

The drill: build and run — the status line
should read "Chirpy Engine 0.35.0 (Swift)"
and name "the console, the inspector,
settings" among the features. Open
js-test.html (helper beside it) and press
Console: promises 10 and 11's evidence is
all there, readable at any window size —
two Console entries ("the console is alive"
and "second line with two arguments"), one
Alert entry, and the alert banner under
the bar. And look at js-test itself: the
plain unstyled page now reads
black-on-white like paper, all eleven
promises still filled — where on 0.34 it
stood black on near-black. In the
JavaScript field type 1+1
and press Return: the answer is 2. Type
document.getElementById("p1").textContent
and Return: the promise-1 sentence. Set
it — document.getElementById("p1")
.textContent = "Changed from the console."
— and watch the page change. Type
chirpyHelperNumber: 42, the helper's gift,
still in scope. Then open the Inspector,
tap the element <p id="p1">, and read the
style our engine resolved for it and the
rules that matched. Settings drill: give
the homepage an address, save it, and
press Home; change the text size and
watch a page grow; turn the link numbers
off and watch the [n]s vanish — and back
on again just as easily.

WHAT'S NEW IN 0.34.0 — THE REPAIR
------------------------------------------------------
Three failures from your own drill on Nov 5,
each traced to its mechanism before it was
touched, and fixed at the root.

* JavaScript runs now. On Nov 5 the js-test
  page landed with all eleven promises still
  reading "waiting for the script" — the whole
  script block had died on one line. The cause,
  proven against the engine's own code: the
  parser's "return" asked the wrong question —
  it took a returned value to begin only when
  the next token was punctuation, so a return
  whose value begins with a name, a number or
  a string was read as a bare return. Worst
  hit: a returned closure, "return function()
  {...}" — the orphaned function was parsed as
  a new statement and died, and because a
  script is parsed whole before any of it
  runs, that one line silenced every promise.
  The question is asked rightly now, and the
  whole drill passes against this code.
  And a script error no longer hides: it leads
  the status line, right after the address,
  instead of riding at the end of it where the
  window's edge cut it out of sight.

* Cards keep their shape. A grid container's
  inline children — the spans a card is built
  of — were gathered into one text item, so
  the hub's directory cards collapsed: name
  and description flowing together in the
  first track, the arrow standing in the
  second, the third track empty. Now every
  child of a grid container stands as its own
  item, as CSS says. And the grid cap is
  twelve hundred containers, not sixty: the
  hub alone declares two hundred grids (every
  card, every arrow disc), and past the old
  cap the rest of the page silently flowed
  un-gridded.

The drill: build and run — the status line
should read "Chirpy Engine 0.34.0 (Swift)" and
name "the repair" among the features. Open
js-test.html again (helper beside it): every
promise should now be filled by the page's
own scripts, the title over the page should
read "JavaScript Lives Here — Set by Script",
and the status line should carry its Console
notes. Then open hub-shape-test.html — three
promises in the hub's own shapes: a directory
card whose name, description and arrow stand
in their own tracks; forty cards in a row's
worth of directory, the fortieth still a
proper card; and a section whose heading and
links keep their two columns. Then look at
jesuslovestyler.com itself: the Faith cards
should stand in three tracks, near and far
down the directory alike. Two honest notes:
a control inside a grid or flex seat still
stands as its labelled placeholder (the
hub's search field is one — the seats are
paint, not text), and two things from your
screenshots are still unproven and unfixed,
named in the repo README: the wide empty
stretch under the hub's search bar, and the
share row's buttons standing full-width.

WHAT'S NEW IN 0.33.0 — JAVASCRIPT, THE FIRST SLICE
------------------------------------------------------
The mountain's first camp, called back onto the
plan by your word: Chirpy now runs a page's own
code — a small, honest slice of JavaScript, with
the interpreter written from scratch like
everything else in the engine.

* Kept and run. The parser no longer throws
  scripts away: a <script> is kept as raw text
  with its attributes, the way style sheets and
  text areas are kept, and after the page lands
  (refresh followed first), every script runs in
  document order before the page is painted — so
  the words a script writes are the words you
  read. Inline code and external src files
  alike; an external file is fetched the way a
  style sheet is, with the Shield asked first
  and the cache beneath, and all of a page's
  scripts share one scope, as in a browser.

* The language. A lexer, a parser and an
  evaluator of our own: var, let and const;
  numbers, strings and booleans; arithmetic and
  comparison, with + joining strings as it
  should; if/else; for, while and do-while;
  functions with parameters, return and
  closures; arrays and plain objects, read and
  written by member and by index; the ternary
  and the logical operators; string and array
  helpers — length, charAt, indexOf, slice,
  split, trim, the case folds, push, pop, join,
  concat; and parseInt, parseFloat, isNaN, and
  the String and Number conversions.

* The bridge to the page. document.
  getElementById finds an element by its id;
  its textContent and innerHTML read and write
  its words (a write lands as text — markup a
  script writes is not parsed in this slice);
  document.title reads and sets the page's
  title. console.log goes to the window's
  status line, marked "Console:", and
  window.alert rides the same road as a note —
  there is no sheet. A script's error stops
  that script alone and is noted on the status
  line the same way; the page still paints.

* Named out of this slice, plainly: event
  handlers and attribute handlers (onclick and
  kin), timers (setTimeout, setInterval), fetch
  and XMLHttpRequest, script-driven navigation,
  and the wider DOM — no querySelector, no
  createElement, no style access from script.
  A name nobody defined reads as undefined
  rather than halting the page, a leniency real
  pages lean on, taken knowingly.

The drill: build and run — the status line
should read "Chirpy Engine 0.33.0 (Swift)" and
name "JavaScript's first slice". Then open
js-test.html (keep js-test-helper.js beside it)
and read the eleven promises: each numbered
sentence was written into the page by the
page's own scripts, and a promise still reading
"waiting for the script" names a piece that did
not run. Promise 10 is the title over the page;
promise 11 lives on the status line itself.
The closing section's button honestly cannot
answer yet. Regression passes after: the home
page, shield-test.html, controls-test.html,
and a picture page for the cache.

WHAT'S NEW IN 0.32.0 — THE CACHE
------------------------------------------------------
The parked piece, built at last now that the CSS
program is done: Chirpy keeps what it fetches, on
your own disk, and serves it again honestly.

* Where it lives. Under the app's caches folder
  (ChirpyBrowser/HTTPCache), as plain files: one
  body file and one small card per kept reply, the
  card carrying the address, the freshness word the
  server sent, and when the reply came in and was
  last used. It is the only thing Chirpy keeps
  between launches, and nothing about it is ever
  reported anywhere — there is no telemetry to
  report it with.

* What is kept. Successful GET replies only —
  pages, style sheets, scripts and pictures, HTML
  and CSS and images alike — and only those whose
  own headers allow keeping. no-store is never
  written down at all. A reply bigger than 25 MB
  is not kept, and the whole cache is capped at
  200 MB: past the cap, the least recently used
  entries are let go until it fits.

* Freshness, the server's own word. Cache-
  Control's max-age first; then Expires; then,
  when a page offers nothing else, a tenth of the
  time it had already lived unchanged when fetched
  (the browsers' old heuristic, bounded at a week
  so nothing rides it forever). no-cache is kept
  but always asked about again. A stale entry with
  an ETag or a Last-Modified is asked about
  conditionally — If-None-Match, If-Modified-
  Since — and a 304 answer renews the entry and
  serves the kept body. Nothing is stale-forever:
  an entry with no freshness word and no validator
  is simply fetched again.

* Every road leads through it. The window's page
  loads (the progress fetcher included), the plain
  page path, sheets, and pictures all come through
  one shared cached GET. A form's POST is never
  cached, and a dropped local file keeps its plain
  path off disk, untouched.

* The Shield still stands first. It is asked
  before every cache lookup: a listed host is
  never served from the cache — and blocked
  content was never fetched, so it is never in
  the cache to serve. The privacy dress is
  unchanged: cross-site subresources still carry
  no cookies and an origin-only Referer, and every
  request still sends Sec-GPC and DNT.

* The broom. The window's bar carries a Clear
  cache button now, beside Go: one press empties
  the whole cache, and the status line says how
  much was let go (or that it was already empty).

The drill: build and run — the status line
should read "Chirpy Engine 0.32.0 (Swift)" and
name "the cache" among the features. Then:
(1) open a picture-bearing page of your own site,
let it settle, press Reload — the page should
come back visibly faster, served off your disk;
(2) press Clear cache and read the status line's
word, then Reload again — the page fetches fresh,
and the button's next press should report the
cache was already empty only after you clear it
twice in a row; (3) shield-test.html end to end —
the blocked doors must stay blocked exactly as
before, cache or no cache; (4) regression passes:
controls-test, flex-test and grid-test end to
end, then the home page.

WHAT'S NEW IN 0.31.0 — LIVE SELECT & TEXTAREA CONTROLS
------------------------------------------------------
The last of the engine's named gaps: a <select>
is a real popup button now, and a <textarea> a
real multi-line editor — the two controls that
rendered as their text since the beginning.

* The select. Its rows gather in document order
  (the parser nests a following <option> inside
  the one before it, there being no implied
  close, so the gathering flattens as it walks);
  each row's value is its value attribute, or
  its label where it has none. An <optgroup>'s
  label stands among the rows as a disabled
  group row. The resting choice is the last
  option carrying selected — the choice a
  browser's parser leaves standing — else the
  first real option. The seat is the widest
  label's measure in the element's font, plus
  room for the popup's own chrome, or the
  declared CSS size. A multiple select seats
  the same popup, resting on its first chosen
  option: picking several at once is NOT built,
  named plainly. The popup wears the page's
  font, and its background as a tint when one is
  declared — the rows' text and the popup's own
  chrome are AppKit's and take no CSS dress,
  and neither do a CSS border or corner radius,
  as with a button's.

* The textarea. Its seed is the element's own
  text, read raw by the parser the way <style>
  is — markup written inside a seed can no
  longer bend the document tree — with the
  entities decoded once as the seed is read,
  and the one leading newline dropped, as HTML
  directs. rows and cols size the seat by the
  element's own font cells, a declared CSS size
  winning. The editor is a plain text view in
  its own scroll view: the scroll view wears
  the border and background of the element's
  style on its layer, the editor the font and
  the text color, and a declared outline rides
  as the border ring while the focus lasts,
  exactly as a field's does. A placeholder
  stands in the editor in the placeholder gray
  while the seed is empty, clearing at the
  reader's first focus; it never comes back,
  and it is never the field's value.

* Both, with the others. The two seat through
  the same attachments, anchors and reaping as
  the fields and buttons — a page's controls
  never outlive the page — take real keyboard
  focus (taking it also releases the text's
  focused link, as a field's focus does), and
  send their current value with their form
  through the standing GET and POST path: the
  popup its chosen row's value, the editor its
  current words. What the reader chose or wrote
  rides across the arrivals re-install beside
  the typed field values. Pressing Enter in an
  editor makes a new line, never a submission,
  and choosing in a popup submits nothing — no
  script is listening, there being no
  JavaScript. A disabled attribute is not read,
  here or on the controls before them. Inside a
  painted box both keep the standing
  bracket-label stand-in — the select wearing
  its resting choice's label there, the editor
  its placeholder or "field", as a field does.

The drill: build and run — the status line
should read "Chirpy Engine 0.31.0 (Swift)" and
name "live selects and text areas" among the
features. Then controls-test.html, all seven
promises, every one of them Tyler's hands: the
popup resting on its chosen dish, its group
rows dimmed in the opened menu (1); the seeded
editor taking new words (2); the Send press
carrying the dish's value and the editor's
words into the address bar (3); the popup in
the page's own dress (4); the styled editor,
its clearing placeholder and its amber focus
ring (5); the floated select standing as its
bracketed label (6); the multiple select
wearing its first chosen option as a plain
popup (7). Regression passes: flex-test,
grid-test, interaction-test, finishing-test,
finishing2-test, banding-test and shield-test
end to end, then the home page. With this
stage the form machinery stands complete:
the engine header's "Not yet" now holds
JavaScript alone.

WHAT'S NEW IN 0.30.0 — THE SMALL COMPLETIONS
------------------------------------------------------
The named outs of 0.24, 0.25 and 0.27, emptied —
the last of the CSS program's honest gaps. Four
pieces:

* Flex completions. align-content joins the flex
  layout: for a container with two or more lines
  and a definite cross size, the leftover height
  (or width, in a column container) is shared
  among the LINES — flex-end and center shift the
  whole stack, space-between / space-around /
  space-evenly widen the gaps between lines, and
  stretch grows every line alike, its stretch and
  center items then answering inside the grown
  line. flex-wrap: wrap-reverse is read truly:
  the cross axis is flipped, so lines stack from
  the cross-end, cross margins trade places, and
  alignment and baselines answer to the flipped
  axis. Fall-backs, named: when the lines overflow
  the cross size, the space distributions and
  stretch fall back to start packing (flex-end and
  center still shift, as CSS directs); a single
  line still takes the container's cross size
  whole, as before.

* Grid completions. Placement now runs in flow
  coordinates — one algorithm serving both flows,
  transposed exactly as the spec writes it.
  grid-auto-flow: column flows items down the
  rows, opening implicit columns as needed; dense
  (either flow) restarts the placement cursor at
  the first cell for every item, so a late small
  item backfills a hole the sparse cursor passed.
  Line names are read in both templates —
  grid-template-columns: [start] 200px [middle]
  1fr [end] — and placement sides answer to them
  (grid-column: middle / end), to their counted
  namesakes (start 2), and to the area-edge names
  (main-start). grid-template-areas draws its
  map of quoted rows; grid-area: <name> places an
  item into the name's rectangle, and the axis
  longhands still layer over it. Fall-backs,
  named: names written inside a repeat() are not
  read, and neither is anything after an
  auto-fill / auto-fit repeat; span <name> reads
  as plain auto placement; a name nothing answers
  — or a grid-area naming no area — falls back to
  auto placement; and a template-areas map in
  which any name fills something other than a
  rectangle, or whose rows disagree in length,
  voids the WHOLE map (its declarations drop, as
  CSS drops an invalid declaration).

* Percentage heights for both containers. A flex
  or grid container's own height, min-height and
  max-height written in % now resolve against the
  definite height of the block ancestor the walk
  has open — a height declared in points, or
  itself a resolved percentage, chained down —
  instead of reading as auto. Still auto, named:
  where no ancestor declares a height, and inside
  a painted item (a flex / grid item's contents, a
  float), whose height is born in layout, after
  the walk has passed.

* Inset shadows and steps(). box-shadow's inset
  keyword paints: the frame between the box and
  its spread-shrunk, offset-shifted inner shape,
  filled with the shadow's color under its blur,
  clipped to the box — above the background and
  its layers, below the contents, on every painter
  that carries the outer kind (block surfaces,
  painted boxes, flex and grid items, fixed
  overlays). A list mixing the kinds paints each
  kind in its own list order, first-listed on
  top. And the timing evaluator reads steps():
  steps(n) and steps(n, start / end), the jump
  terms (jump-start / jump-end / jump-none /
  jump-both), and step-start / step-end — progress
  moving in discrete stands, in transitions and
  keyframe runs alike. (Per-stop keyframe timing
  functions remain unmodelled, as in 0.27: one
  timing serves the whole run.)

The drill: build and run — the status line
should read "Chirpy Engine 0.30.0 (Swift)" and
name "the completions" among the features. Then
flex-test.html — all fourteen promises, 12–14
being the new ones (align-content spreading the
lines in a 300-tall bar; wrap-reverse stacking
from the bottom; a 50% bar inside a
300-declaring wrapper). Then grid-test.html —
all thirteen promises, 9–13 being the new ones
(column flow reading down then across; the small
box backfilled into the first row's hole under
dense; placement by line names; the
template-areas map; a 50% grid inside a
300-declaring wrapper). Then finishing2-test.html
— promise 9 is the inset shadows (a pressed-in
card, and a card carrying an outer shadow and an
inset ring from one list) and promise 10 is
steps() (a hover warming in four jumps; a card
toggling rather than fading) — 10 needs Tyler's
eyes, as all motion does. Regression passes:
banding-test.html and shield-test.html end to
end, then the home page.

WHAT'S NEW IN 0.29.0 — THE BANDING REPAIR
------------------------------------------------------
A defect repair, proven before it was patched. Two
sightings stood open: the hub's hero photograph
painting in horizontal strips (Tyler's screenshot,
Nov 4, Chirpy 0.27), each strip restarting the
picture; and the finishing test's promise 7 — thin
pale strips behind the odd list items, clipped to
the lower half of the line (the Oct 23 drill) —
which 0.23.1 honestly left unfixed for want of a
provable mechanism. They are one defect, and the
mechanism is now proven, not suspected:

A surface's paint depended on which paragraphs the
current draw was asked for. The surface painter
(paintContinuousSurfaces) reckoned an element's
background — which of its paragraphs merge into
one surface, and the one rect its photo and
gradient layers anchor to — from only the
paragraphs inside the draw's glyph range. But
AppKit repaints in slices: a scroll exposes a
strip at a time, and the state and motion
machinery invalidates single elements' ranges.
A draw covering part of a surface computed the
run from that part and anchored the layers to the
part's rect — cover sizing, position and tiling
all resolved against the slice. Slice by slice,
the same photograph was laid down at different
scales and anchors; where slices met, the
picture restarted. The screenshot proves it
numerically: measured against the hub banner's
own photograph (1920x823, cover, center 40%),
successive horizontal stretches of Tyler's
screenshot each follow ONE consistent mapping of
photo rows to screen rows, but the stretches'
mappings disagree with one another — and none of
them is the whole-surface mapping. There was no
one paint to blame; the patchwork was the paint.

The zebra strips are the same dependence in the
color fill: a draw whose range spans two shaded
items bridges their fill across the unshaded item
between them, as a full pass does — but clipped
to the draw's slice, so when a scroll's strip
began halfway down the unshaded item, only its
lower half received the bridged fill, and its
upper half, erased by that same repaint and
covered by no band in the draw's reckoning,
stayed bare. Which half wore the strip depended
on where the strip fell — which is why the
artifact was real, repeatable, and unprovable
from any single pass's code path.

The repair, at the cause, in the shared path:

* paintContinuousSurfaces now grows its band list
  outward to the WHOLE surface run before
  coalescing. The walk tests each neighbouring
  paragraph's band with the coalescing rule itself
  (surfaceCompatible and the same 64-point reach),
  so it extends a run exactly where a whole-range
  pass would merge and stops exactly where it
  would not; a paragraph carrying no surface
  spends only distance, measured on its own
  fragment span. Every draw that touches a run —
  full pass, scroll strip, single-element
  invalidation — now computes the same surfaces
  and the same anchor rects, and lays down exactly
  the pixels a full pass lays down; the graphics
  context still clips the paint to the region
  actually asked for. The per-paragraph band
  reckoning itself is unchanged, only lifted into
  a helper (surfaceBand) the walk and the loop
  share, so a band means the same thing in both.
  Shadows, transforms and opacity ride on bands
  and inherit the consistency.

* A block stamp's state layers (hover / focus /
  active, paintStateLayers) paint ONCE, into the
  union of the stamp's fragment rects, instead of
  re-anchoring at every line: a multi-line block's
  hover photo or gradient is one flow over the
  block's whole extent, margins bridged. An inline
  element's own state layers still paint per
  fragment — per-line anchoring is what CSS asks
  of an inline box's fragments, and those fragments
  are intrinsic to the element, not to the draw.

What provably does not change: a full-range draw
computes the same band list it always did (the
growth walk only adds what the range cut off),
so pages whose backgrounds painted correctly —
single surfaces, boxes, flex and grid seats,
columns, fixed overlays, all of which always
anchored to their own intrinsic rects — paint
the same pixels. Fill colors had no anchoring to
lose; the AppKit per-fragment color pass is
untouched. One honest residue: a repaint whose
glyph range covers ONLY bridged spacing inside a
surface, touching none of its paragraphs or
stamped separators, still paints nothing there —
glyph ranges are fragment-born, and a stamped
separator rides inside nearly every such gap, so
the case is a sliver of a sliver; it is named
rather than chased.

The drill (banding-test.html, in this folder):
1. Build and run. The status line reads "Chirpy
   Engine 0.29.0 (Swift)" and names the banding
   repair.
2. Drag banding-test.html onto the window. Five
   promises: (1) the hero's sunrise is ONE
   continuous picture — one sun, one cross, no
   seams; (2) scroll the hero away and back,
   slowly — the same unbroken picture, where the
   old paint returned it as restarted bands;
   (3) the zebra list: shaded items wear full
   unbroken bands, unshaded items wear nothing,
   on no part of any line; (4) scroll the list
   across the window's edge in strips — promise 3
   again, exactly; (5) rest the pointer on the
   last box: ONE gradient flowing over the whole
   box, not one per line.
3. The live witness: jesuslovestyler.com. Load
   it, scroll down and back up slowly, and look
   at the banner — one continuous photograph of
   the hills, as the page declares it.
4. Regression: shield-test.html — the Shield's
   six promises exactly as in 0.28; nothing about
   the fetcher moved.

WHAT'S NEW IN 0.28.0 — THE SHIELD
------------------------------------------------------
The release Tyler asked for on Nov 4, the evening
the CSS program finished: ad blocking built in,
privacy by default, and pornography and gambling
refused — not as a filter bolted onto the renderer,
but as a gate in the fetcher itself. Every request
this engine issues is built by one of its fetch
helpers, and each helper now asks the Shield first,
before any network I/O. The lists and the gate live
in ChirpyEngine.swift (TBShieldAdDomains,
TBShieldFamilyDomains, tbShieldCategory).

* The matching rule — one rule for both lists. A
  request is refused when its host IS a listed
  domain or sits under one: www.bet365.com is held
  by bet365.com, and tpc.googlesyndication.com by
  googlesyndication.com. Domains are stored bare —
  no scheme, no wildcards — and the lists are
  plainly commented Swift data, so they grow a line
  at a time.

* The ad shield — 299 domains, counted in the file.
  The majors: Google's ad and measurement hosts,
  the big exchanges and native networks, the
  analytics and session-replay services, the
  affiliate and attribution trackers, the pop and
  push networks, and the social platforms'
  advertising hosts. (The social sites themselves
  are NOT listed — facebook.com opens; facebook.net,
  its tracking arm, does not.) A refused picture
  or stylesheet simply never arrives — the picture
  keeps its label, the page renders without the
  sheet, the fallbacks a failed fetch has always
  taken. A refused page load becomes the block
  page, named for the ad shield. HONEST SCOPE:
  this is a curated starter shield, not the
  EasyList corpus — an ad served from a domain on
  nobody's list yet still loads.

* The family filter — 297 domains, counted in the
  file: 141 adult, 156 gambling. The major tube
  and studio and cam sites, the creator platforms,
  the drawn and written adult shelves; the big
  sportsbooks and casinos, offshore and crypto
  books, poker rooms, sweepstakes casinos, racing
  and lottery and bingo operators. It guards the
  side doors as well as the front: a subresource
  addressed to a listed host is refused exactly
  like an ad. ON BY DEFAULT, AND WITH NO OFF
  SWITCH — that is deliberate, and it is Tyler's
  standing word: the home page promises the filter
  is "on on purpose, not buried in a settings
  page," and a promise with a switch is a
  different promise. Extending the list is easy
  (a line of data); weakening it is not offered.

* The block page — generated inside the engine,
  like the home page, in Chirpy's voice. It names
  what stopped the load (the family filter, or the
  ad shield for advertising and tracking), shows
  the refused address, and says plainly that
  nothing was fetched — the refusal happened on
  this Mac before any request left it. There is no
  shaming in it. The way back is honest: this
  engine has no script to walk history from inside
  a page, so the page points to the window's own
  Back button, and links home; the verse it
  carries is the home page's own — Psalm 118:105,
  Douay-Rheims.

* Redirects — the navigation fetcher (the window's
  normal road, the one with the progress bar) asks
  the Shield about redirect targets too: a redirect
  to a listed host is not followed, and the block
  page answers instead. NAMED LIMIT: the plain
  helpers (the fallback page fetch, pictures,
  stylesheets) ride the shared session, whose
  redirects the system follows without asking the
  engine — so a redirect chain that starts on an
  allowed host and lands on a listed one through
  those doors is not re-checked. The address you
  ask for always is, on every door, and a meta
  refresh's target is asked for by name, so it is
  checked too.

* Privacy defaults, at the same layer.
  Cookies: the shared session's ordinary storage
  used to ride on EVERY request, third-party
  pictures included. Now a subresource request
  that crosses to another site — a picture, a
  background photo, a stylesheet whose host's
  registrable domain differs from the page's —
  carries no cookies in either direction: stored
  cookies are not sent with it, and any the reply
  tries to set are not kept. Same-site subresources
  are untouched, and page loads keep the ordinary
  behavior — a site you visit can still hold its
  own cookies; what ended is the trailing.
  Referer: Chirpy has never sent one on a page
  load and still does not. A cross-site subresource
  now sends the asking page's ORIGIN only —
  scheme and host, never its path; same-site
  subresources send none, as before.
  "Same site" is judged by registrable domain —
  the host's last two labels — an approximation,
  named: two-part public suffixes (co.uk and kin)
  read as the domain, which can only make two of
  their subdomains count as one site.
  Signals: every request the engine builds — page,
  post, picture, sheet — now carries Sec-GPC: 1
  and DNT: 1, the honest "do not sell or track"
  flags. They cost nothing and bind nobody; they
  are said out loud anyway.
  Telemetry: there is none, and none was added.
  Chirpy sends nothing about its reader anywhere,
  ever. Stated, not changed — there was nothing
  to change.

* The home page's promises were reworded to stay
  exactly true of this build: "No ads" became what
  is actually kept — an ad shield against the big
  ad and tracking networks, and a family filter
  against the big adult and gambling sites, both
  on on purpose. The verse is untouched.

The drill (shield-test.html, in this folder):
1. Build and run. The status line reads "Chirpy
   Engine 0.28.0 (Swift)" and names the shield.
2. Drag shield-test.html onto the window. Six
   promises: (1) a picture addressed to a listed
   ad domain must NOT appear — its fallback label
   stands; (2) a picture from unlisted
   upload.wikimedia.org loads normally; (3) TAP —
   the bet365 link lands on the block page under
   the FAMILY FILTER's name; (4) TAP — the adult
   link, the family filter again; (5) TAP — the
   doubleclick link, the block page under the AD
   SHIELD's name; (6) a picture addressed to a
   listed adult domain must NOT appear.
3. The home page: its verse, its doors, and its
   promises — now kept by machinery, not just
   words.
4. One real site with heavy advertising: the page
   itself intact, its listed-network ads missing.
What this drill cannot prove, said plainly: the
cookie and Referer dressing leaves no mark a page
can show. The page-load signals can be seen at an
echo page (https://httpbin.org/headers shows
Sec-GPC and DNT among the headers Chirpy sent);
the subresource dressing would need a reflecting
image endpoint to witness, and is described here,
not claimed as proven.

WHAT'S NEW IN 0.27.0 — PAINT & MOTION
------------------------------------------------------
The fourth and final stage of the remaining-CSS
program: how surfaces cast shadows, how paint
itself moves — and, with it, the end of the CSS
roadmap. After this build the engine header's
"Not yet" holds only JavaScript.

* box-shadow — DONE, outer shadows. Offset,
  blur, spread and color; several shadows on one
  box, first-listed on top as CSS paints them.
  Each shadow is its shape filled under its own
  blur, clipped to everywhere except the box it
  belongs to, so a shadow never shows through its
  own box's face. Shadows ride block surfaces and
  painted boxes alike — floats, positioned boxes,
  flex and grid items and their containers,
  multicolumn blocks, fixed overlays. Inset
  shadows are NOT read — named out, not faked.
* text-shadow — DONE. Offset, blur and color,
  inherited as CSS inherits it, drawn under the
  glyphs in every text paint path: the main text,
  floated and positioned boxes, flex and grid item
  contents, column and spanner contents, fixed
  overlays. A held (sticky) element's above-pass
  does not re-draw its text shadows — its glyphs
  ride above, the shadows stay with the ordinary
  pass, the same bracket the sticky set already
  keeps for photo bands.
* State background layers — DONE. Since 0.23 a
  state (hover, and since 0.26 focus and active)
  could change colors; now a state's background
  photo and gradient layers paint too, through the
  same layer painter the resting background uses,
  and lift exactly when the state lifts, restoring
  the covered paint as the colors always have.
* column-span: all — DONE. A multicolumn block is
  cut at its spanning children: the content before
  a spanner balances into columns, the spanner
  paints across the full width, and the content
  after resumes in fresh columns below — as many
  segments as the page declares, each balanced on
  its own. The spanner's own contents paint like
  any column content, nested containers included.
* text-overflow: ellipsis — DONE, engine-side.
  A block that is nowrap, clips its overflow
  (hidden, clip, scroll or auto) and declares
  text-overflow: ellipsis has an over-long line
  shortened at flush time to the widest prefix
  that fits with "…" at the content edge. Honest
  cost, stated on the test page too: the text
  itself is shortened, so selecting or copying the
  line yields the shortened line. Lines inside
  floated boxes keep their clipping instead — the
  float's own width governs there.
* transform — DONE, paint-time only. The 2D
  functions (translate, translateX/Y, scale,
  scaleX/Y, rotate, skewX/Y, matrix) resolve to
  one affine at paint; transform-origin is
  honored (default 50% 50%). A transformed
  element's backgrounds, layers, shadows and
  glyphs move together — block surfaces, painted
  boxes, flex and grid items and containers,
  multicolumn blocks, fixed overlays, and inline
  elements' own fills and glyphs. Flow positions
  never move; nested transforms compose where the
  paint paths nest (a transformed item inside a
  transformed container). Named outs: link
  hit-testing stays at flow positions inside
  transformed paint; a transformed element's
  floated children do not inherit its transform
  (the float seats are resolved outside its paint
  wrap); an inline element's transform moves its
  own paint only, never an ancestor's surface.
* opacity — DONE as a paint trait: a block's or
  box's whole paint (surface, contents, shadows)
  takes its alpha, and it is the trait transitions
  and keyframes animate.
* transition — DONE, for paint traits only:
  color, background-color, border-color (on
  painted boxes), opacity and transform, with
  duration, delay and the timing functions
  (linear, ease, ease-in, ease-out, ease-in-out,
  and cubic-bezier() itself; steps() is read as
  ease — the one approximation, named). Triggered
  by the state changes the engine already tracks:
  when a state starts or stops wearing a trait,
  the trait travels between what the page showed
  and what it should show, from the value on
  screen — an interrupted transition hands its
  current value to the next. The shorthand and
  the longhands are both read.
* @keyframes — DONE, for the same paint traits.
  Named rules with percentage, from and to stops
  (a trait a stop omits reads from the element's
  resting paint); animation-name, duration,
  delay, iteration-count (infinite included) and
  direction (normal, reverse, alternate,
  alternate-reverse) are read; timing functions
  apply across the whole cycle. A finished run
  puts its resting paint back exactly. Animation
  fill modes are NOT read — a finished animation
  returns to rest, as above.
* The motion discipline: ONE timer, created only
  while something is actually animating and
  invalidated by its own tick the moment nothing
  remains — a page with no motion has no timer and
  spends no cycles. Each tick repaints only the
  animated elements' own ranges, and a hidden
  window's animations simply wait. Colors are
  blended in sRGB; transform interpolation is
  component-wise between resolved matrices, not a
  decomposition — honest arithmetic, named.
* prefers-reduced-motion — WIRED THROUGH. With
  Reduce Motion on, the engine stamps no
  animation, transitions land instantly instead of
  travelling, and nothing moves: the stillness is
  the feature working.
* Named out, plainly: animating anything that
  moves layout (width, height, font size, margins
  — text would have to reflow per frame, and this
  engine does not pretend otherwise); animating
  paint inside painted boxes (a float's or flex
  item's CONTENTS rest while their box traits —
  the box's own opacity and transform — do
  animate); inset box-shadows.

The drill (finishing2-test.html, in this folder):
1 is a soft-shadowed card and a card with two
shadows at once; 2 is a text-shadow heading and
line; 3 is a hover card whose gradient layer
arrives on hover and lifts on exit; 4 is a
three-column article with a headline spanning all
of it mid-way, columns resuming below; 5 is the
nowrap ellipsis line in its narrow box; 6 is a
rotated badge, a scaled box and a translated box;
7 is a hover transition — color warming and a
26-point glide over ~0.4s; 8 is two keyframe runs,
an opacity pulse and an alternate-direction scale,
running on their own. The checks that need Tyler's
eyes: 7 and 8 entire (motion cannot be
screenshot-proven), and 3's arrival and lifting.

THE FINAL DRILL — this is the build to compile
------------------------------------------------------
0.27.0 is the stage Tyler builds: 0.24, 0.25 and
0.26 were pushed uncompiled, by the standing
workflow, so this one build carries all four
stages to his screen. In order:
1. Build and run. The status line should read
   "Chirpy Engine 0.27.0 (Swift)" and name
   shadows, transforms, transitions, animations
   among the features.
2. flex-test.html — the whole 0.24 flexbox drill
   (see its section below).
3. grid-test.html — the whole 0.25 grid drill.
4. interaction-test.html — the 0.26 drill above:
   the dressed form with its click-focus and
   press-and-hold checks, the focus and active
   links, the sticky bars (scroll them).
5. finishing-test.html — the 0.23 finishing set
   (font shorthand, media gates, structural
   selectors, hover colors) as a regression pass.
6. finishing2-test.html — the 0.27 drill above.
7. Regression passes: floats-test.html,
   positioning-test.html and multicolumn-test.html
   end to end, then the home page — its verse,
   its cards, and a scroll from top to bottom.
Anything that fails, fails on Tyler's screen
first — that report is the one that counts.

WHAT'S NEW IN 0.26.0 — THE INTERACTION SET
------------------------------------------------------
The third stage of the remaining-CSS program: the
states a page's elements wear while the reader is
touching them, and the position that sticks.

* Form controls dressed by the page — DONE. The
  live controls the view builds — text fields and
  submit / form buttons — now take their dress from
  the element's computed style instead of uniform
  defaults: the font, the text color, the
  background, the border (color and width) and the
  corner radius, with declared width and height
  honored as size hints. A field the page paints
  (background, border or radius declared) stands
  its native bezel down and wears the page's dress
  on its layer; a field the page leaves alone keeps
  the classic bezel it always had. A button wears
  its background as its bezel tint and its color as
  its label's; a button's CSS border and corner
  radius have no native dress to ride on and are
  not worn. Checkbox and radio glyphs take their
  element's color. Selects and textareas still
  render as their text — no live control is built
  for them yet — and a control inside a painted box
  (a float, a flex or grid item, a column) keeps
  the standing bracket-label degradation, as it has
  since those boxes arrived.
* :focus — DONE. :focus joins the selector grammar
  at :hover's standard: a state, never part of the
  resting cascade, resolved apart and reduced to
  the same four paint traits, stamped under its
  own keys. A press on a link gives it the focus,
  as in a real browser, and its :focus paint
  (color, background, underline family) is worn
  while the focus rests there — pressing elsewhere,
  or a live control taking focus, lifts it. A live
  control wears its :focus dress itself: the focus
  background or border takes the field's place, and
  an outline the page declares rides as the
  control's border ring for the focus's duration
  (a button wears its :focus background — or, lacking
  one, its :focus border color — as its tint, the
  closest honest dress a native button has).
* :active — DONE, the same way: a third state
  layer, worn while the pointer is pressed on the
  element and lifted on release. The three layers
  stack hover under focus under active over one
  snapshot of the covered paint, so any combination
  restores exactly. A pressed button wears its
  :active colors for the press.
* position: sticky — DONE. A sticky block flows
  and reserves its space like a relative box; the
  renderer records its range and its containing
  block's, and the view shifts its paint as the
  page scrolls, in the fixed overlays' update
  discipline: with top: T it holds at T once
  scrolling would carry it above, until its
  containing block's bottom edge pushes it off;
  bottom: B mirrors that from below (top wins when
  both are declared). The shift rides the relative
  offsets' paint path, so surfaces and glyphs move
  together and the flow never does, and a held
  element paints above the words scrolling under
  it, as a positioned box does. Horizontal sticking
  is not read (the page does not scroll sideways);
  a sticky inside a painted box flows plain; a
  sticky flex, grid or column container's seat
  shifts while its items paint at the flow seat;
  a form control seated in a sticky element keeps
  its flow seat, as it does inside a relative
  offset; and a held element's photo or gradient
  band is not re-painted in the above-pass — its
  color band and glyphs ride above, the richer
  layers stay where the ordinary pass drew them.
* Cascade — :focus and :active sit in the matcher
  exactly where :hover sits (each also adds its
  ten points of specificity); position: sticky is
  read beside positionKind's family in walkBlock
  and never answers there, so no child is ever
  lifted out of flow by it.

The drill (interaction-test.html, in this folder):
1 is a form dressed by its page — dark fields, gold
borders, a styled submit — with a gold checkbox
glyph, and it asks for your hands twice: click into
a field and watch the :focus dress and the declared
outline arrive, and press-and-hold the submit and
watch its gold deepen while the press lasts; 2 is a
link whose :focus dress shows while a press rests
on it; 3 is a link whose :active dress deepens a
press-and-hold; 4 is a sticky bar that holds at the
top through its section and is pushed away at the
section's end; 5 is a bottom-sticky bar that rides
the window's bottom until its seat arrives; 6
names what is not on the page. The checks that need
Tyler's hands: the click-focus and the submit
press-and-hold (1), the link press-and-holds
(2, 3), and the scrolling (4, 5).

Still not built, named plainly: transforms,
column-span, transitions and keyframes, JavaScript
(the mountain) — and, from this stage, live select
and textarea controls. After 0.26 comes 0.27, the
paint and motion finishing set, and then Tyler
builds.

WHAT'S NEW IN 0.25.0 — GRID
------------------------------------------------------
The second stage of the remaining-CSS program: the
other layout system modern pages are built with. An
element styled display:grid no longer falls back to
plain block stacking — it lays its children out in
rows and columns at once. Grid is built the way flex
was in 0.24, on the same machinery: each element
child is sub-rendered as an item in a renderer of
its own (the floated box's arrangement), each run of
text and inline children becomes one anonymous item,
the container takes its place in the flow as a
single clear seat carrying its spec as an
attributed-string key, the view paints the items at
the seat, and the finalize passes re-lay the grid
out at its true width recursively — nested grids,
grid-inside-flex, and flex-inside-grid all travel
the shared paths, as flex containers do.

* Tracks — DONE. grid-template-columns and
  grid-template-rows take lengths, percentages,
  fr shares, minmax() with fixed or fr bounds,
  auto (content), and repeat() — a fixed count, or
  auto-fill / auto-fit, which count how many tracks
  of the repeated minimum fit the container's real
  size (an auto-fit row axis needs a definite
  height to count against, else the repeat stands
  once; auto-fit tracks no item lands in collapse
  afterward, as the spec directs). The grid-template
  shorthand's rows / columns form is read too.
  Named lines are parsed past; grid-template-areas
  strings are parsed past, not placed by.
* Track sizing — in the spec's spirit. Fixed tracks
  stand at their lengths; percentages resolve
  against the container's real content width (rows:
  against its declared height when it has one, and
  read as content otherwise); content tracks stand
  at the largest item in them, measured the way flex
  measures — unwrapped for the natural size, at a
  sliver for the minimum; an item spanning several
  tracks shares its excess across the spanned
  tracks free to grow; fr tracks then divide what
  is left, never below their minimums, with minmax
  clamps honored during the growth. fr rows under
  an indefinite height size to their content.
* Placement — DONE. grid-column / grid-row with
  line numbers (negative lines count back from the
  explicit grid) and spans, the four
  grid-column-start/end and grid-row-start/end
  longhands, and grid-area in its line-number form.
  Items without a definite place are auto-placed in
  row flow by a sparse cursor that wraps at the
  column count and steps around placed items, spans
  included; items locked to a row scan that row for
  their first free run. Definite placements past
  the template grow implicit content tracks.
* Alignment — DONE. justify-items / align-items
  and the per-item justify-self / align-self:
  stretch (the default — an item fills its area)
  or start / end / center within the area.
  justify-content / align-content distribute a
  track set smaller than its container (start, end,
  center, space-between, space-around). Baseline
  reads as start.
* Gap — DONE. gap, row-gap, and column-gap (and
  the grid- prefixed spellings) stand between
  tracks only, never at the edges, exactly like
  flex's.

Not yet in grid, named plainly: grid-auto-flow:
column (its pages get row flow); dense packing —
the cursor never backs up into a hole it has
passed; placement by line name or by
grid-template-areas; a grid container's percentage
height, there being no definite height above a flow
block to resolve it against. Grid items are paint,
not live text — the standing bargain since 0.17.

The drill: open grid-test.html (drag it onto the
window). Eight numbered promises: fr shares in a
three-column row; a minmax auto-fill gallery that
gains a second row; explicit placement — a banner
spanning two columns, a tall box spanning two
rows, auto items filling under them; auto-placement
flowing around a planted item; gaps only between
tracks; stretch filling a cell against a centered
island; a grid nested inside a grid item; and
percentage columns with fr rows splitting a
declared height. The status line reads Chirpy
Engine 0.25.0.

WHAT'S NEW IN 0.24.0 — FLEXBOX
------------------------------------------------------
The first stage of the remaining-CSS program Tyler
authorized whole on Nov 4: the layout system most
modern pages are built with. Until now an element
styled display:flex or display:grid fell back to
plain block stacking — readable, but every row piled
into a column. Grid keeps that fallback for one more
stage (it is 0.25); flex is real now.

* Flexbox — DONE. A block with display:flex (or
  inline-flex, treated the same) hands its children
  to the flex layout, built the way this engine
  builds every out-of-flow construct: each element
  child is sub-rendered as an item in a renderer of
  its own — the floated box's arrangement — each run
  of text and inline children becomes one anonymous
  item, as the spec requires, the items are laid out
  by the renderer, and the container takes its place
  in the flow as a single clear seat, like a
  multicolumn block, while the view paints the items
  into the seat's line. Read whole: flex-direction
  in all four spellings (the reverses mirror the
  laid-out boxes in the container's main extent, so
  row-reverse truly packs from the right);
  flex-wrap: wrap; justify-content in its six
  distributions (flex-start, flex-end, center,
  space-between, space-around, space-evenly);
  align-items and align-self (stretch, flex-start,
  flex-end, center, baseline); row-gap, column-gap
  and the gap shorthand; order; and the item
  properties flex-grow, flex-shrink, flex-basis and
  the flex shorthand in its standard spellings.
  The layout runs the spec's own shape: base sizes
  (basis, else the main-size property, else the
  contents) clamped to hypothetical sizes; lines
  collected by them; flexible lengths resolved line
  by line — grow sharing free space by factor
  (factors summing under one share only that much
  of it), shrink taking overflow by shrink-times-
  base — with items freezing at their declared
  min/max clamps and at their contents' own size
  under shrink, as min-width:auto directs; cross
  sizes measured at the final main sizes; a lone
  line standing the container's whole cross size
  when the page declared one. Percentages resolve
  against the container's true content size in the
  layout pass, never against a nominal page — the
  0.23.1 float lesson, applied from the start.
  Declared sizes read as the whole box, the floated
  boxes' convention throughout this engine.
* Baseline — DONE, measured. Items aligned to the
  baseline share the line's deepest first baseline,
  each item's measured from its own layout — first
  line fragment, first glyph — the same calls the
  float anchors and column seats are resolved with.
* Nesting — DONE. An item that is itself
  display:flex sub-renders through the same
  machinery; its spec rides on its seat as an
  attribute wherever the painted contents carrying
  it travel, and the finalize corrects it to the
  width it truly stands in (the walk inside a
  painted box runs at the page's nominal width; the
  box's final width is the truth, and wins). A flex
  container inside a floated, positioned or column
  box works the same way. An absolutely positioned
  child of a flex container is no item — it
  registers with the positioned machinery as usual.
  Floated children simply itemize: CSS computes
  float away on a flex item. Past sixty items in
  one container, the rest flow into the last item.
* OUT, named: wrap-reverse (its pages get wrap —
  the reversed cross stacking is more than a seat
  in a text flow can honestly express yet);
  align-content (wrapped lines pack at the cross
  start); a flex container's percentage height
  (there is no definite height above a flow block
  to resolve it against); and grid, which is the
  next stage and keeps the block fallback until
  then. Items are paint, not live text — the
  floated box's bargain, struck again: the link
  cards on the test page show their colors but do
  not click.

The drill. Drag flex-test.html onto the window.
Eleven numbered promises: space-between sharing
the leftover into its two gaps; a growing middle
item taking every point of leftover between two
fixed boxes; three 300-point bases shrinking
evenly into a 480-wide row; five boxes wrapping
three-and-two; a column stacking its rows at full
width; one box centered on both axes of a
120-tall bar; 24-point gaps between items and
none at the edges; order re-sorting three boxes
against their file order; the link cards — a
nested flex row of three equal cards, each a
column flex container itself; row-reverse packing
from the right; and two unlike font sizes sharing
one baseline, their boxes' tops staggered to make
it so.

WHAT'S NEW IN 0.23.0 — THE FINISHING SET
------------------------------------------------------
The last stage of the CSS completion: the shorthand, the
media queries, and the pseudo-classes the engine has
honestly listed as not read since the beginning. This is
also the first build compiled from a stack of four — 0.20
through 0.23 were written back to back — so the drill
below is the full one, and it matters end to end.

* font: shorthand — DONE. The shorthand is read whole:
  style, variant, weight and stretch in any order before
  the required size, an optional /line-height, then the
  family list. It expands into its longhands at exactly
  its own place in the cascade, and components the author
  did not mention reset to normal — that reset is the
  shorthand's defining behavior, and the test page proves
  it (a slant the shorthand never mentions does not
  survive it). A font: whose value arrives through var()
  expands after substitution instead, filling only the
  components no rule set outright. font-family, which the
  shorthand needs to mean anything, is honored on its
  own now too: the first family in the list that resolves
  on this Mac wins, and the generic families map to the
  platform faces CSS expects (serif to a Times,
  sans-serif to a Helvetica, monospace to Menlo).
  font-variant paints small-caps.
  OUT, named: the system-font keywords (font: menu,
  caption, and kin) are read and set aside — this engine
  maps none of them; font-stretch is parsed and carried
  and nothing applies it.
* @media — DONE. More than prefers-color-scheme now:
  min-width, max-width and width are answered against
  the width of the window's text area as the load began
  (resize, then reload, to ask again); prefers-reduced-
  motion is answered from the system's own accessibility
  setting; hover and pointer are answered as the
  constants they are on a Mac — a pointer that can
  hover, and a fine one. Media types other than screen
  and all never match, a query that cannot be read never
  matches, and an unknown feature answers false, which
  keeps its block out — the behavior unknown features
  have always had here. Nested @media is not evaluated.
  A leak is fixed along the way: before this build, the
  second and later rules inside any @media block slipped
  into the plain cascade whatever the query said; now a
  sheet's media rules reach the cascade only through
  their query. prefers-color-scheme works exactly as
  before.
* Structural pseudo-classes — DONE. :first-child,
  :last-child, :nth-child() and :nth-of-type() in every
  An+B spelling (odd, even, a bare index, -n+3, 3n-2),
  :first-of-type, :last-of-type, :not() around a single
  compound (no combinators, no nested :not), and :empty
  in the Selectors 4 sense — no element children and no
  text but whitespace. All are read at match time,
  against the element's real place among its siblings.
* :link and :visited — DONE. A page's anchors divide by
  this window's session: the URLs it has landed on. A
  link to a page this window has opened wears :visited;
  the rest wear :link. The set lives in memory only —
  nothing is written down, nothing survives a relaunch,
  and there is no history for any site to probe beyond
  the colors it can already paint.
* :hover — DONE, as paint, never layout. The renderer
  resolves each element's :hover rules exactly as it
  resolves its resting style, reduces them to the traits
  that can be repainted without moving a glyph — color,
  background color, the underline and strikethrough
  switches (`none` included: a hover may take a link's
  underline away) — and stamps them onto the element's
  text, with the enclosing block's stamp beneath. The
  view watches the pointer; while it rests on stamped
  text, those characters wear the hover paint, and when
  it moves on, the original paint is restored exactly.
  A hover rule that changes a font or a size is read and
  set aside: restyling must never move the text.
  OUT, named: :focus and :active are not read (an
  engine that paints its pages and overlays its form
  controls has no honest focus paint to offer yet), and
  a hover background's photo or gradient layers are not
  painted — its color is.

The drill. Drag finishing-test.html onto the window.
Ten numbered promises: the shorthand whole and as twins
with the longhands; the shorthand's reset; a font: sent
through var(); family and small-caps on their own; the
width gate (resize and reload); the system's color
scheme and Reduce Motion answers; the list under its
structural rules; :not() and :empty; the two session
links — open one, come back, and it wears visited
purple; and the hover card and link, which must repaint
under the pointer and restore when it leaves, without
anything moving.

0.23.0 build fix (Nov 4): Tyler's first compile of the
0.20–0.23 stack stopped on four errors in
ContentView.swift, all in the finishing set's own new
wiring, and all fixed at their cause. refreshInsets
and refreshAfterArrivals are now @MainActor, like
rebuildFormViews already was — so the width write and
the arrivals re-install legally touch the model; the
frame-change observer reaches refreshInsets through
the same Task { @MainActor in } hop the fetch progress
uses. And the hover hit test no longer calls an
NSLayoutManager character-index label that does not
exist: it asks the text view itself,
characterIndexForInsertion(at:), with the old
above/left-of-the-text guard restated in view
coordinates. Nothing else changed; the three yellow
warnings his build showed are warnings, not errors,
and were left alone.

0.23.0 build fix 2 (Nov 4): the rebuild cleared
ContentView entirely and stopped on one last error,
this time in the engine — in the 0.22 multi-column
seat code, a NSMutableAttributedString was built from
another attributed string without its argument label.
The call now reads NSMutableAttributedString(
attributedString: NSAttributedString(attachment:
seat)), and every other attributed-string and
text-storage construction in both files was swept and
verified to carry a label that exists. The mistake
sat in code written for 0.22 that was never compiled
until this build, and no static check — balance,
header scan, grep — can see a missing argument label;
only the first real compile could, and did.

0.23.1 repair (Nov 4): Tyler's drill of 0.23.0
verified the whole stack running and found three
faults, all repaired here at their causes.

(1) Multi-column text never painted — the rules and
the colored block showed, but the words inside every
column block were invisible (floated and fixed boxes'
words had the same disease). The painted-layout
caches kept each layout's manager and containers but
not its text storage; a layout manager holds its
storage only weakly, so the storage died with the
call that built it and every repaint found a manager
with no text behind it. The caches — columns',
floats', and the fixed overlays' — now keep the
storage itself.

(2) Floats-test promise 3: the two 44% columns in
the padded wrapper came out near 47% each, and the
paragraph after the wrapper squeezed into the crack
between them instead of starting below the yellow.
Two causes. A percentage width was settled against
a flat thousand points rather than the containing
block; it is now kept raw on the float spec and
resolved by the view against the real column width
less the containing block's horizontal padding (the
renderer records that padding, as points are
points), with the box's height re-measured at the
resolved width — the division of labor a positioned
box's percentage insets already used. And the
wrapper's containment clear never counted the
wrapper's own floats: a wrapper whose only children
are floats anchors them at the clear's own index,
which the view's range check read as outside the
wrapper. The bound is inclusive now.

(3) A Metal debug-validation assert under the
debugger (instanceCount 0): a zero-size draw
reaching the GPU. Every paint path the 0.20–0.23
work added now refuses to issue one: surface bands
of no height are skipped; background rect arrays
drop rects with no area (an empty paragraph's run
is the case in point); box fills and photo draws
require a rect with area; background layers guard
once for all callers; a failed picture's frame is
not stroked into a content rect of a point or less;
column rules of no height are not drawn.

Not fixed, honestly noted: on finishing-test
promise 7, thin pale strips still paint behind the
odd list items, clipped to the lower half of the
line. Odd items declare no background at all (the
page's own text says so), so the strips are stray
paint from the shared band painter — but they are
not a zero-size draw, and no cause could be proven
from the code alone; they are left for a
screenshot-guided look rather than a guess.

WHAT'S NEW IN 0.22.0 — MULTI-COLUMN & COLOR-MIX
------------------------------------------------------
Stage two of the CSS completion: the column properties
and the color function the engine has honestly listed
as not read since the beginning.

* Multi-column. A block declaring column-count or
  column-width (or the columns shorthand — a count, a
  width, or both) lays its contents out in columns.
  The mechanism is the one this architecture already
  trusts for floated boxes: the block's contents are
  sub-rendered on their own, then laid out across as
  many text containers as the block has columns, and
  painted into a space the flow reserves for them — a
  clear-seat paragraph exactly as wide and as tall as
  the columns. The balancing is real: the height is
  binary-searched, with the layout manager's own
  chaining (down one column, continuing at the top of
  the next) as the test, until the content just fills
  the columns — so the columns end even with each
  other the way CSS balances them, and the number the
  seat reserves is the number the paint needs. A
  declared width derives its count by the spec's
  formula (as many as fit, gaps between; a declared
  count alongside only lowers it); column-gap takes a
  length or `normal`, the spec's word for 1em; a
  column narrower than 60 points sheds columns until
  each can hold text. column-rule is read — shorthand
  or longhands, width/style/color in any order — and
  painted in the gaps: solid styles fill (double,
  groove, ridge, inset and outset paint solid too; a
  rule a point or three wide has no bevel to show),
  dotted and dashed stroke a dashed line. Pictures
  inside a column block arrive in the arrivals act
  like a floated box's: the contents are cleaned and
  the columns re-balanced, and the seat in the page is
  corrected to the final height.
* color-mix(). color-mix(in srgb, …) is now read
  anywhere a color is — text, backgrounds, rules,
  gradient stops (the stop reader now finds the
  paren that balances, so a mix may nest inside a
  mix) — and because var() substitution is textual
  and runs first, a mix may arrive whole from a
  custom property. The mixing is the spec's:
  percentages default (both omitted — 50/50; one
  omitted — 100 minus the other), proportions rule
  the hue, a sum under 100 scales the result's alpha,
  and the channels mix in premultiplied-alpha form
  and divide back out, so a fade toward transparent
  does not darken through a gray it never declared.

Honest limits, plainly. A multicolumn block's
contents are paint, not live text — the floated
box's bargain since 0.17: links inside show their
colors but do not click, form controls stand as
bracketed labels, and the words cannot be selected.
column-span is not read — a child asking to span
all columns flows inside one column like everything
else in the block. The break properties (break-
inside and friends) are not read, and column-fill
is always balance. A block whose columns resolve to
one column simply flows as it always did — the
bargain is not struck for nothing. Columns are laid
at the page column's width, as every measured box in
this engine is; a window narrower than the column
shows them at that measure, the floats' own
approximation. Nested multicolumn — a column block
inside another painted box — flows uncolumned.
color-mix reads the srgb space only: another space
named in the value (lab, oklab, srgb-linear…) makes
the color unreadable rather than approximated under
its name, and relative-color syntax is not read.

The drill. Drag multicolumn-test.html onto the
window: (1) the numbered sentences read down the
first column, continue at the top of the second,
then the third, the columns ending even, a dark red
rule standing in each gap, the next paragraph full
width below; (2) the width-declared block stands in
four columns of a width, dotted rules in the gaps;
(3) the shorthand's two columns hold both paragraphs
between them; (4) the green stands behind all three
columns as one surface; (5) the swatches wear the
colors their labels promise — purple, blue-violet,
middle gray, orange, pale lavender, a gradient from
a mix to a mix, the variable's muted navy, a heading
in mixed gray; (6) the spanning heading stays inside
its column, as the page honestly says it will.
floats-test.html and positioning-test.html should
look exactly as they did. en.wikipedia.org/wiki/Cat
should load as before — except that its references
list, which Wikipedia declares in columns, may now
stand in columns near the bottom: that is the
feature working, not a break. The hub is unchanged.

WHAT'S NEW IN 0.21.0 — POSITIONED LAYOUT
------------------------------------------------------
The CSS completion Tyler called for starts here: the
two position modes the engine has honestly listed as
not read since floats landed in 0.17.

* position:absolute. The box leaves the flow
  completely — no exclusion path, no wrapping; the
  text beneath it never knows it exists, and it paints
  over the page. Its containing block is the nearest
  ancestor with a position of its own (a relative card
  or wrapper — the renderer now tracks those ranges as
  it walks), or the page column itself when there is
  none. Offsets top/right/bottom/left take lengths or
  percentages — across against the containing block's
  width, down against its painted height where it has
  one (an ancestor's surface), against the laid-out
  text height for the page itself. Declared width and
  height win; left and right together derive the
  width (top and bottom the height); anything left
  open is measured from the box's contents, the way a
  block float is measured, by a sub-renderer.
* position:fixed. The box is seated against the
  window instead of the page, so it must stay while
  the page scrolls beneath it — and in this engine
  that means a real overlay view, the way form
  controls are real views. The coordinator creates one
  view per fixed box, paints its backgrounds and its
  rendered contents into it (blocked-out text, links
  shown as bracketed labels, pictures when they
  arrive), and reseats it against the visible area on
  every scroll, resize and rebuild. Percentages are of
  the viewport.
* z-index. An integer z-index orders the positioned
  boxes where they overlap, document order breaking
  ties. Boxes at zero or above paint after the text
  itself, so a badge truly covers the card it hangs
  off. A negative z-index paints in the background
  pass — above the page's background surfaces but
  below its floats and words; real CSS stacks such a
  box behind its own containing block's background,
  interleaved element by element, and this engine's
  one background pass cannot do that interleaving
  honestly, so the approximation is named here rather
  than hidden. Fixed overlays are real views, so they
  sit above every in-document box rather than
  interleaving with them by z-index across the two
  kinds.

Staging follows 0.20's two acts. A positioned box
whose size is declared takes its place at first paint
— its backgrounds paint from the first moment and its
words join at arrivals, when its contents are
measured and cleaned; a box whose size must be
measured from its contents takes its place at
arrivals, like a block float. Fixed overlays appear
on the same terms. And the generation guard covers
them exactly as it covers floats and form views: a
superseded page's overlays are torn down with it and
never leak into the next page.

Honest limits, plainly. position:sticky is still not
read, and neither are transforms. A positioned box
never moves any other box — that is the specification,
not a shortcut. Positioned elements are lifted only
when the walk meets them as block-level children, the
same rule floats live by: one buried inside a run of
inline text flows as text, and one inside a floated
box flows inside that box. A relative element that is
purely inline — a span inside a sentence — establishes
no tracked containing block, so an absolute descendant
resolves against the next block ancestor out, or the
page. Where an inset is left auto, the fallback is the
static position approximated: the containing block's
edge across, the line where the box would have flowed
down. A fixed box whose height is not declared is
measured at the column's width, so if its true
inset-derived width is very different its text may
re-wrap when the overlay draws it. Printing a fixed
box on every page is out — there is no printing yet
to repeat it in.

WHAT'S NEW IN 0.20.0 — FIRST PAINT, AND BATCHED FLOATS
------------------------------------------------------
Living with 0.19 made the remaining problem plain: a
page showed nothing at all until its very last picture
had arrived and every float had been resolved — one
Wikipedia article sat loading for minutes while the
window showed the previous page. Two changes:

* First paint. The page is handed to the window the
  moment it has been walked — all of its text, its
  links live, ready to read and scroll — while its
  pictures are still fetching. A picture whose size the
  page declares (most do) has its box reserved at that
  exact size from the start, so when the picture lands
  it fills its box without moving a single word. The
  progress bar settles at first paint, because the page
  is readable then; while pieces are still arriving the
  status line says so ("pictures still arriving"), and
  when the last one lands the finished page is quietly
  re-installed behind the reader — final picture sizes,
  labels on the ones that failed — and the floats are
  resolved once more against the finished geometry.
* Batched float layout. Resolving the floats used to
  cost one full layout of the whole text per float —
  dozens of passes on an article that floats every
  thumbnail. Now all the placements are computed
  together from the layout as it stands, applied
  together, and recomputed against the new layout until
  they stop moving: at most three passes, and the
  resting place they settle into is the same one the
  old way reached.

Honest limits, plainly. A block floated box (a sidebar
made of text, say) still gets its true size by being
measured after its own pictures land, so floated boxes
of that kind take their places at the arrivals moment,
not at first paint — floated pictures and the text
wrapping around them are there from the first moment.
A picture that declares no size can only reserve a
small standard box until it lands, so its text may
re-wrap once when its real size arrives. Typing in a
form is safe — words typed while pictures are still
arriving are carried across the re-install — but a
text selection made in those first moments is not.
And the walk itself is still one unbroken pass: on a
very heavy page the window can still hold still while
the text is being walked, just for much less of the
wait than before. The roadmap from here is Tyler's:
CSS finished first (positioned layout next), then the
cache; JavaScript stays off the plan unless he calls
it back.

WHAT'S NEW IN 0.19.0 — PARALLEL LOADING
---------------------------------------
The diagnosis after living with 0.18: pages felt slow
mostly because their pieces arrived in single file —
each stylesheet and picture paying its own full round
trip in turn. 0.19 fetches them side by side:

* Stylesheets. Every external stylesheet on a page is
  fetched at the same time instead of one after another.
  They still join the cascade in the order the page
  declares them — arrival order never decides which
  rules win — and a sheet that fails is skipped, exactly
  as before.
* Images, background photos, and floated pictures.
  These flew together before, but all at once; now at
  most six requests are in flight at any moment (the
  browsers' classic per-host number), each new one
  launching as another lands, and every result is
  collected before the page is laid out.
* Everything still travels through the one shared
  session, so connections are reused, and the progress
  bar behaves exactly as in 0.18 — the document's own
  download is its measured part; the rendering, parallel
  fetches and all, stays indeterminate. No blended
  percentage was invented for the pieces.

Honest limits, plainly: block floats still finish one
float at a time — each floated box's own pictures now
fetch in parallel inside it, but the boxes themselves
take their turns, because overlapping them would mean
reaching into several renderers' state at once. And
nothing yet paints until the page is whole: showing the
text before the pictures land (first paint), remembering
pages and pictures between visits (a cache), and
fetching pages ahead are all future steps, named here
so their absence is a plan, not a surprise.

WHAT'S NEW IN 0.18.0 — A PROGRESS BAR, AND DRAG-AND-DROP
--------------------------------------------------------
Two things asked for after living with 0.17:

* A loading bar. While a page is coming in, a thin bar
  sits directly under the address bar. The page's own
  download fills the first 70% of it with real numbers —
  bytes received against the length the server declared —
  so a slow page visibly creeps instead of looking frozen.
  When the server declares no length (a chunked reply),
  the bar is indeterminate: moving, but making no promise.
  Once the page is in, the engine still has to fetch its
  styles and pictures and lay it out; that part has no
  single honest fraction across its passes, so the bar
  stays indeterminate until the page settles, then
  disappears. A failed load clears it too, and starting
  a second page mid-load restarts it cleanly — the first
  fetch is cancelled and its late arrival ignored.
* Drag-and-drop. Drag an HTML file from Finder onto the
  browser window and it opens, the way Chrome opens one.
  Only the first file counts, and only .html/.htm — any
  other file is ignored, because the engine cannot
  render it honestly. Local files load through the same
  path as web pages (they are just fast, so the bar may
  only flash).

Honest limits, plainly: the byte count is of the data as
delivered to the engine, so on a compressed page the bar
can reach the top of its download band early and wait
there for the rest — the fraction is real, the pacing is
the server's. The bar reports the download and shows
activity while the page renders, but the rendering
itself still happens in one unbroken pass on the main
thread: a very heavy page can still hold the window
still while it is laid out. Splitting that work up is a
later step, not this one. Dragging text or web links
into the window is not handled — files only.

THE TEST DRILL — THE FINAL ONE (0.23)
--------------
This build is the first compile of a four-version stack
(0.20 first paint, 0.21 positioning, 0.22 columns and
color-mix, 0.23 the finishing set), so this drill is the
consolidated one: the four test pages in order, then a
real article, then the standing checks. Run it top to
bottom; each page's promises are printed on the page
itself.

1. Build and run. The home page's status line should
   read "Chirpy Engine 0.23.1 (Swift)" and end with
   "no JavaScript yet" — and after any page loads, the
   settled status line should carry the same version.
2. Drag floats-test.html (it rides along in this
   folder) onto the browser window. All six promises:
   a floated box in a paragraph with the text wrapping
   it — and below the box, the paragraph's last lines
   should resume the FULL width of the column; two
   floated columns inside a colored wrapper; a row of
   floated boxes that must pack and wrap; a
   right-floated box; a cleared heading that must start
   below its float; and one relatively shifted box.
   Let the page settle before judging: a screenshot
   taken mid-navigation grades the old page, not this
   one.
3. Drag positioning-test.html onto the window. Five
   promises: (1) a red badge hanging off the top-right
   corner of a yellow card, overlapping its edge, the
   card's text undisturbed; (2) a purple box pinned
   near the page's own top-left that scrolls AWAY as
   you read down — that is what makes it absolute and
   not fixed; (3) a green bar fixed to the top of the
   window that stays exactly there at every scroll
   position, spanning the full width though it declares
   no width; (4) two overlapping boxes in a pale stage
   where the TEAL one (z-index 2) covers the orange one
   (z-index 1) where they cross; (5) a blue box whose
   width is derived from left:40 and right:40 against
   its wrapper, pale showing on both sides.
4. Drag multicolumn-test.html onto the window. Six
   sections: balanced columns ending even with a rule
   in each gap; a width-declared block standing in as
   many columns as fit; the columns shorthand; a green
   surface behind all of a block's columns; the
   color-mix swatches running red-and-blue in their
   proportions (and the gradient bar wearing two mixed
   stops, and the swatch mixed from a var()); and the
   honest section — the column-span child flowing
   inside its column, because column-span is not read.
   Remember the bargain, printed on the page: words
   inside a column block are paint, not live text.
5. Drag finishing-test.html onto the window. Ten
   promises, in the 0.23 section above: the shorthand
   and its longhand twins; the shorthand's reset; the
   font: sent through var(); the width gate (narrow
   the window under 750 and RELOAD — the box turns
   pale red; widen and reload — pale blue returns);
   the system scheme and Reduce Motion boxes, each
   true to your own Mac's settings; the six-item list
   under its structural rules; the :not() highlight
   and the invisible empty paragraph; the two session
   links — open the floats link, come Back, and it
   alone wears visited purple; and the hover card and
   link, which repaint under the resting pointer and
   restore when it leaves, with nothing moving.
6. Open a heavy real page — en.wikipedia.org/wiki/Cat.
   The article's TEXT should be on screen and readable
   within moments — long before its pictures have all
   arrived — and the pictures should pop into their
   boxes as they land, the declared ones without moving
   the text around them. The bar should appear under
   the address bar as the article downloads, turn
   indeterminate while the page is walked, and VANISH
   at first paint; the status line should say
   "pictures still arriving" until the last one lands,
   then drop the note. The infobox should sit at the
   RIGHT with the article text wrapping around it, and
   any picture that fails along the way should end up
   wearing its "[Image: ...]" label rather than leaving
   a hole. Wikipedia's own absolutely positioned pieces
   should sit where they belong against their cards
   and columns, not stranded in a pile at the top of
   the document. And a new sight in 0.22: the article's
   reference list stands in narrow columns — that is
   the column machinery reading Wikipedia's own
   column-width, working as intended, not a break.
7. Open a form page — the search box at
   html.duckduckgo.com/html/ will do. The field and its
   button should sit in their places from the first
   moment and still be sitting there after the page's
   pictures land. If the connection is slow enough,
   start typing in the field while pieces are still
   arriving: your words should survive the pictures
   landing.
8. Start a slow page loading, then type a different
   address and press Return before it finishes. The bar
   should restart for the new page, and the first page
   must never appear — not its text at first paint, and
   not its pictures arriving late over the new page —
   and none of its fixed overlays (if it had any) may
   survive onto the new page either.
9. Open jesuslovestyler.com — the hub should look as it
   always has; nothing may slide or pile up.
10. On any real page that pins a bar or banner with
    position:fixed (many news and documentation sites
    do), scroll slowly: the pinned element should hold
    its place against the window while the article
    moves beneath it, and it should still be there,
    correctly sized, after the window is resized.

HOW TO RUN IT
-------------
1. These files arrive loose (no zip): keep them together
   in one folder, exactly as they came.
2. Open the folder and double-click "ChirpyBrowser.xcodeproj".
   Xcode opens the project.
3. Near the top of the Xcode window, the run destination
   should say "My Mac". If it doesn't, click the destination
   picker and choose "My Mac".
4. Press the triangle Run button (or Command-R).
   Xcode builds the app and the Chirpy Browser window opens
   on the Chirpy home page.
5. Type a real address — example.com, or your own
   jesuslovestyler.com — and press Return. Links carry a
   little number like [3]; click anywhere on the blue link
   text to follow it. Arrows go back and forward.

IF XCODE ASKS ABOUT SIGNING
---------------------------
The project is set to sign simply "to run locally", which
needs no Apple developer account. If Xcode still complains:
click the blue ChirpyBrowser icon at the top of the file
list, choose the "Signing & Capabilities" tab, tick
"Automatically manage signing", and pick your own Apple ID
(Personal Team). Then press Run again.

IF THERE ARE RED ERRORS
-----------------------
Don't wrestle them. Take a screenshot of the errors and show
Noki — she wrote every line and will fix the files from her
side, the same way you two work on Homework Turtle. Fixed
files will come back to swap in.

0.23.2 (Nov 4, 2026): the home-page verse is now Douay-Rheims — Psalm 118:105,
"Thy word is a lamp to my feet, and a light to my paths." — replacing the World
English Bible's Psalm 119:105, at Tyler's word (the Catholic browser quotes the
Catholic Bible). Version strings bumped throughout, so the status line reading
"Chirpy Engine 0.23.2" proves this build; the drill's step 1 expects 0.23.2.
