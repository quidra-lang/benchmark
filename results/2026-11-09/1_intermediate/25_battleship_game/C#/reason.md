# Task B selection — C#

## Answer requirements shared across languages

1. Locate command-token parsing and the distinct FIRE, AI, and TORPEDO dispatches. Explain an exact SHOT-to-FIRE name normalization or equivalent handler alias before those tests, preserving player and the complete ordered target argument list.
2. Follow FIRE through the existing common turn checks and whole-batch allowance/reef validation before battle/shot mutations. Explain that a later invalid command reports its error without undoing an earlier accepted shot, and that a bad later cell in the same batch is rejected before its first shot; no per-cell redispatch or partial validation is introduced.
3. Preserve the ordered shot/result/statistics hooks, duplicate-cell handling by the same shot operation, early stop on victory, and one completion stage per accepted batch with all hit results for winner, turn, CHAIN, and automatic-control handling.
4. Keep AI strategy selection and TORPEDO row/side, one-use validation and distinct action/output paths unchanged. The request explicitly does not require helper implementations: retain necessary caller/callee and update hooks, not target-selection, board geometry, placement, or unrelated command implementations.

## Selected source locations

- `Program.cs`: 96, 97, 105, 106, 107, 108, 109, 110, 250, 251, 252, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 292, 293, 294, 295, 415, 416, 417, 419, 421, 422, 423, 424, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 439, 440, 444, 445, 446, 447, 584, 585, 587, 588, 589, 590, 591, 592, 593, 594

## Evidence and language semantics

Normalize only the parsed command name SHOT to FIRE (or bind SHOT to exactly the existing FIRE handler), before all name-based routing, leaving argument positions and the ordered batch intact. Do not loop by dispatching separate FIRE commands: that would repeat validation/allowance and finish turns independently. The excerpt separates batch validation from action and retains the original per-shot and completion calls. An error in a later command does not undo already accepted state; an invalid later cell in the current batch is discovered during its preflight before any shot. Exceptions/early returns bypass completion. Repeated cells reach the unchanged shot operation in order, so its existing ALREADY behavior remains; victory still stops remaining shots. AI and TORPEDO keep their own operands, handlers, output and action rules. C# reads command before HashSet membership and switch dispatch; normalize that local string before both. LINQ materializes all targets and the foreach preflight finishes before ShootTurn. Its nullable strategy distinguishes explicit FIRE targets from AI selection, and TORPEDO keeps its separate row/side method after TorpedoUsed validation. Shoot calls owner.Record and EndTurn gets the combined IsHit flag, increments turns once and applies CHAIN. One Program retains its Game reference; CommandError caught in Main does not roll back earlier successful commands.

## Minimization and alternatives

Selected complete lines were reviewed individually and then as a standalone excerpt. Dispatch alone would identify an alias entry but not prove preservation of batch validation, failure boundaries, action order or completion; the FIRE body alone would miss the original name-resolution and AI/TORPEDO separation. Necessary state/statistics/completion hooks are retained where their connection is not otherwise visible. As explicitly permitted by the question, helper implementations for geometry, shot-result calculation, strategy algorithms and unrelated command functions are omitted. Adding all helpers or the full dispatcher would add independently unnecessary lines. Separate aliases in every downstream name test are a larger and error-prone alternative to canonicalizing the single input command token; global replacement of SHOT output text is not a command alias.

The excerpt contains 1338 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
