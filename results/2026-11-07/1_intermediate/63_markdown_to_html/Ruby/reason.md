# Task B selection — Ruby

## Answer requirements shared across languages

1. Trace one valid document whose TOC precedes headings, whose explicit heading ID occupies an automatic candidate, and which contains a nested heading, from block and inline parsing to HTML output.
2. Show when IDs are reserved, how automatic suffixes avoid used IDs, and how recorded heading IDs determine TOC links and nesting.
3. Explain the deferred TOC replacement that resolves forward references and distinguish raw heading text, explicit-ID-stripped text, rendered inline HTML, and tag-stripped TOC labels.

## Selected source locations

- `main.rb`: 4, 5, 7, 9, 10, 11, 12, 13, 42, 43, 44, 45, 46, 47, 48, 49, 50, 99, 100, 101, 102, 103, 104, 105, 106, 107, 131, 132, 133, 134, 135, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 196, 197, 198, 199, 210, 211, 212, 213, 286, 287, 288, 289, 290, 291, 292, 307, 308, 309, 310, 315, 316, 321, 322, 323, 324, 325, 416, 417, 418, 419, 420, 421, 422, 448, 449, 450, 451, 453, 454, 456, 458, 459, 460, 461, 463, 467, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585

## Evidence and language semantics

Use the document [TOC], a blank line, # Parent {#foo}, a blank line, > ## Foo, then @@END@@. The source reads input to the terminator, recognizes the TOC paragraph and ATX headings, removes the quote prefix, and recursively parses its level-2 heading. Rendering walks these blocks in order with one shared renderer. The TOC initially emits a sentinel rather than a prematurely computed list. Parent takes explicit ID foo, strips its suffix from display text, and reserves foo. The nested raw heading Foo automatically lowers to candidate foo; the occupied-ID loop chooses foo-1, reserves it and records the same ID used in its h2. Ordinary inline characters become escaped string pieces and are concatenated; their rendered HTML is used for heading content, while tag-stripping that HTML supplies TOC labels Parent and Foo. Slug generation uses raw heading source before inline rendering, not the label or HTML. The heading-level stack makes Foo a child of Parent, including when the heading is inside the quote. After all blocks have been rendered and collected, the TOC links #foo and #foo-1 are built from those stored IDs and replace the earlier marker. Output therefore contains a leading nav with nested ul links, h1 id=foo, and a blockquote containing h2 id=foo-1. Explicit IDs are reserved when encountered in render order; this does not imply a separate global prescan reserving future explicit IDs. Standard sequence iteration, mutable collection membership, string replacement and the shown escape/strip operations establish this trace.

## Minimization and alternatives

The smallest illustrative input uses ordinary alphabetic heading text and an explicit ID before the colliding automatic heading; unrelated inline/link/emphasis cases are not required. Kept the literal-character inline path and its string-piece assembly, rather than assuming the custom inline helper preserves text. Included quote recursion so the nested heading is evidenced both as a nested block and as a TOC child. Full parser, full inline renderer, list/table/footnote handlers, unused empty-TOC handling, and other heading syntaxes would add tokens without supporting an additional requirement. Selecting only heading allocation is smaller but loses forward TOC replacement and raw-versus-rendered provenance. A non-nested example would permit fewer lines but would fail the common requirements. Reviewed the selected excerpt independently against this concrete trace and removed unrelated branches and structural-only lines.

The excerpt contains 1911 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
