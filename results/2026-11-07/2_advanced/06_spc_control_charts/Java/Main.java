import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.TreeSet;
import java.util.stream.IntStream;

public final class Main {
    private static final String[] CHART_NAMES = {"XBAR_R", "R", "XBAR_S", "S", "I", "MR", "CUSUM", "EWMA", "MA"};
    private static final String[] FAMILY_NAMES = {"XBAR_R", "XBAR_S", "I_MR"};
    private static final String[] ATTRIBUTE_NAMES = {"p", "np", "c", "u"};
    private static final String[][] LABELS = {{"XBAR", "R"}, {"XBAR", "S"}, {"I", "MR"}};
    static String row(Object... values) { return String.join(" ", Arrays.stream(values).map(Object::toString).toList()); }
    static String real(double value) { String text = String.format(Locale.ROOT, "%.4f", value); return text.equals("-0.0000") ? "0.0000" : text; }
    static List<Integer> range(int first, int last) { return IntStream.rangeClosed(first, last).boxed().toList(); }
    static String numberList(List<Integer> values) { return values.isEmpty() ? "none" : String.join(" ", values.stream().map(Object::toString).toList()); }
    static String limitText(String label, Limits limits) { return row(label, "lcl", real(limits.lcl()), "cl", real(limits.cl()), "ucl", real(limits.ucl())); }
    static String pairText(int family, Limits[] limits) { return row(limitText(LABELS[family][0], limits[0]), limitText(LABELS[family][1], limits[1])); }
    static String ruleName(int rule) { return rule < 9 ? Integer.toString(rule) : rule == 9 ? "UPPER" : "LOWER"; }
    static String status(boolean converged) { return converged ? "converged" : "stopped"; }
    record EstimationPass(int points, Limits[] limits, List<Integer> outliers) {}
    static final class Estimate {
        final List<EstimationPass> passes = new ArrayList<>();
        Limits[] limits;
        List<Integer> retained, removed;
        boolean converged;
    }
    record Pattern(int chart, int points, List<Signal> signals) {}
    record Proposal(int family, int points, Limits[] limits) {}
    record CusumPoint(int number, double upper, double lower) {}
    record BandPoint(int number, double value, double width) {}
    static final class Event {
        final int number, start;
        int end, onset, outOfSpec, kind;
        final List<Signal> signals = new ArrayList<>();
        final int[] counts = new int[5], detection = new int[9];
        double shift, spread;
        Event(int number, int start) { this.number = number; this.start = start; end = start; onset = start; }
        int length() { return end - start + 1; }
        boolean contains(int point) { return start <= point && point <= end; }
    }
    record AttributePass(int lots, Center center, List<Integer> outliers) {}
    static final class AttributeResult {
        final int chart;
        int retained;
        boolean converged;
        final List<AttributePass> passes = new ArrayList<>();
        final List<Integer> removed = new ArrayList<>();
        final List<LotPoint> points = new ArrayList<>();
        List<Signal> signals;
        AttributeResult(int chart) { this.chart = chart; }
    }
    static final class Analysis {
        final Input data;
        final Settings s;
        final Constants constants;
        final List<Subgroup> groups;
        final Estimate[] estimates = {new Estimate(), new Estimate(), new Estimate()};
        final List<Pattern> patterns = new ArrayList<>();
        final List<Proposal> proposals = new ArrayList<>();
        final List<Signal> signals = new ArrayList<>();
        final List<Event> events = new ArrayList<>();
        final List<CusumPoint> cusum = new ArrayList<>();
        final List<BandPoint> ewma = new ArrayList<>(), average = new ArrayList<>();
        final List<AttributeResult> attributes = new ArrayList<>();
        double mu, sigma, reference, interval, sbar, ewmaWidth, maWidth;
        Analysis(Input data) {
            this.data = data; s = data.settings(); constants = Dataset.controlConstants(s.size);
            groups = VariableCharts.statistics(data.values(), s.size);
        }
        Limits[] familyLimits(int family, List<Integer> points) { return VariableCharts.compute(family, points, data.values(), groups, s.size, constants); }
        Series[] familySeries(int family, List<Integer> points) {
            Series[] result = {new Series(), new Series()};
            for (int j = 0; j < points.size(); j++) {
                int point = points.get(j); result[0].numbers().add(point);
                if (family == 2) {
                    result[0].values().add((double)data.values()[point - 1]);
                    if (j > 0) {
                        result[1].numbers().add(point);
                        result[1].values().add((double)Math.abs(data.values()[point - 1] - data.values()[points.get(j - 1) - 1]));
                    }
                } else {
                    Subgroup group = groups.get(point - 1);
                    result[0].values().add(group.mean); result[1].numbers().add(point);
                    result[1].values().add(family == 0 ? group.range : group.sd);
                }
            }
            return result;
        }
        int subgroup(Signal signal) { return signal.chart() == 4 || signal.chart() == 5 ? (signal.end() - 1) / s.size + 1 : signal.end(); }
        boolean hasSignal(int chart, int end) { return hasSignal(chart, end, 0); }
        boolean hasSignal(int chart, int end, int rule) { return signals.stream().anyMatch(signal -> signal.chart() == chart && signal.end() == end && (rule == 0 || signal.rule() == rule)); }
        Event eventOf(int number) { return events.stream().filter(event -> event.contains(number)).findFirst().orElse(null); }
        void addBand(int chart, BandPoint point, int start) {
            if (point.value > mu + point.width) signals.add(new Signal(chart, 9, start, point.number, point.value, "UP"));
            else if (point.value < mu - point.width) signals.add(new Signal(chart, 10, start, point.number, point.value, "DOWN"));
        }
        void estimateFamilies() {
            for (int family = 0; family < 3; family++) {
                List<Integer> initial = range(1, s.phase1 * (family == 2 ? s.size : 1)), points = new ArrayList<>(initial);
                Estimate estimate = estimates[family];
                for (int pass = 1; pass <= s.passes; pass++) {
                    Limits[] limits = familyLimits(family, points);
                    Series[] sequences = familySeries(family, points);
                    TreeSet<Integer> found = new TreeSet<>();
                    for (int chart = 0; chart < 2; chart++) for (int j = 0; j < sequences[chart].values().size(); j++)
                        if (limits[chart].outside(sequences[chart].values().get(j))) found.add(sequences[chart].numbers().get(j));
                    estimate.passes.add(new EstimationPass(points.size(), limits, new ArrayList<>(found))); estimate.limits = limits;
                    if (found.isEmpty()) { estimate.converged = true; break; }
                    if (pass == s.passes) break;
                    points.removeIf(found::contains);
                }
                estimate.retained = points;
                estimate.removed = new ArrayList<>();
                for (int point : initial) if (!points.contains(point)) estimate.removed.add(point);
            }
            for (int family = 0; family < 3; family++) {
                Series[] sequences = familySeries(family, estimates[family].retained);
                for (int index = 0; index < 2; index++) {
                    int chart = family * 2 + index;
                    patterns.add(new Pattern(chart, sequences[index].values().size(), RunRules.check(chart, sequences[index], estimates[family].limits[index], s.rules.get(chart))));
                }
            }
        }
        void monitor() {
            mu = estimates[0].limits[0].cl(); sigma = estimates[0].limits[1].cl() / constants.d2() / Math.sqrt(s.size);
            reference = s.cusumK * sigma; interval = s.cusumH * sigma; sbar = estimates[1].limits[1].cl();
            for (int chart = 0; chart < 6; chart++) {
                Series sequence = new Series();
                if (chart >= 4) {
                    for (int t = s.phase1 * s.size + 1; t <= data.values().length; t++) {
                        sequence.numbers().add(t);
                        sequence.values().add((double)(chart == 4 ? data.values()[t - 1] : Math.abs(data.values()[t - 1] - data.values()[t - 2])));
                    }
                } else {
                    for (int i = s.phase1; i < groups.size(); i++) {
                        sequence.numbers().add(i + 1);
                        sequence.values().add(chart == 0 || chart == 2 ? groups.get(i).mean : chart == 1 ? groups.get(i).range : groups.get(i).sd);
                    }
                }
                signals.addAll(RunRules.check(chart, sequence, estimates[chart / 2].limits[chart % 2], s.rules.get(chart)));
            }
            double upper = 0, lower = 0, smooth = mu, factor = 1;
            int upperRun = 0, lowerRun = 0;
            double decay = (1 - s.weight) * (1 - s.weight), ratio = s.weight / (2 - s.weight);
            ewmaWidth = s.ewmaL * sigma * Math.sqrt(ratio); maWidth = 3 * sigma / Math.sqrt(s.span);
            for (int i = s.phase1 + 1; i <= groups.size(); i++) {
                Subgroup group = groups.get(i - 1);
                upper = Math.max(0, upper + (group.mean - mu - reference)); lower = Math.max(0, lower + (mu - group.mean - reference));
                upperRun = upper > 0 ? upperRun + 1 : 0; lowerRun = lower > 0 ? lowerRun + 1 : 0;
                cusum.add(new CusumPoint(i, upper, lower));
                if (upper > interval) { signals.add(new Signal(6, 9, i - upperRun + 1, i, upper, "UP")); upper = 0; upperRun = 0; }
                if (lower > interval) { signals.add(new Signal(6, 10, i - lowerRun + 1, i, lower, "DOWN")); lower = 0; lowerRun = 0; }
                smooth = s.weight * group.mean + (1 - s.weight) * smooth; factor = factor * decay;
                BandPoint e = new BandPoint(i, smooth, s.ewmaL * sigma * Math.sqrt(ratio * (1 - factor)));
                ewma.add(e); addBand(7, e, i);
                int first = Math.max(s.phase1 + 1, i - s.span + 1), count = i - first + 1;
                long total = 0;
                for (int j = first; j <= i; j++) total += groups.get(j - 1).total;
                BandPoint a = new BandPoint(i, (double)total / (s.size * count), 3 * sigma / Math.sqrt(count));
                average.add(a); addBand(8, a, first);
            }
            signals.sort(Comparator.comparingInt(Signal::chart).thenComparingInt(Signal::end).thenComparingInt(Signal::rule));
        }
        void buildEvents() {
            for (int point : signals.stream().mapToInt(this::subgroup).distinct().sorted().toArray()) {
                if (!events.isEmpty() && point - events.getLast().end - 1 <= s.gap) events.getLast().end = point;
                else events.add(new Event(events.size() + 1, point));
            }
            for (Event event : events) {
                boolean cusumFound = false;
                for (Signal signal : signals) if (event.contains(subgroup(signal))) {
                    event.signals.add(signal);
                    boolean location = signal.chart() == 0 || signal.chart() == 2 || signal.chart() == 4 || signal.chart() >= 6;
                    int kind = signal.direction().equals("NONE") ? 4 : (location ? 0 : 2) + (signal.direction().equals("DOWN") ? 1 : 0);
                    event.counts[kind]++;
                    int point = subgroup(signal);
                    if (event.detection[signal.chart()] == 0 || point < event.detection[signal.chart()]) event.detection[signal.chart()] = point;
                    if (signal.chart() == 6) { event.onset = cusumFound ? Math.min(event.onset, signal.start()) : signal.start(); cusumFound = true; }
                }
                for (int j = 1; j < 5; j++) if (event.counts[j] > event.counts[event.kind]) event.kind = j;
                long total = 0; double deviations = 0;
                for (int i = event.start; i <= event.end; i++) {
                    total += groups.get(i - 1).total; deviations += groups.get(i - 1).sd;
                    for (long value : groups.get(i - 1).values) if (value < s.lsl || value > s.usl) event.outOfSpec++;
                }
                double mean = (double)total / (s.size * event.length());
                event.shift = (mean - mu) / sigma; event.spread = (deviations / event.length()) / sbar;
            }
            for (int family = 0; family < 3; family++) {
                List<Integer> retained = new ArrayList<>(estimates[family].retained);
                for (int i = s.phase1 + 1; i <= groups.size(); i++) if (eventOf(i) == null) {
                    if (family == 2) retained.addAll(range((i - 1) * s.size + 1, i * s.size));
                    else retained.add(i);
                }
                proposals.add(new Proposal(family, retained.size(), familyLimits(family, retained)));
            }
        }
        void estimateAttributes() {
            for (int chart = 0; chart < 4; chart++) {
                AttributeResult result = new AttributeResult(chart);
                List<Integer> points = new ArrayList<>(range(1, data.lots().size()));
                Center center = null;
                for (int pass = 1; pass <= s.passes; pass++) {
                    center = AttributeCharts.centerLine(chart, data.lots(), points);
                    List<Integer> outliers = new ArrayList<>();
                    for (int number : points) if (!AttributeCharts.point(data.lots().get(number - 1), center).status().equals("ok")) outliers.add(number);
                    result.passes.add(new AttributePass(points.size(), center, outliers));
                    if (outliers.isEmpty()) { result.converged = true; break; }
                    if (pass == s.passes) break;
                    points.removeIf(outliers::contains);
                }
                result.retained = points.size();
                Series standardized = new Series();
                for (Lot lot : data.lots()) {
                    if (!points.contains(lot.number())) result.removed.add(lot.number());
                    LotPoint point = AttributeCharts.point(lot, center); result.points.add(point);
                    standardized.numbers().add(lot.number()); standardized.values().add(point.z());
                }
                result.signals = RunRules.check(chart, standardized, new Limits(-3, 0, 3), s.rules.get(6));
                attributes.add(result);
            }
        }
        List<String> limitsLines() {
            List<String> lines = new ArrayList<>(List.of(row("characteristic", s.characteristic), row("subgroup_size", s.size), row("subgroups", groups.size()), row("samples", data.values().length), row("phase1_subgroups", s.phase1)));
            for (int family = 0; family < 3; family++) {
                Estimate e = estimates[family]; lines.add(row("family", FAMILY_NAMES[family]));
                for (int j = 0; j < e.passes.size(); j++) {
                    EstimationPass p = e.passes.get(j); lines.add(row("pass", j + 1, "points", p.points, pairText(family, p.limits), "out", numberList(p.outliers)));
                }
                lines.add(row("result", status(e.converged), "passes", e.passes.size(), "retained", e.retained.size(), "removed", numberList(e.removed)));
            }
            for (Pattern p : patterns) {
                for (Signal signal : p.signals) lines.add(row("phase1_signal", CHART_NAMES[p.chart], signal.rule(), signal.start(), signal.end(), real(signal.value())));
                lines.add(row("phase1_check", CHART_NAMES[p.chart], "points", p.points, "signals", p.signals.size()));
            }
            for (Proposal p : proposals) lines.add(row("proposed", FAMILY_NAMES[p.family], "points", p.points, pairText(p.family, p.limits)));
            String target = row("target", real(mu), "sigma", real(sigma));
            lines.add(row("cusum", target, "k", real(reference), "h", real(interval)));
            lines.add(row("ewma", target, "lcl", real(mu - ewmaWidth), "ucl", real(mu + ewmaWidth)));
            lines.add(row("ma", target, "span", s.span, "lcl", real(mu - maWidth), "ucl", real(mu + maWidth)));
            for (int chart = 0; chart < 9; chart++) {
                List<Signal> found = new ArrayList<>(); TreeSet<Integer> ends = new TreeSet<>();
                for (Signal signal : signals) if (signal.chart() == chart) { found.add(signal); ends.add(signal.end()); }
                List<Integer> rules = chart < 6 ? s.rules.get(chart) : List.of(9, 10);
                List<String> counts = new ArrayList<>();
                for (int rule : rules) counts.add(ruleName(rule) + ":" + found.stream().filter(signal -> signal.rule() == rule).count());
                int points = (groups.size() - s.phase1) * (chart == 4 || chart == 5 ? s.size : 1);
                lines.add(row("phase2", CHART_NAMES[chart], "points", points, "signals", found.size(), "signalled", ends.size(), "first", ends.isEmpty() ? "none" : ends.first(), "by_rule", String.join(" ", counts)));
            }
            return lines;
        }
        List<String> signalLines() {
            List<String> lines = new ArrayList<>(List.of("chart,rule,start,end,value,direction"));
            for (Signal signal : signals) lines.add(String.join(",", CHART_NAMES[signal.chart()], ruleName(signal.rule()), Integer.toString(signal.start()), Integer.toString(signal.end()), real(signal.value()), signal.direction()));
            return lines;
        }
        List<String> eventLines() {
            String[] types = {"SHIFT_UP", "SHIFT_DOWN", "SPREAD_UP", "SPREAD_DOWN", "PATTERN"};
            List<String> lines = new ArrayList<>(List.of(row("events", events.size())));
            for (Event e : events) {
                List<String> charts = new ArrayList<>(), detection = new ArrayList<>();
                for (int chart = 0; chart < 9; chart++) {
                    if (e.detection[chart] > 0) charts.add(CHART_NAMES[chart]);
                    detection.add(CHART_NAMES[chart] + ":" + (e.detection[chart] == 0 ? "-" : e.detection[chart]));
                }
                lines.add(row("event", e.number, "start", e.start, "end", e.end, "length", e.length(), "signals", e.signals.size(), "charts", String.join(",", charts), "location_up", e.counts[0], "location_down", e.counts[1], "spread_up", e.counts[2], "spread_down", e.counts[3], "pattern", e.counts[4], "onset", e.onset, "shift", real(e.shift), "spread", real(e.spread), "out_of_spec", e.outOfSpec, "type", types[e.kind]));
                lines.add(row("detection", e.number, String.join(" ", detection)));
            }
            return lines;
        }
        List<String> subgroupLines() {
            List<String> lines = new ArrayList<>(List.of("subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event"));
            Zones zones = new Zones(estimates[0].limits[0]);
            for (Subgroup g : groups) {
                boolean phase2 = g.number > s.phase1;
                String phase = phase2 ? "phase2" : estimates[0].removed.contains(g.number) ? "excluded" : "phase1";
                List<String> fields = new ArrayList<>(List.of(Integer.toString(g.number), phase, real(g.mean), zones.name(g.mean), Long.toString(g.range), real(g.sd)));
                if (phase2) {
                    int index = g.number - s.phase1 - 1;
                    fields.addAll(List.of(real(cusum.get(index).upper), real(cusum.get(index).lower), real(ewma.get(index).value), real(average.get(index).value)));
                } else fields.addAll(List.of("-", "-", "-", "-"));
                Event e = eventOf(g.number);
                fields.add(Long.toString(signals.stream().filter(signal -> subgroup(signal) == g.number).count())); fields.add(e == null ? "-" : Integer.toString(e.number));
                lines.add(String.join(",", fields));
            }
            return lines;
        }
        List<String> attributeLines() {
            List<String> lines = new ArrayList<>();
            for (AttributeResult r : attributes) {
                lines.add(row("chart", ATTRIBUTE_NAMES[r.chart]));
                for (int j = 0; j < r.passes.size(); j++) {
                    AttributePass p = r.passes.get(j); lines.add(row("pass", j + 1, "lots", p.lots, "center", real(p.center.value()), "out", numberList(p.outliers)));
                }
                lines.add(row("result", status(r.converged), "passes", r.passes.size(), "retained", r.retained, "removed", numberList(r.removed)));
                for (int j = 0; j < data.lots().size(); j++) {
                    Lot lot = data.lots().get(j); LotPoint p = r.points.get(j);
                    String value = r.chart == 1 ? Long.toString(lot.defectives()) : r.chart == 2 ? Long.toString(lot.defects()) : real(p.value());
                    lines.add(row("lot", lot.number(), "size", lot.inspected(), "value", value, "lcl", real(p.lcl()), "ucl", real(p.ucl()), "z", real(p.z()), "status", p.status()));
                }
                for (Signal signal : r.signals) lines.add(row("signal", signal.rule(), signal.start(), signal.end(), real(signal.value())));
                lines.add(row("signals", r.signals.size()));
            }
            return lines;
        }
        List<Subgroup> selected(List<Integer> points) { return points.stream().map(point -> groups.get(point - 1)).toList(); }
        List<String> capabilityLines() {
            List<String> lines = new ArrayList<>();
            for (int phase = 0; phase < 2; phase++) {
                List<Subgroup> chosen = selected(phase == 0 ? estimates[0].retained : range(s.phase1 + 1, groups.size()));
                Capability r = new Capability(chosen, s, constants);
                lines.add(row("group", phase == 0 ? "phase1" : "phase2", "subgroups", chosen.size(), "values", r.count));
                String[] names = {"mean", "sigma_within", "sigma_sbar", "sigma_overall", "cp", "cpu", "cpl", "cpk", "pp", "ppu", "ppl", "ppk", "cpm"};
                double[] values = {r.mean, r.within, r.sbar, r.overall, r.cp, r.cpu, r.cpl, r.cpk, r.pp, r.ppu, r.ppl, r.ppk, r.cpm};
                for (int j = 0; j < names.length; j++) lines.add(row(names[j], real(values[j])));
                lines.add(row("cpk_ci", real(r.cpkInterval.lower()), real(r.cpkInterval.upper()))); lines.add(row("ppk_ci", real(r.ppkInterval.lower()), real(r.ppkInterval.upper())));
                lines.addAll(List.of(row("below_lsl", r.below), row("above_usl", r.above), row("ppm", real(r.ppm))));
                for (Subgroup g : chosen) for (int j = 0; j < s.size; j++) {
                    long value = g.values[j];
                    if (value < s.lsl || value > s.usl) lines.add(row("out_of_spec sample", (g.number - 1) * s.size + j + 1, "subgroup", g.number, "value", value, "side", value < s.lsl ? "low" : "high"));
                }
                lines.add(row("verdict", r.verdict));
                for (HistogramBin bin : r.bins) {
                    String text = row("bin", bin.lower(), bin.upper(), bin.frequency());
                    if (bin.length() > 0) text += " " + "#".repeat(bin.length());
                    for (String mark : bin.marks()) text += " " + mark;
                    lines.add(text);
                }
            }
            for (int first = s.phase1 + 1; first + s.window - 1 <= groups.size(); first += s.step) {
                int last = first + s.window - 1; Capability r = new Capability(selected(range(first, last)), s, constants);
                lines.add(row("rolling", first, last, "mean", real(r.mean), "sigma_within", real(r.within), "sigma_overall", real(r.overall), "cpk", real(r.cpk), "ppk", real(r.ppk), "verdict", r.verdict));
            }
            return lines;
        }
        String pictureNumber(int number) { return String.format(Locale.ROOT, "%3d", number); }
        List<String> chartLines() {
            List<String> lines = new ArrayList<>();
            for (int picture = 0; picture < 3; picture++) {
                int chart = picture == 0 ? 0 : picture == 1 ? 1 : 3, family = chart / 2;
                Limits limits = estimates[family].limits[chart % 2];
                lines.add(limitText("chart " + (picture == 0 ? "XBAR" : picture == 1 ? "R" : "S"), limits));
                for (Subgroup g : groups) {
                    double value = picture == 0 ? g.mean : picture == 1 ? g.range : g.sd;
                    String mark = g.number > s.phase1 ? "2" : estimates[family].removed.contains(g.number) ? "x" : "1";
                    lines.add(row(pictureNumber(g.number), mark, Plot.limitsBand(limits, value, g.number > s.phase1 && hasSignal(chart, g.number)), real(value)));
                }
            }
            lines.add(row("chart CUSUM h", real(interval)));
            for (CusumPoint p : cusum) lines.add(row(pictureNumber(p.number), Plot.cusumBand(p.upper, p.lower, interval, hasSignal(6, p.number, 9), hasSignal(6, p.number, 10)), real(p.upper), real(p.lower)));
            for (int chart = 7; chart <= 8; chart++) {
                double scale = chart == 7 ? ewmaWidth : maWidth;
                List<BandPoint> points = chart == 7 ? ewma : average;
                lines.add(limitText("chart " + CHART_NAMES[chart], new Limits(mu - scale, mu, mu + scale)));
                for (BandPoint p : points) lines.add(row(pictureNumber(p.number), Plot.widthBand(scale, p.width, p.value, mu, hasSignal(chart, p.number)), real(p.value), real(mu - p.width), real(mu + p.width)));
            }
            String[] pictures = {"P_STD", "NP_STD", "C_STD", "U_STD"};
            for (AttributeResult r : attributes) {
                lines.add(limitText("chart " + pictures[r.chart], new Limits(-3, 0, 3)));
                for (int j = 0; j < data.lots().size(); j++) lines.add(row(pictureNumber(data.lots().get(j).number()), Plot.standardBand(r.points.get(j).z(), r.points.get(j).status().equals("ok")), real(r.points.get(j).z())));
            }
            return lines;
        }
        void write(String name, List<String> lines) throws IOException { Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n", StandardCharsets.US_ASCII); }
        void run() throws IOException {
            estimateFamilies(); monitor(); buildEvents(); estimateAttributes();
            Files.createDirectories(Path.of("output"));
            write("limits.txt", limitsLines()); write("signals.csv", signalLines()); write("events.txt", eventLines());
            write("subgroups.csv", subgroupLines()); write("attribute_charts.txt", attributeLines());
            write("capability.txt", capabilityLines()); write("charts.txt", chartLines());
        }
    }
    public static void main(String[] args) throws IOException { new Analysis(Dataset.read()).run(); }
}
