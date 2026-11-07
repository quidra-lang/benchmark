# Task B selection: 43_run_length_encoding / C++

Trace the two W runs in the second input, show how the decoder consumes a full count, and establish reconstruction from the encoded value.

The B between the two runs interrupts equality or the run match, so the encoder generates two separate `12W` chunks. The encoded sequence is `12W1B12W3B`. The decoder parses all decimal digits of a count up to its letter, repeats that letter by the parsed count and appends it. Using the encoded data as the parser input reconstructs twelve Ws, one B, twelve Ws, and three Bs without reading the original during decoding.

The original literal line is necessary for the separator and trailing run. The selected run and count logic plus its linkage to the decoded result are sufficient; other inputs, buffer capacity, and output formats that do not establish linkage can be omitted.

The standard from_chars consumes consecutive decimal digits and returns the pointer to the first character after that prefix.

Source: `main.cpp`, original lines 7, 9–22. The previous excerpt measures 314 tokens; this evidence set measures 310 tokens.

## Current token measurement

Task A: **412 tokens**. Task B: **305 tokens**. Remeasured with `metric/tokenizer.py`, which counts contiguous `()` as one token. Earlier numerical token comparisons in this rationale are historical and are superseded by these totals; the selected source lines and answer requirements remain the basis of the rationale.
