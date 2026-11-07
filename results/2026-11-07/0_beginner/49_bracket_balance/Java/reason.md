# Task B selection: 49_bracket_balance / Java

The original-position scan includes every character. + is in neither opening-bracket text nor closing-bracket text, so both recognition tests fail and neither push nor pop runs; the scan still advances its original index. Positions are never filtered and renumbered; error positions use that same index.

The scan binding/access and both bracket-action branches establish the ignored-character path. Stack-mismatch validation and final result formatting add no evidence for classifying plus.

Selected complete source lines in `Main.java`: 12, 13, 14, 15, 16, 17, 22, 23, 24. Their original text, indentation and order are preserved. The excerpt uses the language's ordinary control flow, value types and the named standard-library operations; no library implementation source is required.
