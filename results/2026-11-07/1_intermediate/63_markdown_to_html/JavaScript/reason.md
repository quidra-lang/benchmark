# Task B selection — JavaScript

## Answer requirements shared across languages

1. Trace one valid document whose TOC precedes headings, whose explicit heading ID occupies an automatic candidate, and which contains a nested heading, from block and inline parsing to HTML output.
2. Show when IDs are reserved, how automatic suffixes avoid used IDs, and how recorded heading IDs determine TOC links and nesting.
3. Explain the deferred TOC replacement that resolves forward references and distinguish raw heading text, explicit-ID-stripped text, rendered inline HTML, and tag-stripped TOC labels.

## Selected source locations

- `main.js`: 5, 6, 7, 8, 33, 34, 35, 36, 37, 38, 39, 40, 103, 104, 105, 106, 107, 108, 130, 131, 133, 134, 135, 136, 137, 138, 139, 177, 178, 179, 180, 187, 188, 189, 190, 191, 219, 220, 221, 222, 223, 239, 240, 241, 247, 248, 289, 290, 291, 292, 293, 345, 346, 347, 348, 349, 350, 351, 352, 355, 360, 376, 377, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 389, 390, 391, 415, 416, 417, 418, 421, 422, 423, 424, 425, 426, 427, 428, 445, 446, 447, 451, 452, 453, 454

## Evidence and language semantics

Use the document [TOC], a blank line, # Parent {#foo}, a blank line, > ## Foo, then @@END@@. The source reads input to the terminator, recognizes the TOC paragraph and ATX headings, removes the quote prefix, and recursively parses its level-2 heading. Rendering walks these blocks in order with one shared renderer. The TOC initially emits a sentinel rather than a prematurely computed list. Parent takes explicit ID foo, strips its suffix from display text, and reserves foo. The nested raw heading Foo automatically lowers to candidate foo; the occupied-ID loop chooses foo-1, reserves it and records the same ID used in its h2. Ordinary inline characters become escaped string pieces and are concatenated; their rendered HTML is used for heading content, while tag-stripping that HTML supplies TOC labels Parent and Foo. Slug generation uses raw heading source before inline rendering, not the label or HTML. The heading-level stack makes Foo a child of Parent, including when the heading is inside the quote. After all blocks have been rendered and collected, the TOC links #foo and #foo-1 are built from those stored IDs and replace the earlier marker. Output therefore contains a leading nav with nested ul links, h1 id=foo, and a blockquote containing h2 id=foo-1. Explicit IDs are reserved when encountered in render order; this does not imply a separate global prescan reserving future explicit IDs. Standard sequence iteration, mutable collection membership, string replacement and the shown escape/strip operations establish this trace.

## Minimization and alternatives

The smallest illustrative input uses ordinary alphabetic heading text and an explicit ID before the colliding automatic heading; unrelated inline/link/emphasis cases are not required. Kept the literal-character inline path and its string-piece assembly, rather than assuming the custom inline helper preserves text. Included quote recursion so the nested heading is evidenced both as a nested block and as a TOC child. Full parser, full inline renderer, list/table/footnote handlers, unused empty-TOC handling, and other heading syntaxes would add tokens without supporting an additional requirement. Selecting only heading allocation is smaller but loses forward TOC replacement and raw-versus-rendered provenance. A non-nested example would permit fewer lines but would fail the common requirements. Reviewed the selected excerpt independently against this concrete trace and removed unrelated branches and structural-only lines.

The excerpt contains 2151 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
