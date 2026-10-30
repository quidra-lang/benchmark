using System;
using System.Collections.Generic;
public static class Search {
    public record State(int position, int remaining, int lower, int upper);
    public record Leaf(int lower, int upper, int mismatches);
    public record Result(int nodes, List<Leaf> leaves, int positions);
    public static int[] Bounds(string sequence, FmIndex reverse) {
        int[] values = new int[sequence.Length];
        int mismatches = 0;
        FmIndex.Interval range = new(0, reverse.size);
        for (int i = 0; i < values.Length; i++) {
            range = reverse.Extend(range.lower, range.upper, sequence[i]);
            if (range.Empty()) {
                mismatches++;
                range = new(0, reverse.size);
            }
            values[i] = mismatches;
        }
        return values;
    }
    public static Result Backtrack(string sequence, int maximum, FmIndex forward, FmIndex reverse) {
        int[] bounds = Bounds(sequence, reverse);
        Stack<State> stack = new();
        stack.Push(new(sequence.Length - 1, maximum, 0, forward.size));
        int nodes = 0, positions = 0;
        List<Leaf> leaves = new();
        while (stack.Count != 0) {
            State state = stack.Pop();
            nodes++;
            if (state.remaining < (state.position < 0 ? 0 : bounds[state.position]))
                continue;
            if (state.position == -1) {
                leaves.Add(new(state.lower, state.upper, maximum - state.remaining));
                positions += state.upper - state.lower;
                continue;
            }
            foreach (char b in "TGCA") {
                FmIndex.Interval range = forward.Extend(state.lower, state.upper, b);
                if (range.Empty())
                    continue;
                int mismatch = b == sequence[state.position] ? 0 : 1;
                if (mismatch == 0 || state.remaining >= 1)
                    stack.Push(new(state.position - 1, state.remaining - mismatch, range.lower,
                                   range.upper));
            }
        }
        return new(nodes, leaves, positions);
    }
}
