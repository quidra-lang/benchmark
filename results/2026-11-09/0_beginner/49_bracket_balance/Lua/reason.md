The plus sign is not an opening or closing bracket, so it reaches no stack action. It still occupies original zero-based character index 3 in "(a + b) * [c - d]" because the scan indexes the original string rather than a filtered bracket stream.

position visits every original string byte, c is its direct substring, and only matching[c] or the explicit closing-bracket branch acts. Lua physical position 4 corresponds to reported zero-based index 3.

The original scan/index binding and opening/closing tests establish that + is ignored without renumbering positions. Error summaries are unnecessary for this nonbracket path.
