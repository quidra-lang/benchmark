# Task B selection — Quidra

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.qui`: 1, 2, 8, 9, 10, 11, 12, 13, 14, 15, 27, 28, 29, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 81, 82, 83, 84, 85, 90, 91, 92, 93, 94, 95, 127, 128, 129, 130, 131, 132, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 525, 526, 527, 528, 529, 536, 537, 538, 539, 540, 541, 542, 543, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 603, 604, 611, 612, 613, 614, 615, 616, 617, 618, 619, 620, 621, 622, 623, 624, 693, 694, 695, 696, 697, 698, 699, 700, 706, 707, 708, 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 821, 822

## Evidence and language semantics

Replace the existing delete-or-keep decision only for selected NOTE_ON, NOTE_OFF and POLY_PRESSURE events with note=max(0,min(127,old+n)), retaining the event in its original track slot and preserving tick, kind, channel and other fields. Keep the current optional-channel predicate and validation before mutation. Distinct events remain distinct even if they clamp to the same note; neither transformation nor later traversal should deduplicate them. All affected events count as transposed (including n=0 or a note already at the endpoint); retain the result format transposed K dropped 0, with no dropped-event detail lines. DECODE must render the new note at the retained tick/track/position. ENCODE must visit every retained event, emit its updated channel-message payload and derive each delta from the unchanged absolute ticks, including zero deltas for equal-time events. Existing running-status and NOTE_OFF ZERO handling remain in force and must operate on the preserved event sequence. Quidra Event stores tick separately from code and payload, and Track preserves an ordered Event array. The combined TRANSPOSE/FILTER branch builds kept in encounter order. For TRANSPOSE, the revised pitch assignment must always append the modified value, increase changed, and leave remove false. The later song assignment back to songs[at].song makes this value-semantic edit visible to subsequent commands. Numeric family8..10 and optional one-based channel identify the three target types. Validation occurs before the local song rewrite. DECODE text_line uses stored ticks and the updated payload; encoding copies payload_value for NOTE_OFF ZERO and computes deltas from the absolute ev.tick, preserving multiple equal-pitch events independently.

## Minimization and alternatives

Reviewed the final excerpt separately against the shared validation, transformation, result and downstream representation requirements. Full HEX/TEXT parsing, note pairing, timing maps, quantization, velocity, merge/split and statistics were considered and omitted: the song is already valid and only the pitch field changes. Selected the target predicate, mutation/rebuild and drop reporting, argument checks, ordered DECODE traversal and note text conversion, and ENCODE loop/pitch payload/delta/VLQ boundaries. Custom helpers are followed where their behavior determines these facts; ordinary indexing, collections and integer semantics cover the remaining operations. No changed implementation, build or execution is supplied.

The excerpt contains 2577 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
