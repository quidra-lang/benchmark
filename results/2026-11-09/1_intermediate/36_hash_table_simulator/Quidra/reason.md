# Task B selection — Quidra

## Answer requirements shared across languages

1. Locate the PUT/ADD item-argument parsing and validation boundary and explain changing its accepted interval from ±1000000 to ±2000000 without conflating it with the arithmetic result interval.
2. Trace new values and existing-key replacement/addition into item storage, preserving the existing PUT/ADD result rules.
3. Show that empty, live-item and tombstone states are independent of the numeric value, including stored zero.
4. Identify how GET and DUMP represent the stored value, preserving their output rules and leaving unrelated hashing/resizing behavior unchanged.

## Selected source locations

- `main.qui`: 11, 12, 120, 121, 122, 123, 124, 125, 134, 135, 361, 362, 365, 366, 367, 368, 369, 370, 371, 372, 374, 375, 376, 377, 378, 381, 403, 404, 406, 407, 408, 410, 411, 413, 414, 483, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 693, 694, 695, 696

## Evidence and language semantics

PUT and ADD share the selected direct numeric conversion and insertion entry. There is no ±1000000 comparison on this shown path: the current implementation relies on valid command arguments rather than enforcing that particular interval in source. Expanding the input contract therefore needs no narrower type replacement here; if runtime range enforcement is added or maintained at this boundary, use inclusive -2000000..2000000 on the incoming argument for both commands, not on a stored result. For a found key PUT replaces the value, while ADD stores old+argument; for a new key both store the argument. For example, two ADD increments of 2000000 may produce 4000000 and must not be rejected merely for exceeding the input interval. The selected replacement/storage lines and GET/DUMP renderers expose the propagation sites and existing value-result rules. Keep these operations and decimal formats unchanged; numeric magnitude is not a slot-state discriminator. No value-bound-driven change to hashing, capacity, collision handling or rebuild policy follows. int is the existing signed integer representation. Item|none plus a separate tombstone flag separates state from the numeric field, and &table mutation writes the replacement item.

## Minimization and alternatives

Selected the common parse/call boundary, value-bearing declarations or dynamic construction, existing-key arithmetic/storage, and the value/state branches of GET and DUMP. Removed counters, tracing, hash/probe algorithms, resizing, generated keys and position/distance decoration where they occupy separate lines: none decides the proposed item-argument range. A parser-only candidate is shorter but misses accumulated ADD results and zero/state separation; an Item-only candidate misses caller conversion and output. A complete insertion/search/rebuild excerpt also suffices but adds unaffected policy. Using the existing state predicate/format helper plus its call is less expensive than selecting all search/placement branches; helpers needed to resolve stored-item access or numeric formatting remain. Independent excerpt-only review establishes all requirements using standard parsing/formatting, numeric and optional/union semantics; the old task-text interval is not asserted to be a source check.

The excerpt contains 1103 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
