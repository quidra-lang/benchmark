import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.stream.IntStream;

final class Summary {
    final double estimate, average, se, bias, low, high, basicLow, basicHigh;
    final double[] values, ordered;
    Summary(double estimate, double[] values, int lowRank, int highRank) {
        this.estimate = estimate; this.values = values;
        ordered = values.clone(); Arrays.sort(ordered);
        double[] spread = Resampling.meanAndSe(values);
        average = spread[0]; se = spread[1]; bias = average - estimate;
        low = ordered[lowRank - 1]; high = ordered[highRank - 1];
        basicLow = 2 * estimate - high; basicHigh = 2 * estimate - low;
    }
    String csv(String name, String statistic) {
        List<String> fields = new ArrayList<>(List.of(name, statistic));
        for (double value : new double[] {estimate, se, bias, low, high, basicLow, basicHigh}) fields.add(Report.real(value));
        return String.join(",", fields);
    }
    String interval() {
        return "se " + Report.real(se) + " bias " + Report.real(bias) + " percentile " + Report.real(low) + " " + Report.real(high)
            + " basic " + Report.real(basicLow) + " " + Report.real(basicHigh);
    }
}

final class GroupBootstrap {
    final Group group;
    final int[][] indices;
    final long[][] samples;
    final Summary[] summaries = new Summary[4];
    GroupBootstrap(Group group, int[][] indices, int low, int high) {
        this.group = group; this.indices = indices;
        samples = Arrays.stream(indices).map(replicate -> Resampling.sample(group.values(), replicate)).toArray(long[][]::new);
        for (int statistic = 0; statistic < 4; statistic++) {
            double[] values = new double[indices.length];
            for (int i = 0; i < values.length; i++) values[i] = Resampling.groupStatistic(statistic, samples[i]);
            summaries[statistic] = new Summary(Resampling.groupStatistic(statistic, group.values()), values, low, high);
        }
    }
}

final class PairBootstrap {
    final GroupBootstrap first, second;
    final String name;
    final Summary[] summaries = new Summary[4];
    PairBootstrap(GroupBootstrap first, GroupBootstrap second, int low, int high) {
        this.first = first; this.second = second; name = first.group.name() + "-" + second.group.name();
        for (int statistic = 0; statistic < 4; statistic++) {
            double[] values = new double[first.samples.length];
            for (int i = 0; i < values.length; i++) values[i] = Resampling.pairStatistic(statistic, first.samples[i], second.samples[i]);
            summaries[statistic] = new Summary(Resampling.pairStatistic(statistic, first.group.values(), second.group.values()), values, low, high);
        }
    }
}

final class Jackknife {
    final double[] values;
    final double average, variance, bias, se;
    Jackknife(double estimate, double[] values) {
        this.values = values;
        double[] spread = Study.jackknifeSpread(values);
        average = spread[0]; variance = spread[1]; bias = (values.length - 1) * (average - estimate); se = Math.sqrt(variance);
    }
}

final class Tally {
    final long observed;
    int extreme, greater;
    Tally(long observed) { this.observed = observed; }
    void count(long value) {
        if (Math.abs(value) >= Math.abs(observed)) extreme++;
        if (value >= observed) greater++;
    }
    String text(int offset, int denominator) {
        return "extreme " + extreme + " greater " + greater + " p_two " + Report.pValue(extreme + offset, denominator)
            + " p_greater " + Report.pValue(greater + offset, denominator);
    }
}

record DisplayRange(long low, long delta) {
    DisplayRange(long[] values) { this(Arrays.stream(values).min().orElseThrow(), 100 * (Arrays.stream(values).max().orElseThrow() - Arrays.stream(values).min().orElseThrow())); }
    int position(long value) { return (int) ((120 * (value - 100 * low) + delta) / (2 * delta)); }
}
record TestResult(List<String> lines, int[] extremes) {}
record Delta(long numerator, long denominator) implements Comparable<Delta> {
    public int compareTo(Delta other) { return Long.compare(numerator * other.denominator, other.numerator * denominator); }
}

final class Study {
    static final String[] GROUP_STATISTICS = {"mean", "median", "trimmed_mean", "sd"};
    static final String[] PAIR_STATISTICS = {"mean_diff", "median_ratio", "hodges_lehmann", "cohen_d"};
    static final String[] TEST_STATISTICS = {"mean", "median", "ranksum", "absdev"};
    final Dataset data;
    final Settings settings;
    final Minstd generator;
    final int lowRank, highRank;
    final double zLow;

