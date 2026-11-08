# Task B selection — Julia

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.jl`: 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 28, 35, 36, 41, 42, 43, 55, 56, 57, 58, 59, 60, 61, 62, 73, 74, 75, 76, 77, 78, 79, 80, 85, 104, 105, 106, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 354, 355, 356, 357, 358, 359, 413, 414, 415, 416, 417, 418, 433, 434, 435, 436, 437, 438, 439, 440, 441, 453, 454, 455, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570

## Evidence and language semantics

Replace the existing delete-or-keep decision only for selected NOTE_ON, NOTE_OFF and POLY_PRESSURE events with note=max(0,min(127,old+n)), retaining the event in its original track slot and preserving tick, kind, channel and other fields. Keep the current optional-channel predicate and validation before mutation. Distinct events remain distinct even if they clamp to the same note; neither transformation nor later traversal should deduplicate them. All affected events count as transposed (including n=0 or a note already at the endpoint); retain the result format transposed K dropped 0, with no dropped-event detail lines. DECODE must render the new note at the retained tick/track/position. ENCODE must visit every retained event, emit its updated channel-message payload and derive each delta from the unchanged absolute ticks, including zero deltas for equal-time events. Existing running-status and NOTE_OFF ZERO handling remain in force and must operate on the preserved event sequence. Event and Song are mutable structs, with Int64 ticks and ordered vectors. The loop holds each event reference, mutates data[1], pushes it once into a new Event vector and replaces the track, so pitch collisions are retained separately and all other fields survive. Int64 argument parsing and exact integer division supply bounded pitch/delta calculations. Command lookup and missing-song returns precede range validation; invalid arguments take the first branch of the same conditional chain, excluding transformation. event_line formats the updated payload in track order. encode traverses that order, forms exact tick differences and shortest VLQ, and creates a temporary NOTE_OFF ZERO body while retaining the stored status and payload.

## Minimization and alternatives

Reviewed the final excerpt separately against the shared validation, transformation, result and downstream representation requirements. Full HEX/TEXT parsing, note pairing, timing maps, quantization, velocity, merge/split and statistics were considered and omitted: the song is already valid and only the pitch field changes. Selected the target predicate, mutation/rebuild and drop reporting, argument checks, ordered DECODE traversal and note text conversion, and ENCODE loop/pitch payload/delta/VLQ boundaries. Custom helpers are followed where their behavior determines these facts; ordinary indexing, collections and integer semantics cover the remaining operations. No changed implementation, build or execution is supplied.

The excerpt contains 1917 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
