# Task B selection — Lua

## Answer requirements shared across languages

1. Trace one valid document whose TOC precedes headings, whose explicit heading ID occupies an automatic candidate, and which contains a nested heading, from block and inline parsing to HTML output.
2. Show when IDs are reserved, how automatic suffixes avoid used IDs, and how recorded heading IDs determine TOC links and nesting.
3. Explain the deferred TOC replacement that resolves forward references and distinguish raw heading text, explicit-ID-stripped text, rendered inline HTML, and tag-stripped TOC labels.

## Selected source locations

- `main.lua`: 3, 4, 7, 8, 9, 10, 16, 17, 18, 20, 21, 22, 24, 25, 26, 92, 93, 94, 95, 96, 97, 98, 99, 144, 145, 174, 175, 176, 177, 178, 188, 189, 191, 202, 204, 205, 206, 207, 208, 209, 210, 211, 214, 249, 250, 251, 252, 260, 261, 262, 263, 264, 265, 266, 267, 268, 270, 271, 272, 273, 274, 293, 294, 295, 296, 297, 310, 311, 375, 376, 426, 427, 429, 430, 431, 432, 433, 434, 435, 436, 437, 439, 440, 441, 442, 443, 445, 446, 447, 448, 449, 450, 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 501, 502, 503, 512, 533, 534, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 547, 549, 550, 551, 552, 553, 554, 555, 556, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 589, 590, 592

## Evidence and language semantics

Use [TOC], a blank line, # Parent {#foo}, a blank line, > ## Foo, then @@END@@. The TOC is recognized before either heading; the quoted line is stripped of > and recursively parsed as a level-2 heading. The explicit heading reserves foo and removes {#foo} from the display source. The nested automatic heading uses raw Foo to form foo, finds it occupied, then chooses and reserves foo-1. Ordinary inline characters are escaped and assembled into the heading HTML; tag stripping that rendered HTML supplies the TOC labels Parent and Foo. Automatic slugging receives raw heading source, before inline rendering. The same final IDs are recorded for both heading attributes and TOC links. The heading-level tree makes the level-2 Foo a child of level-1 Parent. The earlier TOC placeholder is replaced only after the heading traversal, so the leading nav links #foo and #foo-1 agree with h1 id=foo and the quoted h2 id=foo-1. Lua metatable __index and colon calls bind the same renderer table as self. ipairs and append-by-# preserve traversal order; the used_ids table maps reserved ID strings to true, and an absent key is nil/false in the suffix loop. Heading and child tables are reference values, so placing the same heading in parents and siblings preserves nesting. main creates all state empty, renders the full body, builds toc, then performs a plain-text marker search and splice. IDs are reserved on encounter; no pre-reservation of later explicit IDs is assumed.

## Minimization and alternatives

Selected the ordinary-character inline path for this valid minimal witness. More elaborate emphasis, links, footnotes, tables, lists, code fences, other heading syntaxes, and error handling do not establish an additional answer requirement. Kept quote recursion, shared heading/ID state, suffix selection, label derivation, TOC tree construction, and deferred insertion: dropping any of these loses one part of the requested trace. A witness with only top-level headings would shorten the excerpt but would not demonstrate nested-block collection. An allocation-only excerpt loses forward references and raw-versus-rendered provenance. Every selected source line was considered individually; the assembled excerpt was separately reviewed against the witness. Imports and structural delimiters are retained only when needed to identify the selected state or path. No program was executed.

The excerpt contains 2783 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
