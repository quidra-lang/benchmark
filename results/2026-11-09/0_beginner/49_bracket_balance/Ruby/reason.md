The plus sign is not an opening or closing bracket, so it reaches no stack action. It still occupies original zero-based character index 3 in "(a + b) * [c - d]" because the scan indexes the original string rather than a filtered bracket stream.

each_char.with_index supplies the original position. Opening membership and matching.key? classify only bracket characters; the selected end shows no fallback stack action.

The original scan/index binding and opening/closing tests establish that + is ignored without renumbering positions. Error summaries are unnecessary for this nonbracket path.
