# Task B selection — R

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.R`: 1, 2, 3, 9, 11, 15, 16, 17, 27, 28, 29, 30, 31, 32, 33, 34, 51, 52, 53, 54, 55, 56, 57, 58, 63, 83, 84, 85, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 352, 353, 354, 355, 356, 357, 420, 421, 422, 423, 424, 425, 426, 427, 428, 429, 430, 431, 448, 449, 450, 451, 452, 453, 454, 455, 464, 465, 466, 467, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 575, 576, 577, 578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 594, 595, 700

## Evidence and language semantics

Replace the existing delete-or-keep decision only for selected NOTE_ON, NOTE_OFF and POLY_PRESSURE events with note=max(0,min(127,old+n)), retaining the event in its original track slot and preserving tick, kind, channel and other fields. Keep the current optional-channel predicate and validation before mutation. Distinct events remain distinct even if they clamp to the same note; neither transformation nor later traversal should deduplicate them. All affected events count as transposed (including n=0 or a note already at the endpoint); retain the result format transposed K dropped 0, with no dropped-event detail lines. DECODE must render the new note at the retained tick/track/position. ENCODE must visit every retained event, emit its updated channel-message payload and derive each delta from the unchanged absolute ticks, including zero deltas for equal-time events. Existing running-status and NOTE_OFF ZERO handling remain in force and must operate on the preserved event sequence. R events and payloads are ordinary value lists/vectors; the selected constructor establishes their numeric fields. The transformation edits the local event, appends it to an ordered replacement row, replaces the track and stores the completed song back in its environment. Removing the next/deletion path and clamping data[1] keeps each input slot, including equal notes. Missing-song and argument errors return before this path. DECODE enumerates lists and renders the new first payload element. ENCODE copies the numeric body value, emits ordered bytes and base128 VLQ differences; NOTE_OFF ZERO does not alter the stored payload. All relevant counts, pitch and tick operations are exact integer-valued arithmetic well below2^53; no floating rounding is introduced.

## Minimization and alternatives

Reviewed the final excerpt separately against the shared validation, transformation, result and downstream representation requirements. Full HEX/TEXT parsing, note pairing, timing maps, quantization, velocity, merge/split and statistics were considered and omitted: the song is already valid and only the pitch field changes. Selected the target predicate, mutation/rebuild and drop reporting, argument checks, ordered DECODE traversal and note text conversion, and ENCODE loop/pitch payload/delta/VLQ boundaries. Custom helpers are followed where their behavior determines these facts; ordinary indexing, collections and integer semantics cover the remaining operations. No changed implementation, build or execution is supplied.

The excerpt contains 2274 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
