# Task B selection: 43_run_length_encoding / C

Trace the two W runs in the second input, show how the decoder consumes a full count, and establish reconstruction from the encoded value.

The B between the two runs interrupts equality or the run match, so the encoder generates two separate `12W` chunks. The encoded sequence is `12W1B12W3B`. The decoder parses all decimal digits of a count up to its letter, repeats that letter by the parsed count and appends it. Using the encoded data as the parser input reconstructs twelve Ws, one B, twelve Ws, and three Bs without reading the original during decoding.

The original literal line is necessary for the separator and trailing run. The selected run and count logic plus its linkage to the decoded result are sufficient; other inputs, buffer capacity, and output formats that do not establish linkage can be omitted.

The standard strtol returns the value of the entire base-ten digit prefix and sets end to the first character after that prefix.

Source: `main.c`, original lines 6, 9, 11–20, 22–27. The previous excerpt measures 319 tokens; this evidence set measures 310 tokens.
