# Task B selection — Rust

## Answer requirements shared across languages

1. Trace LOAD name lookup, the missing-name error, restoration of saved week, demand and simulation state, and LOAD name/week output.
2. Show that lookup retains the named snapshot and only current simulation state is replaced; distinguish base demand and the snapshot registry (and other outer game state) from the restored object.

## Selected source locations

- `main.rs`: 202, 203, 204, 205, 206, 207, 208, 410, 411, 412, 413, 414, 567, 568, 569, 570

## Evidence and language semantics

BTreeMap::get borrows the saved Simulation without removing it. Derived Clone copies every Simulation field into current, including week, demand, stages and plant state. base_demand and saved are distinct Game fields. The LOAD arm looks up the argument by name and rejects a missing entry before restoration. It replaces only the current simulation and prints the requested name plus the restored week. The simulation evidence identifies demand, stages, plant state/history and visibility as restored state. Base demand and the registry are separate outer values; LOAD neither assigns them nor removes the looked-up snapshot, so the name remains reusable.

## Minimization and alternatives

The excerpt contains the LOAD path, simulation copy/schema evidence and the outer base/registry boundary. The lookup uses a nonremoving read. Value-copy/deep-copy semantics avoid tracing simulation stepping, policy calculations and later commands. Additional SAVE evidence is retained only when it establishes the serialized object; RESET, DEMAND and simulation methods explain unrelated operations. Custom copying is followed to field copying where necessary; library deepcopy/serialization and value semantics need no library implementation.

The excerpt contains 217 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
