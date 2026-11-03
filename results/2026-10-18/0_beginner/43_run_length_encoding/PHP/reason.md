# Task B selection: 43_run_length_encoding / PHP

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.



Source: `main.php`. Selected original lines: 3,5,8,10,13-14,17-19. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L3: `function encode(string $source): string` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    return preg_replace_callback('/([A-Z])\1*/', fn($run) => strlen($run[0]) . $run[1], $source);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `function decode(string $encoded): string` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    return preg_replace_callback('/([0-9]+)([A-Z])/', fn($run) => str_repeat($run[2], (int) $run[1]), $encoded);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `$sources = [` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    'AAABBBCCCD', 'WWWWWWWWWWWWBWWWWWWWWWWWWBBB', 'ALGORITHM', 'MISSISSIPPI',` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `foreach ($sources as $source) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    $encoded = encode($source);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `    printf("%s -> %s -> %s\n", $source, $encoded, decode($encoded));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **240 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **266 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L3: 227 tokens (versus 240); removes `function encode(string $source): string`.
- Without L5: 184 tokens (versus 240); removes `return preg_replace_callback('/([A-Z])\1*/', fn($run) => strlen($run[0]) . $run[1], $source);`.
- Without L8: 227 tokens (versus 240); removes `function decode(string $encoded): string`.
- Without L10: 174 tokens (versus 240); removes `return preg_replace_callback('/([0-9]+)([A-Z])/', fn($run) => str_repeat($run[2], (int) $run[1]), $encoded);`.
- Without L13: 233 tokens (versus 240); removes `$sources = [`.
- Without L14: 219 tokens (versus 240); removes `'AAABBBCCCD', 'WWWWWWWWWWWWBWWWWWWWWWWWWBBB', 'ALGORITHM', 'MISSISSIPPI',`.
- Without L17: 226 tokens (versus 240); removes `foreach ($sources as $source) {`.
- Without L18: 227 tokens (versus 240); removes `$encoded = encode($source);`.
- Without L19: 203 tokens (versus 240); removes `printf("%s -> %s -> %s\n", $source, $encoded, decode($encoded));`.
