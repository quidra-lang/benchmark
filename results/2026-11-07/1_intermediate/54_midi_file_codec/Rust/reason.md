# Task B selection — Rust

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.rs`: 4, 5, 7, 18, 20, 22, 26, 27, 28, 29, 30, 31, 36, 37, 43, 44, 45, 46, 47, 51, 52, 53, 67, 68, 69, 70, 79, 80, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 332, 333, 334, 335, 336, 337, 338, 363, 364, 365, 366, 367, 368, 385, 386, 387, 389, 390, 396, 397, 398, 400, 401, 402, 403, 404, 405, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 423, 424, 425, 426, 427, 508, 509, 510, 511

## Evidence and language semantics

Replace the existing delete-or-keep decision only for selected NOTE_ON, NOTE_OFF and POLY_PRESSURE events with note=max(0,min(127,old+n)), retaining the event in its original track slot and preserving tick, kind, channel and other fields. Keep the current optional-channel predicate and validation before mutation. Distinct events remain distinct even if they clamp to the same note; neither transformation nor later traversal should deduplicate them. All affected events count as transposed (including n=0 or a note already at the endpoint); retain the result format transposed K dropped 0, with no dropped-event detail lines. DECODE must render the new note at the retained tick/track/position. ENCODE must visit every retained event, emit its updated channel-message payload and derive each delta from the unchanged absolute ticks, including zero deltas for equal-time events. Existing running-status and NOTE_OFF ZERO handling remain in force and must operate on the preserved event sequence. Derived Clone on Event and Song recursively clones owned Vec payloads/tracks. execute clones the selected song, takes each track into an owning iterator, changes a target pitch, pushes each surviving event to a new Vec and commits the song to the map. Retaining every event after clamping preserves value fields and order, and no references are keyed by the new pitch. Errors propagate through Result before mutation. i64 parsing/addition and tick differences are exact within the limits; u8 conversion must follow clamping. Decoded fields/line methods use the modified first data byte, while the encoded output uses borrowed events, shortest VLQ, running status and a transient NOTE_OFF ZERO payload.

## Minimization and alternatives

Reviewed the final excerpt separately against the shared validation, transformation, result and downstream representation requirements. Full HEX/TEXT parsing, note pairing, timing maps, quantization, velocity, merge/split and statistics were considered and omitted: the song is already valid and only the pitch field changes. Selected the target predicate, mutation/rebuild and drop reporting, argument checks, ordered DECODE traversal and note text conversion, and ENCODE loop/pitch payload/delta/VLQ boundaries. Custom helpers are followed where their behavior determines these facts; ordinary indexing, collections and integer semantics cover the remaining operations. No changed implementation, build or execution is supplied.

The excerpt contains 2575 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
