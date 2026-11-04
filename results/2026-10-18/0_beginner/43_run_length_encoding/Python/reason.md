# Task B selection: 43_run_length_encoding / Python

## Common answer requirements

Trace the two twelve-W runs and show decoding of a multi-digit count from the encoded data.

## Source evidence

The second source string contains twelve Ws, a B, another twelve Ws, and three Bs. groupby groups only adjacent equal characters, yielding 12W1B12W3B. The regex collects the entire digit sequence before each letter, int parses that count, and repeated letters are joined. The final display uses decoded, produced from encoded, alongside the original text.

## Minimization

Other input strings do not determine the focused runs. The output line confirms the decoded value is the one displayed, matching the same evidence requirement in Quidra. Selected complete lines of `main.py`: 1, 2, 4, 6, 11, 12, 13, 14, 16.
