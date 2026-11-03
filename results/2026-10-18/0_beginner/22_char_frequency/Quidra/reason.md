# Task B selection: 22_char_frequency / Quidra

## Answer and source dependencies

Change `ignore_case = true` to false so ASCII uppercase letters retain their case before frequencies are counted. `ascii_words` still excludes all characters outside A-Z and a-z. The frequency map holds uppercase and lowercase strings as separate keys. Sorting its entries by their string keys puts ASCII A-Z before a-z; iterating only existing entries suppresses absent letters. The same lowercase-or-uppercase letter binding and count feed the unchanged colon-space-count line.

## Selected evidence

Source: `main.qui`. Complete main.qui source lines: 5, 6, 7, 8.
Every selected line is a complete verbatim source line in source order.

The extraction/normalization line establishes both the unchanged ASCII filter and the switch that must change. Frequency construction shows independent counts by character value. The sorted-entry loop establishes output order and existing-key-only output; its print line preserves case and the output format.

## Semantics and minimization

The excerpt retains the operations needed to support this Task B answer. Imports, unrelated input values, headings and unchanged setup are omitted where they do not establish an answer dependency. Standard library operations use their documented semantics; their implementations do not need to be included. Evidence fragments need not compile independently. This is a dependency-based selection, not a claim of globally minimal token count.
