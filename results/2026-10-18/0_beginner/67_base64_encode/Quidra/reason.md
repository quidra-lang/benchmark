# Task B selection: 67_base64_encode / Quidra

The byte array, loop width and remaining-byte calculation identify the partial final group. The inner loop emits the first min(4, remaining + 1) alphabet symbols and uses '=' only for the other slots. Changing the padding branch leaves the computed alphabet indices, the empty case, and output framing intact.

The selected lines are verbatim and in source order. The excerpt uses the task assumptions and the documented semantics of the imported APIs.

Task A: 340 tokens. Task B: 140 tokens.
