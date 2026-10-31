# Task B selection: 43_run_length_encoding / Kotlin

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.



Source: `main.kt`. Selected original lines: 2-3,6-10. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    val values = listOf(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `        "AAABBBCCCD", "W".repeat(12) + "B" + "W".repeat(12) + "BBB", "ALGORITHM", "MISSISSIPPI",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    val runs = Regex("(.)\\1*")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `    val counts = Regex("(\\d+)([A-Z])")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    for (text in values) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        val encoded = runs.replace(text) { "${it.value.length}${it.value[0]}" }` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        val decoded = counts.replace(encoded) { it.groupValues[2].repeat(it.groupValues[1].toInt()) }` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **202 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **269 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 191 tokens (versus 202); removes `val values = listOf(`.
- Without L3: 150 tokens (versus 202); removes `"AAABBBCCCD", "W".repeat(12) + "B" + "W".repeat(12) + "BBB", "ALGORITHM", "MISSISSIPPI",`.
- Without L6: 182 tokens (versus 202); removes `val runs = Regex("(.)\\1*")`.
- Without L7: 176 tokens (versus 202); removes `val counts = Regex("(\\d+)([A-Z])")`.
- Without L8: 189 tokens (versus 202); removes `for (text in values) {`.
- Without L9: 163 tokens (versus 202); removes `val encoded = runs.replace(text) { "${it.value.length}${it.value[0]}" }`.
- Without L10: 161 tokens (versus 202); removes `val decoded = counts.replace(encoded) { it.groupValues[2].repeat(it.groupValues[1].toInt()) }`.
