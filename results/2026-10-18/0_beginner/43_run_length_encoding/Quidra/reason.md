# Task B selection: 43_run_length_encoding / Quidra

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.



Source: `main.qui`. Selected original lines: 1-11,13-24,26-27,30-32. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `string encode(string text)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    string result = ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    int i = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    while i < int(len(text))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `        int end = i + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        while end < int(len(text)) and text[end] == text[i]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            end += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        int count = end - i` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        result += count.string() + text[i]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        i = end` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    return result` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `string decode(string encoded)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    string result = ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    int i = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `    while i < int(len(encoded))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        int count = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        while i < int(len(encoded)) and "0123456789".contains(encoded[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `            int digit = int.parse(encoded[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            count = count * 10 + digit` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `            i += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `        result += string.repeat(encoded[i], nat(count))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `        i += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `    return result` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `string[] values = [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L27: `    "AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L30: `for string value = values[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L31: `    string encoded = encode(value)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L32: `    print("{value} -> {encoded} -> {decode(encoded)}{NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **396 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **406 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 387 tokens (versus 396); removes `string encode(string text)`.
- Without L2: 386 tokens (versus 396); removes `string result = ""`.
- Without L3: 387 tokens (versus 396); removes `int i = 0`.
- Without L4: 381 tokens (versus 396); removes `while i < int(len(text))`.
- Without L5: 382 tokens (versus 396); removes `int end = i + 1`.
- Without L6: 366 tokens (versus 396); removes `while end < int(len(text)) and text[end] == text[i]`.
- Without L7: 387 tokens (versus 396); removes `end += 1`.
- Without L8: 382 tokens (versus 396); removes `int count = end - i`.
- Without L9: 377 tokens (versus 396); removes `result += count.string() + text[i]`.
- Without L10: 388 tokens (versus 396); removes `i = end`.
- Without L11: 391 tokens (versus 396); removes `return result`.
- Without L13: 387 tokens (versus 396); removes `string decode(string encoded)`.
- Without L14: 386 tokens (versus 396); removes `string result = ""`.
- Without L15: 387 tokens (versus 396); removes `int i = 0`.
- Without L16: 381 tokens (versus 396); removes `while i < int(len(encoded))`.
- Without L17: 386 tokens (versus 396); removes `int count = 0`.
- Without L18: 357 tokens (versus 396); removes `while i < int(len(encoded)) and "0123456789".contains(encoded[i])`.
- Without L19: 377 tokens (versus 396); removes `int digit = int.parse(encoded[i])`.
- Without L20: 378 tokens (versus 396); removes `count = count * 10 + digit`.
- Without L21: 387 tokens (versus 396); removes `i += 1`.
- Without L22: 374 tokens (versus 396); removes `result += string.repeat(encoded[i], nat(count))`.
- Without L23: 388 tokens (versus 396); removes `i += 1`.
- Without L24: 391 tokens (versus 396); removes `return result`.
- Without L26: 387 tokens (versus 396); removes `string[] values = [`.
- Without L27: 375 tokens (versus 396); removes `"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",`.
- Without L30: 385 tokens (versus 396); removes `for string value = values[]`.
- Without L31: 384 tokens (versus 396); removes `string encoded = encode(value)`.
- Without L32: 368 tokens (versus 396); removes `print("{value} -> {encoded} -> {decode(encoded)}{NL}")`.
