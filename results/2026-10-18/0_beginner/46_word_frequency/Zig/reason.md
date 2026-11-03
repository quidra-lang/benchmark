# Task B selection: 46_word_frequency / Zig

## Common answer requirements

Identify case normalization and source word counts; explain descending-frequency then ascending-word tie ordering before top-five selection; choose a tied pair, derive counts from supplied text, and establish which is first.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The source text contains bird in “A bird sang”, “the bird” after barked-at, and “the bird flew away”:3 occurrences. Cat occurs in “The cat sat”, “the cat watched”, and “The cat slept”:also3. After case normalization and alphabetic-word tokenization, these are distinct lowercase keys with equal counts. Frequency is the primary descending key and word spelling is the ascending secondary key, so bird precedes cat. Sorting/tie resolution happens before taking the first5. Lowercasing also combines Dog with dog and The with the rather than creating extra keys. A comparator returning zero on equal counts alone would not establish the required word order; the selected lexical tie rule (or stable grade of pre-sorted words) does.

The user-defined less callback must be read: it compares count descending then std.mem.order(...)=.lt. std.mem.sort receives that callback, and the retained map-entry conversion connects its counts/words to the sorted entries.

Source: `main.zig`. Selected original lines: 5,6,13,14,15,16,18,19,20,21,22,23,24,26,27,28,29,30,31,32,33. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L5: `fn less(_: void, a: Entry, b: Entry) bool {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `    return if (a.count != b.count) a.count > b.count else std.mem.order(u8, a.word, b.word) == .lt;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    const text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    var lower: [text.len]u8 = undefined;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    _ = std.ascii.lowerString(&lower, text);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `    var counts: std.StringHashMapUnmanaged(u32) = .empty;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    var words = std.mem.tokenizeAny(u8, &lower, " ,.");` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `    while (words.next()) |word| {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `        const entry = try counts.getOrPut(std.heap.page_allocator, word);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        if (!entry.found_existing)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `            entry.value_ptr.* = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `        entry.value_ptr.* += 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L26: `    const len = counts.count();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L27: `    var iterator = counts.iterator();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `    var i: usize = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `    while (iterator.next()) |entry| : (i += 1) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L30: `        entries[i] = .{ .word = entry.key_ptr.*, .count = entry.value_ptr.* };` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L31: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L32: `    std.mem.sort(Entry, entries[0..len], {}, less);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L33: `    for (entries[0..5]) |entry|` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **523 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **769 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L5: 499 tokens (versus 523); removes `fn less(_: void, a: Entry, b: Entry) bool {`.
- Without L6: 469 tokens (versus 523); removes `return if (a.count != b.count) a.count > b.count else std.mem.order(u8, a.word, b.word) == .lt;`.
- Without L13: 409 tokens (versus 523); removes `const text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";`.
- Without L14: 505 tokens (versus 523); removes `var lower: [text.len]u8 = undefined;`.
- Without L15: 503 tokens (versus 523); removes `_ = std.ascii.lowerString(&lower, text);`.
- Without L16: 501 tokens (versus 523); removes `var counts: std.StringHashMapUnmanaged(u32) = .empty;`.
- Without L18: 495 tokens (versus 523); removes `var words = std.mem.tokenizeAny(u8, &lower, " ,.");`.
- Without L19: 506 tokens (versus 523); removes `while (words.next()) |word| {`.
- Without L20: 494 tokens (versus 523); removes `const entry = try counts.getOrPut(std.heap.page_allocator, word);`.
- Without L21: 510 tokens (versus 523); removes `if (!entry.found_existing)`.
- Without L22: 508 tokens (versus 523); removes `entry.value_ptr.* = 0;`.
- Without L23: 509 tokens (versus 523); removes `entry.value_ptr.* += 1;`.
- Without L24: 520 tokens (versus 523); removes `}`.
- Without L26: 509 tokens (versus 523); removes `const len = counts.count();`.
- Without L27: 509 tokens (versus 523); removes `var iterator = counts.iterator();`.
- Without L28: 511 tokens (versus 523); removes `var i: usize = 0;`.
- Without L29: 496 tokens (versus 523); removes `while (iterator.next()) |entry| : (i += 1) {`.
- Without L30: 483 tokens (versus 523); removes `entries[i] = .{ .word = entry.key_ptr.*, .count = entry.value_ptr.* };`.
- Without L31: 520 tokens (versus 523); removes `}`.
- Without L32: 497 tokens (versus 523); removes `std.mem.sort(Entry, entries[0..len], {}, less);`.
- Without L33: 507 tokens (versus 523); removes `for (entries[0..5]) |entry|`.
