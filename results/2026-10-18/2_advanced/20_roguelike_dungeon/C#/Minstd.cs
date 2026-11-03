using System;

sealed class Minstd {
    int state;
    public Minstd(int seed) { state = seed; }
    public int Draw() { state = (int)(48271L * state % 2147483647); return state; }
    public int Rnd(int n) => Draw() % n;
    public int Roll(int count, int sides) {
        int total = 0;
        for (int i = 0; i < count; i++) total += 1 + Rnd(sides);
        return total;
    }
    public int Select(int[] weights) {
        int total = 0;
        foreach (int weight in weights) total += weight;
        int q = Rnd(total), cumulative = 0;
        for (int i = 0; i < weights.Length; i++) { cumulative += weights[i]; if (q < cumulative) return i; }
        throw new ArgumentException();
    }
}
