CHIRPY BROWSER — Xcode project
===============================
Chirpy Browser (formerly Turtle Browser) as a Mac app project:
our own engine, written from scratch in Swift. It fetches
pages itself, parses the HTML with its own parser, and paints
the page itself. No WebKit anywhere in it. Public domain
(Unlicense); the source lives in the Chirpy-Browser GitHub
repo (renamed from Turtle-Browser).

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
