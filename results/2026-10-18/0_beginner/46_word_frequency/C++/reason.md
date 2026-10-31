# Task B selection: 46_word_frequency / C++

## Common answer requirements

Identify case normalization and source word counts; explain descending-frequency then ascending-word tie ordering before top-five selection; choose a tied pair, derive counts from supplied text, and establish which is first.

These requirements were fixed for the topic before choosing the language-specific excerpts. Task B assumptions and the language specification/standard-library semantics are used; no Task A program was compiled or executed.

## Answer and source dependencies

The source text contains bird in “A bird sang”, “the bird” after barked-at, and “the bird flew away”:3 occurrences. Cat occurs in “The cat sat”, “the cat watched”, and “The cat slept”:also3. After case normalization and alphabetic-word tokenization, these are distinct lowercase keys with equal counts. Frequency is the primary descending key and word spelling is the ascending secondary key, so bird precedes cat. Sorting/tie resolution happens before taking the first5. Lowercasing also combines Dog with dog and The with the rather than creating extra keys. A comparator returning zero on equal counts alone would not establish the required word order; the selected lexical tie rule (or stable grade of pre-sorted words) does.



Source: `main.cpp`. Selected original lines: 10,11,12,13,14,15,16,17,18,19,20,21,22,23. The following line-by-line dependency record identifies the original statements retained (including unavoidable extra operations on a complete line):

- L10: `    std::string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L11: `    for (char &c : text) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L12: `        unsigned char letter = static_cast<unsigned char>(c);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L13: `        c = std::isalpha(letter) ? static_cast<char>(std::tolower(letter)) : ' ';` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L14: `    }` — This boundary fixes the surrounding control scope; it distinguishes the completed or alternative region from the following operations in the trace/change analysis.
- L15: `    std::map<std::string, int> counts;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L16: `    std::istringstream input(text);` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L17: `    for (std::string w; input >> w;)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L18: `        ++counts[w];` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L19: `    std::vector<std::pair<std::string, int>> entries(counts.begin(), counts.end());` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L20: `    std::sort(entries.begin(), entries.end(), [](const auto &a, const auto &b) {` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L21: `        return a.second != b.second ? a.second > b.second : a.first < b.first;` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L22: `    });` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.
- L23: `    for (int i = 0; i < 5; i++)` — This original statement supplies its explicit data, calculation, branch, mutation, or output operation to the concrete dependency chain above; that operation, rather than its variable/helper name alone, is the evidence retained.

## Minimization and semantics

The selected excerpt measures **391 tokens** with `metric/tokenizer.py` `tokenize`. The complete original source is a sufficient alternative of **519 tokens**; its extra declarations, program wrappers, unrelated cases, and setup are unnecessary for these answer requirements. Source order, indentation, and complete original lines are preserved. No location is repeated.

Each selected statement was reviewed against the answer dependencies above. Scope delimiters are retained where they establish a relevant branch/loop boundary (including completion before a following update or output). Other wrappers, imports, and standard I/O setup are omitted when they carry no needed behavior. Excerpts are evidence fragments and need not form a standalone compilable program. Standard arithmetic, indexing, iteration, collection operations, and formatting have their language/library meanings; implementations of standard operations do not need to be included. User-defined behavior is supported by its selected operations rather than inferred from a helper name.

The following smaller deletion candidates were measured as alternative line sets. They lose the indicated original statement and therefore the corresponding calculation/control/data/output evidence described above; a lower count alone is insufficient. This is a source-dependency minimization, not a proof of a global mathematical optimum.

- Without L10: 275 tokens (versus 391); removes `std::string text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";`.
- Without L11: 375 tokens (versus 391); removes `for (char &c : text) {`.
- Without L12: 368 tokens (versus 391); removes `unsigned char letter = static_cast<unsigned char>(c);`.
- Without L13: 354 tokens (versus 391); removes `c = std::isalpha(letter) ? static_cast<char>(std::tolower(letter)) : ' ';`.
- Without L14: 388 tokens (versus 391); removes `}`.
- Without L15: 375 tokens (versus 391); removes `std::map<std::string, int> counts;`.
- Without L16: 380 tokens (versus 391); removes `std::istringstream input(text);`.
- Without L17: 372 tokens (versus 391); removes `for (std::string w; input >> w;)`.
- Without L18: 382 tokens (versus 391); removes `++counts[w];`.
- Without L19: 357 tokens (versus 391); removes `std::vector<std::pair<std::string, int>> entries(counts.begin(), counts.end());`.
- Without L20: 352 tokens (versus 391); removes `std::sort(entries.begin(), entries.end(), [](const auto &a, const auto &b) {`.
- Without L21: 352 tokens (versus 391); removes `return a.second != b.second ? a.second > b.second : a.first < b.first;`.
- Without L22: 386 tokens (versus 391); removes `});`.
- Without L23: 367 tokens (versus 391); removes `for (int i = 0; i < 5; i++)`.
