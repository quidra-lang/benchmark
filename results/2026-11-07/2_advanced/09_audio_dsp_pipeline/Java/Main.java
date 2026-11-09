import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

public final class Main {
    static final class CommandError extends RuntimeException { CommandError(String message) { super(message); } }
    record Argument(String name, String low, String high) { Argument(String name) { this(name, "", ""); } }
    record Command(List<Argument> arguments, List<Argument> repeated, int minimum, int maximum) {
        Command(List<Argument> arguments) { this(arguments, List.of(), 0, 0); }
        boolean accepts(int count) {
            int extra = count - arguments.size(); return repeated.isEmpty() ? extra == 0 : extra >= 0 && extra % repeated.size() == 0 && extra >= minimum * repeated.size() && extra <= maximum * repeated.size();
        }
        Argument at(int index) { return index < arguments.size() ? arguments.get(index) : repeated.get((index - arguments.size()) % repeated.size()); }
    }
    record Value(String text, long number, Signal source) { Value(String text) { this(text, 0, null); } }
    record Parsed(List<Value> values, List<Signal> sources) {}
    static Argument a(String name, long low, long high) { return new Argument(name, Long.toString(low), Long.toString(high)); }
    static Command cmd(Argument... arguments) { return new Command(Arrays.asList(arguments)); }
    static Map<String, Command> commandTable() {
        Argument dst = new Argument("dst"), src = new Argument("src"), rate = a("rate", 1000, 48000), count = a("count", 1, 20000), num = a("num", -65536, 65536), den = a("den", 1, 65536);
        Argument attack = a("attack", 1, 32768), release = a("release", 1, 32768), start = new Argument("start", "0", "L - 1"), minHz = new Argument("min_hz", "1", "rate div 2 - 1"), maxHz = new Argument("max_hz", "min_hz + 1", "rate div 2");
        Command test = cmd(dst, rate, count, new Argument("pos", "0", "count - 1"), a("amp", -32768, 32767));
        Map<String, Command> commands = new HashMap<>();
        commands.put("SET", new Command(List.of(new Argument("var"), a("value", -10000000, 10000000)), List.of(new Argument("op"), a("operand", -10000000, 10000000)), 0, 1));
        commands.put("IMPULSE", test); commands.put("STEP", test); commands.put("NOISE", cmd(dst, rate, count, a("seed", 1, 2147483646)));
        commands.put("GAIN", cmd(dst, src, num, den)); commands.put("MIX", new Command(List.of(dst, den), List.of(src, a("weight", -65536, 65536)), 1, 8));
        commands.put("DELAY", cmd(dst, src, a("samples", 0, 20000))); commands.put("ECHO", cmd(dst, src, a("delay", 1, 20000), num, den, a("tail", 0, 20000)));
        commands.put("RESAMPLE", cmd(dst, src, a("new_rate", 1000, 48000))); commands.put("FADE", cmd(dst, src, new Argument("in", "0", "L"), new Argument("out", "0", "L")));
        commands.put("TRIM", cmd(dst, src, start, new Argument("count", "1", "L - start"))); commands.put("CONCAT", new Command(List.of(dst), List.of(src), 2, 8));
        commands.put("FIR", new Command(List.of(dst, src, a("divisor", 1, 1000000)), List.of(a("tap", -32768, 32767)), 1, 64));
        commands.put("BIQUAD", new Command(List.of(dst, src), List.of(a("b0", -65536, 65536), a("b1", -65536, 65536), a("b2", -65536, 65536), a("a1", -65536, 65536), a("a2", -65536, 65536)), 1, 4));
        commands.put("MOVAVG", cmd(dst, src, a("width", 1, 1000))); commands.put("DCBLOCK", cmd(dst, src, a("num", 0, 65535), new Argument("den", "num + 1", "65536")));
        commands.put("NORMALIZE", cmd(dst, src, a("target", 1, 32767))); commands.put("GATE", cmd(dst, src, a("threshold", 1, 32768), a("hold", 0, 20000)));
        commands.put("ENVELOPE", cmd(dst, src, attack, release)); commands.put("COMPRESS", cmd(dst, src, a("threshold", 1, 32767), a("ratio_num", 1, 100), new Argument("ratio_den", "1", "ratio_num"), attack, release));
        commands.put("ANALYZE", cmd(src, minHz, maxHz)); commands.put("COMPARE", cmd(src, src)); commands.put("EXPECT", cmd(src, new Argument("metric"), new Argument("op"), a("value", -1000000000, 1000000000)));
        commands.put("SEGMENTS", cmd(src, a("threshold", 1, 32768), a("gap", 1, 20000), a("min_length", 1, 20000)));
        commands.put("ONSETS", cmd(src, attack, release, a("threshold", 1, 32767), a("min_gap", 1, 20000)));
        commands.put("PITCHTRACK", cmd(src, new Argument("frame", "16", "L"), new Argument("hop", "1", "frame"), minHz, maxHz, a("threshold", 0, 32767)));
        commands.put("EXCERPT", cmd(src, start, a("count", 1, 1000)));
        commands.put("PLOT", cmd(src, start, new Argument("count", "1", "L - start"), new Argument("columns", "8", "min(120, count)"), a("half", 2, 20), attack, release));
        commands.put("METER", cmd(src, a("block", 1, 20000))); commands.put("HISTOGRAM", cmd(src, a("bins", 2, 64))); commands.put("TRACE", cmd(src)); commands.put("SAVE", cmd(src));
        return commands;
    }
    static long peak(long[] samples) { return SignalMath.peak(samples); }
    static long rms(long[] samples) { return Analysis.rms(samples); }
    static long rdiv(long numerator, long denominator) { return SignalMath.rdiv(numerator, denominator); }
    static long sum(long[] samples) { long total = 0; for (long sample : samples) total += sample; return total; }
    static String pad(Object value, int width) { String text = value.toString(); return " ".repeat(Math.max(0, width - text.length())) + text; }
    static long milliseconds(long sample, int rate) { return sample * 1000 / rate; }
    static String twoDecimals(long value) { return value / 100 + "." + String.format(Locale.ROOT, "%02d", value % 100); }
    static String frequency(int rate, int lag) { return twoDecimals(rdiv(100L * rate, lag)); }
    static final class Pipeline {
        final Map<String, Signal> signals = new TreeMap<>();
        final Map<String, Long> variables = new HashMap<>();
        final Map<String, Command> commands = commandTable();
        final List<String> log = new ArrayList<>(), analysis = new ArrayList<>(List.of("signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz")), excerpts = new ArrayList<>(), waveforms = new ArrayList<>(), saved = new ArrayList<>();
        int steps, errors, passed, failed;
        Pipeline(List<Signal> loaded) {
            for (Signal signal : loaded) { signals.put(signal.name(), signal); log.add("load " + signal.name() + " rate=" + signal.rate() + " samples=" + signal.samples().length + " peak=" + peak(signal.samples())); }
        }
        static long bound(String text, Map<String, Long> known, Signal source) {
            return switch (text) {
                case "L" -> source.samples().length; case "L - 1" -> source.samples().length - 1; case "L - start" -> source.samples().length - known.get("start");
                case "count - 1" -> known.get("count") - 1; case "min(120, count)" -> Math.min(120, known.get("count")); case "min_hz + 1" -> known.get("min_hz") + 1;
                case "num + 1" -> known.get("num") + 1; case "rate div 2" -> source.rate() / 2; case "rate div 2 - 1" -> source.rate() / 2 - 1;
                default -> known.containsKey(text) ? known.get(text) : Long.parseLong(text);
            };
        }
        Parsed parse(String name, Command command, String[] tokens) {
            List<Value> values = new ArrayList<>(); List<Signal> sources = new ArrayList<>(); Map<String, Long> known = new HashMap<>();
            Set<String> metrics = Set.of("samples", "peak", "rms", "sum", "zero_crossings", "clipped");
            for (int j = 0; j < tokens.length; j++) {
                Argument argument = command.at(j); String token = tokens[j]; Value value = new Value(token);
                switch (argument.name) {
                    case "dst", "var" -> { if (!token.matches("[a-z][a-z0-9_]{0,15}")) throw new CommandError("bad name " + token); }
                    case "src" -> {
                        Signal source = signals.get(token); if (source == null) throw new CommandError("unknown signal " + token);
                        value = new Value(token, 0, source); sources.add(source);
                    }
                    case "metric" -> { if (!metrics.contains(token)) throw new CommandError("unknown metric " + token); }
                    case "op" -> {
                        Set<String> operators = name.equals("SET") ? Set.of("+", "-", "*", "/") : Set.of("eq", "ne", "lt", "le", "gt", "ge");
                        if (!operators.contains(token)) throw new CommandError("unknown operator " + token);
                    }
                    default -> {
                        long number;
                        if (token.startsWith("$")) { Long variable = variables.get(token.substring(1)); if (variable == null) throw new CommandError("undefined variable " + token); number = variable; }
                        else { if (!token.matches("-?(0|[1-9][0-9]{0,9})") || token.equals("-0")) throw new CommandError("bad integer " + token); number = Long.parseLong(token); }
                        Signal source = sources.isEmpty() ? null : sources.getFirst();
                        if (number < bound(argument.low, known, source) || number > bound(argument.high, known, source)) throw new CommandError(argument.name + " out of range");
                        known.put(argument.name, number); value = new Value(token, number, null);
                    }
                }
                values.add(value);
            }
            return new Parsed(values, sources);
        }
        static void sameRate(List<Signal> sources) { for (Signal source : sources) if (source.rate() != sources.getFirst().rate()) throw new CommandError("rate mismatch"); }
        String generate(int number, String name, Parsed parsed) {
            List<Value> a = parsed.values; long[] samples = new long[0], x = parsed.sources.isEmpty() ? new long[0] : parsed.sources.getFirst().samples();
            int rate = parsed.sources.isEmpty() ? (int)a.get(1).number : parsed.sources.getFirst().rate(), length = x.length;
            List<String> extras = new ArrayList<>(); Processed processed = null; String extraName = "clipped";
            switch (name) {
                case "IMPULSE" -> samples = Signals.impulse((int)a.get(2).number, (int)a.get(3).number, a.get(4).number);
                case "STEP" -> samples = Signals.step((int)a.get(2).number, (int)a.get(3).number, a.get(4).number);
                case "NOISE" -> samples = Signals.noise((int)a.get(2).number, a.get(3).number);
                case "GAIN" -> processed = Effects.gain(x, a.get(2).number, a.get(3).number);
                case "MIX" -> {
                    sameRate(parsed.sources); List<long[]> tracks = new ArrayList<>(); List<Long> weights = new ArrayList<>();
                    for (int j = 2; j < a.size(); j += 2) { tracks.add(a.get(j).source.samples()); weights.add(a.get(j + 1).number); } processed = Effects.mix(tracks, weights, a.get(1).number);
                }
                case "DELAY" -> { if (length + a.get(2).number > 20000) throw new CommandError("result too long"); samples = Effects.delay(x, (int)a.get(2).number); }
                case "ECHO" -> {
                    if (Math.abs(a.get(3).number) >= a.get(4).number) throw new CommandError("unstable feedback");
                    if (length + a.get(5).number > 20000) throw new CommandError("result too long"); processed = Effects.echo(x, (int)a.get(2).number, a.get(3).number, a.get(4).number, (int)a.get(5).number);
                }
                case "RESAMPLE" -> {
                    if (Effects.resampledLength(length, rate, (int)a.get(2).number) > 20000) throw new CommandError("result too long"); samples = Effects.resample(x, rate, (int)a.get(2).number); rate = (int)a.get(2).number;
                }
                case "FADE" -> samples = Effects.fade(x, (int)a.get(2).number, (int)a.get(3).number);
                case "TRIM" -> samples = Arrays.copyOfRange(x, (int)a.get(2).number, (int)(a.get(2).number + a.get(3).number));
                case "CONCAT" -> {
                    sameRate(parsed.sources); int total = parsed.sources.stream().mapToInt(source -> source.samples().length).sum(); if (total > 20000) throw new CommandError("result too long");
                    samples = new long[total]; int position = 0; for (Signal source : parsed.sources) { System.arraycopy(source.samples(), 0, samples, position, source.samples().length); position += source.samples().length; }
                }
                case "FIR" -> processed = Filters.fir(x, a.get(2).number, a.stream().skip(3).mapToLong(Value::number).toArray());
                case "BIQUAD" -> { long[] coefficients = a.stream().skip(2).mapToLong(Value::number).toArray(); extras.add("sections=" + coefficients.length / 5); processed = Filters.biquad(x, coefficients); }
                case "MOVAVG" -> samples = Filters.movingAverage(x, (int)a.get(2).number);
                case "DCBLOCK" -> processed = Filters.dcBlock(x, a.get(2).number, a.get(3).number);
                case "NORMALIZE" -> { processed = Dynamics.normalize(x, a.get(2).number); extraName = "source_peak"; }
                case "GATE" -> { processed = Dynamics.gate(x, a.get(2).number, (int)a.get(3).number); extraName = "muted"; }
                case "ENVELOPE" -> samples = Dynamics.envelope(x, a.get(2).number, a.get(3).number);
                case "COMPRESS" -> { Compressed result = Dynamics.compress(x, a.get(2).number, a.get(3).number, a.get(4).number, a.get(5).number, a.get(6).number); samples = result.samples(); extras.add("min_gain=" + result.minGain()); extras.add("reduced=" + result.reduced()); }
            }
            if (processed != null) { samples = processed.samples(); extras.add(extraName + "=" + processed.count()); }
            Signal signal = new Signal(a.getFirst().text, rate, samples, "line " + number + " " + name, parsed.sources); signals.put(signal.name(), signal);
            return signal.name() + " rate=" + rate + " samples=" + samples.length + " peak=" + peak(samples) + " sum=" + sum(samples) + (extras.isEmpty() ? "" : " " + String.join(" ", extras));
        }
        static List<String> waveform(Signal source, int start, int count, int columns, int half, long attack, long release) {
            long[] window = Arrays.copyOfRange(source.samples(), start, start + count), levels = Arrays.copyOfRange(Dynamics.envelope(source.samples(), attack, release), start, start + count);
            int rows = 2 * half + 1; long scale = Math.max(1, peak(window)); char[][] grid = new char[rows][columns]; for (char[] row : grid) Arrays.fill(row, ' ');
            for (int column = 0; column < columns; column++) {
                int first = column * count / columns, last = (column + 1) * count / columns;
                long top = Arrays.stream(window, first, last).max().orElseThrow(), bottom = Arrays.stream(window, first, last).min().orElseThrow(), level = Math.min(scale, Arrays.stream(levels, first, last).max().orElseThrow());
                for (int row = 0; row < rows; row++) grid[row][column] = row == plotRow(level, scale, rows) || row == plotRow(-level, scale, rows) ? '*' : plotRow(top, scale, rows) <= row && row <= plotRow(bottom, scale, rows) ? '#' : row == half ? '-' : ' ';
            }
            List<String> lines = new ArrayList<>(List.of("PLOT " + source.name() + " rate=" + source.rate() + " start=" + start + " count=" + count + " columns=" + columns + " rows=" + rows + " scale=" + scale + " attack=" + attack + " release=" + release));
            for (int row = 0; row < rows; row++) { String label = row == 0 ? Long.toString(scale) : row == half ? "0" : row == rows - 1 ? Long.toString(-scale) : ""; lines.add(pad(label, 6) + " |" + new String(grid[row]) + "|"); }
            StringBuilder axis = new StringBuilder("       +"); for (int column = 0; column < columns; column++) axis.append(column % 10 == 0 ? '+' : '-'); lines.add(axis + "+");
            String time = "    ms"; for (int column = 0; column < columns; column += 10) time += " ".repeat(Math.max(0, 8 + column - time.length())) + milliseconds(start + column * count / columns, source.rate()); lines.add(time); return lines;
        }
        static int plotRow(long value, long scale, int rows) { return (int)rdiv((scale - value) * (rows - 1), 2 * scale); }
        static List<String> meter(Signal source, int block) {
            int length = source.samples().length, blocks = (length + block - 1) / block;
            List<String> lines = new ArrayList<>(List.of("METER " + source.name() + " rate=" + source.rate() + " samples=" + length + " block=" + block + " blocks=" + blocks));
            for (int b = 0; b < blocks; b++) {
                long[] part = Arrays.copyOfRange(source.samples(), b * block, Math.min((b + 1) * block, length)); long p = peak(part), q = rms(part), np = rdiv(p * 40, 32768), nq = rdiv(q * 40, 32768);
                StringBuilder bar = new StringBuilder(); for (int j = 0; j < 40; j++) bar.append(j < nq ? '#' : j < np ? '-' : ' ');
                lines.add(pad(milliseconds(b * block, source.rate()), 6) + " |" + bar + "| peak=" + p + " rms=" + q + " clipped=" + Analysis.clipped(part));
            }
            return lines;
        }
        static List<String> histogram(Signal source, int bins) {
            int[] counts = new int[bins]; for (long sample : source.samples()) counts[(int)((sample + 32768) * bins / 65536)]++; int maximum = Arrays.stream(counts).max().orElseThrow();
            List<String> lines = new ArrayList<>(List.of("HISTOGRAM " + source.name() + " rate=" + source.rate() + " samples=" + source.samples().length + " bins=" + bins + " max=" + maximum));
            for (int b = 0; b < bins; b++) { int low = (b * 65536 + bins - 1) / bins - 32768, high = ((b + 1) * 65536 + bins - 1) / bins - 32769; lines.add(pad(low, 6) + " " + pad(high, 6) + " " + pad(counts[b], 5) + " |" + "#".repeat((int)rdiv(counts[b] * 50, maximum))); } return lines;
        }
        static void trace(Signal source, int depth, List<String> lines) {
            lines.add(" ".repeat(2 * depth) + source.name() + " <- " + source.origin()); for (Signal ingredient : source.ingredients()) trace(ingredient, depth + 1, lines);
        }
        static long measured(long[] samples, String metric) { return switch (metric) { case "samples" -> samples.length; case "peak" -> peak(samples); case "rms" -> rms(samples); case "sum" -> sum(samples); case "zero_crossings" -> Analysis.zeroCrossings(samples); default -> Analysis.clipped(samples); }; }
        List<String> action(String name, Parsed parsed) {
            List<Value> a = parsed.values;
            if (name.equals("SET")) {
                long result = a.get(1).number;
                if (a.size() == 4) {
                    String op = a.get(2).text; long operand = a.get(3).number; if (op.equals("/") && operand == 0) throw new CommandError("division by zero");
                    result = switch (op) { case "+" -> result + operand; case "-" -> result - operand; case "*" -> result * operand; default -> SignalMath.floorDiv(result, operand); };
                    if (Math.abs(result) > 10000000) throw new CommandError("value out of range");
                }
                variables.put(a.getFirst().text, result); return List.of(a.getFirst().text + "=" + result);
            }
            Signal source = parsed.sources.getFirst(); long[] x = source.samples(); int length = x.length, rate = source.rate();
            if (name.equals("ANALYZE") || name.equals("PITCHTRACK")) {
                int minHz = (int)a.get(name.equals("ANALYZE") ? 1 : 3).number, maxHz = (int)a.get(name.equals("ANALYZE") ? 2 : 4).number, low = (rate + maxHz - 1) / maxHz, high = rate / minHz;
                if (low > high) throw new CommandError("empty lag range");
                if (name.equals("ANALYZE")) {
                    if (high >= length) throw new CommandError("signal too short"); Integer lag = Analysis.pitchLag(x, low, high);
                    analysis.add(String.join(",", source.name(), Long.toString(peak(x)), Long.toString(rms(x)), Long.toString(Analysis.zeroCrossings(x)), Long.toString(Analysis.clipped(x)), Analysis.crest(x), lag == null ? "none" : lag.toString(), lag == null ? "none" : frequency(rate, lag)));
                    return List.of(source.name() + " lags=" + low + "-" + high);
                }
                int frame = (int)a.get(1).number, hop = (int)a.get(2).number, threshold = (int)a.get(5).number;
                if (high >= frame) throw new CommandError("frame too short"); int count = (length - frame) / hop + 1, voiced = 0; List<String> rows = new ArrayList<>();
                for (int t = 0; t < count; t++) {
                    long[] window = Arrays.copyOfRange(x, t * hop, t * hop + frame); long level = rms(window); Integer lag = level < threshold ? null : Analysis.pitchLag(window, low, high);
                    char[] band = new char[41]; Arrays.fill(band, ' '); String details = "unvoiced rms=" + level;
                    if (lag != null) { voiced++; int position = high > low ? (int)rdiv((high - lag) * 40, high - low) : 0; band[position] = 'o'; details = "lag=" + lag + " hz=" + frequency(rate, lag) + " rms=" + level; }
                    rows.add(pad(milliseconds(t * hop, rate), 6) + " |" + new String(band) + "| " + details);
                }
                waveforms.add("PITCHTRACK " + source.name() + " rate=" + rate + " frame=" + frame + " hop=" + hop + " lags=" + low + "-" + high + " threshold=" + threshold + " frames=" + count + " voiced=" + voiced); waveforms.addAll(rows);
                return List.of(source.name() + " frames=" + count + " voiced=" + voiced);
            }
            if (name.equals("COMPARE")) {
                sameRate(parsed.sources); Signal other = parsed.sources.get(1); int count = Math.max(length, other.samples().length), differing = 0, first = -1; long maximum = 0, total = 0;
                for (int j = 0; j < count; j++) { long delta = (j < length ? x[j] : 0) - (j < other.samples().length ? other.samples()[j] : 0); if (delta != 0) { differing++; if (first < 0) first = j; } maximum = Math.max(maximum, Math.abs(delta)); total += delta * delta; }
                return List.of(source.name() + " " + other.name() + " differing=" + differing + " max_diff=" + maximum + " first=" + (first < 0 ? "none" : first) + " error_energy=" + total);
            }
            if (name.equals("EXPECT")) {
                long value = measured(x, a.get(1).text), expected = a.get(3).number; String op = a.get(2).text;
                boolean ok = switch (op) { case "eq" -> value == expected; case "ne" -> value != expected; case "lt" -> value < expected; case "le" -> value <= expected; case "gt" -> value > expected; default -> value >= expected; };
                if (ok) passed++; else failed++; return List.of(source.name() + " " + a.get(1).text + "=" + value + " " + op + " " + expected + " " + (ok ? "pass" : "fail"));
            }
            if (name.equals("SEGMENTS")) {
                record Segment(int start, int end) {}
                List<Segment> segments = new ArrayList<>();
                for (int j = 0; j < length; j++) if (Math.abs(x[j]) >= a.get(1).number) {
                    if (!segments.isEmpty() && j - segments.getLast().end <= a.get(2).number) segments.set(segments.size() - 1, new Segment(segments.getLast().start, j)); else segments.add(new Segment(j, j));
                }
                List<String> lines = new ArrayList<>(); int count = 0;
                for (Segment segment : segments) if (segment.end - segment.start + 1 >= a.get(3).number) {
                    long[] part = Arrays.copyOfRange(x, segment.start, segment.end + 1);
                    lines.add("  segment " + ++count + " start=" + segment.start + " end=" + segment.end + " start_ms=" + milliseconds(segment.start, rate) + " end_ms=" + milliseconds(segment.end, rate) + " peak=" + peak(part) + " rms=" + rms(part) + " crossings=" + Analysis.zeroCrossings(part));
                }
                lines.addFirst(source.name() + " segments=" + count); return lines;
            }
            if (name.equals("ONSETS")) {
                long[] levels = Dynamics.envelope(x, a.get(1).number, a.get(2).number); List<Integer> found = new ArrayList<>(), intervals = new ArrayList<>();
                for (int j = 0; j < length; j++) if (levels[j] >= a.get(3).number && (j == 0 || levels[j - 1] < a.get(3).number) && (found.isEmpty() || j - found.getLast() >= a.get(4).number)) found.add(j);
                for (int j = 1; j < found.size(); j++) intervals.add(found.get(j) - found.get(j - 1)); String tempo = "none";
                if (found.size() >= 2) tempo = twoDecimals(rdiv(6000L * rate, intervals.stream().sorted().toList().get((found.size() - 2) / 2)));
                List<String> lines = new ArrayList<>(List.of(source.name() + " onsets=" + found.size() + " tempo=" + tempo));
                for (int j = 0; j < found.size(); j++) lines.add("  onset " + (j + 1) + " sample=" + found.get(j) + " ms=" + milliseconds(found.get(j), rate) + " interval=" + (j == 0 ? "none" : intervals.get(j - 1))); return lines;
            }
            if (name.equals("EXCERPT")) {
                int start = (int)a.get(1).number, count = Math.min((int)a.get(2).number, length - start); excerpts.add("EXCERPT " + source.name() + " rate=" + rate + " samples=" + length + " start=" + start + " count=" + count);
                for (int offset = 0; offset < count; offset += 8) { StringBuilder row = new StringBuilder(pad(start + offset, 5)).append(':'); for (int j = offset; j < Math.min(offset + 8, count); j++) row.append(' ').append(pad(x[start + j], 6)); excerpts.add(row.toString()); }
                return List.of(source.name() + " start=" + start + " count=" + count);
            }
            if (name.equals("PLOT")) {
                waveforms.addAll(waveform(source, (int)a.get(1).number, (int)a.get(2).number, (int)a.get(3).number, (int)a.get(4).number, a.get(5).number, a.get(6).number));
                return List.of(source.name() + " start=" + a.get(1).number + " count=" + a.get(2).number + " columns=" + a.get(3).number + " rows=" + (2 * a.get(4).number + 1));
            }
            if (name.equals("METER")) { waveforms.addAll(meter(source, (int)a.get(1).number)); return List.of(source.name() + " block=" + a.get(1).number); }
            if (name.equals("HISTOGRAM")) { waveforms.addAll(histogram(source, (int)a.get(1).number)); return List.of(source.name() + " bins=" + a.get(1).number); }
            if (name.equals("TRACE")) { List<String> lines = new ArrayList<>(List.of(source.name())); trace(source, 1, lines); return lines; }
            saved.addAll(Signals.format(source)); return List.of(source.name() + " samples=" + length);
        }
        List<String> execute(int number, String name, String[] tokens) {
            Command command = commands.get(name); if (command == null) throw new CommandError("unknown command " + name);
            if (!command.accepts(tokens.length)) throw new CommandError("wrong number of arguments"); Parsed parsed = parse(name, command, tokens);
            return command.arguments.getFirst().name.equals("dst") ? List.of(generate(number, name, parsed)) : action(name, parsed);
        }
        void run() throws IOException {
            List<String> script = Files.readAllLines(Path.of("input/pipeline.txt"));
            for (int j = 0; j < script.size(); j++) {
                String text = script.get(j); if (text.isEmpty() || text.charAt(0) == '#') continue; String[] tokens = text.split(" "); String name = tokens[0];
                try { List<String> lines = execute(j + 1, name, Arrays.copyOfRange(tokens, 1, tokens.length)); log.add("line " + (j + 1) + ": " + name + " " + lines.getFirst()); log.addAll(lines.subList(1, lines.size())); steps++; }
                catch (CommandError error) { log.add("line " + (j + 1) + ": error: " + error.getMessage()); errors++; }
            }
            for (Signal signal : signals.values()) log.add("signal " + signal.name() + " rate=" + signal.rate() + " samples=" + signal.samples().length + " peak=" + peak(signal.samples()) + " rms=" + rms(signal.samples()));
            log.add("summary steps=" + steps + " errors=" + errors + " signals=" + signals.size() + " passed=" + passed + " failed=" + failed); Files.createDirectories(Path.of("output"));
            Map<String, List<String>> outputs = Map.of("log.txt", log, "analysis.csv", analysis, "excerpts.txt", excerpts, "waveforms.txt", waveforms, "signals_out.txt", saved);
            for (var output : outputs.entrySet()) Files.writeString(Path.of("output", output.getKey()), String.join("\n", output.getValue()) + (output.getValue().isEmpty() ? "" : "\n"), StandardCharsets.US_ASCII);
        }
    }
    public static void main(String[] args) throws IOException { new Pipeline(Signals.read()).run(); }
}
