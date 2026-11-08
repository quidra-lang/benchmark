# Task B selection — Zig

## Answer requirements shared across languages

1. Trace LOAD name lookup, the missing-name error, restoration of saved week, demand and simulation state, and LOAD name/week output.
2. Show that lookup retains the named snapshot and only current simulation state is replaced; distinguish base demand and the snapshot registry (and other outer game state) from the restored object.

## Selected source locations

- `main.zig`: 66, 67, 68, 69, 70, 71, 72, 73, 74, 203, 204, 205, 206, 305, 306, 367, 368, 369, 370

## Evidence and language semantics

StringHashMap.get preserves its entry. sim points to self.sim and inline struct assignment copies the saved arrays and fields; the Simulation schema excludes base and snapshots. The LOAD arm looks up the argument by name and rejects a missing entry before restoration. It replaces only the current simulation and prints the requested name plus the restored week. The simulation evidence identifies demand, stages, plant state/history and visibility as restored state. Base demand and the registry are separate outer values; LOAD neither assigns them nor removes the looked-up snapshot, so the name remains reusable.

## Minimization and alternatives

The excerpt contains the LOAD path, simulation copy/schema evidence and the outer base/registry boundary. The lookup uses a nonremoving read. Value-copy/deep-copy semantics avoid tracing simulation stepping, policy calculations and later commands. Additional SAVE evidence is retained only when it establishes the serialized object; RESET, DEMAND and simulation methods explain unrelated operations. Custom copying is followed to field copying where necessary; library deepcopy/serialization and value semantics need no library implementation.

The excerpt contains 340 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
