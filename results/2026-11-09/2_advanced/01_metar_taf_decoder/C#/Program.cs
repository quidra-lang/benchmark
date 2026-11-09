#nullable enable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

sealed record Group(string Text, int Position);
sealed record Slot(string Kind, bool Repeat);
sealed record Runway(string Name, long Heading);
sealed record TrendTime(string Kind, long Hour, long Minute);
sealed record Temporary(string Kind, Section State);
sealed record Component(long Head, long Cross);
sealed record RunwayWind(string Name, Component Mean, Component? Gust, bool Usable);
sealed record ParseError(int Report, int Position, string Content);
delegate void ErrorSink(int position, string reason, string? text);

sealed class Station
{
    public string Code = "", Name = "";
    public long Elevation;
    public List<Runway> Runways = new();
}

sealed class Value
{
    public string Raw = "", Kind = "", Unit = "", Qualifier = "", Qualifier2 = "", Runway = "", Trend = "";
    public string Amount = "", Suffix = "", Intensity = "", Descriptor = "";
    public long Direction, Speed, First, Second, Whole, Num, Meters, Height, Temp, Dew, Number, Inches, Hecto;
    public long Gust = -1, Den = 1;
    public bool Variable, Calm, Mixed, Fractional, Nsw, HasSecond;
    public List<string> Codes = new();
}

sealed class Section
{
    public string Context = "", Category = "";
    public Value? Modifier, Wind, Variation, Visibility, Temperature, Pressure;
    public List<Value> Rvr = new();
    public List<Value>? Weather, Cloud;
    public bool NoTrend;
    public long Ceiling = -1;
}

sealed class Change
{
    public string Kind = "";
    public long Time, Start, End;
    public List<Group> Groups = new();
    public List<TrendTime> Times = new();
    public Section? State;
}

sealed class Hour
{
    public Section Prevailing = new();
    public List<Temporary> Temporary = new();
}

sealed class Report
{
    public int Number, BodyStart;
    public string Kind = "", Modifier = "";
    public Station Station = new();
    public long Time, IssueDay, Start, End;
    public Section? Main, Base;
    public List<Change> Trends = new(), Changes = new();
    public SortedDictionary<long, Hour> Timeline = new();
    public List<long> Slp = new();
    public List<Value> Precise = new();
    public List<string> SpeciReasons = new();
    public long? PressureAltitude, DensityAltitude;
    public List<RunwayWind>? Winds;
    public string Preferred = "none";
}

static class Program
{
    private static string[] ReadLines(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII);

    private static ErrorSink Recorder(List<ParseError> errors, int number) => (position, reason, text) =>
        errors.Add(new ParseError(number, position, reason + (text == null ? "" : $" \"{text}\"")));

    private static Report? Header(List<string> words, int number, Dictionary<string, Station> stations, Calendar calendar, ErrorSink error)
    {
        string kind = words[0];
        if (kind is not ("METAR" or "SPECI" or "TAF"))
        {
            error(1, "rejected report, invalid type", kind);
            return null;
        }
        var r = new Report { Number = number, Kind = kind };
        int i = 1;
        if (kind == "TAF" && i < words.Count && words[i] is "AMD" or "COR") r.Modifier = words[i++];
        string[] items = kind == "TAF" ? new[] { "station", "time", "validity" } : new[] { "station", "time" };
        foreach (string item in items)
        {
            if (i == words.Count)
            {
                error(i + 1, "rejected report, missing " + item, null);
                return null;
            }
            string word = words[i];
            bool ok = false;
            switch (item)
            {
                case "station":
                    ok = stations.TryGetValue(word, out var station);
                    if (ok) r.Station = station!;
                    break;
                case "time":
                    r.Time = calendar.Observation(word);
                    ok = r.Time >= 0;
                    r.IssueDay = r.Time / 1440 + 1;
                    break;
                case "validity":
                    var period = calendar.Period(word, r.IssueDay, 1800);
                    ok = period != null;
                    if (ok) { r.Start = period!.Value.Start; r.End = period.Value.End; }
                    break;
            }
            if (!ok)
            {
                error(i + 1, "rejected report, invalid " + item, word);
                return null;
            }
            i++;
        }
        r.BodyStart = i;
        return r;
    }

