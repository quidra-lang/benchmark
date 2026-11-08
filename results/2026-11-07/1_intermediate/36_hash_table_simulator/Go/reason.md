# Task B selection — Go

## Answer requirements shared across languages

1. Locate the PUT/ADD item-argument parsing and validation boundary and explain changing its accepted interval from ±1000000 to ±2000000 without conflating it with the arithmetic result interval.
2. Trace new values and existing-key replacement/addition into item storage, preserving the existing PUT/ADD result rules.
3. Show that empty, live-item and tombstone states are independent of the numeric value, including stored zero.
4. Identify how GET and DUMP represent the stored value, preserving their output rules and leaving unrelated hashing/resizing behavior unchanged.

## Selected source locations

- `main.go`: 36, 37, 38, 39, 41, 43, 45, 46, 47, 48, 49, 51, 52, 53, 54, 56, 57, 58, 59, 60, 61, 62, 63, 64, 302, 303, 304, 305, 306, 307, 493, 494, 496, 497, 498, 499, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 512, 513, 514, 518, 519, 520, 523, 600, 601, 604, 606, 607, 609, 610, 611, 615, 655, 657, 658, 659, 660, 661, 662, 663, 664, 665, 666, 667, 668, 669, 674, 675, 676, 861, 862, 863, 864, 927, 928

## Evidence and language semantics

PUT and ADD share the selected direct numeric conversion and insertion entry. There is no ±1000000 comparison on this shown path: the current implementation relies on valid command arguments rather than enforcing that particular interval in source. Expanding the input contract therefore needs no narrower type replacement here; if runtime range enforcement is added or maintained at this boundary, use inclusive -2000000..2000000 on the incoming argument for both commands, not on a stored result. For a found key PUT replaces the value, while ADD stores old+argument; for a new key both store the argument. For example, two ADD increments of 2000000 may produce 4000000 and must not be rejected merely for exceeding the input interval. The selected replacement/storage lines and GET/DUMP renderers expose the propagation sites and existing value-result rules. Keep these operations and decimal formats unchanged; numeric magnitude is not a slot-state discriminator. No value-bound-driven change to hashing, capacity, collision handling or rebuild policy follows. ParseInt(...,10,64) supplies int64 storage and arithmetic, and fmt uses decimal output. SlotState tags distinguish empty/live/tombstone; item.value zero does not change that state.

## Minimization and alternatives

Selected the common parse/call boundary, value-bearing declarations or dynamic construction, existing-key arithmetic/storage, and the value/state branches of GET and DUMP. Removed counters, tracing, hash/probe algorithms, resizing, generated keys and position/distance decoration where they occupy separate lines: none decides the proposed item-argument range. A parser-only candidate is shorter but misses accumulated ADD results and zero/state separation; an Item-only candidate misses caller conversion and output. A complete insertion/search/rebuild excerpt also suffices but adds unaffected policy. Using the existing state predicate/format helper plus its call is less expensive than selecting all search/placement branches; helpers needed to resolve stored-item access or numeric formatting remain. Independent excerpt-only review establishes all requirements using standard parsing/formatting, numeric and optional/union semantics; the old task-text interval is not asserted to be a source check. Whitespace-only lines outside source literals and explicit line continuations are omitted: they contribute tokens but no evidence for the answer. Literal content is preserved, and files with ambiguous quote or multiline-literal syntax are left unchanged by this step.

The excerpt contains 1101 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
