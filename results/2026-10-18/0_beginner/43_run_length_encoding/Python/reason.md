# Task B selection: 43_run_length_encoding / Python

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.

itertools.groupby groups consecutive equal keys; re.findall with \d+ captures12 as one group, and char*int(count) expands it.

Source: `main.py`. Selected original lines: 4,6,11-14. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L4: `strings = [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `for text in strings:` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    encoded = "".join(f"{sum(1 for _ in run)}{char}" for char, run in groupby(text))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    decoded = "".join(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        char * int(count) for count, char in re.findall(r"(\d+)([A-Z])", encoded)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **122 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **187 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L4: 116 tokens (versus 122); removes `strings = [`.
- Without L6: 116 tokens (versus 122); removes `"WWWWWWWWWWWWBWWWWWWWWWWWWBBB",`.
- Without L11: 113 tokens (versus 122); removes `for text in strings:`.
- Without L12: 76 tokens (versus 122); removes `encoded = "".join(f"{sum(1 for _ in run)}{char}" for char, run in groupby(text))`.
- Without L13: 111 tokens (versus 122); removes `decoded = "".join(`.
- Without L14: 78 tokens (versus 122); removes `char * int(count) for count, char in re.findall(r"(\d+)([A-Z])", encoded)`.
