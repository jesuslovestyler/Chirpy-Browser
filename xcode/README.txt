CHIRPY BROWSER — Xcode project
===============================
Chirpy Browser (formerly Turtle Browser) as a Mac app project:
our own engine, written from scratch in Swift. It fetches
pages itself, parses the HTML with its own parser, and paints
the page itself. No WebKit anywhere in it. Public domain
(Unlicense); the source lives in the Chirpy-Browser GitHub
repo (renamed from Turtle-Browser).

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
   "Chirpy Engine 0.19.0".
2. Open a heavy page — en.wikipedia.org/wiki/Cat — and
   compare with your memory of 0.18 on the same network:
   the article should arrive noticeably sooner, now that
   its styles and pictures no longer queue in single
   file. The bar should still appear under the address
   bar as the article downloads, move while it comes in,
   turn indeterminate while the page is laid out, and
   vanish when the page settles. The infobox should
   still sit at the RIGHT with the article text wrapping
   around it (the 0.17 check, unchanged), and any picture
   that fails along the way should show its
   "[Image: ...]" label rather than a hole — the page
   must still render whole.
3. Start a slow page loading, then type a different
   address and press Return before it finishes. The bar
   should restart for the new page, and the first page
   must never appear or disturb the new one's bar.
4. Drag floats-test.html (it rides along in this folder)
   from Finder onto the browser window. The test page
   should open: a floated box in a paragraph, two floated
   columns inside a colored wrapper, a row of floated
   boxes that must pack and wrap, a right-floated box, a
   cleared heading that must start below its float, and
   one relatively shifted box.
5. Open jesuslovestyler.com — the hub should look as it
   always has; nothing may slide or pile up.

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
