byId is populated from the messages vector using nonempty message.id; find(request)==end is the missing-message guard. Change only its "not found" literal. Referenced-only thread nodes cannot insert an actual-message entry.

std::map::find returns end for an absent key; the stored integer indexes the real messages vector, not the thread forest.

Evidence: main.cpp: 242–244, 276–278, 281, 283. The selected complete lines contain the decision and its necessary data dependencies. A guard-only excerpt would omit evidence that the lookup contains mailbox messages rather than every referenced ID. Body decoding, thread pruning and output writers are unnecessary for this literal-only change.

Excerpt-only review: reread the saved lines in source order against every requested outcome and removed unrelated work. The selected excerpt is 249 tokenizer tokens. The full selected source file(s) would be 10337 tokens; that alternative adds unrelated behavior without supporting another requested answer. Task A sources are retained; this is source review under the benchmark compilation/correctness assumption, not execution verification.
