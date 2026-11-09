# Task B selection — JavaScript

## Answer requirements shared across languages

1. Locate command-token parsing and the distinct FIRE, AI, and TORPEDO dispatches. Explain an exact SHOT-to-FIRE name normalization or equivalent handler alias before those tests, preserving player and the complete ordered target argument list.
2. Follow FIRE through the existing common turn checks and whole-batch allowance/reef validation before battle/shot mutations. Explain that a later invalid command reports its error without undoing an earlier accepted shot, and that a bad later cell in the same batch is rejected before its first shot; no per-cell redispatch or partial validation is introduced.
3. Preserve the ordered shot/result/statistics hooks, duplicate-cell handling by the same shot operation, early stop on victory, and one completion stage per accepted batch with all hit results for winner, turn, CHAIN, and automatic-control handling.
4. Keep AI strategy selection and TORPEDO row/side, one-use validation and distinct action/output paths unchanged. The request explicitly does not require helper implementations: retain necessary caller/callee and update hooks, not target-selection, board geometry, placement, or unrelated command implementations.

## Selected source locations

- `main.js`: 14, 54, 189, 190, 213, 220, 221, 223, 225, 226, 227, 228, 229, 230, 231, 232, 233, 235, 236, 237, 238, 239, 240, 241, 242, 243, 245, 246, 247, 248, 250, 251, 252, 253, 254, 410, 412, 413, 415, 416, 417, 422, 458, 459, 460, 461, 462, 463, 464, 465, 466, 467, 468, 469, 470, 471, 472, 473, 474, 475, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565

## Evidence and language semantics

Normalize only the parsed command name SHOT to FIRE (or bind SHOT to exactly the existing FIRE handler), before all name-based routing, leaving argument positions and the ordered batch intact. Do not loop by dispatching separate FIRE commands: that would repeat validation/allowance and finish turns independently. The excerpt separates batch validation from action and retains the original per-shot and completion calls. An error in a later command does not undo already accepted state; an invalid later cell in the current batch is discovered during its preflight before any shot. Exceptions/early returns bypass completion. Repeated cells reach the unchanged shot operation in order, so its existing ALREADY behavior remains; victory still stops remaining shots. AI and TORPEDO keep their own operands, handlers, output and action rules. JavaScript resolves the command token before membership in turnCommands and before the FIRE/AI comparisons. Canonicalization must precede both; adding only set membership would fall through to specialTurn. A null strategy selects the supplied cells, whereas AI supplies words[2] and choose is called for each shot. TORPEDO retains its guarded specialTurn call with row/side slice. shoot performs the statistics update; finishTurn receives the OR of all shot hits, including the early-victory prefix. fail throws and the per-input catch prints ERROR; one Program retains its Game between commands.

## Minimization and alternatives

Selected complete lines were reviewed individually and then as a standalone excerpt. Dispatch alone would identify an alias entry but not prove preservation of batch validation, failure boundaries, action order or completion; the FIRE body alone would miss the original name-resolution and AI/TORPEDO separation. Necessary state/statistics/completion hooks are retained where their connection is not otherwise visible. As explicitly permitted by the question, helper implementations for geometry, shot-result calculation, strategy algorithms and unrelated command functions are omitted. Adding all helpers or the full dispatcher would add independently unnecessary lines. Separate aliases in every downstream name test are a larger and error-prone alternative to canonicalizing the single input command token; global replacement of SHOT output text is not a command alias.

The excerpt contains 1330 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
