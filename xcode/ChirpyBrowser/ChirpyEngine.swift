//
//  ChirpyEngine.swift
//  Chirpy Browser — engine 0.39.6 (Swift)
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
//      the positioned machinery as usual. Items are
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
//      directs. Track sizing runs the
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
//      once — and, since 0.30, inset shadows inside
//      them as well); text-shadow rides
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
//      and cubic-bezier()) — and, since 0.30,
//      steps(), which moves in discrete jumps.
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
//    * The banding repair (0.29): a surface's paint
//      no longer depends on which paragraphs a draw
//      was asked for. The surface painter used to
//      reckon an element's background — which of its
//      paragraphs merge into one surface, and the
//      single rect its photo and gradient layers
//      anchor to — from only the paragraphs inside
//      the current draw's glyph range, so a repaint
//      of part of a surface (a scroll exposing a
//      strip at a time, a state or motion
//      invalidation) laid its layers down anchored
//      to the slice, and the slices disagreed: a
//      hero photo restarted at every repaint
//      boundary, and a bridged color fill could
//      cover half of an unbackgrounded paragraph
//      in one draw and leave the other half erased
//      in the next. The painter now grows its band
//      list outward to the whole surface run before
//      coalescing, measured by the coalescing rule
//      itself, so every draw computes the same
//      surfaces and the same anchors — the
//      graphics context still clips the paint to
//      the region asked for. A block stamp's state
//      (hover / focus / active) layers likewise
//      paint once, into the union of the stamp's
//      fragment rects, instead of re-anchoring at
//      every line.
//    * The small completions (0.30): the named outs
//      of 0.24, 0.25 and 0.27, emptied. Flex gains
//      align-content — the six distributions and
//      stretch, sharing a definite cross size's
//      leftover among wrapped lines — and a true
//      wrap-reverse, its cross axis flipped: lines
//      stack from the cross end, and alignment and
//      cross margins answer to the flipped axis.
//      Grid gains grid-auto-flow: column and dense
//      packing, line names in both templates, and
//      grid-template-areas placed by grid-area: a
//      name — an area that fills no rectangle, or a
//      name nothing answers, falls back to auto
//      placement, as the README says. A flex or grid
//      container's percentage height resolves against
//      the definite height of the block ancestor the
//      walk has open — declared in points, or itself
//      a resolved percentage — and reads as auto
//      where no ancestor declares one, and inside a
//      painted item, whose height is born in layout
//      after the walk, still. box-shadow's inset
//      shadows paint: the frame between the box and
//      its shrunk, shifted inner shape, clipped to
//      the box, above its background and below its
//      contents, on the same painters that carry the
//      outer kind, lists mixing the two kinds
//      freely. And steps() timing — step-start,
//      step-end and the jump terms with it — moves
//      transitions and keyframe runs in discrete
//      jumps, as written.
//    * Live select and textarea controls (0.31): a
//      <select> seats a real popup button and a
//      <textarea> a real multi-line editor, through
//      the same attachments, seats and value path
//      as the fields before them. A select's rows
//      gather in document order — the parser nests
//      a following <option> inside the one before
//      it, so the gathering flattens as it walks —
//      an <optgroup>'s label stands among them as
//      a disabled row, and the resting choice is
//      the last option carrying `selected`, else
//      the first (a `multiple` select's is its
//      first chosen one; picking several is not
//      built). A textarea's seed is its own text,
//      read raw by the parser the way <style> is,
//      so markup in a seed cannot bend the tree;
//      one leading newline is dropped, as HTML
//      directs. Both wear their element's resolved
//      style as far as AppKit honestly dresses
//      them, take real keyboard focus, and send
//      their current value with their form; inside
//      a painted box they keep the standing
//      bracket-label stand-in, the select wearing
//      its resting choice's label there.
//    * The cache (0.32): what Chirpy fetched is
//      kept on the reader's own disk, under the
//      app's caches folder, and served again while
//      the server's own freshness word allows —
//      Cache-Control's max-age first, then Expires,
//      then a tenth of the time since the page last
//      changed, bounded at a week. A stale entry
//      carrying an ETag or a Last-Modified is asked
//      about conditionally; a 304 answer renews the
//      entry and the kept body serves. no-store is
//      never written down, no-cache is kept but
//      always asked about again, and only 200 GET
//      replies are kept at all — under the
//      reader's cap (200 MB unless Settings
//      names another) with least-recently-used
//      eviction, and no
//      single reply over 25 MB. Pages come through
//      it (the progress fetcher included), and so do
//      sheets, scripts and pictures, through one
//      shared cached GET. The Shield is still asked
//      before every lookup: a listed host is never
//      served from the cache, and blocked content is
//      never stored, having never been fetched. The
//      window's bar carries a Clear cache button.
//      The cache is the only thing Chirpy keeps
//      between launches, and nothing about it is
//      reported anywhere.
//    * JavaScript, the first slice (0.33): the
//      mountain's first camp. The parser keeps
//      <script> as a raw-text element carrying
//      its attributes, and after the parse —
//      on the landed page, before the walk, so
//      script-written words are what paint —
//      every script runs in document order on
//      one shared page scope: inline code, and
//      external src files fetched the way style
//      sheets are, the Shield asked first and
//      the cache beneath. The interpreter is
//      ours from the ground — a lexer, a parser,
//      an evaluator — covering var, let and
//      const; numbers, strings and booleans;
//      arithmetic and comparison, with string
//      concatenation; if/else; for, while and
//      do-while; functions with parameters,
//      return, and closures; arrays and plain
//      objects with member and index access;
//      and a working set of string and array
//      helpers (length, charAt, indexOf, slice,
//      split, trim, the case folds, push, pop,
//      join, concat). The DOM bridge is small
//      and named: document.getElementById finds
//      an element by its id, and its textContent
//      and innerHTML read and write its words —
//      a write lands as text, because
//      script-written markup is not parsed in
//      this slice. document.title reads and
//      sets the page's title. console.log goes
//      to the window's status line, marked
//      "Console:", and window.alert rides the
//      same road as a note — there is no sheet.
//      A script's error stops that script alone
//      and is noted the same way; a name nobody
//      defined reads as undefined rather than
//      halting the page. NOT in this slice,
//      named plainly: event handlers and
//      attribute handlers (onclick and kin),
//      timers (setTimeout, setInterval), fetch
//      and XMLHttpRequest, script-driven
//      navigation, and the wider DOM — no
//      querySelector, no createElement, no
//      style access. The drill page js-test.html
//      promises each piece above, one numbered
//      promise at a time.
//    * The repair (0.34): three field failures
//      from the hub and the drill, each traced
//      to its mechanism before it was touched.
//      (1) JavaScript's parser read "return"
//      wrongly: its value test demanded the next
//      token be punctuation, so a return whose
//      value begins with a name, number or
//      string — above all a returned closure,
//      "return function() {...}" — was read as a
//      bare return, and the orphaned value was
//      parsed as a new statement and died. One
//      such line in a page's single script block
//      silenced every script on the page (the
//      js-test drill's eleven promises, proven
//      against this code off-device). The test
//      now asks only for ";" or "}" ahead. And a
//      script error now leads the window's
//      status line, right after the address,
//      instead of riding at the end of it where
//      the window's edge cut it out of sight.
//      (2) Grid items: every child of a grid
//      container now stands as its own item,
//      inline children included, as CSS says —
//      before, inline children were gathered
//      into the text run around them, and a
//      card built of spans collapsed into one
//      item with its tracks unfilled (the hub's
//      directory cards). (3) The grid cap is
//      twelve hundred containers, not sixty —
//      the hub alone declares two hundred, and
//      past the old cap the rest of a page
//      silently flowed un-gridded.
//    * Developer tools and settings (0.35):
//      the window grows a console drawer with
//      two faces, and the page stays landed
//      after it paints — its parsed tree, the
//      scope its scripts ran in, and the very
//      renderer that painted it are kept as the
//      page's session, for the tools to work
//      against. The Console face is where a
//      page's words to the console, its script
//      errors and its alerts now live, as
//      readable entries that cannot be cut out
//      of sight: in 0.33 and 0.34 they rode the
//      status line, whose tail the window
//      truncated — an alert could not be seen
//      even full-screen. An alert also raises
//      a banner under the bar until it is
//      dismissed. At the foot of the Console
//      face, a JavaScript console: what is
//      typed there runs through this same
//      interpreter, in the landed page's own
//      scope — a function a fetched helper left
//      behind is still there to call, an
//      element's text can be read, and a write
//      repaints the page from its kept tree so
//      the change is seen. The Inspector face
//      shows the landed page's own tree — tags,
//      ids, classes, its text — and, for the
//      element chosen, the declarations this
//      engine itself resolved for it and the
//      rules that matched, in cascade order:
//      our computed style, the thing to debug
//      when a page looks wrong in Chirpy.
//      The page's canvas is white now where a
//      page gives no background of its own (in
//      the window's install of the painted
//      page): it used to fall back to the
//      system's text background, which follows
//      the Mac's dark appearance, so a plain
//      page like js-test painted black words
//      on a near-black ground; a page that
//      paints its own background — by its
//      styles, or its own color-scheme rules,
//      which join the cascade the background
//      is resolved from — wins exactly as
//      before.
//      Settings joins them, each one honored
//      by the engine and kept in the reader's
//      defaults: the homepage the Home button
//      and a launch open, the cache's cap, the
//      page text size, and whether links carry
//      their [n] numbers. The Shield stands in
//      Settings as fact — its lists' sizes —
//      and never as a switch: no setting turns
//      the Shield, the family filter or ad
//      blocking off. And Chirpy's chosen mark,
//      the singing cardinal in stained glass,
//      stands on the home page and at the head
//      of the repo's README.
//  0.36 is the speed stage, and the repair of
//  the painted-box links. Measured first, on a
//  real Wikipedia article (2,818 elements, 607
//  stylesheet rules): the custom-property
//  environment was the mountain — it matched
//  every rule against every ancestor of every
//  element (86.7s for one pass), though only 4
//  of the 607 rules define a --property at all;
//  it matches only those now. The resting
//  cascade's full scan (2.0s a pass, asked for
//  the same elements again and again) is
//  answered from an index by each selector's
//  rightmost-compound key and remembered per
//  element for the walk's life. A page paints
//  BEFORE its scripts run; script changes
//  repaint a beat later, and the whole script
//  stage — fetches and execution together —
//  lives under a three-second budget, past
//  which one plain console line says the rest
//  were skipped. Every load leaves a Timing
//  entry in the console: fetch, parse,
//  style+layout, scripts, and the total, so
//  the reader's own machine is the profiler.
//  And links inside painted boxes — floated
//  boxes, grid and flex items, columns,
//  positioned boxes, fixed overlays — are
//  followed now: their targets are no longer
//  stripped in the finalize passes, and the
//  view hit-tests the painted seat with the
//  same layout that painted it. A container
//  nested inside a box's own contents is not
//  followed yet (named in the README).
//  0.37 teaches scripts to send the reader
//  onward — the doors DuckDuckGo's results
//  stand behind. Its redirector answers a
//  click with neither a 302 nor a page, but a
//  scrap carrying two send-ons: a script's
//  window.parent.location.replace(url), and a
//  <meta http-equiv="refresh"> folded inside
//  <noscript>. Until now Chirpy opened
//  neither: window existed as a shell holding
//  document, console and alert, but location,
//  parent and top were absent, so the script's
//  road walked into undefined and died; and
//  the parser sets noscript subtrees aside
//  whole, so the refresh scan (which walks
//  the tree) never saw the folded tag. Now
//  window carries a location — href read and
//  written, replace and assign, the same
//  object at document.location and at the
//  bare global name; window.parent, window.top
//  and window.self are the window itself, this
//  being a single-frame world. A script's
//  chosen destination is resolved against the
//  page's own address (http, https and file
//  travel; nothing else does), ends the
//  script stage — the room is being vacated —
//  and is followed in the render the way a
//  meta refresh is: the same three-hop limit,
//  the same Shield-checked fetch, the fetch
//  time joining the load's account, so the
//  address bar and the history name the
//  destination, never the doorway, and a
//  listed host is refused exactly as a typed
//  address is refused. And if the scripts
//  leave the reader standing here, the
//  refresh folded inside <noscript> is read
//  at last — its raw text parsed and asked
//  for a refresh of its own — and followed
//  down the same road: the fallback door,
//  asked after the page's own code, as
//  noscript has always meant. The JavaScript
//  console honors a typed location the same
//  way — through the window's own load. In
//  history's terms every script send-on
//  replaces, as a refresh hop does.
//  0.37.1 is a repair stage for two live
//  failures the doors met in the wild. A live
//  DuckDuckGo result click settled on the
//  white doorway: the paint-first order
//  (0.36) handed the doorway to the window
//  before its scripts ran — the window
//  installed its address, cleared the
//  progress and stood the load down as
//  finished — and only then followed the
//  script's send-on, so on a slow destination
//  the reader sat on a finished white page,
//  and any touch began a new load whose
//  generation guard discarded the destination
//  when it landed. The script stage now runs
//  before the single walk again, as it did
//  from 0.33 to 0.35: a doorway is never
//  presented as a settled page, the console's
//  Timing line loses the repaint member the
//  two-walk shape needed, and the three-
//  second script budget still bounds the
//  wait. The plain refresh chase was never
//  broken — it never paints its doorway —
//  which is why a Google stub chase followed
//  live while the script door seemed shut.
//  The same stage teaches the pointer to
//  know a link when it sees one: hovering
//  text that carries a link, or a painted
//  seat that holds one, now shows the
//  pointing hand — until now the seats were
//  never asked at hover, and no cursor was
//  ever set. Wikipedia's article body was
//  measured with this engine's own cascade
//  against the live page and its real
//  stylesheets: every ancestor of its
//  paragraphs resolves to plain block flow,
//  no grid, flex or float seat swallows it —
//  the drill page (wiki-shape-test.html)
//  separates flow links from seat links so
//  the remaining on-device question can be
//  answered by one click each.
//  0.37.3 is the third speed stage plus the
//  link repair. The 0.37.2 decomposition's
//  two remaining rooms are decomposed in
//  their turn (harness, real "Jesus"
//  article): the resting cascade's 33s is
//  NOT candidate volume — the subject
//  index offers 41.7 candidates per element
//  on average — it is 11.08 million
//  selector matches, 58s by the matcher's
//  own clock, and inside the matcher the
//  multiplication is the descendant walk:
//  every compound of every matched-against
//  selector climbs the ancestor chain and
//  re-derives the element's class list by
//  splitting its class attribute
//  (12.88 million splits) and re-derives
//  its element-sibling list (116 thousand
//  scans over 5.3 million children). The
//  matcher now reads per-element facts the
//  walk stamps once — class list, element
//  index among siblings, sibling counts —
//  instead of re-deriving them per match;
//  a node not yet stamped derives them as
//  before, so values cannot move. And the
//  walk's other room was mostly not the
//  walk at all: of the 26.32s "inline
//  walk," the state resolutions' variable
//  environments took 13.5s — every one of
//  41,313 state resolutions rebuilt the
//  custom-property environment from the
//  FULL rule array (a 1,204-rule filter
//  plus an ancestor walk per call) though
//  only 4 rules define a custom property.
//  The environment is now built once per
//  element and remembered beside the
//  resting style (the resting resolution
//  pays the same rebuild per element
//  today — it shares the remembered one),
//  the custom-rule filter is cached per
//  rule set, and an element whose chain
//  defines no custom property anywhere
//  skips the ancestor walk entirely.
//  Specificity, computed by reduction over
//  a selector's compounds on every sort
//  comparison, is computed once per rule.
//  Cascade equivalence stays 0 mismatches
//  on every corpus and check; the state
//  census of 0.37.2 is untouched.
//  The link repair: a block-level anchor
//  styled display:grid/flex/columns (the
//  hub's cards) laid its text down in its
//  seat's private contents and NEVER
//  received the .link stamp walkBlock's
//  close gives a block anchor — the stamp
//  measures from where the block's inline
//  content began, and a seat's block lays
//  none down in the page's text — so the
//  card wore no link anywhere the pointer
//  or the click looks: the I-beam on the
//  hub, named in the field. The seat's
//  spec now carries the container's own
//  link, resolved where walkBlock resolves
//  the anchor, and the seat hit test
//  answers it for the seat's whole box
//  when no item inside carries a nearer
//  one. A floated or positioned anchor
//  carries its link the same way. And a
//  link whose address differs from the
//  page's only in its #fragment is a
//  scroll, not a load: the window no
//  longer fetches and re-walks the whole
//  page to move within it (wiki-shape #1,
//  whose href is "#landed", reloaded the
//  test page entire); elements' ids are
//  stamped as anchors in the walk so the
//  window can find the landing place.
//  The overprint: 0.37.2's classification
//  is CORRECTED in the README — there is
//  no sibling-adjacency test in this
//  engine at all (the selector grammar
//  refuses + and ~ outright), and no
//  `div.hatnote + p` rule reaches the lead
//  paragraph. What the harness proves is
//  in the README; the drawing itself is
//  AppKit's, and Tyler's screenshot of the
//  article's top remains its judge.
//  First-paint arrivals: DECLINED, with
//  the mechanism named in the README —
//  the first hand-off is one indivisible
//  walkBlock of the whole tree and the
//  arrivals Tyler saw repainting beneath
//  the header are picture seats filling,
//  not text arriving in pieces; what
//  would make an earlier first paint safe
//  is named there too.
//  0.37.2 is the second speed stage, aimed
//  by Tyler's own Console Timing entry for
//  the chased Wikipedia "Jesus" article:
//  fetch 0.09s · parse 0.36s · style+layout
//  66.50s · scripts 0.01s · total 66.95s.
//  The whole wait sat inside renderFirstPaint,
//  and instrumenting the real renderer
//  against the real article (46,631 nodes,
//  1,204 rules) split it: the resting
//  cascade 33.17s, the inline walk 26.32s,
//  and the state resolutions about 24s —
//  nearly all of it a full-sheet scan the
//  resting cascade no longer does: the
//  state resolution was offered EVERY rule
//  through the subject index, though only
//  rules carrying the state flag can ever
//  match (on this article, 4 :hover rules
//  of 1,204), and it ran for every element
//  at every block close (41,313 calls). The
//  state resolution is now offered only its
//  flag's census through the same index —
//  the census is rebuilt per element, never
//  cached, because tbSelectorHasState
//  answers about the leaf compound alone
//  for :hover/:focus/:active-first
//  selectors and about any compound
//  otherwise, which the index's rightmost-
//  compound filing would silently
//  under-include. Values cannot move: the
//  resolution still filters by the flag
//  itself, and every var() substitution
//  still happens. Harness after: the first
//  paint falls from 79.13s to 55.86s here,
//  the state scans from 24.35s to 0.46s;
//  what remains is the walk's own work and
//  the resting cascade's, and Tyler's next
//  Timing entry is the verdict. The same
//  stage repairs the seat hit test's grid
//  and flex items (their rects are offsets
//  inside their container's seat — the
//  painters' own bargain — and the hit test
//  read them as page coordinates, so the
//  wiki shape test's #3 and #4 could
//  neither hover a hand nor follow a
//  click), and the status line now names
//  the landed URL a chase arrived at, as
//  the address bar already did, instead of
//  the doorway that was merely fetched.
//  Named for the next stage, not fixed: the
//  overprint at the "Jesus" article's top —
//  the hatnote paragraph and the lead
//  paragraph are walked as ONE text block
//  (the sheet's `div.hatnote + p` adjacency
//  rule matches the parser's sibling test,
//  which reads adjacency by NODE — 286
//  element nodes intervene, carrying no
//  text), so their shared italic face and
//  small cap share one band, and the glyph
//  overlap itself is AppKit's band layout
//  on the device, which this harness cannot
//  reproduce; see the README for the exact
//  chain and the evidence.
//  Not yet: JavaScript beyond the first slice
//  above — event handlers, timers, fetch and
//  XMLHttpRequest, and the wider DOM. The
//  Inspector shows an element's styles but
//  does not yet edit them live. Live
//  form controls inside grid, flex, float and
//  column seats still stand as labelled
//  placeholders there — the seats are paint,
//  not text (the hub's search field is one).
//  And the outs named in the README.
//  0.38 is JavaScript's second stage — the
//  language core real pages' scripts reach
//  for first, built from where the console
//  showed them dying. Patterns: a regex
//  literal is a value now (the lexer tells
//  it from division by the token before it,
//  as every small lexer does), backed by
//  Foundation's NSRegularExpression — a
//  regex library, not a borrowed JavaScript
//  engine — with the RegExp constructor,
//  test and exec (groups in an array;
//  lastIndex walks under g and y), and a
//  string's match, replace (the $ words
//  expanded: $$, $&, $`, $', $1..$99), split
//  and search keeping their company.
//  Templates: backtick strings with ${…}
//  workings woven in, nested templates
//  included. Guarding: try, catch, finally
//  and throw — a script's own thrown value
//  travels as a value and a catch holds it
//  as itself, while an engine error arrives
//  in the catch as its message; finally
//  runs on every road out, return, break
//  and continue included; and a throw
//  nothing catches now ends its script with
//  a plain line instead of vanishing.
//  Building: `new` — RegExp natively, and a
//  reader's own function as a constructor
//  over a plain object, a method's writes
//  to `this` riding home the same road the
//  array helpers opened. Named gaps, on
//  purpose: an exec result carries no
//  .index or .input of its own; replace
//  will not take a function yet; a pattern
//  inside a template's ${…} holding a "}"
//  would end the working early; classes
//  and arrow functions are not here; and
//  the async world — timers, promises,
//  fetch — is a later stage still. The
//  drill page js2-test.html promises each
//  piece, one numbered promise at a time.
//  0.39 is JavaScript's third stage — the
//  modern shapes real scripts are written
//  in. Bindings: let and const, block-scoped
//  — planted in their room's opening, so
//  reading one before its own line is the
//  temporal-dead-zone error and writing a
//  constant is a refusal, both errors a try
//  can catch; var keeps its old roads. A
//  for head wearing let or const keeps a
//  fresh binding for every round, so a
//  closure made in a round keeps that
//  round's counter. Arrows: (a, b) => expr,
//  (a) => { … }, a => expr — each born
//  holding the `this` of the room it was
//  written in, which no call can take from
//  it; an arrow still cannot be built with.
//  Parameters grow defaults (an explicit
//  undefined wakes one, as a missing
//  argument does) and a closing rest, which
//  gathers what remains into a true array;
//  spread opens an array into another
//  array, a call's arguments, and a
//  building's. for-of walks an array's
//  values and a string's letters, into a
//  let, a const, a var, or a name already
//  standing. Classes: class, extends, new —
//  an instance carries its class in a box
//  held by reference, so two hands on one
//  instance see the same fields; a member
//  read walks instance, class, parent
//  class; super(...) builds the parent part
//  before the child's own body may touch
//  `this`, and super.method() calls the
//  parent's with the child's `this`; a
//  child with no constructor forwards its
//  arguments to the parent's. instanceof
//  walks that same class road, with the
//  root Object above every object-shaped
//  value, and the `in` operator rides
//  beside it. Named gaps, on purpose:
//  static methods and getters/setters are
//  refused by name at the reading, not
//  faked; classes are declarations, not
//  expressions; destructuring is not here
//  (0.40 evidence); instanceof against a
//  plain function constructor answers false
//  — its products are dictionary objects
//  and carry no class stamp to walk; a
//  derived constructor's `this` reads as
//  undefined before super(...) rather than
//  raising, though ending still unbound is
//  an error; for-of walks arrays and
//  strings only. The drill is a suite now,
//  and stays one: js-suite.html opens every
//  stage's page — js-test.html, js2-test.html,
//  and this stage's js3-test.html, ten
//  promises — and no stage is done until
//  the whole suite passes.
//  0.39.1 is the split's first step: the
//  JavaScript interpreter - everything from
//  TBJSValue to the end of tbConsoleEval -
//  moved out of this file into ChirpyJS.swift,
//  whole and word for word, so each part of
//  the codebase can be fixed and built
//  quicker. Nothing else changed: no behavior,
//  no feature. The engine header's stage
//  bullets above stay the interpreter's
//  account of itself, and a marker stands
//  below where the section lived, pointing at
//  its new home.
//  0.39.2 is the split's second step: the
//  Shield - its two domain lists, the category
//  and the match, the block page, and the
//  privacy dressing, a section of its own
//  since 0.28 - moved out of this file into
//  ChirpyShield.swift, whole and word for
//  word, so it can be fixed and built
//  quicker. Nothing else changed: no
//  behavior, no feature. The fetcher still
//  asks the Shield before any network I/O;
//  the Shield simply answers from its own
//  file now. A marker stands below where the
//  section lived, pointing at its new home.
//  0.39.3 is the split's third step: the
//  style system - the selectors and their
//  matching, the stylesheet parser, the
//  cascade in its resting and state
//  resolutions, the CSS variables, the
//  colors, and the font helpers - moved out
//  of this file into ChirpyCSS.swift, whole
//  and word for word, so it can be fixed and
//  built quicker. Nothing else changed: no
//  behavior, no feature. Layout and the
//  renderer still ask the style system what
//  an element wears; it simply answers from
//  its own file now. A marker stands below
//  where the sections lived, pointing at
//  their new home.
//  0.39.4 is the split's fourth step: the
//  layout system - the box and length
//  helpers that stood under the layout mark,
//  and the renderer's own layout regions:
//  positioned layout in both its passes,
//  multi-column, flexbox, and grid - moved
//  out of this file into ChirpyLayout.swift,
//  whole and word for word, so it can be
//  fixed and built quicker. The renderer
//  regions travel as extensions of
//  TBRenderer in their new file, and sixty
//  of the renderer's private members - the
//  ones the two files now share - stand
//  internal instead of private, the only
//  change of any kind inside the moved
//  words. Nothing else changed: no behavior,
//  no feature. The walk and the paint still
//  ask layout where everything sits; it
//  simply answers from its own file now. A
//  marker stands below where the sections
//  lived, pointing at their new home.
//  0.39.5 is the split's fifth step: the
//  paint system - the surface-edge
//  machinery, the background box, and the
//  whole paint & motion country: the
//  shadow, transform, opacity, transition
//  and animation parsing, the state paint
//  styles, the image and background
//  finishes, the first paint, and the walk
//  itself - moved out of this file into
//  ChirpyPaint.swift, whole and word for
//  word, so it can be fixed and built
//  quicker. The paint regions travel as
//  extensions of TBRenderer in their new
//  file, and six of the renderer's private
//  members - the paint state the two files
//  now share - stand internal instead of
//  private, the only change of any kind
//  inside the moved words. Nothing else
//  changed: no behavior, no feature. The
//  render core still asks the paint system
//  for the finished page; it simply answers
//  from its own file now. Markers stand
//  below where the sections lived,
//  pointing at their new home.
//  0.39.6 is the split's sixth step, and
//  its last: the render core - the tag
//  sets and the base styles, the form
//  controls and their attachments, the
//  form specs, TBRenderer itself with its
//  stored state, its style resolutions
//  and its forms, the send-on helpers, and
//  the page pipeline that fetches, runs,
//  renders and repaints - moved out of
//  this file into ChirpyRenderer.swift,
//  whole and word for word, so it can be
//  fixed and built quicker. TBRenderer
//  travels whole, class and stored state
//  together - an extension cannot hold
//  stored properties, which is why the
//  layout and paint regions went as
//  extensions and the class itself waited
//  for its own file. No member changed
//  access this time; the audit found the
//  moved words already reach, and are
//  reached by, only what stands internal.
//  Nothing else changed: no behavior, no
//  feature. What remains in this file is
//  the engine's core: the home page, the
//  entities, the reader settings, the
//  cache, the fetch and the shared spec
//  types, the inspector's report, and the
//  HTML parse. The split is complete: a
//  marker stands below where the render
//  core lived, pointing at its new home.
//

