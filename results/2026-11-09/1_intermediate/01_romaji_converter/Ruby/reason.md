# Task B selection — Ruby

## Answer requirements shared across languages

1. Recognize CONVERT with source HEPBURN, target NIHON and text ji.
2. Trace the input-spelling lookup and equal-spelling tie resolution to the mora value and its source column.
3. Trace target spelling lookup and rendering to the final result zi under the initial case setting.

## Selected source locations

- `main.rb`: 5, 7, 13, 14, 18, 20, 38, 39, 51, 52, 53, 54, 55, 56, 57, 58, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 92, 93, 94, 95, 96, 97, 106, 107, 110, 111, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 148, 150, 151, 152, 153, 154, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 192, 193, 209, 212, 213, 214, 218, 232, 233, 258, 259, 260, 261, 262, 264, 265, 266, 267, 271, 272, 273, 367, 368, 370, 371, 372, 373, 378, 379, 380, 381, 382, 383, 384, 385, 386, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 424, 444, 445, 446, 449, 450, 451, 452, 453, 456, 457, 458, 459, 464, 465, 466

## Evidence and language semantics

CONVERT has two recognized systems and text ji. ROW_DATA and @table order place zi before di; HEPBURN maps both to ji. entries Hash assigns only absent spellings, so zi wins before length sorting. match_at returns the ji/zi pair and parse_word constructs {id:zi,column:1}, advancing two characters. NIHON spelling returns zi unchanged. The sole non-long regular mora renders zi; initial CASE KEEP retains LOWER, and gsub with replace_words produces zi.

## Minimization and alternatives

Retain actual Hash insertion guard and ordered table, since the mapping alone would not establish which ji reading wins. Native Hash order, sorting, regex and string semantics need no implementations. Only the successful matching branch, one-mora long guards, ordinary spelling and lowercase result route are retained; special mora and other command bodies are excluded.

The excerpt contains 2059 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
