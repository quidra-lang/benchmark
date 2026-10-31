import java.util.*;

final class Minstd {
    private long state;
    Minstd(int seed) {
        state = seed;
    }
    int draw() {
        state = state * 48271 % 2147483647;
        return (int)state;
    }
    int below(int limit) {
        return draw() % limit;
    }
    boolean chance(int[] fraction) {
        return draw() % fraction[1] < fraction[0];
    }
    void shuffle(List<Integer> sequence) {
        for (int length = sequence.size(); length >= 2; length--)
            Collections.swap(sequence, length - 1, below(length));
    }
}
