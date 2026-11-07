The second string encodes as "12W1B12W3B" and decodes to the original twelve-W, B, twelve-W, BBB sequence. The complete line is "WWWWWWWWWWWWBWWWWWWWWWWWWBBB -> 12W1B12W3B -> WWWWWWWWWWWWBWWWWWWWWWWWWBBB". Both arrows have one surrounding space.

The backreference run regex greedily captures equal-letter runs; the decoder allMatches(encoded) parses digit sequences and expands each letter. The complete print expression proves decoding does not copy text.

The selected string, run accumulation, multi-digit decode and final interpolation support the full round trip and spacing. Other source strings are not needed for the second case.
