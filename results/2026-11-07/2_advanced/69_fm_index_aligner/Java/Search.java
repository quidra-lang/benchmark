import java.util.*;
final class Search {
    record State(int position, int remaining, int lower, int upper) {}
    record Leaf(int lower, int upper, int mismatches) {}
    record Result(int nodes, List<Leaf> leaves, int positions) {}
    static int[] bounds(String sequence, FmIndex reverse) {
        int[] values = new int[sequence.length()];
        int mismatches = 0;
        FmIndex.Interval interval = new FmIndex.Interval(0, reverse.size);
        for (int i = 0; i < values.length; i++) {
            interval = reverse.extend(interval.lower(), interval.upper(), sequence.charAt(i));
            if (interval.empty()) {
                mismatches++;
                interval = new FmIndex.Interval(0, reverse.size);
            }
            values[i] = mismatches;
        }
        return values;
    }
    static Result backtrack(String sequence, int maximum, FmIndex forward, FmIndex reverse) {
        int[] bounds = bounds(sequence, reverse);
        ArrayDeque<State> stack = new ArrayDeque<>();
        stack.push(new State(sequence.length() - 1, maximum, 0, forward.size));
        int nodes = 0, positions = 0;
        List<Leaf> leaves = new ArrayList<>();
        while (!stack.isEmpty()) {
            State state = stack.pop();
            nodes++;
            if (state.remaining() < (state.position() < 0 ? 0 : bounds[state.position()]))
                continue;
            if (state.position() == -1) {
                leaves.add(new Leaf(state.lower(), state.upper(), maximum - state.remaining()));
                positions += state.upper() - state.lower();
                continue;
            }
            for (char base : "TGCA".toCharArray()) {
                FmIndex.Interval interval = forward.extend(state.lower(), state.upper(), base);
                if (interval.empty())
                    continue;
                int mismatch = base == sequence.charAt(state.position()) ? 0 : 1;
                if (mismatch == 0 || state.remaining() >= 1)
                    stack.push(new State(state.position() - 1, state.remaining() - mismatch,
                                         interval.lower(), interval.upper()));
            }
        }
        return new Result(nodes, leaves, positions);
    }
}
