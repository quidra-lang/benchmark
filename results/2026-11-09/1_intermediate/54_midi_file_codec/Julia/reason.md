# Task B selection — Julia

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.jl`: 3, 4, 5, 6, 7, 9, 10, 11, 12, 28, 35, 36, 41, 42, 43, 73, 74, 75, 76, 77, 78, 79, 80, 105, 321, 322, 323, 324, 325, 326, 328, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 344, 345, 346, 347, 356, 358, 413, 414, 415, 416, 417, 418, 433, 434, 435, 437, 438, 439, 440, 441, 454, 455, 465, 466, 467, 468, 470, 471, 472, 473, 475, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 562, 563, 565, 567, 569, 570

## Evidence and language semantics

The requested change belongs in the event transformation, after target selection and signed pitch addition and before the payload assignment. Replace the range-failure removal path with a lower/upper bound clamp. Every selected event must reach the retained-event path exactly once; leave tick, status/channel, second data byte and track order untouched. Equal resulting pitches are separate sequence entries, including entries at the same tick; no set, grouping or note-pair operation is required. The transposed count includes those now clamped, including a zero shift; dropped becomes zero and its detail loop receives no events. DECODE already formats the stored payload in track order. ENCODE already uses each retained absolute tick minus the previous retained tick, so preserving events preserves the original delta sequence, including zero deltas; the shortest base-128 encoding and channel payload emission remain applicable. Existing running-status compression only suppresses status bytes, while NOTE_OFF ZERO changes status/velocity at encoding time and keeps the pitch. Neither operation coalesces events. Julia Event and Song are mutable structs; songs lookup returns the stored Song reference, and replacing s.tracks[t] persists without a separate dictionary store. Vector append/push retains every event separately, and one-based data[1] is the pitch. For valid MIDI channel statuses the selected <176 predicate covers the three channel families; kind maps these high nibbles to NOTE_OFF/NOTE_ON/POLY_PRESSURE. Signed Int addition is clamped before pitch storage. encode returns bytes based on absolute-tick differences and retains the first data value through running-status/NOTE_OFF zero choices. The command branch prints argument/no-song/unknown errors in the shown order. event_line joins the original tick, track, name, channel and pitch into one displayed entry.

## Minimization and alternatives

A transformation-only excerpt cannot establish downstream display, delta-time encoding or required error precedence. HEX/TEXT construction, pairing, timing, quantization and other edits are omitted because the input song is already valid. The relevant event/list types, selected formatting branches, VLQ code, encoder traversal, command guards and persistent-state write are retained. Custom helper bodies appear only where they determine a required behavior; ordinary collection/ownership rules are stated in the evidence. Source declarations and branch guards needed to identify selected definitions are retained even when a smaller candidate omitted them. This final excerpt was independently read and checked against the same four requirements used for all languages; no implementation changes or program execution were performed.

The excerpt contains 1743 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
