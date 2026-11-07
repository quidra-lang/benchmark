# Task B selection: 46_word_frequency / Swift

Trace normalized counting from the given passage, demonstrate an equal-frequency pair, and explain the tie rule applied before the first five entries are selected.

`bird` occurs three times, in the singing, barking and flying clauses. `cat` occurs three times, in the sitting, watching and sleeping clauses. The secondary ascending word key puts `bird` before `cat` on equal counts; the primary key is descending frequency. The prefix operation or five-entry loop runs after ordering. Lowercasing happens before counting, so the capitalized `Dog` occurrence joins the lowercase `dog` occurrences, giving four.

The passage, token boundaries, count data flow and comparison or documented sort keys are required. The output rendering and distinct-word summary do not affect which pair precedes the other. Standalone closing delimiters can be omitted when the data flow and block boundary remain clear.

Source: `main.swift`, original lines 1–4, 6–7. The previous excerpt measures 290 tokens; this evidence set measures 288 tokens.

## Current token measurement

Task A: **305 tokens**. Task B: **286 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
