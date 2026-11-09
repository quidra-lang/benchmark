# Task B selection — Dart

## Answer requirements shared across languages

1. Trace one valid document whose TOC precedes headings, whose explicit heading ID occupies an automatic candidate, and which contains a nested heading, from block and inline parsing to HTML output.
2. Show when IDs are reserved, how automatic suffixes avoid used IDs, and how recorded heading IDs determine TOC links and nesting.
3. Explain the deferred TOC replacement that resolves forward references and distinguish raw heading text, explicit-ID-stripped text, rendered inline HTML, and tag-stripped TOC labels.

## Selected source locations

- `main.dart`: 1, 5, 7, 8, 9, 45, 46, 47, 48, 49, 52, 55, 56, 57, 58, 66, 67, 68, 69, 70, 71, 72, 73, 74, 105, 106, 107, 134, 135, 136, 137, 138, 139, 149, 162, 163, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 212, 213, 214, 215, 221, 222, 223, 224, 225, 226, 227, 255, 256, 259, 261, 262, 263, 264, 265, 266, 281, 282, 283, 284, 285, 286, 287, 288, 289, 301, 304, 305, 306, 307, 353, 354, 355, 356, 357, 419, 420, 421, 422, 423, 424, 425, 426, 429, 434, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 495, 496, 497, 499, 500, 501, 502, 503, 504, 505, 506, 522, 523, 524, 525, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538

## Evidence and language semantics

Use [TOC], a blank line, # Parent {#foo}, a blank line, > ## Foo, then @@END@@. The TOC is recognized before either heading; the quoted line is stripped of > and recursively parsed as a level-2 heading. The explicit heading reserves foo and removes {#foo} from the display source. The nested automatic heading uses raw Foo to form foo, finds it occupied, then chooses and reserves foo-1. Ordinary inline characters are escaped and assembled into the heading HTML; tag stripping that rendered HTML supplies the TOC labels Parent and Foo. Automatic slugging receives raw heading source, before inline rendering. The same final IDs are recorded for both heading attributes and TOC links. The heading-level tree makes the level-2 Foo a child of level-1 Parent. The earlier TOC placeholder is replaced only after the heading traversal, so the leading nav links #foo and #foo-1 agree with h1 id=foo and the quoted h2 id=foo-1. Dart keeps mutable Set<String> and List<TocEntry> objects on one Renderer; recursive renderBlocks uses that same receiver. Block and Piece constructors make the raw text/level and ordinary inline-string path explicit. tableOfContents executes after renderBlocks in the document method, and replaceAll uses the recorded IDs rather than regenerating slugs. IDs are reserved during this render traversal; no separate reservation of future explicit IDs is asserted.

## Minimization and alternatives

Selected the ordinary-character inline path for this valid minimal witness. More elaborate emphasis, links, footnotes, tables, lists, code fences, other heading syntaxes, and error handling do not establish an additional answer requirement. Kept quote recursion, shared heading/ID state, suffix selection, label derivation, TOC tree construction, and deferred insertion: dropping any of these loses one part of the requested trace. A witness with only top-level headings would shorten the excerpt but would not demonstrate nested-block collection. An allocation-only excerpt loses forward references and raw-versus-rendered provenance. Every selected source line was considered individually; the assembled excerpt was separately reviewed against the witness. Imports and structural delimiters are retained only when needed to identify the selected state or path. No program was executed.

The excerpt contains 2710 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
