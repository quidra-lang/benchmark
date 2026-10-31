import java.util.List;

final class Minstd {
    long state;
    Minstd(long seed) { state = seed; }
    long draw() { return state = 48271 * state % 2147483647; }
    static int select(List<Long> weights, long draw) {
        long q = draw % weights.stream().mapToLong(Long::longValue).sum(), total = 0;
        for (int i = 0; i < weights.size(); i++) { total += weights.get(i); if (q < total) return i; }
        throw new IllegalStateException();
    }
}
