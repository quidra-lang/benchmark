# Task B selection — Rust

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.rs`: 4, 5, 7, 18, 20, 26, 27, 28, 29, 30, 31, 36, 37, 43, 44, 45, 46, 47, 52, 67, 68, 69, 79, 80, 310, 311, 312, 313, 315, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 365, 366, 367, 368, 385, 386, 387, 389, 390, 397, 398, 400, 401, 403, 405, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 509, 528, 529

## Evidence and language semantics

The requested change belongs in the event transformation, after target selection and signed pitch addition and before the payload assignment. Replace the range-failure removal path with a lower/upper bound clamp. Every selected event must reach the retained-event path exactly once; leave tick, status/channel, second data byte and track order untouched. Equal resulting pitches are separate sequence entries, including entries at the same tick; no set, grouping or note-pair operation is required. The transposed count includes those now clamped, including a zero shift; dropped becomes zero and its detail loop receives no events. DECODE already formats the stored payload in track order. ENCODE already uses each retained absolute tick minus the previous retained tick, so preserving events preserves the original delta sequence, including zero deltas; the shortest base-128 encoding and channel payload emission remain applicable. Existing running-status compression only suppresses status bytes, while NOTE_OFF ZERO changes status/velocity at encoding time and keeps the pitch. Neither operation coalesces events. The Event fields and Vec-based tracks establish separate sequence entries; mem::take transfers each entry into the new result Vec, and result.push plus *track=result retain sequence order and duplicates. The signed i64 sum must be clamped before its as u8 conversion, which alone would not saturate. The selected status/code/channel helpers and CHANNEL_TYPES table identify high nibbles 8..10 precisely; pitch and PITCHES establish note text. A cloned song is committed back to self.songs after the match, so that store is necessary evidence. Unknown command is rejected before song lookup, then bounds through inside and bad are checked before mutation. The main result branch shows error: formatting. The encoder borrows the song immutably, and its separate rewritten status/data output preserves pitch and stored events; Rust borrowing makes additional mutation investigation unnecessary.

## Minimization and alternatives

A transformation-only excerpt cannot establish downstream display, delta-time encoding or required error precedence. HEX/TEXT construction, pairing, timing, quantization and other edits are omitted because the input song is already valid. The relevant event/list types, selected formatting branches, VLQ code, encoder traversal, command guards and persistent-state write are retained. Custom helper bodies appear only where they determine a required behavior; ordinary collection/ownership rules are stated in the evidence. Source declarations and branch guards needed to identify selected definitions are retained even when a smaller candidate omitted them. This final excerpt was independently read and checked against the same four requirements used for all languages; no implementation changes or program execution were performed.

The excerpt contains 2124 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
