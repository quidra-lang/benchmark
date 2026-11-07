final class Minstd {
    private int state;
    Minstd(int seed) { state = seed; }
    int draw() { state = (int) (48271L * state % 2147483647); return state; }
    int rnd(int n) { return draw() % n; }
    int roll(int count, int sides) {
        int total = 0;
        for (int i = 0; i < count; i++) total += 1 + rnd(sides);
        return total;
    }
    int select(int[] weights) {
        int total = 0;
        for (int weight : weights) total += weight;
        int q = rnd(total), cumulative = 0;
        for (int i = 0; i < weights.length; i++) { cumulative += weights[i]; if (q < cumulative) return i; }
        throw new IllegalArgumentException();
    }
}
