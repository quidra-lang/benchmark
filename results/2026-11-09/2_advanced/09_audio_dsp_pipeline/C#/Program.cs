global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using static SignalMath;
using static AudioAnalysis;

sealed class CommandError(string message) : Exception(message) {}
record Argument(string Name, string Low = "", string High = "");
sealed class Command(List<Argument> arguments, List<Argument>? repeated = null, int minimum = 0, int maximum = 0)
{
    public List<Argument> Arguments = arguments, Repeated = repeated ?? [];
    public bool Accepts(int count)
    {
        int extra = count - Arguments.Count;
        return Repeated.Count == 0 ? extra == 0 : extra >= 0 && extra % Repeated.Count == 0 && extra >= minimum * Repeated.Count && extra <= maximum * Repeated.Count;
    }
    public Argument At(int index) => index < Arguments.Count ? Arguments[index] : Repeated[(index - Arguments.Count) % Repeated.Count];
}
record Value(string Text, long Number = 0, Signal? Source = null);
record Parsed(List<Value> Values, List<Signal> Sources);

sealed class Pipeline
{
    readonly SortedDictionary<string, Signal> signals = new(StringComparer.Ordinal);
    readonly Dictionary<string, long> variables = new(StringComparer.Ordinal);
    readonly Dictionary<string, Command> commands = CommandTable();
    readonly List<string> log = [], analysis = ["signal,peak,rms,zero_crossings,clipped,crest,pitch_lag,pitch_hz"], excerpts = [], waveforms = [], saved = [];
    int steps, errors, passed, failed;
    static Argument A(string name, long low, long high) => new(name, low.ToString(), high.ToString());
    static Dictionary<string, Command> CommandTable()
    {
        Argument dst = new("dst"), src = new("src"), rate = A("rate", 1000, 48000), count = A("count", 1, 20000), num = A("num", -65536, 65536), den = A("den", 1, 65536);
        Argument attack = A("attack", 1, 32768), release = A("release", 1, 32768), start = new("start", "0", "L - 1"), minHz = new("min_hz", "1", "rate div 2 - 1"), maxHz = new("max_hz", "min_hz + 1", "rate div 2");
        List<Argument> test = [dst, rate, count, new("pos", "0", "count - 1"), A("amp", -32768, 32767)];
        return new(StringComparer.Ordinal) {
            ["SET"] = new([new("var"), A("value", -10000000, 10000000)], [new("op"), A("operand", -10000000, 10000000)], 0, 1),
            ["IMPULSE"] = new(test), ["STEP"] = new(test), ["NOISE"] = new([dst, rate, count, A("seed", 1, 2147483646)]),
            ["GAIN"] = new([dst, src, num, den]), ["MIX"] = new([dst, den], [src, A("weight", -65536, 65536)], 1, 8),
            ["DELAY"] = new([dst, src, A("samples", 0, 20000)]), ["ECHO"] = new([dst, src, A("delay", 1, 20000), num, den, A("tail", 0, 20000)]),
            ["RESAMPLE"] = new([dst, src, A("new_rate", 1000, 48000)]), ["FADE"] = new([dst, src, new("in", "0", "L"), new("out", "0", "L")]),
            ["TRIM"] = new([dst, src, start, new("count", "1", "L - start")]), ["CONCAT"] = new([dst], [src], 2, 8),
            ["FIR"] = new([dst, src, A("divisor", 1, 1000000)], [A("tap", -32768, 32767)], 1, 64),
            ["BIQUAD"] = new([dst, src], [A("b0", -65536, 65536), A("b1", -65536, 65536), A("b2", -65536, 65536), A("a1", -65536, 65536), A("a2", -65536, 65536)], 1, 4),
            ["MOVAVG"] = new([dst, src, A("width", 1, 1000)]), ["DCBLOCK"] = new([dst, src, A("num", 0, 65535), new("den", "num + 1", "65536")]),
            ["NORMALIZE"] = new([dst, src, A("target", 1, 32767)]), ["GATE"] = new([dst, src, A("threshold", 1, 32768), A("hold", 0, 20000)]),
            ["ENVELOPE"] = new([dst, src, attack, release]), ["COMPRESS"] = new([dst, src, A("threshold", 1, 32767), A("ratio_num", 1, 100), new("ratio_den", "1", "ratio_num"), attack, release]),
            ["ANALYZE"] = new([src, minHz, maxHz]), ["COMPARE"] = new([src, src]), ["EXPECT"] = new([src, new("metric"), new("op"), A("value", -1000000000, 1000000000)]),
            ["SEGMENTS"] = new([src, A("threshold", 1, 32768), A("gap", 1, 20000), A("min_length", 1, 20000)]),
            ["ONSETS"] = new([src, attack, release, A("threshold", 1, 32767), A("min_gap", 1, 20000)]),
            ["PITCHTRACK"] = new([src, new("frame", "16", "L"), new("hop", "1", "frame"), minHz, maxHz, A("threshold", 0, 32767)]),
            ["EXCERPT"] = new([src, start, A("count", 1, 1000)]),
            ["PLOT"] = new([src, start, new("count", "1", "L - start"), new("columns", "8", "min(120, count)"), A("half", 2, 20), attack, release]),
            ["METER"] = new([src, A("block", 1, 20000)]), ["HISTOGRAM"] = new([src, A("bins", 2, 64)]), ["TRACE"] = new([src]), ["SAVE"] = new([src])
        };
    }
    public Pipeline(List<Signal> loaded)
    {
        foreach (Signal signal in loaded) { signals[signal.Name] = signal; log.Add($"load {signal.Name} rate={signal.Rate} samples={signal.Samples.Length} peak={Peak(signal.Samples)}"); }
    }
    static long Bound(string text, Dictionary<string, long> known, Signal? source) => text switch {
        "L" => source!.Samples.Length, "L - 1" => source!.Samples.Length - 1, "L - start" => source!.Samples.Length - known["start"],
        "count - 1" => known["count"] - 1, "min(120, count)" => Math.Min(120, known["count"]), "min_hz + 1" => known["min_hz"] + 1,
        "num + 1" => known["num"] + 1, "rate div 2" => source!.Rate / 2, "rate div 2 - 1" => source!.Rate / 2 - 1,
        _ => known.TryGetValue(text, out long value) ? value : long.Parse(text)
    };
    Parsed Parse(string name, Command command, string[] tokens)
    {
        List<Value> values = []; List<Signal> sources = []; Dictionary<string, long> known = new(StringComparer.Ordinal);
        HashSet<string> metrics = ["samples", "peak", "rms", "sum", "zero_crossings", "clipped"];
        for (int j = 0; j < tokens.Length; j++)
        {
            Argument argument = command.At(j); string token = tokens[j]; Value value = new(token);
            if (argument.Name is "dst" or "var")
            {
                if (!Regex.IsMatch(token, "\\A[a-z][a-z0-9_]{0,15}\\z")) throw new CommandError("bad name " + token);
            }
            else if (argument.Name == "src")
            {
                if (!signals.TryGetValue(token, out Signal? source)) throw new CommandError("unknown signal " + token);
                value = new(token, Source: source); sources.Add(source);
            }
            else if (argument.Name == "metric")
            {
                if (!metrics.Contains(token)) throw new CommandError("unknown metric " + token);
            }
            else if (argument.Name == "op")
            {
                string[] operators = name == "SET" ? ["+", "-", "*", "/"] : ["eq", "ne", "lt", "le", "gt", "ge"];
                if (!operators.Contains(token)) throw new CommandError("unknown operator " + token);
            }
            else
            {
                long number;
                if (token.StartsWith('$'))
                {
                    if (!variables.TryGetValue(token[1..], out number)) throw new CommandError("undefined variable " + token);
                }
                else
                {
                    if (!Regex.IsMatch(token, "\\A-?(0|[1-9][0-9]{0,9})\\z") || token == "-0") throw new CommandError("bad integer " + token);
                    number = long.Parse(token);
                }
                Signal? source = sources.FirstOrDefault();
                if (number < Bound(argument.Low, known, source) || number > Bound(argument.High, known, source)) throw new CommandError(argument.Name + " out of range");
                known[argument.Name] = number; value = new(token, number);
            }
            values.Add(value);
        }
        return new(values, sources);
    }
    static void SameRate(List<Signal> sources)
    {
        if (sources.Any(source => source.Rate != sources[0].Rate)) throw new CommandError("rate mismatch");
    }
    string Generate(int number, string name, Parsed parsed)
    {
        List<Value> a = parsed.Values; long N(int index) => a[index].Number; int I(int index) => (int)N(index);
        long[] samples = []; int rate = parsed.Sources.Count == 0 ? I(1) : parsed.Sources[0].Rate; List<string> extras = [];
        long[] x = parsed.Sources.Count == 0 ? [] : parsed.Sources[0].Samples; int length = x.Length;
        void Use(Processed result, string key = "clipped") { samples = result.Samples; extras.Add($"{key}={result.Count}"); }
        switch (name)
        {
            case "IMPULSE": samples = Signals.Impulse(I(2), I(3), N(4)); break;
            case "STEP": samples = Signals.Step(I(2), I(3), N(4)); break;
            case "NOISE": samples = Signals.Noise(I(2), N(3)); break;
            case "GAIN": Use(Effects.Gain(x, N(2), N(3))); break;
            case "MIX":
                SameRate(parsed.Sources); List<long[]> tracks = []; List<long> weights = [];
                for (int j = 2; j < a.Count; j += 2) { tracks.Add(a[j].Source!.Samples); weights.Add(N(j + 1)); }
                Use(Effects.Mix(tracks, weights, N(1))); break;
            case "DELAY":
                if (length + N(2) > 20000) throw new CommandError("result too long"); samples = Effects.Delay(x, I(2)); break;
            case "ECHO":
                if (Math.Abs(N(3)) >= N(4)) throw new CommandError("unstable feedback");
                if (length + N(5) > 20000) throw new CommandError("result too long"); Use(Effects.Echo(x, I(2), N(3), N(4), I(5))); break;
            case "RESAMPLE":
                if (Effects.ResampledLength(length, rate, I(2)) > 20000) throw new CommandError("result too long"); samples = Effects.Resample(x, rate, I(2)); rate = I(2); break;
            case "FADE": samples = Effects.Fade(x, I(2), I(3)); break;
            case "TRIM": samples = x[I(2)..(I(2) + I(3))]; break;
            case "CONCAT":
                SameRate(parsed.Sources); if (parsed.Sources.Sum(source => source.Samples.Length) > 20000) throw new CommandError("result too long"); samples = parsed.Sources.SelectMany(source => source.Samples).ToArray(); break;
            case "FIR": Use(Filters.Fir(x, N(2), a.Skip(3).Select(value => value.Number).ToArray())); break;
            case "BIQUAD":
                long[] coefficients = a.Skip(2).Select(value => value.Number).ToArray(); extras.Add($"sections={coefficients.Length / 5}"); Use(Filters.Biquad(x, coefficients)); break;
            case "MOVAVG": samples = Filters.MovingAverage(x, I(2)); break;
            case "DCBLOCK": Use(Filters.DcBlock(x, N(2), N(3))); break;
            case "NORMALIZE": Use(Dynamics.Normalize(x, N(2)), "source_peak"); break;
            case "GATE": Use(Dynamics.Gate(x, N(2), I(3)), "muted"); break;
            case "ENVELOPE": samples = Dynamics.Envelope(x, N(2), N(3)); break;
            case "COMPRESS":
                Compressed compressed = Dynamics.Compress(x, N(2), N(3), N(4), N(5), N(6)); samples = compressed.Samples; extras.Add($"min_gain={compressed.MinGain}"); extras.Add($"reduced={compressed.Reduced}"); break;
        }
        Signal signal = new(a[0].Text, rate, samples, $"line {number} {name}", parsed.Sources); signals[a[0].Text] = signal;
        return $"{signal.Name} rate={rate} samples={samples.Length} peak={Peak(samples)} sum={samples.Sum()}" + (extras.Count == 0 ? "" : " " + string.Join(" ", extras));
    }
    static string Pad(object value, int width) => value.ToString()!.PadLeft(width);
    static long Milliseconds(long sample, int rate) => sample * 1000 / rate;
    static string TwoDecimals(long value) => $"{value / 100}.{value % 100:D2}";
    static string Frequency(int rate, int lag) => TwoDecimals(Rdiv(100L * rate, lag));
    static List<string> Waveform(Signal source, int start, int count, int columns, int half, long attack, long release)
    {
        long[] window = source.Samples[start..(start + count)], levels = Dynamics.Envelope(source.Samples, attack, release)[start..(start + count)];
        int rows = 2 * half + 1; long scale = Math.Max(1, Peak(window)); char[][] grid = Enumerable.Range(0, rows).Select(_ => new string(' ', columns).ToCharArray()).ToArray();
        int RowOf(long value) => (int)Rdiv((scale - value) * (rows - 1), 2 * scale);
        for (int column = 0; column < columns; column++)
        {
            int first = column * count / columns, last = (column + 1) * count / columns; long[] part = window[first..last];
            long top = part.Max(), bottom = part.Min(), level = Math.Min(scale, levels[first..last].Max());
            for (int row = 0; row < rows; row++) grid[row][column] = row == RowOf(level) || row == RowOf(-level) ? '*' : RowOf(top) <= row && row <= RowOf(bottom) ? '#' : row == half ? '-' : ' ';
        }
        List<string> lines = [$"PLOT {source.Name} rate={source.Rate} start={start} count={count} columns={columns} rows={rows} scale={scale} attack={attack} release={release}"];
        for (int row = 0; row < rows; row++)
        {
            string label = row == 0 ? scale.ToString() : row == half ? "0" : row == rows - 1 ? (-scale).ToString() : ""; lines.Add(Pad(label, 6) + " |" + new string(grid[row]) + "|");
        }
        lines.Add("       +" + new string(Enumerable.Range(0, columns).Select(column => column % 10 == 0 ? '+' : '-').ToArray()) + "+");
        string time = "    ms"; for (int column = 0; column < columns; column += 10) time = time.PadRight(8 + column) + Milliseconds(start + column * count / columns, source.Rate); lines.Add(time); return lines;
    }
    static List<string> Meter(Signal source, int block)
    {
        int length = source.Samples.Length, blocks = (length + block - 1) / block;
        List<string> lines = [$"METER {source.Name} rate={source.Rate} samples={length} block={block} blocks={blocks}"];
        for (int b = 0; b < blocks; b++)
        {
            long[] part = source.Samples[(b * block)..Math.Min((b + 1) * block, length)]; long peak = Peak(part), rms = Rms(part), np = Rdiv(peak * 40, 32768), nq = Rdiv(rms * 40, 32768);
            string bar = new(Enumerable.Range(0, 40).Select(j => j < nq ? '#' : j < np ? '-' : ' ').ToArray());
            lines.Add($"{Pad(Milliseconds(b * block, source.Rate), 6)} |{bar}| peak={peak} rms={rms} clipped={Clipped(part)}");
        }
        return lines;
    }
    static List<string> Histogram(Signal source, int bins)
    {
        int[] counts = new int[bins]; foreach (long sample in source.Samples) counts[(int)((sample + 32768) * bins / 65536)]++; int maximum = counts.Max();
        List<string> lines = [$"HISTOGRAM {source.Name} rate={source.Rate} samples={source.Samples.Length} bins={bins} max={maximum}"];
        for (int b = 0; b < bins; b++)
        {
            int low = (b * 65536 + bins - 1) / bins - 32768, high = ((b + 1) * 65536 + bins - 1) / bins - 32769;
            lines.Add($"{Pad(low, 6)} {Pad(high, 6)} {Pad(counts[b], 5)} |" + new string('#', (int)Rdiv(counts[b] * 50, maximum)));
        }
        return lines;
    }
    static void Trace(Signal source, int depth, List<string> lines)
    {
        lines.Add(new string(' ', depth * 2) + source.Name + " <- " + source.Origin); foreach (Signal ingredient in source.Ingredients) Trace(ingredient, depth + 1, lines);
    }
    static long Measured(long[] samples, string metric) => metric switch {
        "samples" => samples.Length, "peak" => Peak(samples), "rms" => Rms(samples), "sum" => samples.Sum(), "zero_crossings" => ZeroCrossings(samples), _ => Clipped(samples)
    };
    List<string> Action(string name, Parsed parsed)
    {
        List<Value> a = parsed.Values; long N(int index) => a[index].Number; int I(int index) => (int)N(index);
        if (name == "SET")
        {
            long result = N(1);
            if (a.Count == 4)
            {
                string op = a[2].Text; long operand = N(3); if (op == "/" && operand == 0) throw new CommandError("division by zero");
                result = op switch { "+" => result + operand, "-" => result - operand, "*" => result * operand, _ => FloorDiv(result, operand) };
                if (Math.Abs(result) > 10000000) throw new CommandError("value out of range");
            }
            variables[a[0].Text] = result; return [$"{a[0].Text}={result}"];
        }
        Signal source = parsed.Sources[0]; long[] x = source.Samples; int length = x.Length, rate = source.Rate;
        if (name is "ANALYZE" or "PITCHTRACK")
        {
            int minHz = name == "ANALYZE" ? I(1) : I(3), maxHz = name == "ANALYZE" ? I(2) : I(4), low = (rate + maxHz - 1) / maxHz, high = rate / minHz;
            if (low > high) throw new CommandError("empty lag range");
            if (name == "ANALYZE")
            {
                if (high >= length) throw new CommandError("signal too short"); int? lag = PitchLag(x, low, high);
                analysis.Add(string.Join(",", source.Name, Peak(x), Rms(x), ZeroCrossings(x), Clipped(x), Crest(x), lag?.ToString() ?? "none", lag.HasValue ? Frequency(rate, lag.Value) : "none"));
                return [$"{source.Name} lags={low}-{high}"];
            }
            int frame = I(1), hop = I(2), threshold = I(5); if (high >= frame) throw new CommandError("frame too short"); int count = (length - frame) / hop + 1, voiced = 0; List<string> rows = [];
            for (int t = 0; t < count; t++)
            {
                long[] window = x[(t * hop)..(t * hop + frame)]; long level = Rms(window); int? lag = level < threshold ? null : PitchLag(window, low, high);
                char[] band = new string(' ', 41).ToCharArray(); string details = $"unvoiced rms={level}";
                if (lag.HasValue) { voiced++; int position = high > low ? (int)Rdiv((high - lag.Value) * 40, high - low) : 0; band[position] = 'o'; details = $"lag={lag.Value} hz={Frequency(rate, lag.Value)} rms={level}"; }
                rows.Add($"{Pad(Milliseconds(t * hop, rate), 6)} |{new string(band)}| {details}");
            }
            waveforms.Add($"PITCHTRACK {source.Name} rate={rate} frame={frame} hop={hop} lags={low}-{high} threshold={threshold} frames={count} voiced={voiced}"); waveforms.AddRange(rows);
            return [$"{source.Name} frames={count} voiced={voiced}"];
        }
        if (name == "COMPARE")
        {
            SameRate(parsed.Sources); Signal other = parsed.Sources[1]; int count = Math.Max(length, other.Samples.Length), differing = 0, first = -1; long maximum = 0, total = 0;
            for (int j = 0; j < count; j++) { long delta = (j < length ? x[j] : 0) - (j < other.Samples.Length ? other.Samples[j] : 0); if (delta != 0) { differing++; if (first < 0) first = j; } maximum = Math.Max(maximum, Math.Abs(delta)); total += delta * delta; }
            return [$"{source.Name} {other.Name} differing={differing} max_diff={maximum} first={(first < 0 ? "none" : first.ToString())} error_energy={total}"];
        }
        if (name == "EXPECT")
        {
            long value = Measured(x, a[1].Text), expected = N(3); string op = a[2].Text;
            bool ok = op switch { "eq" => value == expected, "ne" => value != expected, "lt" => value < expected, "le" => value <= expected, "gt" => value > expected, _ => value >= expected };
            if (ok) passed++; else failed++; return [$"{source.Name} {a[1].Text}={value} {op} {expected} {(ok ? "pass" : "fail")}"];
        }
        if (name == "SEGMENTS")
        {
            List<(int Start, int End)> segments = [];
            for (int j = 0; j < length; j++) if (Math.Abs(x[j]) >= N(1)) { if (segments.Count > 0 && j - segments[^1].End <= N(2)) segments[^1] = (segments[^1].Start, j); else segments.Add((j, j)); }
            List<string> lines = []; int count = 0;
            foreach (var segment in segments) if (segment.End - segment.Start + 1 >= N(3))
            {
                long[] part = x[segment.Start..(segment.End + 1)]; lines.Add($"  segment {++count} start={segment.Start} end={segment.End} start_ms={Milliseconds(segment.Start, rate)} end_ms={Milliseconds(segment.End, rate)} peak={Peak(part)} rms={Rms(part)} crossings={ZeroCrossings(part)}");
            }
            lines.Insert(0, $"{source.Name} segments={count}"); return lines;
        }
        if (name == "ONSETS")
        {
            long[] levels = Dynamics.Envelope(x, N(1), N(2)); List<int> found = [];
            for (int j = 0; j < length; j++) if (levels[j] >= N(3) && (j == 0 || levels[j - 1] < N(3)) && (found.Count == 0 || j - found[^1] >= N(4))) found.Add(j);
            List<int> intervals = found.Skip(1).Select((sample, j) => sample - found[j]).ToList(); string tempo = "none";
            if (found.Count >= 2) tempo = TwoDecimals(Rdiv(6000L * rate, intervals.Order().ElementAt((found.Count - 2) / 2)));
            List<string> lines = [$"{source.Name} onsets={found.Count} tempo={tempo}"];
            for (int j = 0; j < found.Count; j++) lines.Add($"  onset {j + 1} sample={found[j]} ms={Milliseconds(found[j], rate)} interval={(j == 0 ? "none" : intervals[j - 1].ToString())}"); return lines;
        }
        if (name == "EXCERPT")
        {
            int start = I(1), count = Math.Min(I(2), length - start); excerpts.Add($"EXCERPT {source.Name} rate={rate} samples={length} start={start} count={count}");
            for (int offset = 0; offset < count; offset += 8) excerpts.Add(Pad(start + offset, 5) + ":" + string.Concat(x[(start + offset)..(start + Math.Min(offset + 8, count))].Select(sample => " " + Pad(sample, 6))));
            return [$"{source.Name} start={start} count={count}"];
        }
        if (name == "PLOT") { waveforms.AddRange(Waveform(source, I(1), I(2), I(3), I(4), N(5), N(6))); return [$"{source.Name} start={N(1)} count={N(2)} columns={N(3)} rows={2 * N(4) + 1}"]; }
        if (name == "METER") { waveforms.AddRange(Meter(source, I(1))); return [$"{source.Name} block={N(1)}"]; }
        if (name == "HISTOGRAM") { waveforms.AddRange(Histogram(source, I(1))); return [$"{source.Name} bins={N(1)}"]; }
        if (name == "TRACE") { List<string> lines = [source.Name]; Trace(source, 1, lines); return lines; }
        saved.AddRange(Signals.Format(source)); return [$"{source.Name} samples={length}"];
    }
    List<string> Execute(int number, string name, string[] tokens)
    {
        if (!commands.TryGetValue(name, out Command? command)) throw new CommandError("unknown command " + name);
        if (!command.Accepts(tokens.Length)) throw new CommandError("wrong number of arguments"); Parsed parsed = Parse(name, command, tokens);
        return command.Arguments[0].Name == "dst" ? [Generate(number, name, parsed)] : Action(name, parsed);
    }
    public void Run()
    {
        string[] script = File.ReadAllLines("input/pipeline.txt");
        for (int j = 0; j < script.Length; j++)
        {
            string text = script[j]; if (text.Length == 0 || text[0] == '#') continue; string[] tokens = text.Split(' '); string name = tokens[0];
            try { List<string> lines = Execute(j + 1, name, tokens[1..]); log.Add($"line {j + 1}: {name} {lines[0]}"); log.AddRange(lines.Skip(1)); steps++; }
            catch (CommandError error) { log.Add($"line {j + 1}: error: {error.Message}"); errors++; }
        }
        foreach (Signal signal in signals.Values) log.Add($"signal {signal.Name} rate={signal.Rate} samples={signal.Samples.Length} peak={Peak(signal.Samples)} rms={Rms(signal.Samples)}");
        log.Add($"summary steps={steps} errors={errors} signals={signals.Count} passed={passed} failed={failed}"); Directory.CreateDirectory("output");
        foreach (var output in new[] { ("log.txt", log), ("analysis.csv", analysis), ("excerpts.txt", excerpts), ("waveforms.txt", waveforms), ("signals_out.txt", saved) }) File.WriteAllText(Path.Combine("output", output.Item1), string.Join("\n", output.Item2) + (output.Item2.Count == 0 ? "" : "\n"), Encoding.ASCII);
    }
}
static class Program
{
    static void Main() { CultureInfo.CurrentCulture = CultureInfo.InvariantCulture; new Pipeline(Signals.Read()).Run(); }
}
