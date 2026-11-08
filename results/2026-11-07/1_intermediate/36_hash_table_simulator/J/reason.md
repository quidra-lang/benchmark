# Task B selection — J

## Answer requirements shared across languages

1. Locate the PUT/ADD item-argument parsing and validation boundary and explain changing its accepted interval from ±1000000 to ±2000000 without conflating it with the arithmetic result interval.
2. Trace new values and existing-key replacement/addition into item storage, preserving the existing PUT/ADD result rules.
3. Show that empty, live-item and tombstone states are independent of the numeric value, including stored zero.
4. Identify how GET and DUMP represent the stored value, preserving their output rules and leaving unrelated hashing/resizing behavior unchanged.

## Selected source locations

- `main.ijs`: 10, 42, 43, 44, 45, 46, 47, 48, 49, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 288, 289, 290, 291, 296, 297, 298, 299, 301, 302, 303, 304, 307, 325, 326, 327, 329, 331, 332, 334, 335, 336, 338, 339, 386, 387, 388, 389, 390, 391, 392, 393, 394, 395, 396, 397, 398, 399, 400, 402, 405, 406, 407, 408, 409, 587, 588

## Evidence and language semantics

PUT and ADD share the selected direct numeric conversion and insertion entry. There is no ±1000000 comparison on this shown path: the current implementation relies on valid command arguments rather than enforcing that particular interval in source. Expanding the input contract therefore needs no narrower type replacement here; if runtime range enforcement is added or maintained at this boundary, use inclusive -2000000..2000000 on the incoming argument for both commands, not on a stored result. For a found key PUT replaces the value, while ADD stores old+argument; for a new key both store the argument. For example, two ADD increments of 2000000 may produce 4000000 and must not be rejected merely for exceeding the input interval. The selected replacement/storage lines and GET/DUMP renderers expose the propagation sites and existing value-result rules. Keep these operations and decimal formats unchanged; numeric magnitude is not a slot-state discriminator. No value-bound-driven change to hashing, capacity, collision handling or rebuild policy follows. 0". parses the decimal argument. Items are boxed key/value pairs; item length, rather than its numeric value, distinguishes empty (0), tombstone (1) and item (2). item_at/change_item read and replace the pair; 8!:2 formats the number.

## Minimization and alternatives

Selected the common parse/call boundary, value-bearing declarations or dynamic construction, existing-key arithmetic/storage, and the value/state branches of GET and DUMP. Removed counters, tracing, hash/probe algorithms, resizing, generated keys and position/distance decoration where they occupy separate lines: none decides the proposed item-argument range. A parser-only candidate is shorter but misses accumulated ADD results and zero/state separation; an Item-only candidate misses caller conversion and output. A complete insertion/search/rebuild excerpt also suffices but adds unaffected policy. Using the existing state predicate/format helper plus its call is less expensive than selecting all search/placement branches; helpers needed to resolve stored-item access or numeric formatting remain. Independent excerpt-only review establishes all requirements using standard parsing/formatting, numeric and optional/union semantics; the old task-text interval is not asserted to be a source check.

The excerpt contains 946 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
