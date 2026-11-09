by_id is populated from messages, recording only nonempty ids. Its nil lookup triggers the single-line early return with "not found". Change only this literal; ID-only containers are not messages traversed by that map-building loop.

Lua table indexing yields nil for a missing key. The assigned values are message tables, so the nil test is an actual-message existence guard.

Evidence: main.lua: 373–375, 449–450, 452–453. The selected complete lines contain the decision and its necessary data dependencies. A guard-only excerpt would omit evidence that the lookup contains mailbox messages rather than every referenced ID. Body decoding, thread pruning and output writers are unnecessary for this literal-only change.

Excerpt-only review: reread the saved lines in source order against every requested outcome and removed unrelated work. The selected excerpt is 142 tokenizer tokens. The full selected source file(s) would be 10104 tokens; that alternative adds unrelated behavior without supporting another requested answer. Task A sources are retained; this is source review under the benchmark compilation/correctness assumption, not execution verification.
