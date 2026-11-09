byID is filled only by actual messages with nonempty ID. A lookup produces a nil *Message when missing, and the nil branch returns "not found". Change that literal; do not use thread-container membership to bypass the branch.

Go map lookup of an absent key returns the element zero value, nil for *Message. No nil values are inserted by the selected loop.

The selected caller passes byID to the actual-message parameter of the body-report guard. Evidence: main.go: 662, 664–667, 810–815, 824. The selected complete lines contain the decision and its necessary data dependencies. A guard-only excerpt would omit evidence that the lookup contains mailbox messages rather than every referenced ID. Body decoding, thread pruning and output writers are unnecessary for this literal-only change.

Excerpt-only review: reread the saved lines in source order against every requested outcome and removed unrelated work. The selected excerpt is 157 tokenizer tokens. The full selected source file(s) would be 11273 tokens; that alternative adds unrelated behavior without supporting another requested answer. Task A sources are retained; this is source review under the benchmark compilation/correctness assumption, not execution verification.
