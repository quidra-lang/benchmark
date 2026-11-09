# Task B: 98_bank_queue_simulation / J

Rename the MINSTD state introduction and every recurrence left/right reference and random-value read to rng_state. The accumulated arrival time is a different binding: it adds interarrival intervals and is not the generator state, so its introduction and updates keep their current name. Reusing the same numeric type does not make these bindings identical.

state holds the seed/recurrence result, while arrival starts at zero and adds a value derived from state; both random updates/read expressions resolve the state noun.

Evidence is from `main.ijs`, L2,L3,L7,L8,L9,L10.

- L2: `state =. 42`
- L3: `arrival =. 0`
- L7: `state =. 2147483647|48271*state`
- L8: `arrival =. arrival+1+5|state`
- L9: `state =. 2147483647|48271*state`
- L10: `service =. 2+7|state`

Minimization: The state and arrival introductions plus the two recurrence/read groups establish all references to this one state name. Customer queues and service assignment are outside scope. The selected complete original lines, in source order, cost 87 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 120, and the complete source costs 342. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
