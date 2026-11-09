# Task B selection — Java

## Answer requirements shared across languages

1. Trace LOAD name lookup, the missing-name error, restoration of saved week, demand and simulation state, and LOAD name/week output.
2. Show that lookup retains the named snapshot and only current simulation state is replaced; distinguish base demand and the snapshot registry (and other outer game state) from the restored object.

## Selected source locations

- `Main.java`: 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 395, 396, 397, 398, 781, 782, 783, 784, 785

## Evidence and language semantics

Map.get is nonremoving. The Simulation copy constructor copies demand, week, plant fields/history and visibility and uses the selected Stage copy constructor. Game.base and snapshots are separate fields. The LOAD arm looks up the argument by name and rejects a missing entry before restoration. It replaces only the current simulation and prints the requested name plus the restored week. The simulation evidence identifies demand, stages, plant state/history and visibility as restored state. Base demand and the registry are separate outer values; LOAD neither assigns them nor removes the looked-up snapshot, so the name remains reusable.

## Minimization and alternatives

The excerpt contains the LOAD path, simulation copy/schema evidence and the outer base/registry boundary. The lookup uses a nonremoving read. Value-copy/deep-copy semantics avoid tracing simulation stepping, policy calculations and later commands. Additional SAVE evidence is retained only when it establishes the serialized object; RESET, DEMAND and simulation methods explain unrelated operations. Custom copying is followed to field copying where necessary; library deepcopy/serialization and value semantics need no library implementation.

The excerpt contains 569 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
