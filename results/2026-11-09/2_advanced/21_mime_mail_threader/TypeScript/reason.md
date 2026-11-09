After a real message is appended, its nonempty id is registered in ids. Request lookup uses ids.get(id), and the missing value returns "not found". Change only this literal; a referenced-only thread container must not be inserted in ids.

Map.get yields undefined for an absent key; inserted message objects are truthy. Thus !message recognizes an absent actual message even if a thread node for the id exists.

Evidence: main.ts: 273–274, 487–490. The selected complete lines contain the decision and its necessary data dependencies. A guard-only excerpt would omit evidence that the lookup contains mailbox messages rather than every referenced ID. Body decoding, thread pruning and output writers are unnecessary for this literal-only change.

Excerpt-only review: reread the saved lines in source order against every requested outcome and removed unrelated work. The selected excerpt is 113 tokenizer tokens. The full selected source file(s) would be 8984 tokens; that alternative adds unrelated behavior without supporting another requested answer. Task A sources are retained; this is source review under the benchmark compilation/correctness assumption, not execution verification.
