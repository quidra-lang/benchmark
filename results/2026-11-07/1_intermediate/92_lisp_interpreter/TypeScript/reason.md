# Task B selection — TypeScript

## Answer requirements shared across languages

1. Explain sequential let* initialization, distinct lexical bindings for repeated names, and the environment retained by a closure made between two such bindings.
2. Trace variable lookup and set! to the nearest captured binding and explain the values read after shadowing or mutation; identify closure invocation environment/frame creation.
3. Contrast ordinary let initializers evaluated in the incoming environment with letrec names installed as uninitialized before initializer evaluation.

## Selected source locations

- `main.ts`: 67, 70, 71, 72, 74, 75, 78, 79, 80, 81, 84, 92, 93, 94, 95, 96, 97, 98, 99, 100, 106, 107, 109, 115, 118, 142, 143, 159, 160, 161, 162, 164, 165, 187, 190, 211, 214, 215, 216, 219, 220, 221, 222, 223, 224, 226, 227, 228, 229, 230, 231, 232, 234, 235, 236, 237, 238, 252, 254, 296, 297, 299

## Evidence and language semantics

The selected let* branch evaluates each initializer against the current scope, then constructs a child frame and installs just that binding. For `(let* ((x 1) (f (lambda () x)) (x 2)) (f))`, the first x belongs to an earlier frame; f saves that frame before the later x frame exists, and its call consequently reads 1. Its defining environment is used as the parent of a new call frame, not replaced by the caller's current environment. The selected symbol-evaluation and lookup paths show the nearest binding search. A set! in the final body finds the later x, so changing it leaves f's earlier x unchanged. A set! executed by a closure captured before the later x instead finds and updates the earlier x; f subsequently reads that new value. Thus repeated mutation of one shared x cell would produce observably different results.

The selected ordinary-let branch evaluates all initializers in the incoming environment before installing their results in one child frame. The letrec branch preinstalls every name with its sentinel in one frame, then evaluates initializers in that frame; reading a name before initialization raises the selected uninitialized-variable error. Closures created there retain that frame and can see its later initialized bindings.

Env and Proc are JavaScript reference objects; TypeScript annotations do not change that runtime behavior. The constructor stores the same env reference, and new Env initializes a fresh Map. Reassigning scope cannot change the earlier Proc.env.

## Minimization and alternatives

The selected source locations separately establish frame construction, parent search, captured-environment storage, call-time parent choice, assignment, and the three binding forms. Removing any one of these evidence categories would leave either closure identity, nearest-binding mutation, initializer environment, or the uninitialized-read contrast unsupported. Literal/value parsing, ordinary definition, named-let recursion, procedure arity checks, parameter-list validation, unrelated special forms, built-ins, output and the REPL are not needed for this valid lexical-binding example and were excluded. Parameter binding inside calls is also unnecessary for the zero-argument example.

Compared alternatives included full evaluator/procedure bodies, complete environment routines, and repeated copies of ordinary/named-let closure machinery. The selection keeps only the statements that carry the required semantics (and headers/continuation lines needed to identify those statements), rather than entire routines. Direct constructor assignments are sufficient evidence of reference retention; no memory-management or standard map-library implementation is needed. The excerpt was reviewed without relying on omitted parsing or named-let details.

The excerpt contains 1191 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