import Foundation
import AppKit

let TB_HOME_HTML = """
<!DOCTYPE html>
<html>
<head><title>Chirpy Home</title></head>
<body>
<p><img src="data:image/webp;base64,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" width="160" height="160" alt="Chirpy — a singing cardinal in stained glass"></p>
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

// MARK: - The Shield (0.28) - lives in ChirpyShield.swift

// The Shield stood here from 0.28 until 0.39.2,
// when it moved into ChirpyShield.swift, whole
// and word for word: its two domain lists, the
// category and the match, the block page, and
// the privacy dressing. The split's second step —
// see ChirpyShield.swift.

// MARK: - Reader settings (0.35)

// The reader's own choices, kept in the app's
// defaults between launches and honored by the
// engine itself: every setting here does what
// it says. What is NOT here is deliberate —
// the Shield has no setting. Its lists stand
// in the Settings sheet as facts, and there is
// no key, here or anywhere, that turns the
// Shield, the family filter, or ad blocking
// off.
enum TBSettings {
    static let homepageKey = "chirpy.settings.homepage"
    static let cacheCapKey = "chirpy.settings.cacheCapMB"
    static let textSizeKey = "chirpy.settings.textSizePercent"
    static let linkNumbersKey = "chirpy.settings.showLinkNumbers"

    // The address the Home button and a fresh
    // launch open. Empty means the built-in
    // Chirpy Home (chirpy://home).
    static var homepage: String {
        get { UserDefaults.standard.string(forKey: homepageKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: homepageKey) }
    }
    static var startAddress: String {
        homepage.isEmpty ? "chirpy://home" : homepage
    }

    // The disk cache's cap, in megabytes —
    // 200 until Settings names another.
    static var cacheCapMB: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: cacheCapKey)
            return v == 0 ? 200 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: cacheCapKey) }
    }
    static var cacheCapBytes: Int { cacheCapMB * 1024 * 1024 }

    // The page text size, as a percentage of
    // the sizes the engine would otherwise lay
    // a page out with — 100 until Settings
    // names another.
    static var textSizePercent: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: textSizeKey)
            return v == 0 ? 100 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: textSizeKey) }
    }
    static var textScale: CGFloat {
        CGFloat(textSizePercent) / 100
    }

    // Whether links carry their stamped [n]
    // number after them. On until the reader
    // says otherwise.
    static var showLinkNumbers: Bool {
        get {
            if UserDefaults.standard.object(forKey: linkNumbersKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: linkNumbersKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: linkNumbersKey) }
    }
}

// MARK: - The Cache (0.32)

// The cache: what Chirpy fetched, kept on the
// reader's own disk under the app's caches folder,
// so a page and its pictures need not cross the
// network twice. Only successful GET replies are
// kept — pages, sheets, scripts and pictures —
// each filed under the address it was fetched
// from. The Shield is asked first at every call
// site, before any lookup: a listed host is
// refused before the cache is ever consulted, and
// because a blocked reply is never fetched at all,
// nothing blocked is ever stored.
//
// Freshness is the server's own word, honored the
// way RFC 9111 sketches it: Cache-Control's
// max-age first, then Expires, then — when a page
// offers nothing else — a tenth of the time it had
// already lived unchanged when fetched, bounded
// at a week so nothing rides the heuristic
// forever. A stale entry with an ETag or a
// Last-Modified goes back as a conditional
// request: a 304 answer renews the entry and the
// kept body serves. Nothing here is stale-forever:
// an entry with no freshness word and no validator
// is simply fetched again.
//
// The whole cache is capped at the reader's
// setting (0.35) — 200 MB until Settings names
// another of 50, 100 or 500 MB; when a store
// takes it past the cap, the least recently
// used entries are let go until it fits. A single
// reply larger than 25 MB is never stored. The
// reader can clear the whole cache from the
// window's bar. All of it is plain files on the
// reader's own Mac — the only thing Chirpy keeps
// between launches — and none of it is ever
// reported anywhere.

var TBCacheCapBytes: Int { TBSettings.cacheCapBytes }
let TBCacheEntryCapBytes = 25 * 1024 * 1024

// One kept reply's card: where its body lies, when
// it came in and was last used, and the freshness
// word its server sent with it.
struct TBCacheMeta: Codable {
    var url: String
    var bodyFile: String
    var storedAt: Double
    var lastUsedAt: Double
    var etag: String? = nil
    var lastModified: String? = nil
    var cacheControl: String? = nil
    var expires: String? = nil
    var dateHeader: String? = nil
    var size: Int = 0
}

enum TBCacheLookup {
    case miss
    case fresh(TBCacheMeta, Data)
    case stale(TBCacheMeta)
}

// Every cache file passes through this one queue,
// so the batch fetcher's parallel asks can never
// tread on each other's cards.
private let tbCacheQueue = DispatchQueue(label: "ChirpyBrowser.cache")

func tbCacheDirectory() -> URL? {
    guard let base = FileManager.default.urls(
        for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }
    let dir = base.appendingPathComponent("ChirpyBrowser/HTTPCache",
                                          isDirectory: true)
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir.path) {
        try? fm.createDirectory(at: dir,
                                withIntermediateDirectories: true)
    }
    return dir
}

// The card's name for an address: an FNV-1a hash of
// its words. A collision is answered by the card
// itself, which carries the address it belongs to
// and is only believed when the two agree.
func tbCacheKey(for urlString: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in urlString.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    let hex = String(hash, radix: 16)
    return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
}

func tbParseHTTPDate(_ raw: String?) -> Date? {
    guard let raw = raw else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    if let parsed = formatter.date(from: raw) { return parsed }
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.date(from: raw)
}

func tbHeaderValue(_ response: HTTPURLResponse, _ name: String) -> String? {
    for (key, value) in response.allHeaderFields {
        if let key = key as? String,
           key.caseInsensitiveCompare(name) == .orderedSame {
            return value as? String
        }
    }
    return nil
}

func tbCacheControlTokens(_ header: String?) -> [String] {
    guard let header = header else { return [] }
    return header.lowercased().split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespaces) }
}

func tbCacheMaxAge(_ header: String?) -> Int? {
    for token in tbCacheControlTokens(header) {
        if token.hasPrefix("max-age=") {
            let raw = String(token.dropFirst("max-age=".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return Int(raw)
        }
    }
    return nil
}

// Is the kept entry fresh at `now`, by its server's
// own declared word?
func tbCacheIsFresh(_ meta: TBCacheMeta, now: Date) -> Bool {
    let tokens = tbCacheControlTokens(meta.cacheControl)
    if tokens.contains("no-cache") || tokens.contains("no-store") {
        return false
    }
    let stored = Date(timeIntervalSince1970: meta.storedAt)
    let dateHeader = tbParseHTTPDate(meta.dateHeader)
    // The entry's age when it arrived, by the
    // server's own clock where it declared one.
    var apparentAge: TimeInterval = 0
    if let dateHeader = dateHeader {
        apparentAge = max(0, stored.timeIntervalSince(dateHeader))
    }
    let resident = now.timeIntervalSince(stored)
    let currentAge = apparentAge + resident
    if let maxAge = tbCacheMaxAge(meta.cacheControl) {
        return currentAge < TimeInterval(maxAge)
    }
    if let expires = tbParseHTTPDate(meta.expires) {
        if let dateHeader = dateHeader {
            return currentAge < expires.timeIntervalSince(dateHeader)
        }
        return now < expires
    }
    if let modified = tbParseHTTPDate(meta.lastModified) {
        // The heuristic: fresh for a tenth of the
        // time the page had already lived unchanged
        // when it was fetched, bounded at a week.
        let lifetime = min(stored.timeIntervalSince(modified) / 10,
                           7 * 24 * 3600)
        return lifetime > 0 && resident < lifetime
    }
    return false
}

// Write one card. Called only inside the cache
// queue, like everything that touches the files.
private func tbCacheWriteMeta(_ meta: TBCacheMeta, in dir: URL, key: String) {
    if let raw = try? JSONEncoder().encode(meta) {
        try? raw.write(to: dir.appendingPathComponent(key + ".meta"),
                       options: .atomic)
    }
}

func tbCacheLookup(urlString: String) -> TBCacheLookup {
    return tbCacheQueue.sync {
        guard let dir = tbCacheDirectory() else { return .miss }
        let key = tbCacheKey(for: urlString)
        let metaURL = dir.appendingPathComponent(key + ".meta")
        guard let raw = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(TBCacheMeta.self,
                                                   from: raw),
              meta.url == urlString else { return .miss }
        if tbCacheIsFresh(meta, now: Date()) {
            let bodyURL = dir.appendingPathComponent(meta.bodyFile)
            guard let body = try? Data(contentsOf: bodyURL) else {
                return .miss
            }
            var touched = meta
            touched.lastUsedAt = Date().timeIntervalSince1970
            tbCacheWriteMeta(touched, in: dir, key: key)
            return .fresh(touched, body)
        }
        return .stale(meta)
    }
}

func tbCacheBody(of meta: TBCacheMeta) -> Data? {
    return tbCacheQueue.sync {
        guard let dir = tbCacheDirectory() else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(meta.bodyFile))
    }
}

// Keep a fetched reply, if its own headers allow
// keeping. The reply is filed under the address it
// was asked from; where the server sent the reader
// elsewhere, a second card is filed under the
// address landed on, pointing at the same body, so
// either address finds it.
func tbCacheStore(requestURL: String, response: HTTPURLResponse,
                  data: Data) {
    guard let landed = response.url,
          let scheme = landed.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else { return }
    guard response.statusCode == 200 else { return }
    guard data.count <= TBCacheEntryCapBytes else { return }
    let cacheControl = tbHeaderValue(response, "Cache-Control")
    if tbCacheControlTokens(cacheControl).contains("no-store") { return }
    let etag = tbHeaderValue(response, "ETag")
    let lastModified = tbHeaderValue(response, "Last-Modified")
    let expires = tbHeaderValue(response, "Expires")
    let dateHeader = tbHeaderValue(response, "Date")
    tbCacheQueue.sync {
        guard let dir = tbCacheDirectory() else { return }
        let now = Date().timeIntervalSince1970
        let key = tbCacheKey(for: requestURL)
        let bodyName = key + ".body"
        do {
            try data.write(to: dir.appendingPathComponent(bodyName),
                           options: .atomic)
        } catch { return }
        var meta = TBCacheMeta(url: requestURL, bodyFile: bodyName,
                               storedAt: now, lastUsedAt: now)
        meta.etag = etag
        meta.lastModified = lastModified
        meta.cacheControl = cacheControl
        meta.expires = expires
        meta.dateHeader = dateHeader
        meta.size = data.count
        tbCacheWriteMeta(meta, in: dir, key: key)
        let final = landed.absoluteString
        if final != requestURL {
            var alias = meta
            alias.url = final
            tbCacheWriteMeta(alias, in: dir,
                             key: tbCacheKey(for: final))
        }
        tbCacheEvict(in: dir)
    }
}

// A 304 answer: the kept body stands; the entry
// takes the answer's freshness word as its own and
// starts its clock again.
func tbCacheRevalidate(urlString: String, response: HTTPURLResponse) {
    let etag = tbHeaderValue(response, "ETag")
    let lastModified = tbHeaderValue(response, "Last-Modified")
    let cacheControl = tbHeaderValue(response, "Cache-Control")
    let expires = tbHeaderValue(response, "Expires")
    let dateHeader = tbHeaderValue(response, "Date")
    tbCacheQueue.sync {
        guard let dir = tbCacheDirectory() else { return }
        let key = tbCacheKey(for: urlString)
        let metaURL = dir.appendingPathComponent(key + ".meta")
        guard let raw = try? Data(contentsOf: metaURL),
              var meta = try? JSONDecoder().decode(TBCacheMeta.self,
                                                   from: raw),
              meta.url == urlString else { return }
        let now = Date().timeIntervalSince1970
        meta.storedAt = now
        meta.lastUsedAt = now
        if let etag = etag { meta.etag = etag }
        if let lastModified = lastModified {
            meta.lastModified = lastModified
        }
        if let cacheControl = cacheControl {
            meta.cacheControl = cacheControl
        }
        if let expires = expires { meta.expires = expires }
        if let dateHeader = dateHeader { meta.dateHeader = dateHeader }
        tbCacheWriteMeta(meta, in: dir, key: key)
    }
}

// Let the least recently used entries go until the
// cache fits its cap. A body shared by two cards is
// counted once and removed only when its last card
// goes. Called inside the cache queue.
private func tbCacheEvict(in dir: URL) {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path)
    else { return }
    var metas: [(key: String, meta: TBCacheMeta)] = []
    var bodies: [String: Int] = [:]
    for name in names where name.hasSuffix(".meta") {
        let key = String(name.dropLast(".meta".count))
        guard let raw = try? Data(contentsOf: dir.appendingPathComponent(name)),
              let meta = try? JSONDecoder().decode(TBCacheMeta.self,
                                                   from: raw)
        else { continue }
        metas.append((key, meta))
        if bodies[meta.bodyFile] == nil { bodies[meta.bodyFile] = meta.size }
    }
    var total = bodies.values.reduce(0, +)
    if total <= TBCacheCapBytes { return }
    let oldestFirst = metas.sorted {
        $0.meta.lastUsedAt < $1.meta.lastUsedAt
    }
    var remaining = metas
    for victim in oldestFirst {
        if total <= TBCacheCapBytes { break }
        try? fm.removeItem(at: dir.appendingPathComponent(victim.key + ".meta"))
        remaining.removeAll { $0.key == victim.key }
        let bodyStillUsed = remaining.contains {
            $0.meta.bodyFile == victim.meta.bodyFile
        }
        if !bodyStillUsed {
            try? fm.removeItem(
                at: dir.appendingPathComponent(victim.meta.bodyFile))
            total -= bodies[victim.meta.bodyFile] ?? 0
        }
    }
}

// The reader's broom, on the window's bar: every
// kept page and picture goes, at once.
func tbCacheClear() {
    tbCacheQueue.sync {
        guard let dir = tbCacheDirectory() else { return }
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: dir.path) {
            for name in names {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }
}

func tbCacheSizeBytes() -> Int {
    return tbCacheQueue.sync {
        guard let dir = tbCacheDirectory(),
              let names = try? FileManager.default
                .contentsOfDirectory(atPath: dir.path)
        else { return 0 }
        var total = 0
        var seen: Set<String> = []
        for name in names where name.hasSuffix(".meta") {
            guard let raw = try? Data(
                    contentsOf: dir.appendingPathComponent(name)),
                  let meta = try? JSONDecoder().decode(TBCacheMeta.self,
                                                       from: raw)
            else { continue }
            if seen.insert(meta.bodyFile).inserted { total += meta.size }
        }
        return total
    }
}

struct TBGETResult {
    let data: Data
    let statusCode: Int
    let finalURL: String
}

// One GET through the cache, shared by the helper
// fetchers below — the plain page path, sheets,
// scripts and pictures. The Shield has already been
// asked by the caller; a listed host never gets
// this far. Returns nil only when the fetch itself
// fails: an HTTP error status is a result like any
// other, for the caller to judge as it always has.
func tbGETWithCache(urlString: String, accept: String,
                    pageURLString: String?,
                    timeout: TimeInterval = 60) async -> TBGETResult? {
    guard let url = URL(string: urlString),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else { return nil }
    var stale: TBCacheMeta? = nil
    switch tbCacheLookup(urlString: urlString) {
    case .fresh(_, let body):
        return TBGETResult(data: body, statusCode: 200,
                           finalURL: urlString)
    case .stale(let meta):
        stale = meta
    case .miss:
        break
    }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.37.3.1 (Swift; our own engine)",
                     forHTTPHeaderField: "User-Agent")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("1", forHTTPHeaderField: "Sec-GPC")
    request.setValue("1", forHTTPHeaderField: "DNT")
    tbShieldPrivacy(&request, pageURLString: pageURLString)
    if let stale = stale {
        if let etag = stale.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        } else if let modified = stale.lastModified {
            request.setValue(modified,
                             forHTTPHeaderField: "If-Modified-Since")
        }
    }
    request.timeoutInterval = timeout
    guard let (data, response) = try? await URLSession.shared
        .data(for: request) else { return nil }
    guard let http = response as? HTTPURLResponse else {
        return TBGETResult(data: data, statusCode: 200,
                           finalURL: response.url?.absoluteString
                            ?? urlString)
    }
    if http.statusCode == 304, let stale = stale,
       let body = tbCacheBody(of: stale) {
        tbCacheRevalidate(urlString: urlString, response: http)
        return TBGETResult(data: body, statusCode: 200,
                           finalURL: urlString)
    }
    if http.statusCode == 200 {
        tbCacheStore(requestURL: urlString, response: http, data: data)
    }
    return TBGETResult(data: data, statusCode: http.statusCode,
                       finalURL: response.url?.absoluteString ?? urlString)
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
    // The cache (0.32): an http(s) page comes through
    // the shared cached GET, which serves what it
    // honestly may and keeps what it fetches. Other
    // addresses (a dropped file, above all) keep the
    // plain path below, exactly as before.
    if let scheme = url.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
        guard let got = await tbGETWithCache(
            urlString: urlString,
            accept: "text/html,application/xhtml+xml",
            pageURLString: nil) else {
            throw NSError(domain: "ChirpyBrowser", code: 2,
                          userInfo: [NSLocalizedDescriptionKey:
                                        "That page could not be fetched."])
        }
        let html = String(data: got.data, encoding: .utf8)
            ?? String(decoding: got.data, as: UTF8.self)
        return (got.finalURL, html)
    }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.37.3.1 (Swift; our own engine)",
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
    request.setValue("ChirpyBrowser/0.37.3.1 (Swift; our own engine)",
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
    // The cache (0.32): the stale entry this load is
    // revalidating, if any; the address it was asked
    // for; whether this load is a form's POST (never
    // cached); and the last response's status, which
    // the completion reads to answer a 304 from the
    // cache or to keep a 200.
    private var cacheStale: TBCacheMeta? = nil
    private var cacheRequestURL = ""
    private var cacheIsPost = false
    private var cacheLastStatus = 0

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
        // The cache (0.32): asked only now that the
        // Shield has passed — a listed host is never
        // served from the cache. A fresh entry answers
        // the load whole, off the reader's own disk; a
        // stale one lends its validators to the
        // request below, and the completion decides.
        // A form's POST is never cached.
        cacheStale = nil
        cacheRequestURL = urlString
        cacheIsPost = postBody != nil
        cacheLastStatus = 0
        if postBody == nil {
            switch tbCacheLookup(urlString: urlString) {
            case .fresh(_, let body):
                onProgress(1)
                let html = String(data: body, encoding: .utf8)
                    ?? String(decoding: body, as: UTF8.self)
                return (finalURL: urlString, html: html)
            case .stale(let meta):
                cacheStale = meta
            case .miss:
                break
            }
        }
        var request = URLRequest(url: url)
        if let postBody = postBody {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = postBody.data(using: .utf8)
        }
        request.setValue("ChirpyBrowser/0.37.3.1 (Swift; our own engine)",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Sec-GPC")
        request.setValue("1", forHTTPHeaderField: "DNT")
        if let stale = cacheStale {
            if let etag = stale.etag {
                request.setValue(etag,
                                 forHTTPHeaderField: "If-None-Match")
            } else if let modified = stale.lastModified {
                request.setValue(modified,
                                 forHTTPHeaderField: "If-Modified-Since")
            }
        }
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
        // The cache (0.32): remember the status of
        // the response now beginning — after any
        // redirects, the last one is the page's own,
        // and the completion reads it.
        if let http = response as? HTTPURLResponse {
            cacheLastStatus = http.statusCode
        }
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
        } else if cacheLastStatus == 304, let stale = cacheStale,
                  let body = tbCacheBody(of: stale) {
            // The cache (0.32): the server answered
            // "not modified" — the kept body is the
            // page. Renew the entry with the answer's
            // freshness word and serve what we hold.
            if let http = task.response as? HTTPURLResponse {
                tbCacheRevalidate(urlString: cacheRequestURL,
                                  response: http)
            }
            let html = String(data: body, encoding: .utf8)
                ?? String(decoding: body, as: UTF8.self)
            done?.resume(returning: (finalURL: cacheRequestURL,
                                     html: html))
        } else {
            // The cache (0.32): a whole, ordinary page
            // is kept as it lands, for the next visit.
            if cacheLastStatus == 200 && !cacheIsPost,
               let http = task.response as? HTTPURLResponse {
                tbCacheStore(requestURL: cacheRequestURL,
                              response: http, data: received)
            }
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
    // The cache (0.32): pictures come through the
    // shared cached GET, like everything fetched — a
    // kept picture is served off the disk, a stale
    // one asked about before it is fetched again.
    // Other addresses (a dropped page's own pictures)
    // keep the plain path below.
    if let scheme = url.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
        guard let got = await tbGETWithCache(
            urlString: urlString, accept: "image/*,*/*",
            pageURLString: pageURLString, timeout: 20) else { return nil }
        if got.statusCode >= 400 { return nil }
        return got.data
    }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.37.3.1 (Swift; our own engine)",
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
// The anchor-name stamp (0.37.3): the id (or <a name>)
// of the block whose walked range carries it — the
// target a fragment lands on. The view scans for it
// when a fragment navigation asks to scroll.
let TBAnchorNameKey = NSAttributedString.Key("TBAnchorName")

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
// blur radius, a spread, and a color. An inset
// shadow (0.30) rides the same struct with its flag
// set: the outer kind paints beneath its box, the
// inset kind as the frame inside it, above the
// background — the two kinds keeping their own
// order in a mixed list.
struct TBBoxShadow {
    var dx: CGFloat
    var dy: CGFloat
    var blur: CGFloat
    var spread: CGFloat
    var color: NSColor
    var inset: Bool = false
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

// How a steps() timing climbs (0.30): end holds
// each step's starting value and jumps at its end
// (the default); start jumps at each step's start,
// so progress is already one step up at x = 0;
// none spreads the jumps so neither endpoint holds
// a step of its own (jump-none); both holds a step
// at both ends (jump-both).
enum TBStepPosition {
    case end, start, none, both
}

// A CSS timing function: a cubic Bézier — the two
// control points between (0, 0) and (1, 1) — or,
// since 0.30, a steps() count, which is no Bézier
// at all and answers in discrete jumps. evaluate()
// answers eased progress for linear progress — for
// a Bézier, the x(t) inversion every browser does,
// solved by Newton-Raphson with a bisection
// fallback.
struct TBTimingFunction {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double
    var stepCount: Int? = nil
    var stepPosition: TBStepPosition = .end
    static let linear = TBTimingFunction(x1: 0, y1: 0, x2: 1, y2: 1)
    static let ease = TBTimingFunction(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeIn = TBTimingFunction(x1: 0.42, y1: 0, x2: 1, y2: 1)
    static let easeOut = TBTimingFunction(x1: 0, y1: 0, x2: 0.58, y2: 1)
    static let easeInOut = TBTimingFunction(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    func evaluate(_ x: Double) -> Double {
        if let count = stepCount {
            // steps(): the staircase itself. The
            // count of jumps taken is the whole part
            // of progress times the count; the jump
            // terms differ only in where the held
            // steps sit, as the enum above says.
            let n = max(count, 1)
            let clamped = min(max(x, 0), 1)
            let jumped = (clamped * Double(n)).rounded(.down)
            switch stepPosition {
            case .end:
                return clamped >= 1 ? 1 : jumped / Double(n)
            case .start:
                return min(jumped + 1, Double(n)) / Double(n)
            case .none:
                if n == 1 { return clamped >= 1 ? 1 : 0 }
                return min(jumped, Double(n - 1)) / Double(n - 1)
            case .both:
                return min(jumped + 1, Double(n + 1))
                    / Double(n + 1)
            }
        }
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

// A timing word, a cubic-bezier(), or a steps() —
// step-start and step-end are steps(1) under their
// own names, and steps() itself takes its count
// with an optional jump term (start, end,
// jump-none, jump-both; end when none is written).
func tbTimingFunction(_ token: String) -> TBTimingFunction {
    let t = token.trimmingCharacters(in: .whitespaces).lowercased()
    switch t {
    case "linear": return .linear
    case "ease": return .ease
    case "ease-in": return .easeIn
    case "ease-out": return .easeOut
    case "ease-in-out": return .easeInOut
    case "step-start", "step-end":
        var stepped = TBTimingFunction.ease
        stepped.stepCount = 1
        stepped.stepPosition = t == "step-start" ? .start : .end
        return stepped
    default:
        if t.hasPrefix("steps("), t.hasSuffix(")") {
            let parts = t.dropFirst(6).dropLast()
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = parts.first, let n = Int(first), n > 0 {
                var position: TBStepPosition = .end
                if parts.count > 1 {
                    switch parts[1] {
                    case "start", "jump-start": position = .start
                    case "jump-none": position = .none
                    case "jump-both": position = .both
                    default: position = .end
                    }
                }
                var stepped = TBTimingFunction.ease
                stepped.stepCount = n
                stepped.stepPosition = position
                return stepped
            }
        }
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
    // The wrapping anchor's link, when this seat's
    // block IS an <a> (0.37.3): the card links on
    // real pages are anchors styled as grid/flex
    // containers, and their text never lands in
    // the main string for a stamp to reach — the
    // seat itself carries the destination so hover
    // and click can find it. Inner links inside
    // the seat's own text still win over it.
    // Where the float was met in the text; the view hangs
    // the box from the top of the line that starts there.
    let anchorCharIndex: Int
    let side: TBFloatSide
    let isImage: Bool
    // The border box the view packs and paints. For image
    // floats the renderer's finish pass replaces the
    // provisional size with the picture's real one.
    var borderWidth: CGFloat
    var containerLink: String? = nil
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
    // The wrapping anchor's link, when this seat's
    // block IS an <a> (0.37.3): the card links on
    // real pages are anchors styled as grid/flex
    // containers, and their text never lands in
    // the main string for a stamp to reach — the
    // seat itself carries the destination so hover
    // and click can find it. Inner links inside
    // the seat's own text still win over it.
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
    var containerLink: String? = nil
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
    // The wrapping anchor's link, when this seat's
    // block IS an <a> (0.37.3): the card links on
    // real pages are anchors styled as grid/flex
    // containers, and their text never lands in
    // the main string for a stamp to reach — the
    // seat itself carries the destination so hover
    // and click can find it. Inner links inside
    // the seat's own text still win over it.
    // The segments the block's contents were cut into
    // at its column-span: all children (0.27) — one
    // part when there is no spanner.
    var parts: [TBColumnPart] = []
    var containerLink: String? = nil
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
    // The wrapping anchor's link, when this seat's
    // block IS an <a> (0.37.3): the card links on
    // real pages are anchors styled as grid/flex
    // containers, and their text never lands in
    // the main string for a stamp to reach — the
    // seat itself carries the destination so hover
    // and click can find it. Inner links inside
    // the seat's own text still win over it.
    // The paint & motion set (0.27): the container's
    // shadows, paint transform and opacity — its seat's
    // surface reads the stamps for the shadow; the item
    // and content painters wrap in the transform and
    // opacity so the whole container moves together.
    var boxShadows: TBBoxShadowSet? = nil
    var containerLink: String? = nil
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
    // The small completions (0.30): align-content,
    // normalized like justify (flex-start, flex-end,
    // center, space-between, space-around,
    // space-evenly, stretch), distributing a wrapped
    // line stack inside a definite cross size; and
    // wrapReverse — flex-wrap: wrap-reverse read
    // honestly at last: the cross axis runs flipped,
    // lines stacking from the cross end.
    var alignContent: String = "flex-start"
    var wrapReverse: Bool = false
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
    // resolved to content-box points at spec time —
    // percentages against the walk's definite
    // ancestor height, like the height itself (0.30).
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
    // The wrapping anchor's link, when this seat's
    // block IS an <a> (0.37.3): the card links on
    // real pages are anchors styled as grid/flex
    // containers, and their text never lands in
    // the main string for a stamp to reach — the
    // seat itself carries the destination so hover
    // and click can find it. Inner links inside
    // the seat's own text still win over it.
    // The paint & motion set (0.27): the container's
    // shadows, paint transform and opacity — its seat's
    // surface reads the stamps for the shadow; the item
    // and content painters wrap in the transform and
    // opacity so the whole container moves together.
    var boxShadows: TBBoxShadowSet? = nil
    var containerLink: String? = nil
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
    // The small completions (0.30): the auto-flow
    // reading — column flow (items fill down a
    // column before marching to the next) and dense
    // packing (the placement cursor restarts at the
    // first cell for every item, backfilling the
    // holes the sparse cursor steps over) — and the
    // names: both templates' bracketed line names by
    // 1-based line index, and the
    // grid-template-areas map, each area name to its
    // rectangle of lines (1-based, end lines one
    // past the last cell), that grid-area: <name>
    // and the named sides place by.
    var autoFlowColumn = false
    var autoFlowDense = false
    var columnLineNames: [Int: [String]] = [:]
    var rowLineNames: [Int: [String]] = [:]
    var templateAreas: [String: (rowStart: Int, colStart: Int,
                                 rowEnd: Int, colEnd: Int)] = [:]
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
// the explicit grid), a span, a name (0.30 — the
// name and the count of the line bearing it, which
// dress resolves against the container's templates
// and areas), or nothing — auto.
enum TBGridSide {
    case line(Int)
    case span(Int)
    case name(String, Int)
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
    // The cache (0.32): sheets come through the
    // shared cached GET, like everything fetched.
    // Other addresses keep the plain path below.
    if let scheme = url.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
        guard let got = await tbGETWithCache(
            urlString: urlString, accept: "text/css,*/*",
            pageURLString: pageURLString) else { return nil }
        return String(data: got.data, encoding: .utf8)
            ?? String(decoding: got.data, as: UTF8.self)
    }
    var request = URLRequest(url: url)
    request.setValue("ChirpyBrowser/0.37.3.1 (Swift; our own engine)",
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

// MARK: - JavaScript (0.33-0.39) - lives in ChirpyJS.swift
//
// The interpreter moved to its own file in
// 0.39.1 - the split's first step, at Tyler's
// direction. Everything that stood here under
// the old mark - the values, the lexer, the
// parser, the evaluator, the page bridge, and
// the console's road in - now stands in
// ChirpyJS.swift, word for word: the runner
// and the session it keeps, the console's
// outcome and its road in, and every TBJS*
// and tbJS* declaration with them, the script
// collectors among them. The interpreter
// header there points back the other way.


// The Inspector's report for one element
// (0.35): the declarations this engine
// resolved for it — read from the very
// renderer that painted the page — and the
// rules that match it, in cascade order, so a
// wrong look can be traced to the rule that
// caused it. The resolved list is the final
// word; the rules are the evidence under it.
func tbInspectorReport(session: TBPageSession, node: TBNode) -> String {
    guard let renderer = session.renderer else {
        return "The page's renderer is not at hand."
    }
    var lines: [String] = []
    let resolved = renderer.resolvedStyle(node: node)
    lines.append("Resolved style — what the engine painted:")
    if resolved.isEmpty {
        lines.append("  (no declarations — the element wears the defaults)")
    } else {
        for name in resolved.keys.sorted() {
            lines.append("  " + name + ": " + (resolved[name] ?? ""))
        }
    }
    if let inline = node.attrs["style"], !inline.isEmpty {
        lines.append("")
        lines.append("Inline style attribute:")
        lines.append("  " + inline)
    }
    var matched: [(order: Int, declarations: [String: String])] = []
    for rule in renderer.rules
    where tbSelectorMatches(rule.selector, node: node) {
        matched.append((order: rule.order,
                        declarations: rule.declarations))
    }
    lines.append("")
    if matched.isEmpty {
        lines.append("No stylesheet rules match this element.")
    } else {
        lines.append("Rules that match, in cascade order:")
        for entry in matched {
            let body = entry.declarations.keys.sorted()
                .map { $0 + ": " + (entry.declarations[$0] ?? "") }
                .joined(separator: "; ")
            lines.append("  Rule #\(entry.order): " + body)
        }
    }
    return lines.joined(separator: "\n")
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
    // The matcher memo (0.37.3): the facts a compound
    // match derives about this element — its class list
    // as a set, and its place among its element
    // siblings — derived once and read by every match
    // thereafter. Before, each of the walk's millions
    // of matches re-derived them: the class attribute
    // re-split (12.88 million times on the measured
    // article), the sibling list re-filtered. A node
    // never stamped derives them on the spot, exactly
    // as before, so an unstamped tree matches the same;
    // a stamped one reads the same values from here.
    var matchClassSet: Set<String>? = nil
    var matchSiblingIndex: Int = -1   // 0-based among element siblings; -1 = derive
    var matchSiblingCount: Int = -1
    var matchTypeIndex: Int = -1      // 0-based among same-tag siblings
    var matchTypeCount: Int = -1
    init(tag: String, text: String = "") {
        self.tag = tag
        self.text = text
    }
}

let TBVoidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr",
                               "img", "input", "link", "meta", "param",
                               "source", "track", "wbr"]
let TBSkipTags: Set<String> = ["noscript", "template",
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
            if lname == "textarea" && !selfClosing {
                // Raw-text element (0.31), the way
                // <style> is read above: everything
                // up to </textarea is the control's
                // seed, kept undecoded as a single
                // text child — markup inside a seed
                // cannot bend the tree, and the
                // renderer decodes the entities once
                // as it reads the seed.
                let closeStart = findCloseTag("textarea", from: i)
                let rawEnd = closeStart >= 0 ? closeStart : n
                if rawEnd > i {
                    let textNode = TBNode(tag: "#text",
                                          text: String(chars[i..<rawEnd]))
                    textNode.parent = node
                    node.children.append(textNode)
                }
                i = closeStart >= 0 ? afterTag(closeStart) : n
                continue
            }
            if lname == "script" && !selfClosing {
                // Raw-text element (0.33), read the
                // way <style> and <textarea> are: the
                // code up to </script is kept
                // undecoded as a single text child,
                // and the node above carries the
                // attributes (src among them), so
                // the JavaScript first slice can
                // find every script in document
                // order and run it after the parse.
                // The render walk skips script
                // nodes, as it always has.
                let closeStart = findCloseTag("script", from: i)
                let rawEnd = closeStart >= 0 ? closeStart : n
                if rawEnd > i {
                    let textNode = TBNode(tag: "#text",
                                          text: String(chars[i..<rawEnd]))
                    textNode.parent = node
                    node.children.append(textNode)
                }
                i = closeStart >= 0 ? afterTag(closeStart) : n
                continue
            }
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
    // The matcher memo (0.37.3): stamp the tree's
    // per-element match facts before it is handed
    // out — see tbStampMatchFacts.
    tbStampMatchFacts(root)
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

// MARK: - CSS - lives in ChirpyCSS.swift

// The style system stood here - the CSS,
// CSS variables, Colors, and Font helpers
// sections - from the engine's first CSS
// until 0.39.3, when it moved into
// ChirpyCSS.swift, whole and word for word:
// the selectors and their matching, the
// cascade, the variables, the colors, and
// the font helpers. The split's third step
// - see ChirpyCSS.swift.

// MARK: - Layout (step one) - lives in ChirpyLayout.swift

// The layout helpers stood here - the box
// values, length values, fixed caps, and
// block metrics - from layout's first step
// until 0.39.4, when they moved into
// ChirpyLayout.swift, whole and word for
// word. The split's fourth step - see
// ChirpyLayout.swift.

// MARK: - Render - lives in ChirpyRenderer.swift

// The render core stood here - the tag
// sets and the base styles, the form
// controls and their attachments, the
// form specs, TBRenderer itself with its
// stored state, its style resolutions
// and its forms, the send-on helpers, and
// the page pipeline (tbRenderPage and
// tbRepaintPage) - from the first paint
// until 0.39.6, when it moved into
// ChirpyRenderer.swift, whole and word
// for word. The split's sixth step, and
// its last - see ChirpyRenderer.swift.
