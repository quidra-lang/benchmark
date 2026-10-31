# Task B selection: 46_word_frequency / Quidra

## Common answer requirements

Identify case normalization and source word counts; explain descending-frequency then ascending-word tie ordering before top-five selection; choose a tied pair, derive counts from supplied text, and establish which is first.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The source text contains bird in “A bird sang”, “the bird” after barked-at, and “the bird flew away”:3 occurrences. Cat occurs in “The cat sat”, “the cat watched”, and “The cat slept”:also3. After case normalization and alphabetic-word tokenization, these are distinct lowercase keys with equal counts. Frequency is the primary descending key and word spelling is the ascending secondary key, so bird precedes cat. Sorting/tie resolution happens before taking the first5. Lowercasing also combines Dog with dog and The with the rather than creating extra keys. A comparator returning zero on equal counts alone would not establish the required word order; the selected lexical tie rule (or stable grade of pre-sorted words) does.

words is sorted alphabetically before repeated selection. The inner search replaces best only for strictly greater counts, so an equal-count later word cannot displace the alphabetically earlier candidate; used prevents reselection. This implicit tie mechanism needs all those dependencies.

Source: `main.qui`. Selected original lines: 1-29. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L1: `string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L2: `string alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L3: `string normalized = ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L4: `for nat i < len(text)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L5: `    match alphabet.find(text[i])` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L6: `        nat position` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L7: `            normalized += alphabet[position % 26]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L8: `        none` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L9: `            normalized += " "` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L10: `string[] tokens = normalized.split(" ")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `set.Set<string> distinct = set.Set<string>()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `for string word = tokens[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `    if word != ""` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `        .distinct.add(word)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L15: `string[] words = distinct.values().sorted()` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `int[] counts = array(len(words), fill = 0)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `for nat i < len(words)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `    for string word = tokens[]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `        if word == words[i]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `            counts[i] += 1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `bool[] used = array(len(words), fill = false)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `for 0 <= int rank < 5` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `    int best = -1` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L24: `    for nat i < len(words)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L25: `        if not used[i]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L26: `            if best == -1 or counts[i] > counts[best]` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L27: `                best = int(i)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L28: `    used[best] = true` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L29: `    print("{words[best]}: {counts[best]}{NL}")` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **495 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **515 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L1: 383 tokens (versus 495); removes `string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door."`.
- Without L2: 484 tokens (versus 495); removes `string alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"`.
- Without L3: 486 tokens (versus 495); removes `string normalized = ""`.
- Without L4: 482 tokens (versus 495); removes `for nat i < len(text)`.
- Without L5: 482 tokens (versus 495); removes `match alphabet.find(text[i])`.
- Without L6: 489 tokens (versus 495); removes `nat position`.
- Without L7: 478 tokens (versus 495); removes `normalized += alphabet[position % 26]`.
- Without L8: 491 tokens (versus 495); removes `none`.
- Without L9: 484 tokens (versus 495); removes `normalized += " "`.
- Without L10: 479 tokens (versus 495); removes `string[] tokens = normalized.split(" ")`.
- Without L11: 475 tokens (versus 495); removes `set.Set<string> distinct = set.Set<string>()`.
- Without L12: 484 tokens (versus 495); removes `for string word = tokens[]`.
- Without L13: 485 tokens (versus 495); removes `if word != ""`.
- Without L14: 485 tokens (versus 495); removes `.distinct.add(word)`.
- Without L15: 478 tokens (versus 495); removes `string[] words = distinct.values().sorted()`.
- Without L16: 473 tokens (versus 495); removes `int[] counts = array(len(words), fill = 0)`.
- Without L17: 482 tokens (versus 495); removes `for nat i < len(words)`.
- Without L18: 483 tokens (versus 495); removes `for string word = tokens[]`.
- Without L19: 482 tokens (versus 495); removes `if word == words[i]`.
- Without L20: 483 tokens (versus 495); removes `counts[i] += 1`.
- Without L21: 473 tokens (versus 495); removes `bool[] used = array(len(words), fill = false)`.
- Without L22: 481 tokens (versus 495); removes `for 0 <= int rank < 5`.
- Without L23: 485 tokens (versus 495); removes `int best = -1`.
- Without L24: 481 tokens (versus 495); removes `for nat i < len(words)`.
- Without L25: 484 tokens (versus 495); removes `if not used[i]`.
- Without L26: 469 tokens (versus 495); removes `if best == -1 or counts[i] > counts[best]`.
- Without L27: 482 tokens (versus 495); removes `best = int(i)`.
- Without L28: 485 tokens (versus 495); removes `used[best] = true`.
- Without L29: 472 tokens (versus 495); removes `print("{words[best]}: {counts[best]}{NL}")`.
