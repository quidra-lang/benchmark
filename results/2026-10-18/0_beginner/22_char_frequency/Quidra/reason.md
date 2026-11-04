# Task B selection: 22_char_frequency / Quidra

The qualified text.ascii_words call filters to ASCII letters and currently folds case. Disable ignore_case, leaving the joins and character split to supply distinct original-case keys to collections frequencies. sorted_entries enumerates present keys by their ASCII order, so capitals precede lowercase; println keeps the label and count format.

Complete main.qui lines: 1, 5, 6, 7, 8. The explicit text namespace already identifies that API; the collections import binds the unqualified frequencies extension. The sentence and import of an already identified namespace do not supply needed change evidence. The benchmark tokenizer counts 81 tokens in this excerpt.

Measurement: Task A 109; Task B 81. Tokenizer: metric/tokenizer.py, unchanged.
