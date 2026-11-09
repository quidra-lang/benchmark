The by_id environment is filled only from real messages with a nonempty id. !exists(request,envir=by_id,inherits=FALSE) immediately returns "not found"; change this literal. An ID-only thread container is not registered by that message loop.

exists with inherits=FALSE checks this environment only; a name outside it cannot make the request succeed. Its values are actual mailbox messages.

Evidence: main.R: 452, 454, 536–537. The selected complete lines contain the decision and its necessary data dependencies. A guard-only excerpt would omit evidence that the lookup contains mailbox messages rather than every referenced ID. Body decoding, thread pruning and output writers are unnecessary for this literal-only change.

Excerpt-only review: reread the saved lines in source order against every requested outcome and removed unrelated work. The selected excerpt is 127 tokenizer tokens. The full selected source file(s) would be 10186 tokens; that alternative adds unrelated behavior without supporting another requested answer. Task A sources are retained; this is source review under the benchmark compilation/correctness assumption, not execution verification.
