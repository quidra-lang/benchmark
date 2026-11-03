# Task B selection: 81_lru_cache / Quidra

Identify the capacity-dependent change from three to four while preserving recency and all printed results.

Only the full-cache threshold is capacity-dependent. The cache is dynamic; its existing last-element removal, front insertion, counters and formatting already follow the actual cache state. Changing the threshold to four permits three-key misses to grow the cache and evicts only on four-key misses.

The retained condition locates the only required edit. The previous fixed eviction index and prefix length have been replaced by documented length-based collection operations, so they no longer require corresponding edits. Retaining unchanged recency or reporting operations would not identify another required modification.

Selected complete source lines in order: 15.

Every selected line is copied verbatim from `main.qui` in source order. The reviewed alternatives were the relevant contiguous span and complete source; each adds unchanged context. This is a reviewed sufficient selection, not a proof of a global minimum. Task B assumes Task A correctness as required by the benchmark README.

Task A uses 206 tokens. Task B uses 13 tokens under the unchanged `metric/tokenizer.py`. Source selection and token measurement do not establish compilation or execution.
