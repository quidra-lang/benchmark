The first two MINSTD states are 595905495 and 1558181227, yielding dice 4 and 2 and sum 6. Each of 1000 trials advances the state exactly twice and increments one sum bucket. Eleven bucket lines for sums 2..12 plus one most-frequent line give twelve lines; equal maxima retain the smaller sum.

List.filled initializes all buckets, i<1000 fixes trials, the sum loop prints 2..12 ascending and strict > preserves the first maximum.

The seed/recurrence, two random reads, bucket update and strict winner scan are necessary for the first trial and smaller-sum tie rule; full arrays of all trials are not source evidence.
