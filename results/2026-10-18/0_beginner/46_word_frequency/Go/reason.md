# Task B selection: 46_word_frequency / Go

## Common answer requirements

Identify case normalization and source word counts; explain descending-frequency then ascending-word tie ordering before top-five selection; choose a tied pair, derive counts from supplied text, and establish which is first.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The source text contains bird in “A bird sang”, “the bird” after barked-at, and “the bird flew away”:3 occurrences. Cat occurs in “The cat sat”, “the cat watched”, and “The cat slept”:also3. After case normalization and alphabetic-word tokenization, these are distinct lowercase keys with equal counts. Frequency is the primary descending key and word spelling is the ascending secondary key, so bird precedes cat. Sorting/tie resolution happens before taking the first5. Lowercasing also combines Dog with dog and The with the rather than creating extra keys. A comparator returning zero on equal counts alone would not establish the required word order; the selected lexical tie rule (or stable grade of pre-sorted words) does.



Source: `main.go`. Selected original lines: 10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L10: `	text := "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `	words := strings.FieldsFunc(strings.ToLower(text), func(c rune) bool {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `		return c < 'a' || c > 'z'` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `	})` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `	counts := map[string]int{}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `	for _, w := range words {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `		counts[w]++` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `	}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L18: `	entries := []string{}` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `	for w := range counts {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `		entries = append(entries, w)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `	}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L22: `	sort.Slice(entries, func(i, j int) bool {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `		a, b := entries[i], entries[j]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `		if counts[a] != counts[b] {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `			return counts[a] > counts[b]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `		}` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L27: `		return a < b` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `	})` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `	for _, w := range entries[:5] {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **361 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **451 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L10: 250 tokens (versus 361); removes `text := "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."`.
- Without L11: 331 tokens (versus 361); removes `words := strings.FieldsFunc(strings.ToLower(text), func(c rune) bool {`.
- Without L12: 339 tokens (versus 361); removes `return c < 'a' || c > 'z'`.
- Without L13: 357 tokens (versus 361); removes `})`.
- Without L14: 348 tokens (versus 361); removes `counts := map[string]int{}`.
- Without L15: 345 tokens (versus 361); removes `for _, w := range words {`.
- Without L16: 353 tokens (versus 361); removes `counts[w]++`.
- Without L17: 358 tokens (versus 361); removes `}`.
- Without L18: 351 tokens (versus 361); removes `entries := []string{}`.
- Without L19: 348 tokens (versus 361); removes `for w := range counts {`.
- Without L20: 347 tokens (versus 361); removes `entries = append(entries, w)`.
- Without L21: 358 tokens (versus 361); removes `}`.
- Without L22: 339 tokens (versus 361); removes `sort.Slice(entries, func(i, j int) bool {`.
- Without L23: 341 tokens (versus 361); removes `a, b := entries[i], entries[j]`.
- Without L24: 343 tokens (versus 361); removes `if counts[a] != counts[b] {`.
- Without L25: 344 tokens (versus 361); removes `return counts[a] > counts[b]`.
- Without L26: 357 tokens (versus 361); removes `}`.
- Without L27: 351 tokens (versus 361); removes `return a < b`.
- Without L28: 357 tokens (versus 361); removes `})`.
- Without L29: 342 tokens (versus 361); removes `for _, w := range entries[:5] {`.