    Study(Dataset data) {
        this.data = data; settings = data.settings(); generator = new Minstd(settings.seed());
        lowRank = (settings.bootstrap() + 1) * (100 - settings.confidence()) / 200;
        highRank = settings.bootstrap() + 1 - lowRank;
        zLow = Resampling.phiInverse((100 - settings.confidence()) / 200.0);
    }
    static String r(double value) { return Report.real(value); }
    static String p(long numerator, long denominator) { return Report.pValue(numerator, denominator); }
    static long[] concat(long[] first, long[] second) {
        long[] result = Arrays.copyOf(first, first.length + second.length);
        System.arraycopy(second, 0, result, first.length, second.length);
        return result;
    }
    static double[] jackknifeSpread(double[] values) {
        double average = Resampling.sequentialSum(values) / values.length, squares = 0;
        for (double value : values) { double difference = value - average; squares += difference * difference; }
        return new double[] {average, (values.length - 1) * squares / values.length};
    }
    List<Integer> outliers(long[] values) {
        long first = Resampling.quantileNumerator(values, 25), third = Resampling.quantileNumerator(values, 75);
        List<Integer> outliers = new ArrayList<>();
        for (int i = 0; i < values.length; i++)
            if (200 * values[i] < 5 * first - 3 * third || 200 * values[i] > 5 * third - 3 * first) outliers.add(i);
        return outliers;
    }
    List<String> seriesLines(String kind, String name, long[] values, DisplayRange display, boolean stems) {
        long[] ordered = Resampling.sorted(values);
        int count = values.length;
        double mean = Resampling.mean(values), sd = Resampling.sd(values);
        double[] moments = Resampling.centralMoments(values);
        long[] clipped = Resampling.winsorized(values);
        long first = Resampling.quantileNumerator(values, 25), third = Resampling.quantileNumerator(values, 75);
        List<Integer> outliers = outliers(values);
        long low = Long.MAX_VALUE, high = Long.MIN_VALUE;
        for (int i = 0; i < count; i++) if (!outliers.contains(i)) { low = Math.min(low, values[i]); high = Math.max(high, values[i]); }
        char[] band = new char[61]; Arrays.fill(band, '.');
        Arrays.fill(band, display.position(100 * low), display.position(100 * high) + 1, '-');
        Arrays.fill(band, display.position(first), display.position(third) + 1, '=');
        band[display.position(Resampling.quantileNumerator(values, 50))] = '|';
        for (int index : outliers) band[display.position(100 * values[index])] = 'o';
        List<String> lines = new ArrayList<>(List.of(kind + " " + name, "n " + count, "mean " + r(mean), "median " + r(Resampling.median(values)),
            "trimmed_mean " + r(Resampling.trimmedMean(values)) + " trim " + count / 10,
            "winsorized_mean " + r(Resampling.mean(clipped)) + " winsorized_sd " + r(Resampling.sd(clipped)), "sd " + r(sd),
            "se_mean " + r(sd / Math.sqrt(count)), "cv " + r(sd / mean), "skewness " + r(moments[1] / (moments[0] * Math.sqrt(moments[0]))),
            "kurtosis " + r(moments[2] / (moments[0] * moments[0]) - 3), "mad " + r(Resampling.mad(values)), "min " + r(ordered[0] / 100.0),
            "q1 " + r(first / 10000.0), "q3 " + r(third / 10000.0), "iqr " + r((third - first) / 10000.0), "max " + r(ordered[count - 1] / 100.0)));
        List<String> percentiles = new ArrayList<>();
        for (int percent : new int[] {5, 10, 90, 95}) percentiles.add("p" + (percent < 10 ? "0" : "") + percent + " " + r(Resampling.quantileNumerator(values, percent) / 10000.0));
        lines.add("percentiles " + String.join(" ", percentiles));
        lines.add("whiskers " + r(low / 100.0) + " " + r(high / 100.0));
        lines.add("outliers " + Report.numberList(outliers.stream().map(index -> index + 1).toList()));
        lines.add("box " + new String(band));
        if (stems) for (long stem = ordered[0] / 100; stem <= ordered[count - 1] / 100; stem++) {
            StringBuilder leaves = new StringBuilder();
            for (long value : ordered) if (value / 100 == stem) leaves.append(value % 100 / 10);
            lines.add("stem " + stem + (leaves.isEmpty() ? "" : " " + leaves));
        }
        return lines;
    }
    List<String> descriptiveLines() {
        long[] everything = data.groups().stream().flatMapToLong(group -> Arrays.stream(group.values())).toArray();
        List<String> lines = new ArrayList<>(List.of("groups " + data.groups().size() + " observations " + everything.length));
        DisplayRange display = new DisplayRange(everything);
        for (Group group : data.groups()) lines.addAll(seriesLines("group", group.name(), group.values(), display, true));
        PairedSample paired = data.paired();
        lines.add("paired subjects " + paired.differences().length);
        display = new DisplayRange(concat(paired.before(), paired.after()));
        lines.addAll(seriesLines("series", "before", paired.before(), display, false));
        lines.addAll(seriesLines("series", "after", paired.after(), display, false));
        lines.addAll(seriesLines("series", "diff", paired.differences(), new DisplayRange(paired.differences()), false));
        return lines;
    }
    Summary[] pairedBootstrap() {
        PairedSample paired = data.paired();
        double[] means = new double[settings.bootstrap()], correlations = new double[settings.bootstrap()];
        int[][] indices = Resampling.ordinaryIndices(generator, paired.before().length, settings.bootstrap());
        for (int i = 0; i < indices.length; i++) {
            means[i] = Resampling.mean(Resampling.sample(paired.differences(), indices[i]));
            correlations[i] = Resampling.correlation(Resampling.sample(paired.before(), indices[i]), Resampling.sample(paired.after(), indices[i]));
        }
        return new Summary[] {new Summary(Resampling.mean(paired.differences()), means, lowRank, highRank),
            new Summary(Resampling.correlation(paired.before(), paired.after()), correlations, lowRank, highRank)};
    }
    List<String> bootstrapLines(List<GroupBootstrap> ordinary, List<GroupBootstrap> balanced, List<PairBootstrap> pairs) {
        List<String> lines = new ArrayList<>(List.of("group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"));
        for (int i = 0; i < ordinary.size(); i++) {
            for (int statistic = 0; statistic < 4; statistic++) lines.add(ordinary.get(i).summaries[statistic].csv(ordinary.get(i).group.name(), GROUP_STATISTICS[statistic]));
            for (int statistic = 0; statistic < 4; statistic++) lines.add(balanced.get(i).summaries[statistic].csv(ordinary.get(i).group.name(), "balanced_" + GROUP_STATISTICS[statistic]));
        }
        for (PairBootstrap pair : pairs) for (int statistic = 0; statistic < 4; statistic++) lines.add(pair.summaries[statistic].csv(pair.name, PAIR_STATISTICS[statistic]));
        return lines;
    }
    List<String> histogramLines(String name, String statistic, Summary summary) {
        int bins = settings.bins(), top = 0;
        double low = summary.ordered[0], high = summary.ordered[summary.ordered.length - 1];
        int[] counts = new int[bins];
        for (double value : summary.values) counts[Report.binNumber(value, low, high, bins) - 1]++;
        for (int count : counts) top = Math.max(top, count);
        List<List<String>> marks = new ArrayList<>();
        for (int i = 0; i < bins; i++) marks.add(new ArrayList<>());
        marks.get(Report.binNumber(summary.low, low, high, bins) - 1).add("L");
        String estimateBin = "none";
        if (summary.estimate >= low && summary.estimate <= high) {
            int bin = Report.binNumber(summary.estimate, low, high, bins);
            estimateBin = Integer.toString(bin); marks.get(bin - 1).add("E");
        }
        marks.get(Report.binNumber(summary.high, low, high, bins) - 1).add("H");
        List<String> convergence = new ArrayList<>();
        for (int quarter = 1; quarter <= 4; quarter++) {
            int size = quarter * settings.bootstrap() / 4;
            convergence.add(size + ":" + r(Resampling.meanAndSe(Arrays.copyOf(summary.values, size))[1]));
        }
        List<String> lines = new ArrayList<>(List.of("histogram " + name + " " + statistic + " min " + r(low) + " max " + r(high)
            + " width " + r((high - low) / bins) + " top " + top + " estimate_bin " + estimateBin, "convergence " + String.join(" ", convergence)));
        for (int i = 0; i < bins; i++) {
            String line = "bin " + (i + 1) + " " + r(low + (high - low) * i / bins) + " " + counts[i];
            if (counts[i] > 0) line += " " + Report.bar(counts[i], top);
            if (!marks.get(i).isEmpty()) line += " " + String.join(" ", marks.get(i));
            lines.add(line);
        }
        return lines;
    }
    String bcaLine(String statistic, Summary summary, Jackknife jackknife) {
        int below = (int) Arrays.stream(summary.values).filter(value -> value < summary.estimate).count();
        double z0 = Resampling.phiInverse((double) below / settings.bootstrap()), squares = 0, cubes = 0;
        for (double value : jackknife.values) {
            double difference = jackknife.average - value;
            squares += difference * difference; cubes += difference * difference * difference;
        }
        double acceleration = cubes / (6 * squares * Math.sqrt(squares));
        int lower = (int) Math.floor((settings.bootstrap() + 1) * bcaAlpha(z0, acceleration, zLow));
        int upper = settings.bootstrap() + 1 - (int) Math.floor((settings.bootstrap() + 1) * (1 - bcaAlpha(z0, acceleration, -zLow)));
        lower = Math.min(Math.max(lower, 1), settings.bootstrap()); upper = Math.min(Math.max(upper, 1), settings.bootstrap());
        return "bca " + statistic + " below " + below + " z0 " + r(z0) + " acceleration " + r(acceleration) + " ranks " + lower + " " + upper
            + " interval " + r(summary.ordered[lower - 1]) + " " + r(summary.ordered[upper - 1]);
    }
    double bcaAlpha(double z0, double acceleration, double z) { return Resampling.phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z))); }
    List<String> groupJackknife(GroupBootstrap bootstrap) {
        long[] values = bootstrap.group.values();
        int count = values.length;
        Jackknife[] jackknives = new Jackknife[4];
        List<String> lines = new ArrayList<>(List.of("group " + bootstrap.group.name() + " n " + count));
        for (int statistic = 0; statistic < 4; statistic++) {
            double[] removed = new double[count];
            for (int i = 0; i < count; i++) removed[i] = Resampling.groupStatistic(statistic, Resampling.without(values, i));
            Jackknife jackknife = new Jackknife(bootstrap.summaries[statistic].estimate, removed);
            jackknives[statistic] = jackknife;
            lines.add("jackknife " + GROUP_STATISTICS[statistic] + " estimate " + r(bootstrap.summaries[statistic].estimate) + " average " + r(jackknife.average)
                + " bias " + r(jackknife.bias) + " se " + r(jackknife.se));
        }
        for (int statistic = 0; statistic < 4; statistic++) lines.add(bcaLine(GROUP_STATISTICS[statistic], bootstrap.summaries[statistic], jackknives[statistic]));
        List<List<Integer>> omitted = new ArrayList<>();
        for (int i = 0; i < count; i++) omitted.add(new ArrayList<>());
        for (int replicate = 0; replicate < bootstrap.indices.length; replicate++) {
            boolean[] chosen = new boolean[count];
            for (int index : bootstrap.indices[replicate]) chosen[index] = true;
            for (int i = 0; i < count; i++) if (!chosen[i]) omitted.get(i).add(replicate);
        }
        double[][] errors = new double[4][count];
        for (int statistic = 0; statistic < 4; statistic++) {
            Summary summary = bootstrap.summaries[statistic];
            for (int i = 0; i < count; i++) errors[statistic][i] = Resampling.meanAndSe(omitted.get(i).stream().mapToDouble(index -> summary.values[index]).toArray())[1];
            double[] spread = jackknifeSpread(errors[statistic]);
            lines.add("after_bootstrap " + GROUP_STATISTICS[statistic] + " se " + r(summary.se) + " average " + r(spread[0]) + " se_of_se " + r(Math.sqrt(spread[1])));
        }
        lines.add("without min " + omitted.stream().mapToInt(List::size).min().orElseThrow() + " max " + omitted.stream().mapToInt(List::size).max().orElseThrow());
        long total = Resampling.sum(values);
        List<Integer> ranking = IntStream.range(0, count).boxed().sorted(Comparator.<Integer>comparingLong(index -> Math.abs(count * values[index] - total)).reversed().thenComparingInt(index -> index)).limit(5).toList();
        for (int rank = 0; rank < ranking.size(); rank++) {
            int index = ranking.get(rank), size = omitted.get(index).size();
            double influence = (count - 1) * (jackknives[0].average - jackknives[0].values[index]);
            Summary summary = bootstrap.summaries[0];
            double[] shifted = omitted.get(index).stream().mapToDouble(replicate -> summary.values[replicate] - summary.estimate).sorted().toArray();
            lines.add("influence " + (rank + 1) + " obs " + (index + 1) + " value " + r(values[index] / 100.0) + " l " + r(influence) + " without " + size
                + " se " + r(errors[0][index]) + " q05 " + r(shifted[(5 * size + 99) / 100 - 1]) + " q50 " + r(shifted[(50 * size + 99) / 100 - 1])
                + " q95 " + r(shifted[(95 * size + 99) / 100 - 1]));
        }
        return lines;
    }
    List<String> pairJackknife(PairBootstrap pair) {
        long[] x = pair.first.group.values(), y = pair.second.group.values();
        List<String> lines = new ArrayList<>();
        for (int statistic = 0; statistic < 4; statistic++) {
            double[] first = new double[x.length], second = new double[y.length];
            for (int i = 0; i < x.length; i++) first[i] = Resampling.pairStatistic(statistic, Resampling.without(x, i), y);
            for (int i = 0; i < y.length; i++) second[i] = Resampling.pairStatistic(statistic, x, Resampling.without(y, i));
            Jackknife a = new Jackknife(pair.summaries[statistic].estimate, first), b = new Jackknife(pair.summaries[statistic].estimate, second);
            double bias = 0; bias += a.bias; bias += b.bias;
            double variance = 0; variance += a.variance; variance += b.variance;
            lines.add("pair " + pair.name + " " + PAIR_STATISTICS[statistic] + " estimate " + r(pair.summaries[statistic].estimate) + " bias " + r(bias) + " se " + r(Math.sqrt(variance)));
        }
        return lines;
    }
    long deviationTotal(long[] values, long center) { long total = 0; for (long value : values) total += Math.abs(2 * value - center); return total; }
    long[] splitStatistics(long[] values, long[] ranks, int[] order, int size) {
        long[] x = Resampling.sample(values, Arrays.copyOf(order, size)), y = Resampling.sample(values, Arrays.copyOfRange(order, size, order.length));
        long firstCenter = Resampling.doubledMedian(x), secondCenter = Resampling.doubledMedian(y), rankTotal = 0;
        for (int i = 0; i < size; i++) rankTotal += ranks[order[i]];
        return new long[] {Tests.contrast(Resampling.sum(x), x.length, Resampling.sum(y), y.length), firstCenter - secondCenter,
            rankTotal - (long) size * (order.length + 1), Tests.contrast(deviationTotal(x, firstCenter), x.length, deviationTotal(y, secondCenter), y.length)};
    }
    TestResult permutationLines(long[] x, long[] y) {
        long[] combined = concat(x, y), ranks = Tests.doubledRanks(combined);
        int[] positions = IntStream.range(0, combined.length).toArray();
        long[] observed = splitStatistics(combined, ranks, positions, x.length);
        Tally[] tallies = Arrays.stream(observed).mapToObj(Tally::new).toArray(Tally[]::new);
        for (int repeat = 0; repeat < settings.permutations(); repeat++) {
            int[] order = positions.clone(); generator.shuffle(order);
            long[] trial = splitStatistics(combined, ranks, order, x.length);
            for (int i = 0; i < 4; i++) tallies[i].count(trial[i]);
        }
        long rankTotal = Resampling.sum(Arrays.copyOf(ranks, x.length));
        int denominator = settings.permutations() + 1;
        return new TestResult(new ArrayList<>(List.of("permutation n " + x.length + " " + y.length + " perms " + settings.permutations(),
            "mean diff " + r(Resampling.meanDifference(x, y)) + " " + tallies[0].text(1, denominator),
            "median diff " + r(observed[1] / 200.0) + " " + tallies[1].text(1, denominator),
            "ranksum w " + r(rankTotal / 2.0) + " u " + r((rankTotal - (long) x.length * (x.length + 1)) / 2.0) + " " + tallies[2].text(1, denominator),
            "absdev diff " + r((double) observed[3] / (200L * x.length * y.length)) + " " + tallies[3].text(1, denominator))),
            Arrays.stream(tallies).mapToInt(tally -> tally.extreme).toArray());
    }
    String powerLine(long[] x, long[] y) {
        int rejections = 0;
        for (int simulation = 0; simulation < settings.powerSims(); simulation++) {
            long[] first = Resampling.sample(x, Resampling.resampleIndices(generator, x.length));
            long[] second = Resampling.sample(y, Resampling.resampleIndices(generator, y.length));
            long[] combined = concat(first, second);
            long total = Resampling.sum(combined), observed = Math.abs(Tests.contrast(Resampling.sum(first), x.length, Resampling.sum(second), y.length));
            int count = 0;
            for (int repeat = 0; repeat < settings.powerPerms(); repeat++) {
                long[] shuffled = combined.clone(); generator.shuffle(shuffled);
                long head = Resampling.sum(Arrays.copyOf(shuffled, x.length));
                if (Math.abs(Tests.contrast(head, x.length, total - head, y.length)) >= observed) count++;
            }
            if (100 * (count + 1) <= (100 - settings.confidence()) * (settings.powerPerms() + 1)) rejections++;
        }
        double power = (double) rejections / settings.powerSims();
        return "power sims " + settings.powerSims() + " perms " + settings.powerPerms() + " rejections " + rejections + " power " + r(power)
            + " se " + r(Math.sqrt(power * (1 - power) / settings.powerSims()));
    }
    List<String> exactLines(long[] x, long[] y) {
        int size = settings.pilot();
        long[] first = Arrays.copyOf(x, size), second = Arrays.copyOf(y, size), combined = concat(first, second), ranks = Tests.doubledRanks(combined);
        long total = Resampling.sum(combined);
        List<int[]> choices = Tests.positionChoices(2 * size, size);
        long[] meanValues = new long[choices.size()], rankValues = new long[choices.size()];
        for (int i = 0; i < choices.size(); i++) {
            long chosen = 0, rank = 0;
            for (int position : choices.get(i)) { chosen += combined[position]; rank += ranks[position]; }
            meanValues[i] = Tests.contrast(chosen, size, total - chosen, size);
            rankValues[i] = rank - (long) size * (2 * size + 1);
        }
        Tally mean = new Tally(meanValues[0]), rank = new Tally(rankValues[0]);
        for (int i = 0; i < choices.size(); i++) { mean.count(meanValues[i]); rank.count(rankValues[i]); }
        long rankTotal = Resampling.sum(Arrays.copyOf(ranks, size));
        int cumulative = 0, attained = 0;
        Long critical = null;
        TreeMap<Long, Integer> absolute = new TreeMap<>();
        for (long value : meanValues) absolute.merge(Math.abs(value), 1, Integer::sum);
        for (var entry : absolute.descendingMap().entrySet()) {
            cumulative += entry.getValue();
            if (100 * cumulative > (100 - settings.confidence()) * choices.size()) break;
            critical = entry.getKey(); attained = cumulative;
        }
        String criticalLine = critical == null ? "critical diff none attained none" : "critical diff " + r((double) critical / (100L * size * size)) + " attained " + p(attained, choices.size());
        return List.of("exact size " + size + " splits " + choices.size(), "mean diff " + r(Resampling.meanDifference(first, second)) + " " + mean.text(0, choices.size()),
            "ranksum w " + r(rankTotal / 2.0) + " u " + r((rankTotal - (long) size * (size + 1)) / 2.0) + " " + rank.text(0, choices.size()), criticalLine);
    }
    List<String> studentizedLines(PairBootstrap pair) {
        long[] x = pair.first.group.values(), y = pair.second.group.values();
        int k = x.length, m = y.length;
        double estimate = Resampling.meanDifference(x, y), firstSd = Resampling.sd(x), secondSd = Resampling.sd(y);
        double firstVariance = firstSd * firstSd / k, secondVariance = secondSd * secondSd / m, se0 = Math.sqrt(firstVariance + secondVariance), t = estimate / se0;
        double[] statistics = new double[settings.bootstrap()];
        int extreme = 0;
        for (int i = 0; i < statistics.length; i++) {
            double first = pair.first.summaries[3].values[i], second = pair.second.summaries[3].values[i];
            statistics[i] = (pair.summaries[0].values[i] - estimate) / Math.sqrt(first * first / k + second * second / m);
            if (Math.abs(statistics[i]) >= Math.abs(t)) extreme++;
        }
        Arrays.sort(statistics);
        double lower = estimate - statistics[highRank - 1] * se0, upper = estimate - statistics[lowRank - 1] * se0;
        double degrees = (firstVariance + secondVariance) * (firstVariance + secondVariance)
            / (firstVariance * firstVariance / (k - 1) + secondVariance * secondVariance / (m - 1));
        long greater = 0, equal = 0;
        for (long a : x) for (long b : y) { if (a > b) greater++; if (a == b) equal++; }
        double d = Resampling.cohenD(x, y), hedges = d * (1 - 3.0 / (4 * (k + m - 2) - 1)), cles = (double) (2 * greater + equal) / (2L * k * m);
        return List.of("bootstrap_t t " + r(t) + " df " + r(degrees) + " extreme " + extreme + " p " + p(extreme + 1, settings.bootstrap() + 1)
            + " interval " + r(lower) + " " + r(upper), "effect pooled_sd " + r(Resampling.pooledSd(x, y)) + " cohen_d " + r(d) + " hedges_g " + r(hedges) + " cles " + r(cles));
    }
    List<String> holmLines(List<int[]> extremes) {
        List<String> lines = new ArrayList<>();
        int count = data.pairs().size(), denominator = settings.permutations() + 1;
        for (int statistic = 0; statistic < 4; statistic++) {
            int column = statistic;
            List<Integer> order = IntStream.range(0, count).boxed().sorted(Comparator.<Integer>comparingInt(index -> extremes.get(index)[column]).thenComparingInt(index -> index)).toList();
            int adjusted = 0;
            for (int i = 0; i < order.size(); i++) {
                int index = order.get(i), extreme = extremes.get(index)[statistic];
                adjusted = Math.max(adjusted, Math.min(denominator, (count - i) * (extreme + 1)));
                Comparison pair = data.pairs().get(index);
                lines.add("holm " + TEST_STATISTICS[statistic] + " rank " + (i + 1) + " " + pair.first().name() + " " + pair.second().name()
                    + " p " + p(extreme + 1, denominator) + " adjusted " + p(adjusted, denominator) + " "
                    + (100 * adjusted <= (100 - settings.confidence()) * denominator ? "reject" : "retain"));
            }
        }
        return lines;
    }
    double tanh(double value) { double growth = Math.exp(2 * value); return (growth - 1) / (growth + 1); }
    List<String> pairedLines(Summary[] summaries) {
        PairedSample paired = data.paired();
        long[] differences = paired.differences();
        int count = differences.length, positive = 0, negative = 0;
        for (long value : differences) { if (value > 0) positive++; if (value < 0) negative++; }
        double average = Resampling.mean(differences), sd = Resampling.sd(differences), correlation = Resampling.correlation(paired.before(), paired.after());
        double z = 0.5 * Math.log((1 + correlation) / (1 - correlation)), halfWidth = -zLow / Math.sqrt(count - 3);
        return List.of("paired subjects " + count + " positive " + positive + " negative " + negative + " zero " + (count - positive - negative),
            "paired before " + r(Resampling.mean(paired.before())) + " after " + r(Resampling.mean(paired.after())) + " diff " + r(average) + " sd_diff " + r(sd)
                + " t " + r(average / (sd / Math.sqrt(count))) + " dz " + r(average / sd), "paired_bootstrap " + summaries[0].interval(),
            "correlation r " + r(correlation) + " " + summaries[1].interval() + " fisher " + r(tanh(z - halfWidth)) + " " + r(tanh(z + halfWidth)));
    }
    List<String> signFlipLines() {
        long[] differences = data.paired().differences();
        long[] magnitudes = Arrays.stream(differences).filter(value -> value != 0).map(Math::abs).toArray(), ranks = Tests.doubledRanks(magnitudes);
        Map<Long, Long> rankOf = new TreeMap<>();
        for (int i = 0; i < ranks.length; i++) rankOf.put(magnitudes[i], ranks[i]);
        long[] signed = Arrays.stream(differences).map(value -> value == 0 ? 0 : (value > 0 ? 1 : -1) * rankOf.get(Math.abs(value))).toArray();
        Tally mean = new Tally(Resampling.sum(differences)), rank = new Tally(Resampling.sum(signed));
        for (int repeat = 0; repeat < settings.permutations(); repeat++) {
            long sum = 0, rankSum = 0;
            for (int i = 0; i < differences.length; i++) { int sign = generator.draw() % 2 == 1 ? -1 : 1; sum += sign * differences[i]; rankSum += sign * signed[i]; }
            mean.count(sum); rank.count(rankSum);
        }
        long positive = 0;
        for (long value : signed) if (value > 0) positive += value;
        return List.of("signflip flips " + settings.permutations(), "mean diff " + r(Resampling.mean(differences)) + " " + mean.text(1, settings.permutations() + 1),
            "signedrank w_plus " + r(positive / 2.0) + " " + rank.text(1, settings.permutations() + 1));
    }
    List<Delta> deltas(List<long[]> samples, List<int[]> pairs) {
        List<Delta> deltas = new ArrayList<>();
        for (int[] pair : pairs) {
            long[] x = samples.get(pair[0]), y = samples.get(pair[1]);
            deltas.add(new Delta(Math.abs(Tests.contrast(Resampling.sum(x), x.length, Resampling.sum(y), y.length)), (long) x.length * y.length));
        }
        return deltas;
    }
    String welchLine(List<long[]> samples) {
        double[] means = samples.stream().mapToDouble(Resampling::mean).toArray(), weights = new double[samples.size()];
        for (int i = 0; i < weights.length; i++) { double sd = Resampling.sd(samples.get(i)); weights[i] = samples.get(i).length / (sd * sd); }
        double total = Resampling.sequentialSum(weights), center = 0;
        for (int i = 0; i < weights.length; i++) center += weights[i] * means[i];
        center /= total;
        double spread = 0;
        for (int i = 0; i < weights.length; i++) { double difference = means[i] - center; spread += weights[i] * (difference * difference); }
        spread /= samples.size() - 1;
        double lambda = 0;
        for (int i = 0; i < weights.length; i++) { double share = 1 - weights[i] / total; lambda += share * share / (samples.get(i).length - 1); }
        int groups = samples.size();
        double f = spread / (1 + 2 * (groups - 2) * lambda / (groups * groups - 1)), degrees = (groups * groups - 1) / (3 * lambda);
        return "welch f " + r(f) + " df " + (groups - 1) + " " + r(degrees);
    }
    List<String> anovaLines(List<GroupBootstrap> ordinary) {
        List<long[]> samples = data.groups().stream().map(Group::values).toList();
        int[] sizes = samples.stream().mapToInt(sample -> sample.length).toArray();
        int groups = samples.size(), total = Arrays.stream(sizes).sum();
        double[] squares = Tests.sumsOfSquares(samples);
        double between = squares[0], within = squares[1], f = Tests.fStatistic(between, within, groups, total), eta = between / (between + within);
        double msw = within / (total - groups), omega = (between - (groups - 1) * msw) / (between + within + msw);
        double[] etaValues = new double[settings.bootstrap()];
        for (int i = 0; i < etaValues.length; i++) {
            List<long[]> replicate = new ArrayList<>();
            for (GroupBootstrap bootstrap : ordinary) replicate.add(bootstrap.samples[i]);
            double[] spread = Tests.sumsOfSquares(replicate); etaValues[i] = spread[0] / (spread[0] + spread[1]);
        }
        Summary etaSummary = new Summary(eta, etaValues, lowRank, highRank);
        long[] combined = samples.stream().flatMapToLong(Arrays::stream).toArray(), ranks = Tests.doubledRanks(combined);
        long[] rankSums = Tests.splitList(ranks, sizes).stream().mapToLong(Resampling::sum).toArray();
        long tieTotal = 0;
        int tieGroups = 0;
        for (int count : Tests.valueCounts(combined).values()) if (count >= 2) { tieGroups++; tieTotal += (long) count * count * count - count; }
        double correction = 1 - (double) tieTotal / ((long) total * total * total - total), h = Tests.hStatistic(rankSums, sizes, correction);
        List<String> lines = new ArrayList<>(List.of("anova groups " + groups + " observations " + total + " ssb " + r(between) + " ssw " + r(within)
            + " df " + (groups - 1) + " " + (total - groups) + " f " + r(f) + " eta_squared " + r(eta) + " omega_squared " + r(omega),
            "eta_bootstrap " + etaSummary.interval(), welchLine(samples), "kruskal h " + r(h) + " tie_groups " + tieGroups));
        List<int[]> pairs = new ArrayList<>();
        for (int i = 0; i < groups; i++) for (int j = i + 1; j < groups; j++) pairs.add(new int[] {i, j});
        List<Delta> observed = deltas(samples, pairs);
        int fExtreme = 0, hExtreme = 0;
        int[] extremes = new int[pairs.size()], maxima = new int[pairs.size()], positions = IntStream.range(0, total).toArray();
        for (int repeat = 0; repeat < settings.permutations(); repeat++) {
            int[] order = positions.clone(); generator.shuffle(order);
            List<int[]> parts = Tests.splitList(order, sizes);
            List<long[]> trial = new ArrayList<>();
            long[] trialRanks = new long[groups];
            for (int i = 0; i < groups; i++) {
                trial.add(Resampling.sample(combined, parts.get(i)));
                for (int index : parts.get(i)) trialRanks[i] += ranks[index];
            }
            double[] spread = Tests.sumsOfSquares(trial);
            if (Tests.fStatistic(spread[0], spread[1], groups, total) >= f - 0.000000001 * f) fExtreme++;
            if (Tests.hStatistic(trialRanks, sizes, correction) >= h - 0.000000001 * h) hExtreme++;
            List<Delta> values = deltas(trial, pairs);
            Delta largest = values.stream().max(Comparator.naturalOrder()).orElseThrow();
            for (int i = 0; i < pairs.size(); i++) {
                if (values.get(i).compareTo(observed.get(i)) >= 0) extremes[i]++;
                if (largest.compareTo(observed.get(i)) >= 0) maxima[i]++;
            }
        }
        int denominator = settings.permutations() + 1;
        lines.add("anova_permutation perms " + settings.permutations() + " f_extreme " + fExtreme + " f_p " + p(fExtreme + 1, denominator)
            + " h_extreme " + hExtreme + " h_p " + p(hExtreme + 1, denominator));
        for (int i = 0; i < pairs.size(); i++) {
            Group first = data.groups().get(pairs.get(i)[0]), second = data.groups().get(pairs.get(i)[1]);
            lines.add("pairwise " + first.name() + " " + second.name() + " diff " + r(Resampling.meanDifference(first.values(), second.values()))
                + " extreme " + extremes[i] + " p " + p(extremes[i] + 1, denominator) + " maxt " + maxima[i] + " adjusted " + p(maxima[i] + 1, denominator));
        }
        return lines;
    }
    Map<String, List<String>> run() {
        List<GroupBootstrap> ordinary = new ArrayList<>(), balanced = new ArrayList<>();
        for (Group group : data.groups()) ordinary.add(new GroupBootstrap(group, Resampling.ordinaryIndices(generator, group.values().length, settings.bootstrap()), lowRank, highRank));
        for (Group group : data.groups()) balanced.add(new GroupBootstrap(group, Resampling.balancedIndices(generator, group.values().length, settings.bootstrap()), lowRank, highRank));
        Summary[] paired = pairedBootstrap();
        List<PairBootstrap> pairs = new ArrayList<>();
        for (Comparison comparison : data.pairs()) pairs.add(new PairBootstrap(ordinary.get(comparison.first().number() - 1), ordinary.get(comparison.second().number() - 1), lowRank, highRank));
        List<String> tests = new ArrayList<>();
        List<int[]> extremes = new ArrayList<>();
        for (PairBootstrap pair : pairs) {
            long[] x = pair.first.group.values(), y = pair.second.group.values();
            tests.add("compare " + pair.first.group.name() + " " + pair.second.group.name());
            TestResult result = permutationLines(x, y); tests.addAll(result.lines()); extremes.add(result.extremes());
            tests.add(powerLine(x, y)); tests.addAll(exactLines(x, y)); tests.addAll(studentizedLines(pair));
        }
        tests.addAll(holmLines(extremes)); tests.addAll(pairedLines(paired)); tests.addAll(signFlipLines()); tests.addAll(anovaLines(ordinary));
        List<String> jackknife = new ArrayList<>(), histograms = new ArrayList<>();
        for (GroupBootstrap bootstrap : ordinary) {
            jackknife.addAll(groupJackknife(bootstrap));
            for (int statistic = 0; statistic < 4; statistic++) histograms.addAll(histogramLines(bootstrap.group.name(), GROUP_STATISTICS[statistic], bootstrap.summaries[statistic]));
        }
        for (PairBootstrap pair : pairs) {
            jackknife.addAll(pairJackknife(pair));
            for (int statistic = 0; statistic < 4; statistic++) histograms.addAll(histogramLines(pair.name, PAIR_STATISTICS[statistic], pair.summaries[statistic]));
        }
        return Map.of("descriptives.txt", descriptiveLines(), "bootstrap.csv", bootstrapLines(ordinary, balanced, pairs), "jackknife.txt", jackknife, "tests.txt", tests, "histograms.txt", histograms);
    }
}

public final class Main {
    public static void main(String[] args) throws IOException { Report.writeFiles(new Study(Dataset.load("input")).run()); }
}
