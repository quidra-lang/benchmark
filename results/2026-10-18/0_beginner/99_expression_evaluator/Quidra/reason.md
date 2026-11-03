# Task B selection: 99_expression_evaluator / Quidra

The question requires the integer division change site and the already evaluated operands needed for a floor correction. The selected int value and int right bindings establish integer operands, and value /= right identifies the truncating quotient update. At that local site compute the truncating quotient and remainder, then decrement only when the remainder is nonzero and operand signs differ. Exact divisions and nonnegative quotients keep their truncating result. Keep the existing right-operand evaluation, zero check, try propagation, precedence loops and success-only assignment unchanged.

The compiler repairs preserve every const tokens/variables parameter and all explicit int types. A local map<string, int> value copy isolates map.get's generated scratch field from the const input; ordinary value semantics ensure the caller's map cannot change. A typed int temporary evaluates unary negation before returning it through int | error, avoiding the pinned backend's incorrect union-return negation lowering. Neither repair changes the requested Task B division boundary or implements floor division.

The original three-line excerpt remains byte-for-byte sufficient for the local modification. A bare /= line omits operand-type evidence, while the complete parser or contiguous span adds unchanged parsing, error and assignment machinery. These remain preservation constraints, not change sites. No omitted helper body is used to infer a return value or external I/O behavior.

Selected complete main.qui lines: 25, 31, 37. Each is copied verbatim once and in source order.

Using unchanged metric/tokenizer.py: Task A **1035** tokens; Task B **52** tokens. These are source-token measures. This is a minimized sufficient selection among the reviewed alternatives, not a proof of a global minimum. Native compiler/output checks are recorded separately in validation.json.
