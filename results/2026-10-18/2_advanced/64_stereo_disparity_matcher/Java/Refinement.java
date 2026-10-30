final class Refinement {
    static String hundredths(long value) {
        return value / 100 + "." + (value % 100 < 10 ? "0" : "") + value % 100;
    }
    static String two(long a, long b) { return hundredths((200 * a + b) / (2 * b)); }
    static long depthHundredths(int disparity, long focal, long baseline) {
        return (200 * focal * baseline + disparity) / (2 * disparity);
    }
    static String[] subpixel(int d, long[] costs, int min, int max, long focal, long baseline) {
        int index = d - min;
        long a = 0, b = 1;
        if (min < d && d < max && costs[index - 1] > costs[index] &&
            costs[index + 1] >= costs[index]) {
            a = costs[index - 1] - costs[index + 1];
            b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1]);
        }
        long q = (200 * (d * b + a) + b) / (2 * b);
        return new String[] {hundredths(q), two(100 * focal * baseline, q)};
    }
}
