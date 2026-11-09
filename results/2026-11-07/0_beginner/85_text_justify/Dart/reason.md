Whitespace splitting keeps "names," as one six-character token, including its comma. Greedy packing accepts a word only while character lengths plus mandatory gaps fit width 30. For a nonfinal line with at least two words, total spaces=30-letter_count and gaps=word_count-1; each gap gets the quotient and the earliest remainder gaps get one extra space. Framing bars are outside those thirty characters.

The <=width inner loop counts letters and end-start gaps. Final/single-word lines join and padRight; other lines use integer ~/ and % with i<remainder. StringBuffer adds bars and one newline, then emits the buffer.

Tokenization, greedy width check, letter/gap counts, quotient/remainder distribution and frame output establish punctuation and spaces. A generic formatter body cannot substitute for the actual remainder policy.
