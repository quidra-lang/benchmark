# Task B selection — Quidra

## Answer requirements shared across languages

1. Explain sequential let* initialization, distinct lexical bindings for repeated names, and the environment retained by a closure made between two such bindings.
2. Trace variable lookup and set! to the nearest captured binding and explain the values read after shadowing or mutation; identify closure invocation environment/frame creation.
3. Contrast ordinary let initializers evaluated in the incoming environment with letrec names installed as uninitialized before initializer evaluation.

## Selected source locations

- `main.qui`: 16, 17, 28, 29, 30, 31, 110, 111, 112, 113, 115, 116, 118, 119, 120, 121, 122, 123, 124, 125, 128, 129, 130, 131, 132, 133, 134, 188, 189, 194, 195, 196, 201, 202, 203, 204, 205, 207, 208, 209, 210, 233, 237, 259, 261, 262, 263, 264, 266, 267, 268, 271, 272, 273, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 293, 294, 295, 302, 303, 304, 334, 335, 336, 337, 338, 341, 520, 521, 528, 534

## Evidence and language semantics

The selected let* branch evaluates each initializer against the current scope, then constructs a child frame and installs just that binding. For `(let* ((x 1) (f (lambda () x)) (x 2)) (f))`, the first x belongs to an earlier frame; f saves that frame before the later x frame exists, and its call consequently reads 1. Its defining environment is used as the parent of a new call frame, not replaced by the caller's current environment. The selected symbol-evaluation and lookup paths show the nearest binding search. A set! in the final body finds the later x, so changing it leaves f's earlier x unchanged. A set! executed by a closure captured before the later x instead finds and updates the earlier x; f subsequently reads that new value. Thus repeated mutation of one shared x cell would produce observably different results.

The selected ordinary-let branch evaluates all initializers in the incoming environment before installing their results in one child frame. The letrec branch preinstalls every name with its sentinel in one frame, then evaluates initializers in that frame; reading a name before initialization raises the selected uninitialized-variable error. Closures created there retain that frame and can see its later initialized bindings.

The interpreter represents environments by integer indices into engine.frames. extend_frame appends a Frame with a new map and parent index; Value.env_id retains the defining index. Shared mutations are explicit through Engine &engine. Copying a Value or index does not clone the frame graph; bind updates the map at that retained index.

## Minimization and alternatives

The selected source locations separately establish frame construction, parent search, captured-environment storage, call-time parent choice, assignment, and the three binding forms. Removing any one of these evidence categories would leave either closure identity, nearest-binding mutation, initializer environment, or the uninitialized-read contrast unsupported. Literal/value parsing, ordinary definition, named-let recursion, procedure arity checks, parameter-list validation, unrelated special forms, built-ins, output and the REPL are not needed for this valid lexical-binding example and were excluded. Parameter binding inside calls is also unnecessary for the zero-argument example.

Compared alternatives included full evaluator/procedure bodies, complete environment routines, and repeated copies of ordinary/named-let closure machinery. The selection keeps only the statements that carry the required semantics (and headers/continuation lines needed to identify those statements), rather than entire routines. Direct constructor assignments are sufficient evidence of reference retention; no memory-management or standard map-library implementation is needed. The excerpt was reviewed without relying on omitted parsing or named-let details.

The excerpt contains 1431 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
