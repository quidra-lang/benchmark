# Task B selection: 67_base64_encode / Swift

## Common answer requirements

Identify how to emit two, three or four symbols per existing group, preserving the alphabet, empty case and output framing.

## Supported analysis

Keep grouping and the alphabet lookups. Skip the slots whose existing branch emits an equals sign: a one-byte group retains two symbols, a two-byte group retains three, and a complete group retains four. Empty input performs no group write or takes the explicit empty guard. The selected size and emission operations locate the change; the bit packing and quote formatting stay in place.

The excerpt is copied verbatim from `main.swift`, in source order. Retained source lines: 3, 4, 5, 6, 10, 11, 12, 13.

## Minimization and alternatives

Keeping the group size and padding decisions is sufficient. An unchanged alphabet literal or bit construction would only identify symbol identity. A trailing loop close adds no scope information when no following operation is retained. The prior selection used 190 tokens; this selection uses 187 tokens. Task A is assumed to satisfy its requirements for this analysis, as specified in README §2.3.
