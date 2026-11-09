final class Minstd {
    private long state;
    Minstd(long seed) { state = seed; }
    long draw() { state = 48271L * state % 2147483647L; return state; }
    int below(int limit) { return (int) (draw() % limit); }
    void shuffle(int[] items) {
        for (int i = items.length - 1; i > 0; i--) {
            int j = below(i + 1), value = items[i];
            items[i] = items[j]; items[j] = value;
        }
    }
    void shuffle(long[] items) {
        for (int i = items.length - 1; i > 0; i--) {
            int j = below(i + 1);
            long value = items[i]; items[i] = items[j]; items[j] = value;
        }
    }
}
