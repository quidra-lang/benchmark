# Task B selection: 43_run_length_encoding / Swift

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.



Source: `main.swift`. Selected original lines: 1,3,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `let values = [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    String(repeating: "W", count: 12) + "B" + String(repeating: "W", count: 12) + "BBB",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `for text in values {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `    let chars = Array(text)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    var encoded = "", i = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    while i < chars.count {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        var j = i + 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        while j < chars.count && chars[j] == chars[i] { j += 1 }` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        encoded += String(j - i) + String(chars[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `        i = j` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `    let bytes = Array(encoded.utf8)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    var decoded = ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `    i = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `    while i < bytes.count {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        var count = 0` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `        while bytes[i] >= 48 && bytes[i] <= 57 {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `            count = count * 10 + Int(bytes[i]) - 48` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `            i += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L26: `        decoded += String(repeating: String(UnicodeScalar(bytes[i])), count: count)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L27: `        i += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.

## Minimization and semantics

The selected excerpt measures **361 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **452 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 353 tokens (versus 361); removes `let values = [`.
- Without L3: 311 tokens (versus 361); removes `String(repeating: "W", count: 12) + "B" + String(repeating: "W", count: 12) + "BBB",`.
- Without L8: 351 tokens (versus 361); removes `for text in values {`.
- Without L9: 349 tokens (versus 361); removes `let chars = Array(text)`.
- Without L10: 344 tokens (versus 361); removes `var encoded = "", i = 0`.
- Without L11: 348 tokens (versus 361); removes `while i < chars.count {`.
- Without L12: 347 tokens (versus 361); removes `var j = i + 1`.
- Without L13: 325 tokens (versus 361); removes `while j < chars.count && chars[j] == chars[i] { j += 1 }`.
- Without L14: 336 tokens (versus 361); removes `encoded += String(j - i) + String(chars[i])`.
- Without L15: 353 tokens (versus 361); removes `i = j`.
- Without L16: 358 tokens (versus 361); removes `}`.
- Without L17: 347 tokens (versus 361); removes `let bytes = Array(encoded.utf8)`.
- Without L18: 351 tokens (versus 361); removes `var decoded = ""`.
- Without L19: 354 tokens (versus 361); removes `i = 0`.
- Without L20: 348 tokens (versus 361); removes `while i < bytes.count {`.
- Without L21: 351 tokens (versus 361); removes `var count = 0`.
- Without L22: 333 tokens (versus 361); removes `while bytes[i] >= 48 && bytes[i] <= 57 {`.
- Without L23: 332 tokens (versus 361); removes `count = count * 10 + Int(bytes[i]) - 48`.
- Without L24: 352 tokens (versus 361); removes `i += 1`.
- Without L25: 357 tokens (versus 361); removes `}`.
- Without L26: 331 tokens (versus 361); removes `decoded += String(repeating: String(UnicodeScalar(bytes[i])), count: count)`.
- Without L27: 353 tokens (versus 361); removes `i += 1`.
- Without L28: 358 tokens (versus 361); removes `}`.
