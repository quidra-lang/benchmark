import java.util.*;

final class Hrv {
    static long sum(List<Long> values) {
        long result = 0;
        for (long value : values)
            result += value;
        return result;
    }
    static long squares(List<Long> values) {
        long result = 0;
        for (long value : values)
            result += value * value;
        return result;
    }
    static long mean(List<Long> values) {
        return values.isEmpty() ? -1 : Report.rdiv(100 * sum(values), values.size());
    }
    static long heartRate(List<Long> values) {
        return values.isEmpty() ? -1 : Report.rdiv(6000000L * values.size(), sum(values));
    }
    static final class Rr {
        int count, shortBeat, longBeat;
        long mean = -1, hr = -1, shortest = Long.MAX_VALUE, longest = -1;
    }
    static Rr rr(List<Main.Beat> beats) {
        Rr result = new Rr();
        List<Long> values = new ArrayList<>();
        for (Main.Beat b : beats)
            if (b.number > 1) {
                values.add(b.rr);
                if (b.rr < result.shortest) {
                    result.shortest = b.rr;
                    result.shortBeat = b.number;
                }
                if (b.rr > result.longest) {
                    result.longest = b.rr;
                    result.longBeat = b.number;
                }
            }
        result.count = values.size();
        result.mean = mean(values);
        result.hr = heartRate(values);
        return result;
    }
    static final class Nn {
        int e, k, nn50, maximum;
        long mean = -1, sdnn = -1, rmssd = -1, sdsd = -1, pnn50 = -1, sd1 = -1, sd2 = -1;
        SortedMap<Long, Integer> histogram = new TreeMap<>();
    }
    static Nn nn(List<Main.Beat> beats) {
        Nn result = new Nn();
        boolean[] normal = new boolean[beats.size()];
        List<Long> values = new ArrayList<>(), differences = new ArrayList<>(), sums = new ArrayList<>();
        for (int i = 2; i < beats.size(); i++) {
            Main.Beat b = beats.get(i), previous = beats.get(i - 1);
            if (b.label.equals("N") && previous.label.equals("N") &&
                5 * Math.abs(b.rr - previous.rr) <= previous.rr) {
                normal[i] = true;
                values.add(b.rr);
                if (normal[i - 1]) {
                    differences.add(b.rr - previous.rr);
                    sums.add(b.rr + previous.rr);
                }
            }
        }
        int e = values.size(), k = differences.size();
        result.e = e;
        result.k = k;
        result.mean = mean(values);
        long total = sum(values);
        if (e >= 2)
            result.sdnn = Report.root(e * squares(values) - total * total, (long)e * (e - 1));
        long ds = sum(differences), ys = sum(sums), d2 = squares(differences);
        for (long d : differences)
            if (Math.abs(d) > 50)
                result.nn50++;
        if (k > 0) {
            result.rmssd = Report.root(d2, k);
            result.pnn50 = Report.rdiv(10000L * result.nn50, k);
        }
        if (k >= 2) {
            long numerator = k * d2 - ds * ds, denominator = (long)k * (k - 1);
            result.sdsd = Report.root(numerator, denominator);
            result.sd1 = Report.root(numerator, 2 * denominator);
            result.sd2 = Report.root(k * squares(sums) - ys * ys, 2 * denominator);
        }
        for (long u : values) {
            long bin = 16 * u / 125;
            result.histogram.put(bin, result.histogram.getOrDefault(bin, 0) + 1);
        }
        for (int value : result.histogram.values())
            result.maximum = Math.max(result.maximum, value);
        return result;
    }
    static List<int[]> ranges(List<Integer> indices) {
        List<int[]> result = new ArrayList<>();
        for (int i : indices) {
            if (!result.isEmpty() && result.getLast()[1] + 1 == i)
                result.getLast()[1] = i;
            else
                result.add(new int[] {i, i});
        }
        return result;
    }
}
