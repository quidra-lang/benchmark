import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

record HistogramBin(int lower, int upper, int frequency, int length, List<String> marks) {}
record Interval(double lower, double upper) {}
final class Capability {
    final int count, below, above;
    final double mean, within, sbar, overall, cp, cpu, cpl, cpk, pp, ppu, ppl, ppk, cpm, ppm;
    final Interval cpkInterval, ppkInterval;
    final String verdict;
    final List<HistogramBin> bins = new ArrayList<>();
    Capability(List<Subgroup> groups, Settings s, Constants c) {
        long total = 0, ranges = 0;
        double deviations = 0;
        List<Long> values = new ArrayList<>();
        for (Subgroup group : groups) {
            for (long value : group.values) values.add(value);
            total += group.total; ranges += group.range; deviations += group.sd;
        }
        count = values.size(); mean = (double)total / count;
        within = ((double)ranges / groups.size()) / c.d2(); sbar = (deviations / groups.size()) / c.c4();
        double squares = 0;
        for (long value : values) squares += (value - mean) * (value - mean);
        overall = Math.sqrt(squares / (count - 1));
        cp = (s.usl - s.lsl) / (6 * within); cpu = (s.usl - mean) / (3 * within); cpl = (mean - s.lsl) / (3 * within); cpk = Math.min(cpu, cpl);
        pp = (s.usl - s.lsl) / (6 * overall); ppu = (s.usl - mean) / (3 * overall); ppl = (mean - s.lsl) / (3 * overall); ppk = Math.min(ppu, ppl);
        double offset = mean - s.target;
        cpm = (s.usl - s.lsl) / (6 * Math.sqrt(overall * overall + offset * offset));
        cpkInterval = interval(cpk, s.ciZ); ppkInterval = interval(ppk, s.ciZ);
        below = (int)values.stream().filter(value -> value < s.lsl).count(); above = (int)values.stream().filter(value -> value > s.usl).count();
        ppm = (double)(1000000L * (below + above)) / count;
        verdict = cpk >= 1.33 ? "capable" : cpk >= 1 ? "marginal" : "incapable";
        long minimum = values.stream().mapToLong(Long::longValue).min().orElseThrow(), maximum = values.stream().mapToLong(Long::longValue).max().orElseThrow();
        int low = s.bin * (int)(Math.min(minimum, s.lsl) / s.bin), high = s.bin * (int)(Math.max(maximum, s.usl) / s.bin) + s.bin;
        int[] frequencies = new int[(high - low) / s.bin];
        for (long value : values) frequencies[(int)(value - low) / s.bin]++;
        int top = Arrays.stream(frequencies).max().orElseThrow();
        for (int j = 0; j < frequencies.length; j++) {
            int lower = low + j * s.bin, upper = lower + s.bin - 1, frequency = frequencies[j];
            List<String> marks = new ArrayList<>();
            if (lower <= s.lsl && s.lsl <= upper) marks.add("lsl");
            if (lower <= s.target && s.target <= upper) marks.add("target");
            if (lower <= s.usl && s.usl <= upper) marks.add("usl");
            bins.add(new HistogramBin(lower, upper, frequency, (50 * frequency + top - 1) / top, marks));
        }
    }
    private Interval interval(double index, double z) {
        double delta = z * Math.sqrt(1.0 / (9 * count) + index * index / (2 * (count - 1)));
        return new Interval(index - delta, index + delta);
    }
}
