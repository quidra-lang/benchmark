At final i=1, the state advances before j is selected as state modulo 2, so j is only 0 or 1. The swap executes even when j==i; a self-swap still consumed that random state. The decreasing loop stops before i=0.

downto(1) is inclusive and terminates after 1; the state update, modulo and parallel swap appear in that exact order.

The decreasing index loop, random recurrence/read and unconditional swap establish the final state consumption. Earlier shuffling outcomes do not determine whether the last self-swap advances the generator.
