# Task B selection: 46_word_frequency / C

## Common answer requirements

Identify case normalization and source word counts; explain descending-frequency then ascending-word tie ordering before top-five selection; choose a tied pair, derive counts from supplied text, and establish which is first.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The source text contains bird in “A bird sang”, “the bird” after barked-at, and “the bird flew away”:3 occurrences. Cat occurs in “The cat sat”, “the cat watched”, and “The cat slept”:also3. After case normalization and alphabetic-word tokenization, these are distinct lowercase keys with equal counts. Frequency is the primary descending key and word spelling is the ascending secondary key, so bird precedes cat. Sorting/tie resolution happens before taking the first5. Lowercasing also combines Dog with dog and The with the rather than creating extra keys. A comparator returning zero on equal counts alone would not establish the required word order; the selected lexical tie rule (or stable grade of pre-sorted words) does.

The compare callback returns descending count difference or strcmp on the words. qsort’s call ties that callback to entries; no stability assumption is needed because strcmp resolves distinct tied words.

Source: `main.c`. Selected original lines: 11,12,13,14,15,19,20,21,22,23,25,26,27,28,29,30,31,32,33,34,35,36,37. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L11: `int compare(const void *a, const void *b) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `    const Entry *x = a, *y = b;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    if (x->count != y->count)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        return y->count - x->count;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `    return strcmp(x->word, y->word);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `    char text[] = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `    for (int i = 0; text[i]; i++) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        unsigned char c = (unsigned char)text[i];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `        text[i] = isalpha(c) ? (char)tolower(c) : ' ';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L25: `    int count = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `    for (char *w = strtok(text, " "); w; w = strtok(NULL, " ")) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L27: `        int j = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `        while (j < count && strcmp(entries[j].word, w))` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `            j++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L30: `        if (j == count) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L31: `            entries[count].word = w;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L32: `            entries[count++].count = 0;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L33: `        }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L34: `        entries[j].count++;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L35: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L36: `    qsort(entries, count, sizeof(Entry), compare);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L37: `    for (int i = 0; i < 5; i++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **483 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **625 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L11: 461 tokens (versus 483); removes `int compare(const void *a, const void *b) {`.
- Without L12: 462 tokens (versus 483); removes `const Entry *x = a, *y = b;`.
- Without L13: 468 tokens (versus 483); removes `if (x->count != y->count)`.
- Without L14: 468 tokens (versus 483); removes `return y->count - x->count;`.
- Without L15: 467 tokens (versus 483); removes `return strcmp(x->word, y->word);`.
- Without L19: 368 tokens (versus 483); removes `char text[] = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";`.
- Without L20: 458 tokens (versus 483); removes `for (int i = 0; text[i]; i++) {`.
- Without L21: 462 tokens (versus 483); removes `unsigned char c = (unsigned char)text[i];`.
- Without L22: 452 tokens (versus 483); removes `text[i] = isalpha(c) ? (char)tolower(c) : ' ';`.
- Without L23: 480 tokens (versus 483); removes `}`.
- Without L25: 473 tokens (versus 483); removes `int count = 0;`.
- Without L26: 441 tokens (versus 483); removes `for (char *w = strtok(text, " "); w; w = strtok(NULL, " ")) {`.
- Without L27: 472 tokens (versus 483); removes `int j = 0;`.
- Without L28: 457 tokens (versus 483); removes `while (j < count && strcmp(entries[j].word, w))`.
- Without L29: 476 tokens (versus 483); removes `j++;`.
- Without L30: 469 tokens (versus 483); removes `if (j == count) {`.
- Without L31: 469 tokens (versus 483); removes `entries[count].word = w;`.
- Without L32: 468 tokens (versus 483); removes `entries[count++].count = 0;`.
- Without L33: 479 tokens (versus 483); removes `}`.
- Without L34: 473 tokens (versus 483); removes `entries[j].count++;`.
- Without L35: 480 tokens (versus 483); removes `}`.
- Without L36: 464 tokens (versus 483); removes `qsort(entries, count, sizeof(Entry), compare);`.
- Without L37: 459 tokens (versus 483); removes `for (int i = 0; i < 5; i++)`.
