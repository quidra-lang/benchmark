Rename the MINSTD binding state to rng_state at its introduction, both recurrence left/right references and both random reads for interarrival and service durations. arrival is a separately initialized accumulated time and retains its own name and updates; it is not another alias for random state.

state=42 and arrival=0 introduce independent locals. The two state*48271 modulo updates and state%5/state%7 reads all resolve to state; arrival += accumulates a time using one derived value.

The generator binding, recurrence and both random reads locate all rename uses. The separate arrival initializer/update is included only to disambiguate accumulated time from generator state.
