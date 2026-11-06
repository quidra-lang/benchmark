# Task B selection — 81_lru_cache / Quidra

The full-miss test is the only fixed capacity; change the length comparison to four. The dynamically sized array and tail/front operations do not encode a slot number. Hit refresh, access sequence, counts, and output do not require edits. Including those paths adds no further capacity dependency.

Selected complete source lines: 15.

With the benchmark tokenizer, this selection measures 14 tokens; the previous selection measured 60. The full source is 193 tokens.

The `:=` bindings infer their static types from their initializers under the current Core literal defaults.

Current measurement with unchanged `metric/tokenizer.py`: Task A 193; Task B 14.

Measurement: Task A 193; Task B 14. Tokenizer: metric/tokenizer.py, unchanged.
