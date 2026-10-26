using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program
{
    sealed record Range(long Low, long High);
    sealed class QueryError : Exception { public QueryError(string message) : base(message) { } }
    static string[] Read(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII);
    static long YearStart(int year) => DayRules.DayNumber(year, 1, 1) * DayRules.Day;
    static int Integer(string text) => int.Parse(text, CultureInfo.InvariantCulture);
    static long ClockSeconds(string text) => Integer(text[..2]) * 3600L + Integer(text[3..5]) * 60L;
    static string NamesOrNone(IEnumerable<string> names, string separator) { var values = names.ToArray(); return values.Length == 0 ? "none" : string.Join(separator, values); }
    static List<string> Indented(List<string> lines) => lines.Select((line, i) => (i == 0 ? "" : "  ") + line).ToList();

    static List<Range> MergeIntervals(List<Range> intervals)
    {
        var result = new List<Range>();
        foreach (Range range in intervals.OrderBy(range => range.Low).ThenBy(range => range.High))
        {
            if (result.Count > 0 && range.Low <= result[^1].High) result[^1] = new Range(result[^1].Low, Math.Max(result[^1].High, range.High));
            else result.Add(range);
        }
        return result;
    }

    static List<Range> IntersectIntervals(List<Range> first, List<Range> second)
    {
        var pieces = new List<Range>();
        foreach (Range one in first) foreach (Range other in second)
        {
            long low = Math.Max(one.Low, other.Low), high = Math.Min(one.High, other.High);
            if (low < high) pieces.Add(new Range(low, high));
        }
        return MergeIntervals(pieces);
    }

    sealed class SourceLine
    {
        public int Number { get; }
        public string[] Fields { get; }
        public string Kind { get; }
        public Block? Block;
        public int Position;
        public ZoneLine? ZoneLine;
        public bool FieldError;
        public string? Error;

        public SourceLine(int number, string content)
        {
            Number = number;
            Fields = TzParser.Fields(content);
            Kind = TzParser.Continuation(content) ? "continuation" : Fields[0] is "Rule" or "Zone" or "Link" ? Fields[0] : "unknown";
        }
        public bool AcceptsContinuation() => Kind == "Zone" ? Fields.Length >= 6 : Kind == "continuation" && Fields.Length >= 4;
    }

    sealed class Block
    {
        public string Name { get; }
        public int Number { get; }
        public List<SourceLine> Lines { get; } = new();
        public bool Defined;
        public Block(SourceLine first) { Name = first.Fields[1]; Number = first.Number; Add(first); }
        public void Add(SourceLine line) { line.Block = this; line.Position = Lines.Count; Lines.Add(line); }
    }

    sealed class ZoneLine
    {
        public long Stdoff { get; }
        public string RulesText { get; }
        public string? RuleSet { get; }
        public string Format { get; }
        public long Save { get; }
        public TzParser.Until? Until { get; }
        public long Start = DayRules.NegativeInfinity;
        public long End = DayRules.PositiveInfinity;

        public ZoneLine(string[] fields)
        {
            Stdoff = TzParser.Offset(fields[0]);
            RulesText = fields[1];
            if (RulesText[0] >= '0' && RulesText[0] <= '9') Save = TzParser.Save(RulesText);
            else RuleSet = RulesText == "-" ? null : RulesText;
            Format = fields[2];
            TzParser.CheckFormat(Format, RuleSet != null);
            Until = fields.Length > 3 ? TzParser.ParseUntil(fields[3..]) : null;
        }
        public string RulesNotation() => RuleSet ?? (RulesText == "-" ? "-" : Report.Clock(Save));
        public string UntilNotation() => $"{Until!.YearText} {Until.MonthText} {Until.DayText} {Report.Clock(Until.Time)}{Until.Type}";
    }

    sealed class Zone
    {
        public string Name { get; }
        public List<ZoneLine> Lines { get; }
        public List<string> Aliases { get; } = new();
        public Dictionary<int, int> Applied { get; } = new();
        public Resolver.Timeline Timeline = null!;
        public Zone(string name, List<ZoneLine> lines) { Name = name; Lines = lines; }
        public List<string> RuleSets()
        {
            var names = new List<string>();
            foreach (ZoneLine line in Lines) if (line.RuleSet != null && !names.Contains(line.RuleSet)) names.Add(line.RuleSet);
            return names;
        }
        public int LineNumberAt(long time)
        {
            for (int i = 0; i < Lines.Count; i++) if (Lines[i].Start <= time && time < Lines[i].End) return i + 1;
            throw new InvalidOperationException();
        }
    }

    static Transitions.Rule ParseRule(SourceLine line)
    {
        string[] fields = line.Fields;
        int from = TzParser.Year(fields[2]), to = TzParser.ToYear(fields[3], from);
        if (fields[4] != "-") throw new TzParser.FieldError("syntax error");
        int month = TzParser.Month(fields[5]);
        DayRules.DaySpec day = TzParser.ParseDay(fields[6], month);
        TzParser.Time time = TzParser.ParseTime(fields[7]);
        long save = TzParser.Save(fields[8]);
        string letter = TzParser.Letter(fields[9]);
        return new Transitions.Rule(line.Number, fields, from, to, month, day, time.Value, time.Type, save, letter);
    }

    sealed class Database
    {
        public List<SourceLine> Lines { get; } = new();
        public List<Block> Blocks { get; } = new();
        public Dictionary<string, List<Transitions.Rule>> Rules { get; } = new(StringComparer.Ordinal);
        public List<string> RuleNames { get; } = new();
        public Dictionary<string, List<Transitions.Instance>> Sequences { get; } = new(StringComparer.Ordinal);
        public Dictionary<string, Zone> Zones { get; } = new(StringComparer.Ordinal);
        readonly Dictionary<string, Zone> aliases = new(StringComparer.Ordinal);

        public Database(string[] rawLines)
        {
            for (int i = 0; i < rawLines.Length; i++) { string content = TzParser.Content(rawLines[i]); if (content.Length > 0) Lines.Add(new SourceLine(i + 1, content)); }
            SourceLine? previous = null;
            foreach (SourceLine line in Lines)
            {
                if (line.Kind == "Zone") Blocks.Add(new Block(line));
                else if (line.Kind == "continuation" && previous?.Block != null && previous.AcceptsContinuation()) previous.Block.Add(line);
                previous = line;
            }
            foreach (SourceLine line in Lines)
            {
                try { ParseFields(line); }
                catch (TzParser.FieldError error) { line.FieldError = true; line.Error = error.Message; }
            }
            var zoneNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (SourceLine line in Lines) if (line.ZoneLine != null) line.Error = StructuralError(line, zoneNames);
            foreach (string name in RuleNames) Sequences[name] = Transitions.Instances(Rules[name]);
            foreach (Block block in Blocks) { block.Defined = block.Lines.All(line => line.Error == null); if (block.Defined) DefineZone(block); }
            foreach (SourceLine line in Lines) if (line.Kind == "Link" && line.Error == null) RegisterLink(line);
        }

        void ParseFields(SourceLine line)
        {
            int low, high;
            switch (line.Kind)
            {
                case "Rule": low = high = 10; break;
                case "Zone": low = 5; high = 9; break;
                case "continuation": if (line.Block == null) throw new TzParser.FieldError("syntax error"); low = 3; high = 7; break;
                case "Link": low = high = 3; break;
                default: throw new TzParser.FieldError("syntax error");
            }
            if (line.Fields.Length < low || line.Fields.Length > high) throw new TzParser.FieldError("syntax error");
            if (line.Kind == "Rule")
            {
                Transitions.Rule rule = ParseRule(line);
                if (!Rules.ContainsKey(rule.Name)) { Rules[rule.Name] = new List<Transitions.Rule>(); RuleNames.Add(rule.Name); }
                Rules[rule.Name].Add(rule);
            }
            else if (line.Kind == "Zone") line.ZoneLine = new ZoneLine(line.Fields[2..]);
            else if (line.Kind == "continuation") line.ZoneLine = new ZoneLine(line.Fields);
        }

        string? StructuralError(SourceLine line, HashSet<string> zoneNames)
        {
            ZoneLine value = line.ZoneLine!;
            if (line.Kind == "Zone" && !zoneNames.Add(line.Fields[1])) return "duplicate zone " + line.Fields[1];
            if (value.RuleSet != null && !Rules.ContainsKey(value.RuleSet)) return "unknown rule " + value.RuleSet;
            if (value.Until == null) return null;
            if (line.Kind == "continuation")
            {
                SourceLine previous = line.Block!.Lines[line.Position - 1];
                if (!previous.FieldError && value.Until.Value <= previous.ZoneLine!.Until!.Value) return "until not increasing";
            }
            return line.Position == line.Block!.Lines.Count - 1 ? "missing continuation" : null;
        }

        void DefineZone(Block block)
        {
            var zone = new Zone(block.Name, block.Lines.Select(line => line.ZoneLine!).ToList());
            var switches = new List<Resolver.Period>();
            long start = DayRules.NegativeInfinity;
            foreach (ZoneLine line in zone.Lines)
            {
                line.Start = start;
                foreach (Transitions.Switch value in LineSwitches(zone, line)) switches.Add(new Resolver.Period(value.Time, line.Stdoff + value.Save, value.Save != 0, Transitions.Abbreviation(line.Format, value.Save, value.Letter)));
                start = line.End;
            }
            var periods = new List<Resolver.Period>();
            foreach (Resolver.Period period in switches) if (periods.Count == 0 || !periods[^1].SameState(period)) periods.Add(period);
            zone.Timeline = new Resolver.Timeline(periods);
            Zones[zone.Name] = zone;
        }

        List<Transitions.Switch> LineSwitches(Zone zone, ZoneLine line)
        {
            if (line.RuleSet == null)
            {
                if (line.Until != null) line.End = line.Until.Value - Transitions.Adjustment(line.Until.Type, line.Stdoff, line.Save);
                return new List<Transitions.Switch> { new(line.Start, line.Save, "") };
            }
            List<Transitions.Instance> instances = Sequences[line.RuleSet];
            Transitions.LineRun run = Transitions.Run(instances, line.Stdoff, line.Start, line.Until);
            line.End = run.End;
            long save = 0;
            string letter = "";
            if (run.PreStart.Count > 0) { Transitions.Rule last = run.PreStart[^1]; save = last.Save; letter = last.Letter; }
            else foreach (Transitions.Instance instance in instances) if (instance.Rule.Save == 0) { letter = instance.Rule.Letter; break; }
            var switches = new List<Transitions.Switch> { new(line.Start, save, letter) };
            foreach (Transitions.Applied value in run.Applied)
            {
                switches.Add(new Transitions.Switch(value.Time, value.Rule.Save, value.Rule.Letter));
                zone.Applied[value.Rule.Number] = zone.Applied.GetValueOrDefault(value.Rule.Number) + 1;
            }
            return switches;
        }

        void RegisterLink(SourceLine line)
        {
            string target = line.Fields[1], alias = line.Fields[2];
            if (!Zones.ContainsKey(target)) line.Error = "unknown link target " + target;
            else if (Zones.ContainsKey(alias) || aliases.ContainsKey(alias)) line.Error = "duplicate link " + alias;
            else { aliases[alias] = Zones[target]; Zones[target].Aliases.Add(alias); }
        }
        public Zone? FindZone(string name) => Zones.TryGetValue(name, out Zone? zone) ? zone : aliases.GetValueOrDefault(name);
        public List<string> ErrorLines() => Lines.Where(line => line.Error != null).Select(line => $"line {line.Number}: {line.Error}").ToList();
    }

    static long OffsetShift(Resolver.Timeline timeline, int index) => timeline.Periods[index].Offset - timeline.Periods[index - 1].Offset;
    static List<int> TransitionsBetween(Resolver.Timeline timeline, long low, long high) => Enumerable.Range(1, timeline.Periods.Count - 1).Where(i => low <= timeline.Periods[i].Start && timeline.Periods[i].Start < high).ToList();
    static string ChangeAt(Resolver.Timeline timeline, int index) => Report.Change(timeline.Periods[index].Start, timeline.Periods[index - 1], timeline.Periods[index]);
    static string TransitionLine(Resolver.Timeline timeline, int index)
    {
        long time = timeline.Periods[index].Start, shift = OffsetShift(timeline, index);
        string kind = shift > 0 ? "gap " + Report.Duration(shift) : shift < 0 ? "overlap " + Report.Duration(-shift) : "no shift";
        return $"{ChangeAt(timeline, index)} (local {Report.Local(time + timeline.Periods[index - 1].Offset)} -> {Report.Local(time + timeline.Periods[index].Offset)}, {kind})";
    }
    static string ShiftsText(Resolver.Timeline timeline, List<int> indices)
    {
        int gaps = 0, overlaps = 0, unchanged = 0;
        foreach (int index in indices) { long shift = OffsetShift(timeline, index); if (shift > 0) gaps++; else if (shift < 0) overlaps++; else unchanged++; }
        return $"gaps {gaps}, overlaps {overlaps}, no shift {unchanged}";
    }
    static string CandidateText(Resolver.Timeline timeline, long local, int index) { Resolver.Period period = timeline.Periods[index]; return $"{Report.Ut(local - period.Offset)} ({Report.State(period)})"; }
    static int? ChosenCandidate(List<int> candidates, string? option)
    {
        if (candidates.Count == 1 || candidates.Count == 2 && option == "EARLIER") return candidates[0];
        return candidates.Count == 2 && option == "LATER" ? candidates[1] : null;
    }
    static string UnresolvedText(Resolver.Timeline timeline, long local, List<int> candidates)
    {
        if (candidates.Count > 0) return "AMBIGUOUS " + string.Join(" or ", candidates.Select(index => CandidateText(timeline, local, index)));
        int index = timeline.SkippingTransition(local);
        long time = timeline.Periods[index].Start;
        return $"NONEXISTENT gap {Report.Local(time + timeline.Periods[index - 1].Offset)} to {Report.Local(time + timeline.Periods[index].Offset)} at {Report.Ut(time)}";
    }
    static List<Range> WorkingHours(Resolver.Timeline timeline, long start, long end)
    {
        var pieces = new List<Range>();
        for (int i = timeline.NearbyFirst(start); i <= timeline.NearbyLast(end); i++)
        {
            long offset = timeline.Periods[i].Offset, low = Math.Max(start - offset, timeline.Periods[i].Start), high = Math.Min(end - offset, timeline.EndOf(i));
            if (low < high) pieces.Add(new Range(low, high));
        }
        return MergeIntervals(pieces);
    }
    static long? ParseValue(string kind, string word)
    {
        int year = Integer(word[..4]);
        if (year < 1800 || year > 2099) return null;
        if (kind == "year") return year;
        int month = Integer(word[5..7]), day = Integer(word[8..10]);
        if (month < 1 || month > 12 || day < 1 || day > DayRules.DaysInMonth(year, month)) return null;
        if (kind == "date") return DayRules.DayNumber(year, month, day);
        int hour = Integer(word[11..13]), minute = Integer(word[14..16]), second = Integer(word[17..19]);
        return hour > 23 || minute > 59 || second > 59 ? null : DayRules.TimeValue(year, month, day, hour, minute, second);
    }

    sealed class QueryRunner
    {
        readonly Database database;
        readonly long workStart, workEnd;
        public List<string> Answers { get; } = new();
        public List<List<string>> TransitionBlocks { get; } = new();
        public QueryRunner(Database database, long start, long end) { this.database = database; workStart = start; workEnd = end; }

        public void Run(string line)
        {
            string[] words = line.Split(' ');
            string command = words[0];
            string? option = null;
            var arguments = words.Skip(1).ToList();
            if ((command is "TOUTC" or "CONVERT") && (arguments[^1] is "EARLIER" or "LATER")) { option = arguments[^1]; arguments.RemoveAt(arguments.Count - 1); }
            string[] kinds = command switch
            {
                "TOUTC" => new[] { "zone", "local" },
                "TOLOCAL" or "OFFSET" => new[] { "zone", "ut" },
                "CONVERT" => new[] { "zone", "zone", "local" },
                "TRANSITIONS" => new[] { "zone", "year", "year" },
                "DURATION" => new[] { "zone", "local", "local" },
                _ => new[] { "date" }.Concat(Enumerable.Repeat("zone", arguments.Count - 1)).ToArray()
            };
            string result;
            try
            {
                var values = new List<object>();
                for (int i = 0; i < arguments.Count; i++)
                {
                    string kind = kinds[i], word = arguments[i];
                    if (kind == "zone") values.Add(database.FindZone(word) ?? throw new QueryError("unknown zone " + word));
                    else values.Add(ParseValue(kind, word) ?? throw new QueryError("invalid value " + word));
                }
                result = Answer(line, command, values, arguments, option);
            }
            catch (QueryError error) { result = "ERROR " + error.Message; }
            Answers.Add(line + " => " + result);
        }

        string Answer(string line, string command, List<object> values, List<string> arguments, string? option)
        {
            if (command == "MEETING") return Meeting((long)values[0], values.Skip(1).Cast<Zone>().ToList(), arguments.Skip(1).ToList());
            Zone zone = (Zone)values[0];
            return command switch
            {
                "TOUTC" => ToUtc(zone, (long)values[1], option),
                "TOLOCAL" => ToLocal(zone, (long)values[1]),
                "CONVERT" => Convert(zone, (Zone)values[1], (long)values[2], option),
                "OFFSET" => Offset(zone, (long)values[1]),
                "TRANSITIONS" => TransitionsQuery(line, zone, (int)(long)values[1], (int)(long)values[2]),
                _ => Duration(zone, (long)values[1], (long)values[2], arguments.Skip(1).ToList())
            };
        }
        static string ToUtc(Zone zone, long local, string? option)
        {
            List<int> candidates = zone.Timeline.Candidates(local);
            int? index = ChosenCandidate(candidates, option);
            return index == null ? UnresolvedText(zone.Timeline, local, candidates) : CandidateText(zone.Timeline, local, index.Value);
        }
        static string ToLocal(Zone zone, long time) { Resolver.Period period = zone.Timeline.PeriodAt(time); return $"{Report.Local(time + period.Offset)} ({Report.State(period)})"; }
        static string Convert(Zone source, Zone target, long local, string? option)
        {
            List<int> candidates = source.Timeline.Candidates(local);
            int? index = ChosenCandidate(candidates, option);
            if (index == null) return UnresolvedText(source.Timeline, local, candidates);
            long time = local - source.Timeline.Periods[index.Value].Offset;
            Resolver.Period period = target.Timeline.PeriodAt(time);
            long targetLocal = time + period.Offset, shift = DayRules.FloorDiv(targetLocal, DayRules.Day) - DayRules.FloorDiv(local, DayRules.Day);
            return $"{Report.Local(targetLocal)} ({Report.State(period)}) at {Report.Ut(time)}, day shift {(shift > 0 ? "+" : "")}{shift}";
        }
        static string Offset(Zone zone, long time)
        {
            Resolver.Timeline timeline = zone.Timeline;
            int index = timeline.IndexAt(time);
            string text = Report.State(timeline.Periods[index]);
            if (index >= 1) text += " since " + Report.Ut(timeline.Periods[index].Start);
            if (index + 1 < timeline.Periods.Count) text += " until " + Report.Ut(timeline.Periods[index + 1].Start);
            return text;
        }
        string TransitionsQuery(string line, Zone zone, int first, int last)
        {
            if (first > last) throw new QueryError("invalid range");
            List<int> selected = TransitionsBetween(zone.Timeline, YearStart(first), YearStart(last + 1));
            var block = new List<string> { line };
            foreach (int index in selected) block.Add(TransitionLine(zone.Timeline, index));
            block.Add(ShiftsText(zone.Timeline, selected));
            TransitionBlocks.Add(block);
            return "transitions: " + selected.Count;
        }
        static string Duration(Zone zone, long first, long second, List<string> words)
        {
            var periods = new Resolver.Period[2];
            long[] locals = { first, second };
            for (int i = 0; i < 2; i++)
            {
                List<int> candidates = zone.Timeline.Candidates(locals[i]);
                if (candidates.Count == 2) return "AMBIGUOUS " + words[i];
                if (candidates.Count == 0) return "NONEXISTENT " + words[i];
                periods[i] = zone.Timeline.Periods[candidates[0]];
            }
            long elapsed = (second - periods[1].Offset) - (first - periods[0].Offset), change = periods[1].Offset - periods[0].Offset;
            return $"{elapsed} s ({Report.Duration(elapsed)}), wall clock {Report.Duration(second - first)}, offset change {Report.Offset(change)}";
        }
        string Meeting(long day, List<Zone> zones, List<string> words)
        {
            long start = day * DayRules.Day + workStart, end = day * DayRules.Day + workEnd;
            List<Range> common = WorkingHours(zones[0].Timeline, start, end);
            for (int i = 1; i < zones.Count; i++) common = IntersectIntervals(common, WorkingHours(zones[i].Timeline, start, end));
            var parts = new List<string>();
            foreach (Range range in common)
            {
                var members = new List<string>();
                for (int i = 0; i < zones.Count; i++) { Resolver.Period period = zones[i].Timeline.PeriodAt(range.Low); members.Add($"{words[i]} {Report.Local(range.Low + period.Offset)} {period.Abbreviation}"); }
                parts.Add($"{Report.Ut(range.Low)} to {Report.Ut(range.High)} ({Report.Duration(range.High - range.Low)}) [{string.Join(", ", members)}]");
            }
            return parts.Count == 0 ? "NONE" : string.Join("; ", parts);
        }
    }

    static string RuleText(Transitions.Rule rule)
    {
        string[] fields = rule.Fields;
        return $"rule {rule.Name} {fields[2]} {fields[3]} {fields[5]} {fields[6]} {Report.Clock(rule.At)}{rule.Type} {Report.Clock(rule.Save)} {fields[9]}";
    }
    static List<string> DatabaseBlock(Database database)
    {
        int ruleLines = database.Lines.Count(line => line.Kind == "Rule"), linkLines = database.Lines.Count(line => line.Kind == "Link");
        int validRules = database.Lines.Count(line => line.Kind == "Rule" && line.Error == null), validLinks = database.Lines.Count(line => line.Kind == "Link" && line.Error == null);
        var used = new HashSet<string>(StringComparer.Ordinal);
        foreach (Zone zone in database.Zones.Values) used.UnionWith(zone.RuleSets());
        var unused = database.RuleNames.Where(name => !used.Contains(name));
        var invalid = database.Blocks.Where(block => !block.Defined).Select(block => $"{block.Name} (line {block.Number})");
        var lines = new List<string>
        {
            "DATABASE", $"rule lines: {validRules} valid, {ruleLines - validRules} invalid", $"zones: {database.Zones.Count} defined, {database.Blocks.Count - database.Zones.Count} invalid",
            $"zone lines: {database.Zones.Values.Sum(zone => zone.Lines.Count)} in defined zones", $"links: {validLinks} defined, {linkLines - validLinks} invalid", $"errors: {database.ErrorLines().Count}",
            "unused rules: " + NamesOrNone(unused, " "), "invalid zones: " + NamesOrNone(invalid, ", ")
        };
        foreach (string name in database.RuleNames)
        {
            List<Transitions.Rule> rules = database.Rules[name];
            int first = rules.Min(rule => rule.FromYear);
            string last = rules.Any(rule => rule.Fields[3] == "max") ? "max" : rules.Max(rule => rule.ToYear).ToString(CultureInfo.InvariantCulture);
            int count = database.Zones.Values.Count(zone => zone.RuleSets().Contains(name));
            lines.Add($"rule set {name}: lines {rules.Count}, years {first}-{last}, zones {count}");
        }
        return lines;
    }
    static List<string> DstLines(Resolver.Timeline timeline, long reference)
    {
        var indices = Enumerable.Range(0, timeline.Periods.Count).Where(i => timeline.Periods[i].Dst).ToArray();
        var lines = new List<string>();
        if (indices.Length == 0) lines.Add("dst years: none");
        else
        {
            int[] years = indices.Select(i => DayRules.SplitTime(timeline.Periods[i].Start)[0]).ToArray();
            lines.Add($"dst years: {years.Min()}-{years.Max()}");
        }
        int year = DayRules.SplitTime(reference)[0];
        long low = YearStart(year), high = YearStart(year + 1), total = 0;
        var pieces = new List<Range>();
        foreach (int index in indices) { long start = Math.Max(low, timeline.Periods[index].Start), end = Math.Min(high, timeline.EndOf(index)); if (start < end) pieces.Add(new Range(start, end)); }
        foreach (Range range in MergeIntervals(pieces)) { lines.Add($"dst period: {Report.Ut(range.Low)} to {Report.Ut(range.High)} ({Report.Duration(range.High - range.Low)})"); total += range.High - range.Low; }
        lines.Add($"dst total {year}: {Report.Duration(total)}");
        return lines;
    }
    static List<string> ZoneBlock(Database database, Zone zone, long reference)
    {
        Resolver.Timeline timeline = zone.Timeline;
        List<Resolver.Period> periods = timeline.Periods;
        var lines = new List<string> { "ZONE " + zone.Name, "aliases: " + NamesOrNone(zone.Aliases, " ") };
        for (int i = 0; i < zone.Lines.Count; i++)
        {
            ZoneLine value = zone.Lines[i];
            string text = $"line {i + 1}: {Report.Offset(value.Stdoff)} {value.RulesNotation()} {value.Format}";
            if (i >= 1) text += " from " + Report.Ut(value.Start);
            if (value.Until != null) text += $" until {value.UntilNotation()} = {Report.Ut(value.End)}";
            lines.Add($"{text}, transitions {TransitionsBetween(timeline, value.Start, value.End).Count}");
        }
        foreach (string name in zone.RuleSets()) foreach (Transitions.Rule rule in database.Rules[name]) lines.Add($"{RuleText(rule)}, applied {zone.Applied.GetValueOrDefault(rule.Number)}");
        lines.Add($"offset range: {Report.Offset(periods.Min(period => period.Offset))} to {Report.Offset(periods.Max(period => period.Offset))}");
        foreach (var group in periods.GroupBy(Report.State, StringComparer.Ordinal)) lines.Add($"state {group.Key}, periods {group.Count()}");
        int index = timeline.IndexAt(reference);
        Resolver.Period period = periods[index];
        lines.Add($"reference: {Report.Local(reference + period.Offset)} ({Report.State(period)}), line {zone.LineNumberAt(reference)}");
        lines.Add("previous transition: " + (index >= 1 ? ChangeAt(timeline, index) : "none"));
        lines.Add("next transition: " + (index + 1 < periods.Count ? ChangeAt(timeline, index + 1) : "none"));
        List<int> every = Enumerable.Range(1, periods.Count - 1).ToList();
        lines.Add($"transitions: {every.Count}, {ShiftsText(timeline, every)}");
        lines.AddRange(DstLines(timeline, reference));
        return lines;
    }

    static void Main()
    {
        var database = new Database(Read("tzdata.txt"));
        string[] parameters = Read("params.txt");
        long reference = ParseValue("ut", parameters[0].Split(' ')[1])!.Value;
        string[] workday = parameters[1].Split(' ');
        var runner = new QueryRunner(database, ClockSeconds(workday[1]), ClockSeconds(workday[2]));
        foreach (string line in Read("queries.txt")) runner.Run(line);
        var blocks = new List<List<string>> { Indented(DatabaseBlock(database)) };
        foreach (string name in database.Zones.Keys.OrderBy(name => name, StringComparer.Ordinal)) blocks.Add(Indented(ZoneBlock(database, database.Zones[name], reference)));
        Directory.CreateDirectory("output");
        Report.WriteLines("answers.txt", runner.Answers);
        Report.WriteLines("errors.txt", database.ErrorLines());
        Report.WriteBlocks("transitions.txt", runner.TransitionBlocks);
        Report.WriteBlocks("zone_summary.txt", blocks);
    }
}
