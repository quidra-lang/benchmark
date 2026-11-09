The decoder already consumes encoded Morse alone, splits words at / delimiters, splits letters at whitespace, performs exact complete-token lookup and rejoins decoded letters without gaps and words with one space. Exact keys keep "." -> E separate from ".-" -> A; no prefix matching or original-message fallback is needed.

reverse_mapping[code] is built from complete whitespace-delimited codes. The decoder splits slash-separated words and full nonspace tokens, then table.concat joins letters and decoded_words restores word spaces.

The decoder consumes the encoded string via exact inverse-map lookup and word/letter split/join operations. The encoder and original-message output are not necessary to establish decoder independence.
