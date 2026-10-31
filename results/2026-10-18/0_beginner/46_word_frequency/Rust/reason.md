# Task B selection: 46_word_frequency / Rust

## Common answer requirements

Identify case normalization and source word counts; explain descending-frequency then ascending-word tie ordering before top-five selection; choose a tied pair, derive counts from supplied text, and establish which is first.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The source text contains bird in “A bird sang”, “the bird” after barked-at, and “the bird flew away”:3 occurrences. Cat occurs in “The cat sat”, “the cat watched”, and “The cat slept”:also3. After case normalization and alphabetic-word tokenization, these are distinct lowercase keys with equal counts. Frequency is the primary descending key and word spelling is the ascending secondary key, so bird precedes cat. Sorting/tie resolution happens before taking the first5. Lowercasing also combines Dog with dog and The with the rather than creating extra keys. A comparator returning zero on equal counts alone would not establish the required word order; the selected lexical tie rule (or stable grade of pre-sorted words) does.



Source: `main.rs`. Selected original lines: 2,3,4,5,6,7,8,9,10,11,12,13. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L2: `    let text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `    let mut counts = std::collections::BTreeMap::new();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `    let lower = text.to_ascii_lowercase();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    for w in lower` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        .split(|c: char| !c.is_ascii_alphabetic())` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `        .filter(|w| !w.is_empty())` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `    {` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L9: `        *counts.entry(w).or_default() += 1;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L11: `    let mut entries: Vec<(&str, i32)> = counts.into_iter().collect();` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    entries.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    for (w, c) in entries.iter().take(5) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **330 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **387 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L2: 216 tokens (versus 330); removes `let text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";`.
- Without L3: 308 tokens (versus 330); removes `let mut counts = std::collections::BTreeMap::new();`.
- Without L4: 312 tokens (versus 330); removes `let lower = text.to_ascii_lowercase();`.
- Without L5: 321 tokens (versus 330); removes `for w in lower`.
- Without L6: 306 tokens (versus 330); removes `.split(|c: char| !c.is_ascii_alphabetic())`.
- Without L7: 311 tokens (versus 330); removes `.filter(|w| !w.is_empty())`.
- Without L8: 327 tokens (versus 330); removes `{`.
- Without L9: 309 tokens (versus 330); removes `*counts.entry(w).or_default() += 1;`.
- Without L10: 327 tokens (versus 330); removes `}`.
- Without L11: 296 tokens (versus 330); removes `let mut entries: Vec<(&str, i32)> = counts.into_iter().collect();`.
- Without L12: 292 tokens (versus 330); removes `entries.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));`.
- Without L13: 305 tokens (versus 330); removes `for (w, c) in entries.iter().take(5) {`.
