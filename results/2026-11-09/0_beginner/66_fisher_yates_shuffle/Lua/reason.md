At final i=1, the state advances before j is selected as state modulo 2, so j is only 0 or 1. The swap executes even when j==i; a self-swap still consumed that random state. The decreasing loop stops before i=0.

The numeric for step -1 has inclusive lower bound 1. j is a logical zero-based index and both deck accesses translate it and i by +1; no j==i branch skips the update.

The decreasing index loop, random recurrence/read and unconditional swap establish the final state consumption. Earlier shuffling outcomes do not determine whether the last self-swap advances the generator.
