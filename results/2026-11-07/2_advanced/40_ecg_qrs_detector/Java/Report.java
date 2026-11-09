final class Report {
    static long div(long a, long b) {
        return Math.floorDiv(a, b);
    }
    static long rdiv(long a, long b) {
        return div(2 * a + b, 2 * b);
    }
    static long root(long p, long q) {
        long value = div(40000 * p, q), low = 0, high = value + 1;
        while (high - low > 1) {
            long middle = (low + high) / 2;
            if (middle <= value / middle)
                low = middle;
            else
                high = middle;
        }
        return (low + 1) / 2;
    }
    static String pad(String s, int width) {
        return " ".repeat(Math.max(0, width - s.length())) + s;
    }
    static String two(long h) {
        long a = Math.abs(h);
        String tail = Long.toString(a % 100);
        return (h < 0 ? "-" : "") + (a / 100) + "."
            + "0".repeat(2 - tail.length()) + tail;
    }
    static String four(long h) {
        String tail = Long.toString(h % 10000);
        return (h / 10000) + "."
            + "0".repeat(4 - tail.length()) + tail;
    }
    static String fraction(long a, long b) {
        long x = a, y = b;
        while (y != 0) {
            long remainder = x % y;
            x = y;
            y = remainder;
        }
        return (a / x) + "/" + (b / x);
    }
    static String ratio(long a, long b) {
        return a + "/" + b +
            (b == 0 ? " none" : " reduced=" + fraction(a, b) + " percent=" + two(rdiv(10000 * a, b)));
    }
    static String maybe(long value) {
        return value < 0 ? "none" : two(value);
    }
    static String dash(Object value) {
        return value == null ? "-" : value.toString();
    }
}
