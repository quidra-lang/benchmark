import java.util.*;
final class Report {
    record Statistics(int peak, int minimum, int maximum, long rms, int crossings) {}
    static String hex2(int value) {
        return String.format(Locale.ROOT, "%02X", value);
    }
    static String hex1(int value) {
        return Integer.toHexString(value).toUpperCase(Locale.ROOT);
    }
    static String hex8(long value) {
        return String.format(Locale.ROOT, "%08X", value);
    }
    static String aligned(long value, int width) {
        return String.format(Locale.ROOT, "%" + width + "d", value);
    }
    static List<String> dump(int[] samples, int size) {
        List<String> output = new ArrayList<>();
        for (int start = 0; start < size; start += 32) {
            StringBuilder line = new StringBuilder();
            for (int i = start; i < Math.min(size, start + 32); i++)
                line.append(hex2(samples[i]));
            output.add(line.toString());
        }
        return output;
    }
    static long adler(int[] samples, int size) {
        long a = 1, b = 0;
        for (int i = 0; i < size; i++) {
            a = (a + samples[i]) % 65521;
            b = (b + a) % 65521;
        }
        return b * 65536 + a;
    }
    static long isqrt(long n) {
        long low = 0, high = 1;
        while (high <= n / high)
            high *= 2;
        while (low + 1 < high) {
            long mid = (low + high) / 2;
            if (mid <= n / mid)
                low = mid;
            else
                high = mid;
        }
        return low;
    }
    static Statistics statistics(int[] values, int start, int length, int center) {
        int peak = 0, minimum = Integer.MAX_VALUE, maximum = Integer.MIN_VALUE, crossings = 0;
        long squares = 0;
        for (int i = start; i < start + length; i++) {
            long v = values[i] - center;
            peak = Math.max(peak, (int)Math.abs(v));
            minimum = Math.min(minimum, values[i]);
            maximum = Math.max(maximum, values[i]);
            squares += v * v;
            if (i > start && (values[i - 1] < center) != (values[i] < center))
                crossings++;
        }
        return new Statistics(peak, minimum, maximum, isqrt(squares / length), crossings);
    }
}
