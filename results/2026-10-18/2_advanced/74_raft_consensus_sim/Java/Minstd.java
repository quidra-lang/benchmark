final class Minstd {
    long state;
    int draws;
    Minstd(int seed) { state = seed; }
    int draw() {
        state = 48271 * state % 2147483647;
        draws++;
        return (int)state;
    }
    int between(int minimum, int maximum) { return minimum + draw() % (maximum - minimum + 1); }
}
