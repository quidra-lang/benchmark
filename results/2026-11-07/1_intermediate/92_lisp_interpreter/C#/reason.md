# Task B selection — C#

## Answer requirements shared across languages

1. Explain sequential let* initialization, distinct lexical bindings for repeated names, and the environment retained by a closure made between two such bindings.
2. Trace variable lookup and set! to the nearest captured binding and explain the values read after shadowing or mutation; identify closure invocation environment/frame creation.
3. Contrast ordinary let initializers evaluated in the incoming environment with letrec names installed as uninitialized before initializer evaluation.

## Selected source locations

- `Program.cs`: 10, 12, 13, 14, 15, 16, 19, 20, 21, 22, 25, 34, 38, 41, 97, 98, 117, 118, 119, 120, 122, 124, 144, 148, 165, 168, 169, 170, 173, 174, 175, 176, 177, 178, 179, 181, 182, 183, 184, 185, 186, 187, 190, 191, 192, 194, 195, 202, 204, 241, 242, 243, 244

## Evidence and language semantics

The selected let* branch evaluates each initializer against the current scope, then constructs a child frame and installs just that binding. For `(let* ((x 1) (f (lambda () x)) (x 2)) (f))`, the first x belongs to an earlier frame; f saves that frame before the later x frame exists, and its call consequently reads 1. Its defining environment is used as the parent of a new call frame, not replaced by the caller's current environment. The selected symbol-evaluation and lookup paths show the nearest binding search. A set! in the final body finds the later x, so changing it leaves f's earlier x unchanged. A set! executed by a closure captured before the later x instead finds and updates the earlier x; f subsequently reads that new value. Thus repeated mutation of one shared x cell would produce observably different results.

The selected ordinary-let branch evaluates all initializers in the incoming environment before installing their results in one child frame. The letrec branch preinstalls every name with its sentinel in one frame, then evaluates initializers in that frame; reading a name before initialization raises the selected uninitialized-variable error. Closures created there retain that frame and can see its later initialized bindings.

Environment and Procedure are reference types. New dictionaries belong to new Environment instances; retaining Scope preserves the earlier reference. Find returns the owning frame and Frame[name] assignment updates that particular dictionary.

## Minimization and alternatives

The selected source locations separately establish frame construction, parent search, captured-environment storage, call-time parent choice, assignment, and the three binding forms. Removing any one of these evidence categories would leave either closure identity, nearest-binding mutation, initializer environment, or the uninitialized-read contrast unsupported. Literal/value parsing, ordinary definition, named-let recursion, procedure arity checks, parameter-list validation, unrelated special forms, built-ins, output and the REPL are not needed for this valid lexical-binding example and were excluded. Parameter binding inside calls is also unnecessary for the zero-argument example.

Compared alternatives included full evaluator/procedure bodies, complete environment routines, and repeated copies of ordinary/named-let closure machinery. The selection keeps only the statements that carry the required semantics (and headers/continuation lines needed to identify those statements), rather than entire routines. Direct constructor assignments are sufficient evidence of reference retention; no memory-management or standard map-library implementation is needed. The excerpt was reviewed without relying on omitted parsing or named-let details.

The excerpt contains 1168 tokens under `metric/tokenizer.py`. Only complete source lines are counted; the question and this rationale are excluded. Task B uses the README assumption that the Task A program satisfies its contract; this selection does not claim compilation or runtime verification.
