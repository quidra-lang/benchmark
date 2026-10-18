using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

static class CollectionExtensions {
    public static bool IsEmpty<T>(this ICollection<T> items) => items.Count == 0;
    public static bool IsEmpty(this string text) => text.Length == 0;
    public static bool MatchesAt(this string text, string prefix, int position) =>
        text.AsSpan(position).StartsWith(prefix.AsSpan(),StringComparison.Ordinal);
}
class Program {
    record Cue(long Index, long Start, long End, List<string> Text) {
        public long Duration() => End-Start;
        public long Chars() => Text.Sum(t => (long)t.Length);
        public bool Dialogue() => Text.Any(t => t.StartsWith("- ",StringComparison.Ordinal));
    }
    record Undo(string Command, List<Cue> Cues);
    record Item(string Text, int Kind, int Digit);
    class Problem : Exception {
        public Problem(string message) : base(message) {}
    }
    List<Cue> cues = new();
    readonly Stack<Undo> history = new();
    static readonly Dictionary<string,string> Schemas = new(StringComparer.Ordinal) {
        ["LIST"] = "",
        ["VALIDATE"] = "",
        ["SEARCH"] = "X",
        ["AT"] = "T",
        ["GAPS"] = "g",
        ["STATS"] = "",
        ["PRINT"] = "",
        ["TOVTT"] = "",
        ["TOASS"] = "",
        ["FRAMES"] = "F",
        ["SHIFT"] = "I",
        ["SHIFTFROM"] = "PI",
        ["SCALE"] = "rr",
        ["SYNC"] = "PTPT",
        ["SNAP"] = "F",
        ["FIXOVERLAP"] = "g",
        ["EXTEND"] = "e",
        ["TIME"] = "PTT",
        ["SORT"] = "",
        ["RENUMBER"] = "",
        ["MERGE"] = "g",
        ["SPLIT"] = "w",
        ["INSERT"] = "PTTX",
        ["DELETE"] = "P",
        ["TEXT"] = "PX",
        ["BALANCE"] = "",
        ["STRIP"] = "",
        ["CLEANHI"] = "",
        ["REPLACE"] = "X",
        ["UNDO"] = "",
    };
    static readonly HashSet<string> Modify = new(StringComparer.Ordinal) {
        "SHIFT","SHIFTFROM","SCALE","SYNC","SNAP","FIXOVERLAP","EXTEND","TIME","SORT",
        "RENUMBER","MERGE","SPLIT","INSERT","DELETE","TEXT","BALANCE","STRIP","CLEANHI","REPLACE"
    };
    static long Floor(long a, long b) {
        long q = a/b;
        return a%b < 0 ? q-1 : q;
    }
    static void Bad() { throw new Problem("bad arguments"); }
    static long Number(string s) {
        if (!Regex.IsMatch(s,@"\A[0-9]{1,9}\z")) Bad();
        return long.Parse(s);
    }
    static long Time(string s) {
        if (!Regex.IsMatch(s,@"\A[0-9]{2}:[0-5][0-9]:[0-5][0-9],[0-9]{3}\z")) Bad();
        return long.Parse(s.Substring(0,2))*3600000+long.Parse(s.Substring(3,2))*60000+
            long.Parse(s.Substring(6,2))*1000+long.Parse(s.Substring(9));
    }
    static long[] Fps(string s) {
        string[] pieces = s.Split('/');
        if (pieces.Length > 2) Bad();
        long a = Number(pieces[0]), b = pieces.Length == 2 ? Number(pieces[1]) : 1;
        if (a < 1 || a > 100000 || b < 1 || b > 100000) Bad();
        return new long[]{a,b};
    }
    static List<string> Text(string s) {
        List<string> lines = s.Split('|').ToList();
        if (lines.Any(x => x.Length == 0)) Bad();
        return lines;
    }
    static string Pad(long n, int width) {
        string s = Convert.ToString(n);
        return new string('0',Math.Max(0,width-s.Length))+s;
    }
    static string Srt(long t) {
        return Pad(t/3600000,2)+":"+Pad(t/60000%60,2)+":"+Pad(t/1000%60,2)+","+Pad(t%1000,3);
    }
    static string Ass(long t) {
        long c = (t+5)/10;
        return c/360000+":"+Pad(c/6000%60,2)+":"+Pad(c/100%60,2)+"."+Pad(c%100,2);
    }
    static string Decimal(long v) { return v/100+"."+Pad(v%100,2); }
    static long Round(long a, long b) {
        if (b < 0) {
            a = -a;
            b = -b;
        }
        return Floor(2*a+b,2*b);
    }
    static List<string> Words(List<string> lines) {
        return string.Join(" ",lines).Split(' ',StringSplitOptions.RemoveEmptyEntries).ToList();
    }
    static List<string> Wrap(List<string> lines, long width) {
        List<string> result = new();
        foreach (string word in Words(lines)) {
            if (result.IsEmpty() || result.Last().Length+1+word.Length > width) {
                result.Add(word);
            } else {
                result[result.Count-1] = result.Last()+" "+word;
            }
        }
        return result;
    }
    static string Normalize(string s) { return string.Join(" ",Words(new List<string> {s})); }
    static List<Item> Markup(string line) {
        List<Item> result = new();
        int p = 0;
        while (p < line.Length) {
            string token = null;
            int kind = 0, digit = 0;
            foreach (string tag in new List<string> {"<i>","</i>","<b>","</b>","<u>","</u>"}) {
                if (line.MatchesAt(tag,p)) {
                    token = tag;
                    kind = 1;
                    break;
                }
            }
            if (token == null && line.MatchesAt("</font>",p)) {
                token = "</font>";
                kind = 2;
            }
            if (token == null && line.MatchesAt("<font",p) && p+5 < line.Length &&
                (line[p+5] == ' ' || line[p+5] == '>')) {
                int end = line.IndexOf('>',p+5);
                if (end >= 0) {
                    token = line.Substring(p,end+1-p);
                    kind = 2;
                }
            }
            if (token == null && p+6 <= line.Length && line.MatchesAt("{\\an",p) &&
                line[p+4] >= '1' && line[p+4] <= '9' && line[p+5] == '}') {
                token = line.Substring(p,6);
                kind = 3;
                digit = line[p+4]-'0';
            }
            if (token == null) token = line.Substring(p,1);
            result.Add(new Item(token,kind,digit));
            p += token.Length;
        }
        return result;
    }
    static string Listing(int p, Cue c) {
        return p+" "+c.Index+" "+Srt(c.Start)+" "+Srt(c.End)+" "+string.Join("|",c.Text);
    }
    void Load(List<List<string>> blocks, List<string> output) {
        int bad = 0;
        for (int i = 0; i < blocks.Count; i++) {
            List<string> block = blocks[i];
            string reason = "";
            long start = 0, end = 0;
            if (!Regex.IsMatch(block.First(),@"\A[0-9]{1,6}\z")) reason = "index";
            else {
                try {
                    if (block.Count < 2 || block[1].Length != 29 || !block[1].Substring(12,5).Equals(" --> ")) Bad();
                    start = Time(block[1].Substring(0,12));
                    end = Time(block[1].Substring(17));
                } catch (Problem) {
                    reason = "time";
                }
                if (reason.IsEmpty() && block.Count < 3) reason = "no text";
            }
            if (!reason.IsEmpty()) {
                output.Add("BAD CUE "+(i+1)+": "+reason);
                bad++;
            } else {
                cues.Add(new Cue(long.Parse(block.First()),start,end,block.Skip(2).ToList()));
            }
        }
        output.Add("LOAD cues="+cues.Count+" bad="+bad);
    }
    List<string> Execute(string line) {
        string command = line.Split(new[]{' '},2,StringSplitOptions.None)[0];
        if (!Schemas.ContainsKey(command)) throw new Problem("unknown command");
        string schema = Schemas[command];
        if (command.Equals("DELETE") && line.Split(' ').Length == 3) schema = "PP";
        string[] tokens = schema.EndsWith("X",StringComparison.Ordinal) ?
            line.Split(new[]{' '},schema.Length+1,StringSplitOptions.None) : line.Split(' ');
        if (tokens.Length != schema.Length+1) Bad();
        string[] args = tokens.Skip(1).ToArray();
        long[] values = new long[args.Length];
        for (int i = 0; i < args.Length; i++) {
            char type = schema[i];
            if (type == 'T') values[i] = Time(args[i]);
            else if (type == 'F') Fps(args[i]);
            else if (type == 'X') {
                if (command.Equals("INSERT") || command.Equals("TEXT")) Text(args[i]);
                if (command.Equals("REPLACE")) {
                    string[] parts = args[i].Split('|');
                    if (parts.Length != 2 || parts[0].IsEmpty() || parts[1].IsEmpty()) Bad();
                }
            } else {
                string raw = args[i];
                bool negative = type == 'I' && raw.StartsWith("-");
                values[i] = Number(negative ? raw.Substring(1) : raw)*(negative ? -1 : 1);
                if (type == 'P' && values[i] < 1 || type == 'r' && (values[i] < 1 || values[i] > 100000) ||
                    type == 'g' && values[i] > 60000 || type == 'e' && (values[i] < 1 || values[i] > 60000) ||
                    type == 'w' && (values[i] < 10 || values[i] > 80)) Bad();
            }
        }
        if (command.Equals("DELETE") && values.Length == 2 && values[1] < values[0]) Bad();
        for (int i = 0; i < args.Length; i++) {
            if (schema[i] == 'P' && values[i] > cues.Count+(command.Equals("INSERT") ? 1 : 0)) {
                throw new Problem("no cue "+values[i]);
            }
        }
        if (command.Equals("SYNC") && cues[(int)values[0]-1].Start == cues[(int)values[2]-1].Start) {
            throw new Problem("sync points coincide");
        }
        if (command.Equals("UNDO")) {
            if (history.Count == 0) throw new Problem("nothing to undo");
            Undo undo = history.Pop();
            cues = undo.Cues;
            return new List<string> {"UNDO command="+undo.Command};
        }
        if (Modify.Contains(command)) history.Push(new Undo(command,new List<Cue>(cues)));
        List<string> output = new();
        int n = cues.Count;
        long v = values.Length == 0 ? 0 : values[0];
        switch (command) {
            case "LIST":
            case "AT":
            case "SEARCH":
            case "GAPS": {
                int count = 0;
                for (int i = 0; i < n; i++) {
                    Cue cue = cues[i];
                    if (command.Equals("LIST") || command.Equals("AT") && cue.Start <= v && v < cue.End) {
                        output.Add(Listing(i+1,cue));
                        count++;
                    }
                    if (command.Equals("SEARCH")) {
                        foreach (string t in cue.Text) {
                            if (t.Contains(args[0])) {
                                output.Add((i+1)+" "+Srt(cue.Start)+" "+t);
                                count++;
                                break;
                            }
                        }
                    }
                    if (command.Equals("GAPS") && i+1 < n && cues[i+1].Start-cue.End < v) {
                        output.Add((i+1)+" "+(i+2)+" "+(cues[i+1].Start-cue.End));
                        count++;
                    }
                }
                if (!command.Equals("LIST")) output.Add(command+(command == "AT" ? " active=" : command == "SEARCH" ? " found=" : " count=")+count);
                break;
            }
            case "VALIDATE": {
                for (int i = 0; i < n; i++) {
                    Cue c = cues[i];
                    long d = c.Duration();
                    string p = "cue "+(i+1)+": ";
                    if (c.Index != i+1) output.Add(p+"index "+c.Index+" (expected "+(i+1)+")");
                    if (d <= 0) output.Add(p+"end not after start");
                    if (i > 0 && c.Start < cues[i-1].End) output.Add(p+"overlaps previous by "+(cues[i-1].End-c.Start)+" ms");
                    if (d >= 1 && d < 700) output.Add(p+"too short ("+d+" ms)");
                    if (d > 7000) output.Add(p+"too long ("+d+" ms)");
                    for (int j = 0; j < c.Text.Count; j++) {
                        int size = c.Text[j].Length;
                        if (size > 42) output.Add(p+"line "+(j+1)+" too long ("+size+" chars)");
                    }
                    if (c.Text.Count >= 3) output.Add(p+"too many lines ("+c.Text.Count+")");
                    if (d >= 1 && c.Chars()*1000 > 21*d) output.Add(p+"too fast ("+Decimal(c.Chars()*100000/d)+" cps)");
                }
                output.Add("VALIDATE problems="+output.Count);
                break;
            }
            case "STATS": {
                output.Add("STATS cues="+n);
                if (n == 0) break;
                long total = 0, chars = 0, longest = -1, gap = long.MinValue;
                int position = 0, gapPosition = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues[i];
                    long d = Math.Max(0,c.Duration());
                    total += d;
                    if (d > 0) chars += c.Chars();
                    if (d > longest) {
                        longest = d;
                        position = i+1;
                    }
                    if (i+1 < n && cues[i+1].Start-c.End > gap) {
                        gap = cues[i+1].Start-c.End;
                        gapPosition = i+1;
                    }
                }
                output.Add("duration total="+Srt(total)+" mean="+Srt(total/n));
                output.Add("speed "+(total == 0 ? "-" : Decimal(chars*100000/total)));
                output.Add("longest cue="+position+" duration="+Srt(longest));
                output.Add(n == 1 ? "gap none" : "gap cue="+gapPosition+" ms="+gap);
                break;
            }
            case "PRINT":
            case "TOVTT":
            case "TOASS": {
                if (command.Equals("TOVTT")) output.AddRange(new List<string> {"WEBVTT",""});
                if (command.Equals("TOASS")) output.AddRange(new List<string> {"[Events]","Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"});
                foreach (Cue c in cues) {
                    List<string> lines = new();
                    int code = 0;
                    foreach (string t in c.Text) {
                        StringBuilder converted = new StringBuilder();
                        foreach (Item item in Markup(t)) {
                            if (code == 0 && item.Kind == 3) code = item.Digit;
                            if (command.Equals("PRINT")) converted.Append(item.Text);
                            else if (command.Equals("TOASS")) {
                                if (item.Kind == 1) {
                                    char tag = item.Text[item.Text.StartsWith("</") ? 2 : 1];
                                    converted.Append("{\\").Append(tag).Append(item.Text.StartsWith("</") ? "0}" : "1}");
                                } else if (item.Kind != 2) converted.Append(item.Text);
                            } else if (item.Kind == 1) converted.Append(item.Text);
                            else if (item.Kind == 0) converted.Append(item.Text switch {
                                "&" => "&amp;",
                                "<" => "&lt;",
                                ">" => "&gt;",
                                _ => item.Text
                            });
                        }
                        string convertedText = converted.ToString();
                        if (command.Equals("TOVTT")) convertedText = convertedText.Trim(' ');
                        if (!command.Equals("TOVTT") || !convertedText.IsEmpty()) lines.Add(convertedText);
                    }
                    if (command.Equals("TOASS")) {
                        output.Add("Dialogue: 0,"+Ass(c.Start)+","+Ass(c.End)+",Default,,0,0,0,,"+string.Join("\\N",lines));
                    } else if (!lines.IsEmpty()) {
                        string settings = "";
                        if (command.Equals("TOVTT") && code != 0) {
                            if (code >= 7) settings += " line:0";
                            else if (code >= 4) settings += " line:50%";
                            if (code%3 == 1) settings += " align:start";
                            if (code%3 == 0) settings += " align:end";
                        }
                        output.Add(Convert.ToString(c.Index));
                        string times = Srt(c.Start)+" --> "+Srt(c.End);
                        output.Add((command.Equals("TOVTT") ? times.Replace(',','.') : times)+settings);
                        output.AddRange(lines);
                        output.Add("");
                    }
                }
                break;
            }
            case "FRAMES": {
                long[] rate = Fps(args[0]);
                for (int i = 0; i < n; i++) {
                    Cue c = cues[i];
                    output.Add((i+1)+" "+c.Start*rate[0]/(1000*rate[1])+" "+c.End*rate[0]/(1000*rate[1]));
                }
                break;
            }
            case "SHIFT":
            case "SHIFTFROM":
            case "SCALE":
            case "SYNC":
            case "SNAP": {
                int first = command.Equals("SHIFTFROM") ? (int)v-1 : 0;
                long delta = command.Equals("SHIFTFROM") ? values[1] : v;
                long s1 = command.Equals("SYNC") ? cues[(int)v-1].Start : 0;
                long s2 = command.Equals("SYNC") ? cues[(int)values[2]-1].Start : 0;
                long[] rate = command.Equals("SNAP") ? Fps(args[0]) : new long[]{1,1};
                int clamped = 0, changed = 0;
                for (int i = first; i < n; i++) {
                    Cue c = cues[i];
                    long[] times = {c.Start,c.End};
                    bool clamp = false;
                    for (int j = 0; j < 2; j++) {
                        long old = times[j], next;
                        if (command.Equals("SCALE")) next = Round(old*v,values[1]);
                        else if (command.Equals("SYNC")) next = Round(values[1]*(s2-s1)+(old-s1)*(values[3]-values[1]),s2-s1);
                        else if (command.Equals("SNAP")) next = Round(Round(old*rate[0],1000*rate[1])*1000*rate[1],rate[0]);
                        else next = old+delta;
                        if (next < 0) clamp = true;
                        times[j] = Math.Max(0,next);
                        if (times[j] != old) changed++;
                    }
                    if (clamp) clamped++;
                    cues[i] = new Cue(c.Index,times[0],times[1],c.Text);
                }
                if (command.Equals("SNAP")) output.Add("SNAP changed="+changed);
                else output.Add(command+" cues="+(n-first)+(command.Equals("SCALE") ? "" : " clamped="+clamped));
                break;
            }
            case "FIXOVERLAP":
            case "EXTEND": {
                int changed = 0, failed = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues[i];
                    long end = c.End;
                    if (command.Equals("FIXOVERLAP") && i+1 < n && end > cues[i+1].Start-v) {
                        long candidate = cues[i+1].Start-v;
                        if (candidate > c.Start) {
                            end = candidate;
                            changed++;
                        } else {
                            output.Add("cue "+(i+1)+": cannot fix");
                            failed++;
                        }
                    }
                    if (command.Equals("EXTEND") && c.Duration() < v) {
                        long candidate = c.Start+v;
                        if (i+1 < n) candidate = Math.Min(candidate,cues[i+1].Start);
                        if (candidate > end) {
                            end = candidate;
                            changed++;
                        }
                    }
                    cues[i] = new Cue(c.Index,c.Start,end,c.Text);
                }
                if (command.Equals("FIXOVERLAP")) output.Add("FIXOVERLAP fixed="+changed+" failed="+failed);
                else output.Add("EXTEND extended="+changed+" short="+cues.Count(c => c.Duration() < v));
                break;
            }
            case "TIME": {
                Cue c = cues[(int)v-1];
                cues[(int)v-1] = new Cue(c.Index,values[1],values[2],c.Text);
                output.Add("TIME cue="+v);
                break;
            }
            case "SORT": {
                List<Cue> old = new List<Cue>(cues);
                cues = cues.OrderBy(c => c.Start).ThenBy(c => c.End).ToList();
                int moved = 0;
                for (int i = 0; i < n; i++) {
                    if (!ReferenceEquals(old[i],cues[i])) moved++;
                }
                output.Add("SORT moved="+moved);
                break;
            }
            case "RENUMBER": {
                int changed = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues[i];
                    if (c.Index != i+1) changed++;
                    cues[i] = new Cue(i+1,c.Start,c.End,c.Text);
                }
                output.Add("RENUMBER changed="+changed);
                break;
            }
            case "MERGE": {
                List<Cue> result = new();
                int merged = 0;
                foreach (Cue b in cues) {
                    if (!result.IsEmpty()) {
                        Cue a = result.Last();
                        List<string> both = new List<string>(a.Text);
                        both.AddRange(b.Text);
                        List<string> wrapped = Wrap(both,42);
                        if (b.Start-a.End < v && !a.Dialogue() && !b.Dialogue() && wrapped.Count <= 2) {
                            result[result.Count-1] = new Cue(a.Index,a.Start,Math.Max(a.End,b.End),wrapped);
                            merged++;
                            continue;
                        }
                    }
                    result.Add(b);
                }
                cues = result;
                output.Add("MERGE merged="+merged+" cues="+cues.Count);
                break;
            }
            case "SPLIT": {
                List<Cue> result = new();
                int split = 0;
                foreach (Cue c in cues) {
                    if (c.Duration() <= 0 || c.Dialogue()) {
                        result.Add(c);
                        continue;
                    }
                    List<string> wrapped = Wrap(c.Text,v);
                    if (wrapped.Count <= 2) {
                        result.Add(new Cue(c.Index,c.Start,c.End,wrapped));
                        continue;
                    }
                    split++;
                    List<List<string>> parts = new();
                    for (int i = 0; i < wrapped.Count; i += 2) parts.Add(wrapped.GetRange(i,Math.Min(2,wrapped.Count-i)));
                    long total = parts.Sum(part => (long)part.Sum(t => t.Length));
                    long[] durations = new long[parts.Count], remainders = new long[parts.Count];
                    List<int> order = new();
                    long allocated = 0;
                    for (int i = 0; i < parts.Count; i++) {
                        long count = parts[i].Sum(t => (long)t.Length);
                        durations[i] = c.Duration()*count/total;
                        remainders[i] = c.Duration()*count%total;
                        allocated += durations[i];
                        order.Add(i);
                    }
                    order = order.OrderByDescending(i => remainders[i]).ThenBy(i => i).ToList();
                    for (int i = 0; i < c.Duration()-allocated; i++) durations[order[i]]++;
                    long start = c.Start;
                    for (int i = 0; i < parts.Count; i++) {
                        result.Add(new Cue(c.Index,start,start+durations[i],parts[i]));
                        start += durations[i];
                    }
                }
                cues = result;
                output.Add("SPLIT split="+split+" cues="+cues.Count);
                break;
            }
            case "INSERT": {
                cues.Insert((int)v-1,new Cue(v,values[1],values[2],Text(args[3])));
                output.Add("INSERT cue="+v+" cues="+cues.Count);
                break;
            }
            case "DELETE": {
                long last = values.Length == 2 ? values[1] : v;
                cues.RemoveRange((int)v-1,(int)(last-v+1));
                output.Add("DELETE removed="+(last-v+1)+" cues="+cues.Count);
                break;
            }
            case "TEXT": {
                Cue c = cues[(int)v-1];
                List<string> lines = Text(args[1]);
                cues[(int)v-1] = new Cue(c.Index,c.Start,c.End,lines);
                output.Add("TEXT cue="+v+" lines="+lines.Count);
                break;
            }
            case "BALANCE": {
                int changed = 0, skipped = 0, dialogue = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues[i];
                    if (c.Dialogue()) {
                        dialogue++;
                        continue;
                    }
                    List<string> tokens2 = Words(c.Text);
                    string joined = string.Join(" ",tokens2);
                    List<string> best = joined.Length <= 42 ? new List<string> {joined} : null;
                    int difference = int.MaxValue, firstLength = int.MaxValue;
                    for (int j = 1; joined.Length > 42 && j < tokens2.Count; j++) {
                        string a = string.Join(" ",tokens2.Take(j)), b = string.Join(" ",tokens2.Skip(j));
                        int d = Math.Abs(a.Length-b.Length);
                        if (a.Length <= 42 && b.Length <= 42 && (d < difference || d == difference && a.Length < firstLength)) {
                            best = new List<string> {a,b};
                            difference = d;
                            firstLength = a.Length;
                        }
                    }
                    if (best == null) skipped++;
                    else if (!best.SequenceEqual(c.Text)) {
                        changed++;
                        cues[i] = new Cue(c.Index,c.Start,c.End,best);
                    }
                }
                output.Add("BALANCE changed="+changed+" skipped="+skipped+" dialogue="+dialogue);
                break;
            }
            case "STRIP":
            case "CLEANHI": {
                List<Cue> result = new();
                int tags = 0, segments = 0, labels = 0, removed = 0;
                foreach (Cue c in cues) {
                    List<string> lines = new();
                    foreach (string t in c.Text) {
                        StringBuilder builder = new StringBuilder();
                        if (command.Equals("STRIP")) {
                            foreach (Item item in Markup(t)) {
                                if (item.Kind == 0) builder.Append(item.Text);
                                else tags++;
                            }
                        } else {
                            int p = 0;
                            while (p < t.Length) {
                                char ch = t[p];
                                int end = ch == '[' || ch == '(' ? t.IndexOf(ch == '[' ? ']' : ')',p+1) : -1;
                                if (end >= 0) {
                                    segments++;
                                    p = end+1;
                                } else {
                                    builder.Append(ch);
                                    p++;
                                }
                            }
                        }
                        string cleaned = command.Equals("STRIP") ? builder.ToString().Trim(' ') : Normalize(builder.ToString());
                        if (command.Equals("CLEANHI")) {
                            string prefix = cleaned.StartsWith("- ") ? "- " : "";
                            string body = cleaned.Substring(prefix.Length);
                            int colon = body.IndexOf(':');
                            if (colon > 0 && Regex.IsMatch(body.Substring(0,colon),@"\A[A-Z][A-Z0-9 ]*\z")) {
                                labels++;
                                cleaned = Normalize(prefix+body.Substring(colon+1));
                            }
                        }
                        if (cleaned.IsEmpty() || command.Equals("CLEANHI") && cleaned.Equals("-")) removed++;
                        else lines.Add(cleaned);
                    }
                    if (!lines.IsEmpty()) result.Add(new Cue(c.Index,c.Start,c.End,lines));
                }
                int removedCues = n-result.Count;
                cues = result;
                output.Add(command.Equals("STRIP") ? "STRIP tags="+tags+" removed_lines="+removed+" removed_cues="+removedCues :
                    "CLEANHI segments="+segments+" labels="+labels+" removed_lines="+removed+" removed_cues="+removedCues);
                break;
            }
            case "REPLACE": {
                string[] parts = args[0].Split('|');
                string old = parts[0], replacement = parts[1];
                int count = 0, changed = 0;
                for (int i = 0; i < n; i++) {
                    Cue c = cues[i];
                    List<string> lines = new();
                    int before = count;
                    foreach (string t in c.Text) {
                        StringBuilder result = new StringBuilder();
                        int cursor = 0, found;
                        while ((found = t.IndexOf(old,cursor,StringComparison.Ordinal)) >= 0) {
                            result.Append(t,cursor,found-cursor).Append(replacement);
                            cursor = found+old.Length;
                            count++;
                        }
                        lines.Add(result.Append(t.Substring(cursor)).ToString());
                    }
                    if (count > before) changed++;
                    cues[i] = new Cue(c.Index,c.Start,c.End,lines);
                }
                output.Add("REPLACE count="+count+" cues="+changed);
                break;
            }
        }
        return output;
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var blocks = new List<List<string>>();
        var block = new List<string>();
        string line;
        while ((line = Console.ReadLine()!) != "###") {
            if (line.Length == 0) {
                if (block.Count > 0) blocks.Add(block);
                block = new List<string>();
            } else {
                block.Add(line);
            }
        }
        if (block.Count > 0) blocks.Add(block);
        var editor = new Program();
        var loaded = new List<string>();
        editor.Load(blocks,loaded);
        foreach (string output in loaded) Console.WriteLine(output);
        int count = int.Parse(Console.ReadLine()!,CultureInfo.InvariantCulture);
        for (int i = 0; i < count; i++) {
            try {
                foreach (string output in editor.Execute(Console.ReadLine()!)) Console.WriteLine(output);
            } catch (Problem problem) {
                Console.WriteLine("ERROR "+problem.Message);
            }
        }
    }
}
