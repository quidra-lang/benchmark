Rename the MINSTD binding state to rng_state at its introduction, both recurrence left/right references and both random reads for interarrival and service durations. arrival is a separately initialized accumulated time and retains its own name and updates; it is not another alias for random state.

The var declaration infers separate int locals. Rename every state occurrence in the displayed recurrence/reads, leaving arrival += and its initializer unchanged.

The generator binding, recurrence and both random reads locate all rename uses. The separate arrival initializer/update is included only to disambiguate accumulated time from generator state.
