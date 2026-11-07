# Task B: 98_bank_queue_simulation / Julia

Rename the MINSTD state introduction and every recurrence left/right reference and random-value read to rng_state. The accumulated arrival time is a different binding: it adds interarrival intervals and is not the generator state, so its introduction and updates keep their current name. Reusing the same numeric type does not make these bindings identical.

The initial tuple binds state and arrival separately; state=mod(48271*state,...) and the die/interval reads follow the rename, while arrival+=... retains arrival.

Evidence is from `main.jl`, L4,L7,L8,L9,L10.

- L4: `state, arrival, total_wait, max_wait = 42, 0, 0, 0`
- L7: `state = (state*48271)%2147483647`
- L8: `arrival += state%5+1`
- L9: `state = (state*48271)%2147483647`
- L10: `service = state%7+2`

Minimization: The state and arrival introductions plus the two recurrence/read groups establish all references to this one state name. Customer queues and service assignment are outside scope. The selected complete original lines, in source order, cost 108 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 134, and the complete source costs 355. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