    private static List<Group> JoinGroups(List<string> words, int start)
    {
        var result = new List<Group>();
        for (int i = start; i < words.Count; i++)
        {
            int position = i + 1;
            string text = words[i];
            if (Groups.Match(@"\d", text) != null && i + 1 < words.Count && Groups.Match(@"\d/\d{1,2}SM", words[i + 1]) != null)
                text += " " + words[++i];
            result.Add(new Group(text, position));
        }
        return result;
    }

    private static Section MatchSection(List<Group> body, List<Slot> slots, string context, Station station, ErrorSink error)
    {
        var s = new Section { Context = context };
        int current = 0;
        foreach (var g in body)
        {
            int found = current;
            Value? value = null;
            while (found < slots.Count)
            {
                value = Metar.Test(slots[found], g.Text);
                if (value != null) break;
                found++;
            }
            if (found == slots.Count)
            {
                string reason = "unknown group";
                for (int i = 0; i < current; i++)
                    if (Metar.Test(slots[i], g.Text) != null) { reason = "out of order group"; break; }
                error(g.Position, reason, g.Text);
                continue;
            }
            var slot = slots[found];
            if (!Groups.Valid(slot.Kind, value!, s, station))
            {
                error(g.Position, "invalid group", g.Text);
                continue;
            }
            Groups.Accept(s, slot.Kind, value!);
            current = found + (slot.Repeat ? 0 : 1);
            if (slot.Kind == "visibility" && value!.Kind == "cavok") current = slots.FindIndex(x => x.Kind == "cloud") + 1;
        }
        return s;
    }

    public static void Derive(Section s)
    {
        s.Ceiling = s.Cloud?.FirstOrDefault(c => c.Amount is "BKN" or "OVC" or "VV")?.Height ?? -1;
        var v = s.Visibility == null ? ((long Numerator, long Denominator)?)null : Units.Miles(s.Visibility);
        long c = s.Ceiling;
        if (c >= 0 && c < 500 || v != null && v.Value.Numerator < v.Value.Denominator) s.Category = "LIFR";
        else if (c >= 0 && c < 1000 || v != null && v.Value.Numerator < 3 * v.Value.Denominator) s.Category = "IFR";
        else if (c >= 0 && c <= 3000 || v != null && v.Value.Numerator <= 5 * v.Value.Denominator) s.Category = "MVFR";
        else s.Category = "VFR";
    }

    private static Component Components(long direction, long heading, long speed)
    {
        long angle = direction - heading;
        return new Component(Units.FloorDiv(speed * Units.Cos(angle), 1000), Units.FloorDiv(speed * Units.Sin(angle), 1000));
    }

    private static void RunwayWinds(Report r, long crosswind, long tailwind)
    {
        var wind = r.Main!.Wind;
        if (wind == null || wind.Variable || wind.Calm) return;
        r.Winds = new();
        long best = long.MinValue;
        foreach (var runway in r.Station.Runways)
        {
            var mean = Components(wind.Direction, runway.Heading, wind.Speed);
            var gust = wind.Gust < 0 ? null : Components(wind.Direction, runway.Heading, wind.Gust);
            var deciding = gust ?? mean;
            bool usable = Math.Abs(deciding.Cross) <= crosswind && -deciding.Head <= tailwind;
            r.Winds.Add(new RunwayWind(runway.Name, mean, gust, usable));
            if (usable && mean.Head > best) { best = mean.Head; r.Preferred = runway.Name; }
        }
    }

    private static List<string> WindChanges(Value? a, Value? b, long alpha)
    {
        var reasons = new List<string>();
        if (a == null || b == null) return reasons;
        if (!a.Variable && !a.Calm && !b.Variable && !b.Calm && Math.Max(a.Speed, b.Speed) >= 10)
        {
            long d = Math.Abs(a.Direction - b.Direction) % 360;
            if (Math.Min(d, 360 - d) >= alpha) reasons.Add("wind shift");
        }
        if (Math.Abs(a.Speed - b.Speed) >= 10) reasons.Add("wind speed");
        return reasons;
    }

