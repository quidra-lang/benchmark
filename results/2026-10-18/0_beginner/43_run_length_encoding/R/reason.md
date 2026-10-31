# Task B selection: 43_run_length_encoding / R

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.

Standard rle groups consecutive equal characters. The decoder matches whole digit-plus-letter runs, separates the count and letter, parses as.integer and uses strrep.

Source: `main.R`. Selected original lines: 1-3,6-8,11-12,15-17. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `encode <- function(source) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `  runs <- rle(strsplit(source, "", fixed = TRUE)[[1]])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `  paste(paste0(runs$lengths, runs$values), collapse = "")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `decode <- function(encoded) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `  runs <- regmatches(encoded, gregexpr("[0-9]+[A-Z]", encoded))[[1]]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `  paste(strrep(sub("[0-9]+", "", runs), as.integer(sub("[A-Z]", "", runs))), collapse = "")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `sources <- c(` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `  "AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `for (source in sources) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `  encoded <- encode(source)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `  cat(sprintf("%s -> %s -> %s\n", source, encoded, decode(encoded)))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **251 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **266 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 240 tokens (versus 251); removes `encode <- function(source) {`.
- Without L2: 224 tokens (versus 251); removes `runs <- rle(strsplit(source, "", fixed = TRUE)[[1]])`.
- Without L3: 227 tokens (versus 251); removes `paste(paste0(runs$lengths, runs$values), collapse = "")`.
- Without L6: 240 tokens (versus 251); removes `decode <- function(encoded) {`.
- Without L7: 217 tokens (versus 251); removes `runs <- regmatches(encoded, gregexpr("[0-9]+[A-Z]", encoded))[[1]]`.
- Without L8: 193 tokens (versus 251); removes `paste(strrep(sub("[0-9]+", "", runs), as.integer(sub("[A-Z]", "", runs))), collapse = "")`.
- Without L11: 244 tokens (versus 251); removes `sources <- c(`.
- Without L12: 230 tokens (versus 251); removes `"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB", "ALGORITHM", "MISSISSIPPI",`.
- Without L15: 239 tokens (versus 251); removes `for (source in sources) {`.
- Without L16: 241 tokens (versus 251); removes `encoded <- encode(source)`.
- Without L17: 215 tokens (versus 251); removes `cat(sprintf("%s -> %s -> %s\n", source, encoded, decode(encoded)))`.
