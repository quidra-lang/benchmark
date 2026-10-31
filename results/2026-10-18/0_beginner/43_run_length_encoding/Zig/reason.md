# Task B selection: 43_run_length_encoding / Zig

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.

elen and dlen delimit the initialized portions of the buffers; the decimal accumulator reads both digits and @memset writes count copies into the new decoded buffer.

Source: `main.zig`. Selected original lines: 7,9,14,16,17,18,19,20,21,22,23,24,25,27,28,29,30,31,32,33,34,35,36,37. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    const strings = [_][]const u8{` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    for (strings) |s| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        var elen: usize = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `        var i: usize = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        while (i < s.len) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `            var end = i + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            while (end < s.len and s[end] == s[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `                end += 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `            const part = try std.fmt.bufPrint(encoded[elen..], "{d}{c}", .{ end - i, s[i] });` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `            elen += part.len;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `            i = end;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L27: `        var dlen: usize = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `        i = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `        while (i < elen) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L30: `            var count: usize = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L31: `            while (i < elen and std.ascii.isDigit(encoded[i])) : (i += 1)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L32: `                count = count * 10 + encoded[i] - '0';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L33: `            const c = encoded[i];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L34: `            i += 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L35: `            @memset(decoded[dlen..][0..count], c);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L36: `            dlen += count;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L37: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.

## Minimization and semantics

The selected excerpt measures **395 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **637 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 379 tokens (versus 395); removes `const strings = [_][]const u8{`.
- Without L9: 388 tokens (versus 395); removes `"WWWWWWWWWWWWBWWWWWWWWWWWWBBB",`.
- Without L14: 382 tokens (versus 395); removes `for (strings) |s| {`.
- Without L16: 381 tokens (versus 395); removes `var elen: usize = 0;`.
- Without L17: 382 tokens (versus 395); removes `var i: usize = 0;`.
- Without L18: 379 tokens (versus 395); removes `while (i < s.len) {`.
- Without L19: 379 tokens (versus 395); removes `var end = i + 1;`.
- Without L20: 366 tokens (versus 395); removes `while (end < s.len and s[end] == s[i])`.
- Without L21: 384 tokens (versus 395); removes `end += 1;`.
- Without L22: 341 tokens (versus 395); removes `const part = try std.fmt.bufPrint(encoded[elen..], "{d}{c}", .{ end - i, s[i] });`.
- Without L23: 383 tokens (versus 395); removes `elen += part.len;`.
- Without L24: 385 tokens (versus 395); removes `i = end;`.
- Without L25: 391 tokens (versus 395); removes `}`.
- Without L27: 381 tokens (versus 395); removes `var dlen: usize = 0;`.
- Without L28: 386 tokens (versus 395); removes `i = 0;`.
- Without L29: 381 tokens (versus 395); removes `while (i < elen) {`.
- Without L30: 380 tokens (versus 395); removes `var count: usize = 0;`.
- Without L31: 357 tokens (versus 395); removes `while (i < elen and std.ascii.isDigit(encoded[i])) : (i += 1)`.
- Without L32: 366 tokens (versus 395); removes `count = count * 10 + encoded[i] - '0';`.
- Without L33: 380 tokens (versus 395); removes `const c = encoded[i];`.
- Without L34: 385 tokens (versus 395); removes `i += 1;`.
- Without L35: 373 tokens (versus 395); removes `@memset(decoded[dlen..][0..count], c);`.
- Without L36: 385 tokens (versus 395); removes `dlen += count;`.
- Without L37: 391 tokens (versus 395); removes `}`.
