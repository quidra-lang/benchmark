final class FixedPoint {
    static final long S = 4096;
    static long divide(long a, long b) {
        return Math.floorDiv(a, b);
    }
    static long multiply(long a, long b) {
        return divide(a * b, S);
    }
    static long isqrt(long n) {
        if (n == 0)
            return 0;
        long x = n, y = (x + 1) / 2;
        while (y < x) {
            x = y;
            y = (x + n / x) / 2;
        }
        return x;
    }
}
