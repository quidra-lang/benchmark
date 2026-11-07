The decoder already consumes encoded Morse alone, splits words at / delimiters, splits letters at whitespace, performs exact complete-token lookup and rejoins decoded letters without gaps and words with one space. Exact keys keep "." -> E separate from ".-" -> A; no prefix matching or original-message fallback is needed.

The symbols/codes association and inverted Hash establish full-token values; encoded.split(" / "), word.split(" ") and reverse[code] already implement the required boundaries and joins.

The decoder consumes the encoded string via exact inverse-map lookup and word/letter split/join operations. The encoder and original-message output are not necessary to establish decoder independence.
