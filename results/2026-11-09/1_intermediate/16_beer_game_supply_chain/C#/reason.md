# Task B selection — C#

## Answer requirements shared across languages

1. Trace LOAD name lookup, the missing-name error, restoration of saved week, demand and simulation state, and LOAD name/week output.
2. Show that lookup retains the named snapshot and only current simulation state is replaced; distinguish base demand and the snapshot registry (and other outer game state) from the restored object.

## Selected source locations

- `Program.cs`: 125, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 154, 156, 157, 166, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 356, 357, 358, 359, 845, 846, 847, 848, 849, 850

## Evidence and language semantics

TryGetValue supplies the saved Simulation; Copy constructs a fresh demand list, copies simulation fields and uses the shown Stage copy operation. The registry and baseDemands belong to Game. The LOAD arm looks up the argument by name and rejects a missing entry before restoration. It replaces only the current simulation and prints the requested name plus the restored week. The simulation evidence identifies demand, stages, plant state/history and visibility as restored state. Base demand and the registry are separate outer values; LOAD neither assigns them nor removes the looked-up snapshot, so the name remains reusable.

## Minimization and alternatives

The excerpt contains the LOAD path, simulation copy/schema evidence and the outer base/registry boundary. The lookup uses a nonremoving read. Value-copy/deep-copy semantics avoid tracing simulation stepping, policy calculations and later commands. Additional SAVE evidence is retained only when it establishes the serialized object; RESET, DEMAND and simulation methods explain unrelated operations. Custom copying is followed to field copying where necessary; library deepcopy/serialization and value semantics need no library implementation.

The excerpt contains 530 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