    private static bool WeatherFlag(Section s, bool freezing) => s.Weather?.Any(w => freezing
        ? w.Descriptor == "FZ" && (w.Codes.Contains("DZ") || w.Codes.Contains("RA"))
        : w.Descriptor == "TS") ?? false;

    private static List<string> SpeciCheck(Report? previous, Report r)
    {
        if (previous == null) return new() { "no previous report" };
        var a = previous.Main!;
        var b = r.Main!;
        var reasons = new List<string>();
        if (a.Category != b.Category) reasons.Add($"category {a.Category} to {b.Category}");
        reasons.AddRange(WindChanges(a.Wind, b.Wind, 45));
        foreach (bool freezing in new[] { false, true })
            if (WeatherFlag(a, freezing) != WeatherFlag(b, freezing))
                reasons.Add((freezing ? "freezing precipitation" : "thunderstorm") + " " + (WeatherFlag(b, freezing) ? "began" : "ended"));
        return reasons.Count == 0 ? new() { "no criteria met" } : reasons;
    }

    private static void DecodeObservation(Report r, List<Group> body, long crosswind, long tailwind, ErrorSink error)
    {
        var parts = Metar.Split(body);
        r.Main = MatchSection(parts.Main, Metar.MainSlots, "main", r.Station, error);
        Derive(r.Main);
        r.Trends = Metar.Trends(parts.Trends, error);
        foreach (var trend in r.Trends) trend.State = MatchSection(trend.Groups, Taf.Slots, "trend", r.Station, error);
        Metar.Remarks(r, parts.Remarks);
        if (r.Main.Pressure != null)
        {
            long a = r.Station.Elevation + (2992 - r.Main.Pressure.Inches) * 10;
            r.PressureAltitude = a;
            if (r.Main.Temperature != null)
                r.DensityAltitude = a + Units.FloorDiv(120 * (1000 * r.Main.Temperature.Temp - 15000 + 2 * a), 1000);
        }
        RunwayWinds(r, crosswind, tailwind);
    }

    private static void DecodeForecast(Report r, List<Group> body, Calendar calendar, ErrorSink error)
    {
        var parts = Taf.Split(body, r, calendar, error);
        r.Base = MatchSection(parts.Base, Taf.Slots, "base", r.Station, error);
        r.Changes = parts.Changes;
        foreach (var change in r.Changes) change.State = MatchSection(change.Groups, Taf.Slots, "change", r.Station, error);
        Taf.Expand(r);
    }

    private static string WindPhrase(Value w)
    {
        if (w.Calm) return "calm";
        return (w.Variable ? "variable" : Units.Pad(w.Direction, 3) + " degrees") + $" at {w.Speed} KT" +
            (w.Gust < 0 ? "" : $" gusting {w.Gust} KT");
    }

    private static string WindCode(Value w) => w.Calm ? "00000KT" :
        (w.Variable ? "VRB" : Units.Pad(w.Direction, 3)) + Units.Pad(w.Speed, 2) +
        (w.Gust < 0 ? "" : "G" + Units.Pad(w.Gust, 2)) + "KT";

    private static string MileNumber(Value v) => !v.Fractional ? v.Whole.ToString() :
        (v.Whole == 0 ? "" : v.Whole + " ") + $"{v.Num}/{v.Den}";

    private static string Qualifier(string q) => q switch { "M" => "less than ", "P" => "more than ", _ => "" };

    private static string VisibilityPhrase(Value v) => v.Kind switch
    {
        "cavok" => "10 km or more (CAVOK)",
        "meter" => v.Qualifier == "P" ? "10 km or more" : $"{v.Meters} m",
        _ => Qualifier(v.Qualifier) + MileNumber(v) + " SM"
    };

    private static string VisibilityCode(Value v) => v.Kind == "mile" ? v.Qualifier + MileNumber(v) + "SM" : v.Raw;

    private static string WeatherPhrase(Value w)
    {
        if (w.Nsw) return "no significant weather";
        var parts = new List<string>();
        if (w.Intensity != "") parts.Add(Groups.Intensities[w.Intensity]);
        if (w.Descriptor != "") parts.Add(Groups.Descriptors[w.Descriptor]);
        if (w.Codes.Count > 0) parts.Add(string.Join(" and ", w.Codes.Select(c => Groups.Phenomena[c])));
        return string.Join(" ", parts);
    }

