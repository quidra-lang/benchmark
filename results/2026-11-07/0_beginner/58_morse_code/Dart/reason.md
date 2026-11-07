The decoder already consumes encoded Morse alone, splits words at / delimiters, splits letters at whitespace, performs exact complete-token lookup and rejoins decoded letters without gaps and words with one space. Exact keys keep "." -> E separate from ".-" -> A; no prefix matching or original-message fallback is needed.

The table entries at indices 0 and 4 and alphabet identify A and E. codes.indexOf(c) compares complete strings, not prefixes; the chained splits and joins consume only encoded. Other table entries are unnecessary for the two examples.

The decoder consumes the encoded string via exact inverse-map lookup and word/letter split/join operations. The encoder and original-message output are not necessary to establish decoder independence.
