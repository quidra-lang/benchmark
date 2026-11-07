The first two MINSTD states are 595905495 and 1558181227, yielding dice 4 and 2 and sum 6. Each of 1000 trials advances the state exactly twice and increments one sum bucket. Eleven bucket lines for sums 2..12 plus one most-frequent line give twelve lines; equal maxima retain the smaller sum.

Array.new(13,0) represents zero buckets. The ascending range supplies output order and max_by returns the first maximum encountered, giving the smaller tied sum.

The seed/recurrence, two random reads, bucket update and strict winner scan are necessary for the first trial and smaller-sum tie rule; full arrays of all trials are not source evidence.