    private static string CloudPhrase(Value c)
    {
        if (Groups.Clear.TryGetValue(c.Amount, out string? phrase)) return phrase;
        if (c.Amount == "VV") return $"vertical visibility {c.Height} ft";
        return $"{Groups.Amounts[c.Amount]} at {c.Height} ft" +
            (c.Suffix == "" ? "" : c.Suffix == "CB" ? " cumulonimbus" : " towering cumulus");
    }

    private static string Summary(Section s)
    {
        var parts = new List<string>();
        if (s.Wind != null) parts.Add("wind " + WindPhrase(s.Wind));
        if (s.Visibility != null) parts.Add("visibility " + VisibilityPhrase(s.Visibility));
        if (s.Weather?.Count > 0) parts.Add("weather " + string.Join(", ", s.Weather.Select(WeatherPhrase)));
        if (s.Cloud?.Count > 0) parts.Add("cloud " + string.Join(", ", s.Cloud.Select(CloudPhrase)));
        return parts.Count == 0 ? "no conditions" : string.Join("; ", parts);
    }

    private static string Tokens(Section s)
    {
        var parts = new List<string>();
        if (s.Wind != null) parts.Add(WindCode(s.Wind));
        if (s.Visibility != null) parts.Add(VisibilityCode(s.Visibility));
        if (s.Weather != null) parts.AddRange(s.Weather.Where(w => !w.Nsw).Select(w => w.Raw));
        if (s.Cloud != null) parts.AddRange(s.Cloud.Select(c => c.Raw));
        parts.Add(s.Category);
        return string.Join(" ", parts);
    }

    private static string Tenth(long v) => (v < 0 ? "-" : "") + $"{Math.Abs(v) / 10}.{Math.Abs(v) % 10}";

    private static string PressurePhrase(Value p)
    {
        string a = $"{p.Inches / 100}.{Units.Pad(p.Inches % 100, 2)} inHg", q = $"{p.Hecto} hPa";
        return p.Unit == "A" ? $"{a} ({q})" : $"{q} ({a})";
    }

    private static string RvrPhrase(Value v)
    {
        string a = Qualifier(v.Qualifier) + v.First;
        if (v.HasSecond) a = "between " + a + " and " + Qualifier(v.Qualifier2) + v.Second;
        string trend = v.Trend switch { "U" => ", rising", "D" => ", falling", "N" => ", no change", _ => "" };
        return $"runway {v.Runway} {a} {v.Unit}{trend}";
    }

    private static string ComponentPhrase(Component c)
    {
        string phrase = c.Head < 0 ? $"tailwind {-c.Head} KT" : $"headwind {c.Head} KT";
        return phrase + (c.Cross == 0 ? ", crosswind 0 KT" : $", crosswind {Math.Abs(c.Cross)} KT from " + (c.Cross > 0 ? "right" : "left"));
    }

    private static string Altitude(long? a) => a == null ? "not available" : $"{a} ft";

