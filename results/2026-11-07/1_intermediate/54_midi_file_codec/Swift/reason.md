# Task B selection — Swift

## Answer requirements shared across languages

1. Trace TRANSPOSE dispatch and preserve unknown-command, missing-song and numeric-argument validation precedence, including optional channel and semitone bounds.
2. Identify NOTE_ON, NOTE_OFF and POLY_PRESSURE target events and replace out-of-range deletion with clamping while retaining every event, tick and within-track position, even when different events obtain the same note.
3. Preserve the command result schema: all affected retained events contribute to transposed, dropped is zero and no dropped-event detail lines are produced.
4. Trace subsequent DECODE note rendering and ordered traversal and ENCODE traversal, note/status payload, absolute-to-delta conversion and VLQ output so the edited song remains consistent.

## Selected source locations

- `main.swift`: 3, 4, 5, 6, 7, 8, 9, 10, 22, 25, 26, 27, 31, 32, 33, 34, 35, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 63, 64, 65, 66, 78, 82, 83, 84, 85, 86, 93, 94, 95, 122, 123, 124, 136, 137, 138, 139, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567, 568, 569, 570, 571, 572, 573, 574, 575, 576, 582, 583, 584, 585, 586, 587, 588, 589, 590, 591, 592, 593, 640, 641, 642, 643, 644, 645, 646, 647, 652, 663, 664, 665, 666, 691, 692, 693, 694, 695, 696, 697, 698, 699, 713, 714, 715, 716, 720, 721, 722, 723, 724, 725, 726, 727, 728, 729, 743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 753, 754, 755, 756, 757, 758, 759, 760, 761, 762, 763, 764, 907, 908, 909

## Evidence and language semantics

Replace the existing delete-or-keep decision only for selected NOTE_ON, NOTE_OFF and POLY_PRESSURE events with note=max(0,min(127,old+n)), retaining the event in its original track slot and preserving tick, kind, channel and other fields. Keep the current optional-channel predicate and validation before mutation. Distinct events remain distinct even if they clamp to the same note; neither transformation nor later traversal should deduplicate them. All affected events count as transposed (including n=0 or a note already at the endpoint); retain the result format transposed K dropped 0, with no dropped-event detail lines. DECODE must render the new note at the retained tick/track/position. ENCODE must visit every retained event, emit its updated channel-message payload and derive each delta from the unchanged absolute ticks, including zero deltas for equal-time events. Existing running-status and NOTE_OFF ZERO handling remain in force and must operate on the preserved event sequence. Event and Song are value structs with value arrays. execute obtains a mutable song value, copies each Event into a loop variable, edits only data[0], appends the value to a rebuilt track and stores the modified Song back in songs. The replacement clamp therefore retains each event, tick and position; Swift array copy-on-write preserves value semantics. The type/channel/code and fields/line properties establish target families and decoded pitch. ENCODE consumes ordered values and computes exact Int deltas, converting them to shortest VLQ while preserving running status and NOTE_OFF ZERO. The existing small integer bounds are within Swift Int, and thrown fail paths establish validation precedence.

## Minimization and alternatives

Reviewed the final excerpt separately against the shared validation, transformation, result and downstream representation requirements. Full HEX/TEXT parsing, note pairing, timing maps, quantization, velocity, merge/split and statistics were considered and omitted: the song is already valid and only the pitch field changes. Selected the target predicate, mutation/rebuild and drop reporting, argument checks, ordered DECODE traversal and note text conversion, and ENCODE loop/pitch payload/delta/VLQ boundaries. Custom helpers are followed where their behavior determines these facts; ordinary indexing, collections and integer semantics cover the remaining operations. No changed implementation, build or execution is supplied.

The excerpt contains 2346 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
