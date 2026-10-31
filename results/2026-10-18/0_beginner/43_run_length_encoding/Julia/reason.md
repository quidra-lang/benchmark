# Task B selection: 43_run_length_encoding / Julia

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.



Source: `main.jl`. Selected original lines: 1-2,4-6,9,11,16-17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `encode(source) =` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `    join(string(length(m.match), first(m.match)) for m in eachmatch(r"([A-Z])\1*", source))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `decode(encoded) = replace(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    encoded,` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    r"[0-9]+[A-Z]" => run -> repeat(string(run[end]), parse(Int, run[1:(end-1)])),` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `for source in [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `    encoded = encode(source)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    println(source, " -> ", encoded, " -> ", decode(encoded))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **174 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **206 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 167 tokens (versus 174); removes `encode(source) =`.
- Without L2: 126 tokens (versus 174); removes `join(string(length(m.match), first(m.match)) for m in eachmatch(r"([A-Z])\1*", source))`.
- Without L4: 164 tokens (versus 174); removes `decode(encoded) = replace(`.
- Without L5: 170 tokens (versus 174); removes `encoded,`.
- Without L6: 122 tokens (versus 174); removes `r"[0-9]+[A-Z]" => run -> repeat(string(run[end]), parse(Int, run[1:(end-1)])),`.
- Without L9: 166 tokens (versus 174); removes `for source in [`.
- Without L11: 168 tokens (versus 174); removes `"WWWWWWWWWWWWBWWWWWWWWWWWWBBB",`.
- Without L16: 164 tokens (versus 174); removes `encoded = encode(source)`.
- Without L17: 145 tokens (versus 174); removes `println(source, " -> ", encoded, " -> ", decode(encoded))`.