    private static List<string> ObservationLines(Report r, Calendar calendar)
    {
        var s = r.Main!;
        var lines = new List<string> { "time: " + calendar.Stamp(r.Time) };
        if (s.Modifier != null) lines.Add("modifier: " + (s.Modifier.Raw == "AUTO" ? "automated" : "corrected"));
        string wind = s.Wind == null ? "not reported" : WindPhrase(s.Wind);
        if (s.Variation != null) wind += $", varying between {Units.Pad(s.Variation.First, 3)} and {Units.Pad(s.Variation.Second, 3)} degrees";
        lines.Add("wind: " + wind);
        lines.Add("visibility: " + (s.Visibility == null ? "not reported" : VisibilityPhrase(s.Visibility)));
        foreach (var v in s.Rvr) lines.Add("runway visual range: " + RvrPhrase(v));
        if (s.Weather != null) foreach (var w in s.Weather) lines.Add("weather: " + WeatherPhrase(w));
        if (s.Visibility?.Kind == "cavok") lines.Add("cloud: no significant cloud");
        else if (s.Cloud == null) lines.Add("cloud: not reported");
        else foreach (var cloud in s.Cloud) lines.Add("cloud: " + CloudPhrase(cloud));
        var t = s.Temperature;
        lines.Add("temperature: " + (t == null ? "not reported" : $"{t.Temp} C, dew point {t.Dew} C, spread {t.Temp - t.Dew} C"));
        lines.Add("altimeter: " + (s.Pressure == null ? "not reported" : PressurePhrase(s.Pressure)));
        if (s.NoTrend) lines.Add("trend: no significant change");
        foreach (var trend in r.Trends)
        {
            string phrase = trend.Kind == "BECMG" ? "becoming" : "temporarily";
            foreach (var time in trend.Times)
            {
                string label = time.Kind switch { "FM" => "from", "TL" => "until", _ => "at" };
                phrase += $" {label} {Units.Pad(time.Hour, 2)}:{Units.Pad(time.Minute, 2)}Z";
            }
            lines.Add($"trend: {phrase}: {Summary(trend.State!)}");
        }
        foreach (long p in r.Slp) lines.Add($"sea level pressure: {Tenth(p)} hPa");
        foreach (var p in r.Precise) lines.Add($"precise temperature: {Tenth(p.Temp)} C, dew point {Tenth(p.Dew)} C");
        lines.Add("ceiling: " + (s.Ceiling < 0 ? "none" : $"{s.Ceiling} ft"));
        lines.Add("flight category: " + s.Category);
        lines.Add("pressure altitude: " + Altitude(r.PressureAltitude));
        lines.Add("density altitude: " + Altitude(r.DensityAltitude));
        if (r.Winds == null) lines.Add("runway wind: not computed");
        else
        {
            var usable = new List<string>();
            foreach (var rw in r.Winds)
            {
                lines.Add($"runway {rw.Name}: {ComponentPhrase(rw.Mean)}" + (rw.Gust == null ? "" : "; gusts " + ComponentPhrase(rw.Gust)));
                if (rw.Usable) usable.Add(rw.Name);
            }
            lines.Add("usable runways: " + (usable.Count == 0 ? "none" : string.Join(" ", usable)));
            lines.Add("preferred runway: " + r.Preferred);
        }
        if (r.Kind == "SPECI") lines.Add("speci check: " + string.Join(", ", r.SpeciReasons));
        return lines;
    }

    private static List<string> ForecastLines(Report r, Calendar c)
    {
        var lines = new List<string> { "issued: " + c.Stamp(r.Time) };
        if (r.Modifier != "") lines.Add("modifier: " + (r.Modifier == "AMD" ? "amended" : "corrected"));
        lines.Add($"valid: {c.Stamp(r.Start)} to {c.Stamp(r.End)}");
        lines.Add("base: " + Summary(r.Base!));
        foreach (var change in r.Changes)
        {
            string period = change.Kind == "FM" ? c.Stamp(change.Time) : $"{c.Stamp(change.Start)} to {c.Stamp(change.End)}";
            lines.Add($"{change.Kind} {period}: {Summary(change.State!)}");
        }
        return lines;
    }

    private static string DecodedBlock(Report r, Calendar c)
    {
        var lines = new List<string> { $"REPORT {r.Number}: {r.Kind} {r.Station.Code} ({r.Station.Name})" };
        lines.AddRange((r.Kind == "TAF" ? ForecastLines(r, c) : ObservationLines(r, c)).Select(line => "  " + line));
        return string.Join("\n", lines);
    }

    private static string Counts(long[] counts) => string.Join(", ", Verification.Categories.Select((category, i) => $"{category} {counts[i]}"));

    private static string TimelineBlock(Report r, Calendar c)
    {
        var lines = new List<string> { $"TAF {r.Station.Code} issued {c.Stamp(r.Time)} valid {c.Stamp(r.Start)} to {c.Stamp(r.End)}" };
        var counts = new long[4];
        foreach (var (time, hour) in r.Timeline)
        {
            string line = c.Stamp(time) + " " + Tokens(hour.Prevailing);
            counts[Array.IndexOf(Verification.Categories, hour.Prevailing.Category)]++;
            foreach (var t in hour.Temporary) line += $" | {t.Kind} {Tokens(t.State)}";
            lines.Add(line);
        }
        lines.Add("summary: " + Counts(counts));
        return string.Join("\n", lines);
    }

