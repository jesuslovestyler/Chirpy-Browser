CHIRPY BROWSER — Xcode project
===============================
Chirpy Browser (formerly Turtle Browser) as a Mac app project:
our own engine, written from scratch in Swift. It fetches
pages itself, parses the HTML with its own parser, and paints
the page itself. No WebKit anywhere in it. Public domain
(Unlicense); the source lives in the Chirpy-Browser GitHub
repo (renamed from Turtle-Browser).

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

THE TEST DRILL
--------------
1. Build and run. The home page's status line should read
   "Chirpy Engine 0.21.0".
2. Drag positioning-test.html (it rides along in this
   folder) onto the browser window. Five promises:
   (1) a red badge hanging off the top-right corner of
   a yellow card, overlapping its edge, the card's text
   undisturbed; (2) a purple box pinned near the page's
   own top-left that scrolls AWAY as you read down —
   that is what makes it absolute and not fixed;
   (3) a green bar fixed to the top of the window that
   stays exactly there at every scroll position,
   spanning the full width though it declares no width;
   (4) two overlapping boxes in a pale stage where the
   TEAL one (z-index 2) covers the orange one
   (z-index 1) where they cross; (5) a blue box whose
   width is derived from left:40 and right:40 against
   its wrapper, pale showing on both sides.
3. Open a heavy page — en.wikipedia.org/wiki/Cat. The
   article's TEXT should be on screen and readable
   within moments — long before its pictures have all
   arrived — and the pictures should pop into their
   boxes as they land, the declared ones without moving
   the text around them. The whole page should also
   finish settling plainly sooner than it did under
   0.19 on the same network, now that the floats no
   longer cost a layout apiece. The bar should appear
   under the address bar as the article downloads, turn
   indeterminate while the page is walked, and VANISH
   at first paint; the status line should say
   "pictures still arriving" until the last one lands,
   then drop the note. The infobox should sit at the
   RIGHT with the article text wrapping around it (the
   0.17 check, unchanged), and any picture that fails
   along the way should end up wearing its
   "[Image: ...]" label rather than leaving a hole.
   New in 0.21: watch Wikipedia's own absolutely
   positioned pieces — the pieces the page lifts out of
   its flow — and check they sit where they belong
   against their cards and columns, not stranded in a
   pile at the top of the document.
4. Drag floats-test.html (it rides along in this folder)
   from Finder onto the browser window. All six
   promises must read exactly as they did under 0.19:
   a floated box in a paragraph with the text wrapping
   it, two floated columns inside a colored wrapper, a
   row of floated boxes that must pack and wrap, a
   right-floated box, a cleared heading that must start
   below its float, and one relatively shifted box.
5. Open a form page — the search box at
   html.duckduckgo.com/html/ will do. The field and its
   button should sit in their places from the first
   moment and still be sitting there after the page's
   pictures land. If the connection is slow enough,
   start typing in the field while pieces are still
   arriving: your words should survive the pictures
   landing.
6. Start a slow page loading, then type a different
   address and press Return before it finishes. The bar
   should restart for the new page, and the first page
   must never appear — not its text at first paint, and
   not its pictures arriving late over the new page —
   and none of its fixed overlays (if it had any) may
   survive onto the new page either.
7. Open jesuslovestyler.com — the hub should look as it
   always has; nothing may slide or pile up.
8. On any real page that pins a bar or banner with
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
