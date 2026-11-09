bodyReport scans []Message, accepting only a nonempty matching message.id. found stays null for an unknown requested ID; its null branch writes "not found" and returns. Change that literal. Scanning actual Message records never treats a Container as a mailbox message.

?*Message is an optional pointer; null is distinct from every actual message pointer. The scan and h.eq predicate, rather than thread-container existence, determine success.

Evidence: main.zig: 469, 472–479. The selected complete lines contain the decision and its necessary data dependencies. A guard-only excerpt would omit evidence that the lookup contains mailbox messages rather than every referenced ID. Body decoding, thread pruning and output writers are unnecessary for this literal-only change.

Excerpt-only review: reread the saved lines in source order against every requested outcome and removed unrelated work. The selected excerpt is 140 tokenizer tokens. The full selected source file(s) would be 12701 tokens; that alternative adds unrelated behavior without supporting another requested answer. Task A sources are retained; this is source review under the benchmark compilation/correctness assumption, not execution verification.