    private static string CategoryLine(Report r, Calendar c)
    {
        var s = r.Main!;
        return string.Join(",", r.Station.Code, c.Stamp(r.Time), s.Ceiling < 0 ? "NONE" : s.Ceiling.ToString(),
            s.Visibility == null ? "NONE" : s.Visibility.Qualifier + Units.Meters(s.Visibility), s.Category);
    }

    private static long Strength(Value w) => w.Gust < 0 ? w.Speed : w.Gust;

    private static List<string> ExtremeLines(List<Report> observations, Calendar c)
    {
        var selected = new Report?[5];
        foreach (var o in observations)
        {
            var s = o.Main!;
            if (s.Temperature != null)
            {
                if (selected[0] == null || s.Temperature.Temp < selected[0]!.Main!.Temperature!.Temp) selected[0] = o;
                if (selected[1] == null || s.Temperature.Temp > selected[1]!.Main!.Temperature!.Temp) selected[1] = o;
            }
            if (s.Wind != null && (selected[2] == null || Strength(s.Wind) > Strength(selected[2]!.Main!.Wind!))) selected[2] = o;
            if (s.Ceiling >= 0 && (selected[3] == null || s.Ceiling < selected[3]!.Main!.Ceiling)) selected[3] = o;
            if (s.Visibility != null && (selected[4] == null || Units.CompareVisibility(s.Visibility, selected[4]!.Main!.Visibility!) < 0)) selected[4] = o;
        }
        string[] labels = { "lowest temperature", "highest temperature", "strongest wind", "lowest ceiling", "lowest visibility" };
        var lines = new List<string>();
        for (int i = 0; i < 5; i++)
        {
            var o = selected[i];
            string value = "not available";
            if (o != null)
            {
                var s = o.Main!;
                value = i switch
                {
                    0 or 1 => $"{s.Temperature!.Temp} C",
                    2 => WindPhrase(s.Wind!),
                    3 => $"{s.Ceiling} ft",
                    _ => VisibilityPhrase(s.Visibility!)
                };
                value += " at " + c.Stamp(o.Time);
            }
            lines.Add(labels[i] + ": " + value);
        }
        return lines;
    }

    private static string TableRow(string label, IEnumerable<string> values) => label.PadRight(8) + string.Concat(values.Select(v => v.PadLeft(6)));

    private static string VerificationBlock(Station station, List<Report> observations, List<Report> tafs, Calendar c)
    {
        var a = Verification.Analyze(observations, tafs);
        long metars = observations.Count(o => o.Kind == "METAR");
        var counts = new long[4];
        foreach (var o in observations) counts[Array.IndexOf(Verification.Categories, o.Main!.Category)]++;
        var lines = new List<string>
        {
            $"station {station.Code} ({station.Name})",
            $"reports: METAR {metars}, SPECI {observations.Count - metars}",
            "observed categories: " + Counts(counts)
        };
        lines.AddRange(ExtremeLines(observations, c));
        lines.Add("verified: " + a.Total);
        lines.Add("no forecast: " + a.NoForecast);
        lines.Add(TableRow("forecast", Verification.Categories.Append("total")));
        for (int i = 0; i < 4; i++)
        {
            var values = new List<string>();
            for (int j = 0; j < 4; j++) values.Add(a.Table[i, j].ToString());
            values.Add(a.Rows[i].ToString());
            lines.Add(TableRow(Verification.Categories[i], values));
        }
        lines.Add(TableRow("total", a.Columns.Select(n => n.ToString()).Append(a.Total.ToString())));
        lines.Add("hit rate: " + a.HitRate);
        lines.Add("hit rate with temporary groups: " + a.TemporaryRate);
        lines.Add("heidke skill score: " + a.Skill);
        for (int i = 0; i < 4; i++) lines.Add($"{Verification.Categories[i]}: pod {a.Pod(i)}, far {a.Far(i)}");
        for (int i = 0; i < 5; i++) lines.Add($"hours {i * 6}-{i * 6 + 5}: {Units.Fraction(a.Buckets[i, 0], a.Buckets[i, 1])}");
        foreach (var choice in a.Choices)
        {
            var observed = choice.Observation.Main!;
            var forecast = choice.Forecast.Prevailing;
            var reasons = new List<string>();
            if (!choice.TemporaryHit) reasons.Add($"category {observed.Category}, forecast {forecast.Category}");
            if (WindChanges(forecast.Wind, observed.Wind, 60).Count > 0) reasons.Add($"wind {WindCode(observed.Wind!)}, forecast {WindCode(forecast.Wind!)}");
            if (reasons.Count > 0) lines.Add($"amendment {c.Stamp(choice.Observation.Time)}: {string.Join("; ", reasons)}");
        }
        return string.Join("\n", lines);
    }

