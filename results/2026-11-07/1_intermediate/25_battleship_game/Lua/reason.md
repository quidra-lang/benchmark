# Task B selection — Lua

## Answer requirements shared across languages

1. Locate command-token parsing and the distinct FIRE, AI, and TORPEDO dispatches. Explain an exact SHOT-to-FIRE name normalization or equivalent handler alias before those tests, preserving player and the complete ordered target argument list.
2. Follow FIRE through the existing common turn checks and whole-batch allowance/reef validation before battle/shot mutations. Explain that a later invalid command reports its error without undoing an earlier accepted shot, and that a bad later cell in the same batch is rejected before its first shot; no per-cell redispatch or partial validation is introduced.
3. Preserve the ordered shot/result/statistics hooks, duplicate-cell handling by the same shot operation, early stop on victory, and one completion stage per accepted batch with all hit results for winner, turn, CHAIN, and automatic-control handling.
4. Keep AI strategy selection and TORPEDO row/side, one-use validation and distinct action/output paths unchanged. The request explicitly does not require helper implementations: retain necessary caller/callee and update hooks, not target-selection, board geometry, placement, or unrelated command implementations.

## Selected source locations

- `main.lua`: 13, 269, 270, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 314, 483, 484, 485, 487, 488, 495, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601

## Evidence and language semantics

Normalize only the parsed command name SHOT to FIRE (or bind SHOT to exactly the existing FIRE handler), before all name-based routing, leaving argument positions and the ordered batch intact. Do not loop by dispatching separate FIRE commands: that would repeat validation/allowance and finish turns independently. The excerpt separates batch validation from action and retains the original per-shot and completion calls. An error in a later command does not undo already accepted state; an invalid later cell in the current batch is discovered during its preflight before any shot. Exceptions/early returns bypass completion. Repeated cells reach the unchanged shot operation in order, so its existing ALREADY behavior remains; victory still stops remaining shots. AI and TORPEDO keep their own operands, handlers, output and action rules. Lua has two name sets: player_commands controls extraction of the player as well as turn_commands controlling the action. Normalize words[1] into command before both tests. The FIRE preflight builds all cells without calling shoot; failures throw a tagged table through pcall. The same mutable Game table is retained, so a failed later command does not erase earlier accepted attacks, and validation never partially fires the current batch. A nil strategy uses supplied cells; AI passes words[3]. TORPEDO retains one-use validation and its dedicated row/side call. The owner:record hook and aggregate finish_turn CHAIN update are shown.

## Minimization and alternatives

Selected complete lines were reviewed individually and then as a standalone excerpt. Dispatch alone would identify an alias entry but not prove preservation of batch validation, failure boundaries, action order or completion; the FIRE body alone would miss the original name-resolution and AI/TORPEDO separation. Necessary state/statistics/completion hooks are retained where their connection is not otherwise visible. As explicitly permitted by the question, helper implementations for geometry, shot-result calculation, strategy algorithms and unrelated command functions are omitted. Adding all helpers or the full dispatcher would add independently unnecessary lines. Separate aliases in every downstream name test are a larger and error-prone alternative to canonicalizing the single input command token; global replacement of SHOT output text is not a command alias.

The excerpt contains 1500 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
