The enumeration starts from an empty partial permutation and chooses unused A,B,C,D in order at each depth. It prints "1: ABCD" first and "24: DCBA" last, for 4!=24 lines. After ADCB the return path restores used choices through the A branch, unmarks A, chooses B and then A,C,D, producing BACD.

word stores the partial positions and used stores availability. Recursive depth advances until 4; each position is overwritten on a new branch and used[i] resets after return, so no deep copy or prefix rollback is needed.

Fresh partial/used state, ordered choices, restoration and output counter establish first/last permutations and the ADCB-to-BACD transition. A library permutation implementation is not assumed.
