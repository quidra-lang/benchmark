# Task B selection — J

## Answer requirements shared across languages

1. Locate the result-only TRANSPOSE boundary and identify the existing allowed MIDI and octave range.
2. Describe changing only the TRANSPOSE OUT OF RANGE test to reject MIDI 127, preserving CANNOT SPELL precedence and number arguments for other commands.

## Selected source locations

- `main.ijs`: 24, 25, 26, 27, 82, 96, 363, 370, 373, 374, 375, 376

## Evidence and language semantics

valid_note tests MIDI against 127; parse_number passes 127 to canonical. fail uses throw. to abort. Extend the local OUT OF RANGE condition with rejection of the computed result MIDI 127 (or require its MIDI <=126), after the spelling check; do not lower a shared validity or NUMBER-parser bound. Existing lower and octave limits continue to apply.

## Minimization and alternatives

A whole transposition implementation, scale/voice commands, and generic numeric parsing implementation add no facts needed for this boundary edit. The local result check plus the shared validity predicate is smaller than tracing all consumers of that predicate. The selected value arithmetic identifies the result pitch, while the error lines establish their order. No proposed modification is implemented.

The excerpt contains 205 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
