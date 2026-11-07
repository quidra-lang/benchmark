Whitespace splitting keeps "names," as one six-character token, including its comma. Greedy packing accepts a word only while character lengths plus mandatory gaps fit width 30. For a nonfinal line with at least two words, total spaces=30-letter_count and gaps=word_count-1; each gap gets the quotient and the earliest remainder gaps get one extra space. Framing bars are outside those thirty characters.

The named width is used by packing, ljust and divmod. Final/single-word lines use single-space join then ljust; other lines start from words[0] and append distributed spaces and subsequent words.

Tokenization, greedy width check, letter/gap counts, quotient/remainder distribution and frame output establish punctuation and spaces. A generic formatter body cannot substitute for the actual remainder policy.