    private static string Text(List<string> lines, string separator) => lines.Count == 0 ? "" : string.Join(separator, lines) + "\n";

    public static void Main()
    {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var stations = new Dictionary<string, Station>();
        foreach (string line in ReadLines("stations.txt"))
        {
            string[] p = line.Split(' ', 4);
            var s = new Station { Code = p[0], Elevation = Groups.Number(p[1]), Name = p[3] };
            foreach (string entry in p[2].Split(','))
            {
                string[] r = entry.Split('/');
                s.Runways.Add(new Runway(r[0], Groups.Number(r[1])));
            }
            stations[s.Code] = s;
        }
        var settings = new Dictionary<string, string[]>();
        foreach (string line in ReadLines("params.txt"))
        {
            string[] p = line.Split(' ');
            settings[p[0]] = p[1..];
        }
        var c = new Calendar(Groups.Number(settings["YEAR"][0]), Groups.Number(settings["MONTH"][0]));
        long crosswind = Groups.Number(settings["CROSSWIND_LIMIT"][0]), tailwind = Groups.Number(settings["TAILWIND_LIMIT"][0]);
        var raw = new List<List<string>>();
        foreach (string line in ReadLines("reports.txt"))
        {
            string[] words = line.TrimStart(' ').Split(' ');
            if (line.StartsWith(' ')) raw[^1].AddRange(words);
            else raw.Add(words.ToList());
        }
        var reports = new List<Report>();
        var observations = new List<Report>();
        var tafs = new List<Report>();
        var errors = new List<ParseError>();
        var previous = new Dictionary<string, Report>();
        for (int i = 0; i < raw.Count; i++)
        {
            var error = Recorder(errors, i + 1);
            var r = Header(raw[i], i + 1, stations, c, error);
            if (r == null) continue;
            var body = JoinGroups(raw[i], r.BodyStart);
            if (r.Kind == "TAF") { DecodeForecast(r, body, c, error); tafs.Add(r); }
            else
            {
                DecodeObservation(r, body, crosswind, tailwind, error);
                if (r.Kind == "SPECI") r.SpeciReasons = SpeciCheck(previous.GetValueOrDefault(r.Station.Code), r);
                previous[r.Station.Code] = r;
                observations.Add(r);
            }
            reports.Add(r);
        }
        var decoded = reports.Select(r => DecodedBlock(r, c)).ToList();
        var csv = new List<string> { "station,time,ceiling,visibility,category" };
        csv.AddRange(observations.Select(r => CategoryLine(r, c)));
        var timelines = tafs.Select(r => TimelineBlock(r, c)).ToList();
        var verified = settings["VERIFY"].Select(code => VerificationBlock(stations[code],
            observations.Where(r => r.Station.Code == code).ToList(), tafs.Where(r => r.Station.Code == code).ToList(), c)).ToList();
        var errorLines = errors.OrderBy(e => e.Report).ThenBy(e => e.Position)
            .Select(e => $"report {e.Report} word {e.Position}: {e.Content}").ToList();
        var outputs = new Dictionary<string, string>
        {
            ["decoded.txt"] = Text(decoded, "\n\n"),
            ["categories.csv"] = Text(csv, "\n"),
            ["taf_timeline.txt"] = Text(timelines, "\n\n"),
            ["verification.txt"] = Text(verified, "\n\n"),
            ["errors.txt"] = Text(errorLines, "\n")
        };
        Directory.CreateDirectory("output");
        foreach (var (name, text) in outputs) File.WriteAllText(Path.Combine("output", name), text, Encoding.ASCII);
    }
}
