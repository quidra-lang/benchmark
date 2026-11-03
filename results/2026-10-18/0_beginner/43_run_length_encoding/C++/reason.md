# Task B selection: 43_run_length_encoding / C++

## Common answer requirements

Identify the second input, trace contiguous-run encoding of its separate twelve-W runs, explain decimal two-digit count parsing, and establish decoded reconstruction from encoded data.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The second input is W repeated12, then B, then W repeated12, then BBB. Its encoding is `12W1B12W3B`: the intervening B ends the first W run, so equal letters separated by that B never merge. Each encoder groups only adjacent equal characters and writes the decimal run length followed by the character. Each decoder consumes all consecutive digits (the accumulator 0→1→12 or a multi-digit regex/parse), then repeats the following letter that many times; this reconstructs both twelve-W runs separated by B. Decoding receives the encoded string and builds a new result from its counts/letters, not from the original input.

from_chars reads all digits and returns the first non-digit pointer; append(count,*next) reconstructs that run. p=next+1 advances to the next count.

Source: `main.cpp`. Selected original lines: 7,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L7: `    for (const std::string &s : std::array<std::string, 5>{"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `        std::string encoded, decoded;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `        for (std::size_t i = 0; i < s.size();) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `            std::size_t j = i + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `            while (j < s.size() && s[j] == s[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `                j++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `            encoded += std::to_string(j - i) + s[i];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `            i = j;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L17: `        const char *end = encoded.data() + encoded.size();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        for (const char *p = encoded.data(); p < end;) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `            int count = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            const char *next = std::from_chars(p, end, count).ptr;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `            decoded.append(count, *next);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `            p = next + 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.

## Minimization and semantics

The selected excerpt measures **314 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **418 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L7: 277 tokens (versus 314); removes `for (const std::string &s : std::array<std::string, 5>{"AAABBBCCCD", "WWWWWWWWWWWWBWWWWWWWWWWWWBBB",`.
- Without L9: 302 tokens (versus 314); removes `std::string encoded, decoded;`.
- Without L10: 282 tokens (versus 314); removes `for (std::size_t i = 0; i < s.size();) {`.
- Without L11: 294 tokens (versus 314); removes `std::size_t j = i + 1;`.
- Without L12: 283 tokens (versus 314); removes `while (j < s.size() && s[j] == s[i])`.
- Without L13: 306 tokens (versus 314); removes `j++;`.
- Without L14: 286 tokens (versus 314); removes `encoded += std::to_string(j - i) + s[i];`.
- Without L15: 304 tokens (versus 314); removes `i = j;`.
- Without L16: 310 tokens (versus 314); removes `}`.
- Without L17: 288 tokens (versus 314); removes `const char *end = encoded.data() + encoded.size();`.
- Without L18: 283 tokens (versus 314); removes `for (const char *p = encoded.data(); p < end;) {`.
- Without L19: 302 tokens (versus 314); removes `int count = 0;`.
- Without L20: 284 tokens (versus 314); removes `const char *next = std::from_chars(p, end, count).ptr;`.
- Without L21: 299 tokens (versus 314); removes `decoded.append(count, *next);`.
- Without L22: 300 tokens (versus 314); removes `p = next + 1;`.
- Without L23: 310 tokens (versus 314); removes `}`.
