# Task B selection — Dart

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.dart`: 4, 8, 10, 11, 12, 13, 14, 16, 17, 21, 22, 29, 30, 31, 32, 33, 60, 61, 62, 63, 64, 65, 70, 73, 88, 89, 90, 91, 92, 93, 96, 97, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 362, 363, 364, 365, 366, 367, 368, 369, 370, 426, 428, 429, 437, 450, 451, 452, 453, 454, 455, 457, 458, 463, 464, 465, 468, 473, 474, 475, 476, 477, 478, 479, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508

## Evidence and language semantics

Replace the existing delete-or-keep decision only for selected NOTE_ON, NOTE_OFF and POLY_PRESSURE events with note=max(0,min(127,old+n)), retaining the event in its original track slot and preserving tick, kind, channel and other fields. Keep the current optional-channel predicate and validation before mutation. Distinct events remain distinct even if they clamp to the same note; neither transformation nor later traversal should deduplicate them. All affected events count as transposed (including n=0 or a note already at the endpoint); retain the result format transposed K dropped 0, with no dropped-event detail lines. DECODE must render the new note at the retained tick/track/position. ENCODE must visit every retained event, emit its updated channel-message payload and derive each delta from the unchanged absolute ticks, including zero deltas for equal-time events. Existing running-status and NOTE_OFF ZERO handling remain in force and must operate on the preserved event sequence. Event and Song are reference objects with ordered List fields. A target Event mutates data[0] and is then appended to a replacement track; removing the current continue path makes every original event survive once. Kind and ch derive MIDI family/channel, and noteName/eventText render its new note. Encode uses exact integer tick subtraction, base128 VLQ and ordered payload appends, with a temporary payload for NOTE_OFF ZERO and running status reset at non-channel events. emit writes lines. Missing-song failure occurs before numeric range validation, with fail throwing; the small existing integer bounds are exact in Dart native and JavaScript numeric representations.

## Minimization and alternatives

Reviewed the final excerpt separately against the shared validation, transformation, result and downstream representation requirements. Full HEX/TEXT parsing, note pairing, timing maps, quantization, velocity, merge/split and statistics were considered and omitted: the song is already valid and only the pitch field changes. Selected the target predicate, mutation/rebuild and drop reporting, argument checks, ordered DECODE traversal and note text conversion, and ENCODE loop/pitch payload/delta/VLQ boundaries. Custom helpers are followed where their behavior determines these facts; ordinary indexing, collections and integer semantics cover the remaining operations. No changed implementation, build or execution is supplied.

The excerpt contains 2323 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
