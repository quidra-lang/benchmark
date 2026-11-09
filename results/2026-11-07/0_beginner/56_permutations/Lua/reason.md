The enumeration starts from an empty partial permutation and chooses unused A,B,C,D in order at each depth. It prints "1: ABCD" first and "24: DCBA" last, for 4!=24 lines. After ADCB the return path restores used choices through the A branch, unmarks A, chooses B and then A,C,D, producing BACD.

The prefix string is immutable, concatenation constructs the child, and used[i]=false restores availability after return. The base case returns after its numbered output; finite 1..4 choice loops exhaust branches.

Fresh partial/used state, ordered choices, restoration and output counter establish first/last permutations and the ADCB-to-BACD transition. A library permutation implementation is not assumed.
