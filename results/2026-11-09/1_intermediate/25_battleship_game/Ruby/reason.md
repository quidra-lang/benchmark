# Task B selection — Ruby

## Answer requirements shared across languages

1. Locate command-token parsing and the distinct FIRE, AI, and TORPEDO dispatches. Explain an exact SHOT-to-FIRE name normalization or equivalent handler alias before those tests, preserving player and the complete ordered target argument list.
2. Follow FIRE through the existing common turn checks and whole-batch allowance/reef validation before battle/shot mutations. Explain that a later invalid command reports its error without undoing an earlier accepted shot, and that a bad later cell in the same batch is rejected before its first shot; no per-cell redispatch or partial validation is introduced.
3. Preserve the ordered shot/result/statistics hooks, duplicate-cell handling by the same shot operation, early stop on victory, and one completion stage per accepted batch with all hit results for winner, turn, CHAIN, and automatic-control handling.
4. Keep AI strategy selection and TORPEDO row/side, one-use validation and distinct action/output paths unchanged. The request explicitly does not require helper implementations: retain necessary caller/callee and update hooks, not target-selection, board geometry, placement, or unrelated command implementations.

## Selected source locations

- `main.rb`: 9, 128, 147, 148, 149, 150, 151, 293, 294, 314, 315, 316, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 342, 343, 347, 348, 349, 350, 493, 494, 496, 497, 498, 500, 501, 502, 503, 504, 505, 506, 507, 508, 510, 511, 512, 513, 514, 515, 516, 517, 519, 524, 525, 526, 527, 646, 647, 648, 649, 650, 651, 652, 653

## Evidence and language semantics

Normalize only the parsed command name SHOT to FIRE (or bind SHOT to exactly the existing FIRE handler), before all name-based routing, leaving argument positions and the ordered batch intact. Do not loop by dispatching separate FIRE commands: that would repeat validation/allowance and finish turns independently. The excerpt separates batch validation from action and retains the original per-shot and completion calls. An error in a later command does not undo already accepted state; an invalid later cell in the current batch is discovered during its preflight before any shot. Exceptions/early returns bypass completion. Repeated cells reach the unchanged shot operation in order, so its existing ALREADY behavior remains; victory still stops remaining shots. AI and TORPEDO keep their own operands, handlers, output and action rules. Ruby resolves words[0] before TURN_COMMANDS membership and case selection. FIRE passes all targets using keyword targets:, AI instead supplies strategy:, and TORPEDO invokes a separate row/side method after its one-use check. shooting_turn calls shoot in order, combines hit? for the whole turn, stops on defeat and finishes once. The statistics hook is owner.stats.record(result); finish_turn contains turn and CHAIN updates. An exception escapes execute before mutations on validation failure and the per-input rescue preserves the same Program and Game.

## Minimization and alternatives

Selected complete lines were reviewed individually and then as a standalone excerpt. Dispatch alone would identify an alias entry but not prove preservation of batch validation, failure boundaries, action order or completion; the FIRE body alone would miss the original name-resolution and AI/TORPEDO separation. Necessary state/statistics/completion hooks are retained where their connection is not otherwise visible. As explicitly permitted by the question, helper implementations for geometry, shot-result calculation, strategy algorithms and unrelated command functions are omitted. Adding all helpers or the full dispatcher would add independently unnecessary lines. Separate aliases in every downstream name test are a larger and error-prone alternative to canonicalizing the single input command token; global replacement of SHOT output text is not a command alias.

The excerpt contains 1015 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
