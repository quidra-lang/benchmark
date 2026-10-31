# Task B selection: 46_word_frequency / C#

## Common answer requirements

Identify case normalization and source word counts; explain descending-frequency then ascending-word tie ordering before top-five selection; choose a tied pair, derive counts from supplied text, and establish which is first.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The source text contains bird in “A bird sang”, “the bird” after barked-at, and “the bird flew away”:3 occurrences. Cat occurs in “The cat sat”, “the cat watched”, and “The cat slept”:also3. After case normalization and alphabetic-word tokenization, these are distinct lowercase keys with equal counts. Frequency is the primary descending key and word spelling is the ascending secondary key, so bird precedes cat. Sorting/tie resolution happens before taking the first5. Lowercasing also combines Dog with dog and The with the rather than creating extra keys. A comparator returning zero on equal counts alone would not establish the required word order; the selected lexical tie rule (or stable grade of pre-sorted words) does.



Source: `Program.cs`. Selected original lines: 8-12. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L8: `string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `var counts = Regex.Matches(text.ToLowerInvariant(), "[a-z]+")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `    .GroupBy(m => m.Value)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    .ToDictionary(g => g.Key, g => g.Count());` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `foreach (var pair in counts.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).Take(5))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **230 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **320 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L8: 117 tokens (versus 230); removes `string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";`.
- Without L9: 201 tokens (versus 230); removes `var counts = Regex.Matches(text.ToLowerInvariant(), "[a-z]+")`.
- Without L10: 216 tokens (versus 230); removes `.GroupBy(m => m.Value)`.
- Without L11: 204 tokens (versus 230); removes `.ToDictionary(g => g.Key, g => g.Count());`.
- Without L12: 182 tokens (versus 230); removes `foreach (var pair in counts.OrderByDescending(p => p.Value).ThenBy(p => p.Key, StringComparer.Ordinal).Take(5))`.
