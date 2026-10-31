# Task B selection: 43_run_length_encoding / Rust

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.

slice chunk_by compares adjacent bytes; split_inclusive at uppercase letters makes chunks such as12W, then split_at isolates the entire decimal prefix and parse/ repeat rebuild the run.

Source: `main.rs`. Selected original lines: 2,4,9-11,13-16. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    for s in [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `        "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        let mut encoded = String::new();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        for run in s.as_bytes().chunk_by(|a, b| a == b) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            encoded.push_str(&format!("{}{}", run.len(), run[0] as char));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        let mut decoded = String::new();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        for run in encoded.split_inclusive(|c: char| c.is_ascii_uppercase()) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            let (count, letter) = run.split_at(run.len() - 1);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `            decoded.push_str(&letter.repeat(count.parse::<usize>().unwrap()));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **223 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **308 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 214 tokens (versus 223); removes `for s in [`.
- Without L4: 216 tokens (versus 223); removes `"WWWWWWWWWWWWBWWWWWWWWWWWWBBB",`.
- Without L9: 206 tokens (versus 223); removes `let mut encoded = String::new();`.
- Without L10: 187 tokens (versus 223); removes `for run in s.as_bytes().chunk_by(|a, b| a == b) {`.
- Without L11: 183 tokens (versus 223); removes `encoded.push_str(&format!("{}{}", run.len(), run[0] as char));`.
- Without L13: 206 tokens (versus 223); removes `let mut decoded = String::new();`.
- Without L14: 189 tokens (versus 223); removes `for run in encoded.split_inclusive(|c: char| c.is_ascii_uppercase()) {`.
- Without L15: 191 tokens (versus 223); removes `let (count, letter) = run.split_at(run.len() - 1);`.
- Without L16: 192 tokens (versus 223); removes `decoded.push_str(&letter.repeat(count.parse::<usize>().unwrap()));`.
