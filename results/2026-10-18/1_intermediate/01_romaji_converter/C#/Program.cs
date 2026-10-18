using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

class Program {
    record Meta(string Id, string Row, string Dan, bool Contracted);
    record Mora(string Id, int Column);
    record Word(string Text, int Start, int Pattern, List<Mora> Morae);
    record MatchResult(string Id, int Length);
    record LongInfo(bool[] Paired, bool[] Elements, char[] Vowels);
    record Element(string Base, int Voice, int Size);
    class Problem : Exception {
        public Problem(string message) : base(message) {}
    }
    static readonly string[] Systems = { "HEPBURN","TRADITIONAL","KUNREI","NIHON","WAPURO" };
    static readonly string[] Rows = { "a","ka","sa","ta","na","ha","ma","ya","ra","wa","ga","za","da","ba","pa" };
    const string Gojuon = "a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N";
    const string Iroha = "i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N";
    readonly List<Meta> table = new();
    readonly Dictionary<string,Meta> metadata = new(StringComparer.Ordinal);
    readonly Dictionary<string,Dictionary<string,string>> readers = new(StringComparer.Ordinal);
    string longSetting = "KEEP", caseSetting = "KEEP", orderSetting = "GOJUON";

    Program() {
        string[] rows = { "a i u e o", "ka ki ku ke ko", "sa si su se so", "ta ti tu te to",
            "na ni nu ne no", "ha hi hu he ho", "ma mi mu me mo", "ya yu yo", "ra ri ru re ro",
            "wa wi we wo", "ga gi gu ge go", "za zi zu ze zo", "da di du de do", "ba bi bu be bo", "pa pi pu pe po" };
        for (int i = 0; i < rows.Length; i++) {
            foreach (string id in rows[i].Split(' ')) {
                AddMeta(new Meta(id,Rows[i],id[^1].ToString(),false));
            }
        }
        foreach (string row in new[] { "ka","sa","ta","na","ha","ma","ra","ga","za","da","ba","pa" }) {
            foreach (string dan in new[] { "ya","yu","yo" }) {
                string id = row[..1] + dan;
                AddMeta(new Meta(id,row,dan,true));
            }
        }
        foreach (string system in Systems) {
            readers[system] = new(StringComparer.Ordinal);
        }
        readers["ANY"] = new(StringComparer.Ordinal);
        foreach (Meta meta in table) {
            foreach (string system in Systems) {
                string spelling = Spelling(system,meta.Id);
                readers[system].TryAdd(spelling,meta.Id);
                readers["ANY"].TryAdd(spelling,meta.Id);
            }
        }
    }
    void AddMeta(Meta meta) {
        table.Add(meta);
        metadata.Add(meta.Id,meta);
    }
    static void Fail(string message) {
        throw new Problem(message);
    }
    static void Column(int value, string message) {
        Fail($"col {value}: {message}");
    }
    static bool Letter(char c) => c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z';
    static bool Begins(string text, string choices) => text.Length > 0 && choices.Contains(text[0]);
    bool Regular(string id) => metadata.ContainsKey(id);
    static bool Vowel(string id) => id.Length == 1 && "aiueo".Contains(id,StringComparison.Ordinal);
    static char Last(string id) => id[^1];
    static string Devoice(string id) {
        int index = "gzdbp".IndexOf(id[0]);
        return index < 0 ? id : "ksthh"[index]+id[1..];
    }
    static string BaseRow(string row) => row switch {
        "ga" => "ka", "za" => "sa", "da" => "ta", "ba" or "pa" => "ha", _ => row
    };
    static int Voice(string row) => row == "pa" ? 2 : new[] { "ga","za","da","ba" }.Contains(row) ? 1 : 0;
    static string Spelling(string system, string id) {
        bool hepburn = system is "HEPBURN" or "TRADITIONAL", wapuro = system == "WAPURO";
        if (hepburn || wapuro) {
            string result = id switch {
                "si" => "shi", "ti" => "chi", "tu" => "tsu", "hu" => "fu", "zi" => "ji",
                "di" => hepburn ? "ji" : id, "du" => hepburn ? "zu" : id,
                "wi" => hepburn ? "i" : id, "we" => hepburn ? "e" : id, "wo" => hepburn ? "o" : id,
                _ => id
            };
            if (id.StartsWith("sy",StringComparison.Ordinal)) {
                return "sh"+Last(id);
            }
            if (id.StartsWith("ty",StringComparison.Ordinal)) {
                return "ch"+Last(id);
            }
            if (id.StartsWith("zy",StringComparison.Ordinal) || hepburn && id.StartsWith("dy",StringComparison.Ordinal)) {
                return "j"+Last(id);
            }
            return result;
        }
        if (system == "KUNREI") {
            return id switch {
                "di" => "zi", "du" => "zu", "wi" => "i", "we" => "e", "wo" => "o",
                _ => id.StartsWith("dy",StringComparison.Ordinal) ? "z"+id[1..] : id
            };
        }
        return id;
    }
    MatchResult? Match(string text, int position, string system) {
        for (int length = Math.Min(3,text.Length-position); length >= 1; length--) {
            if (readers[system].TryGetValue(text.Substring(position,length),out string? id)) {
                return new MatchResult(id,length);
            }
        }
        return null;
    }
    List<Mora> Parse(Word word, string system) {
        string text = word.Text.ToLowerInvariant();
        var result = new List<Mora>();
        bool normalize = system == "ANY";
        int p = 0;
        while (p < text.Length) {
            char c = text[p], next = p+1 < text.Length ? text[p+1] : '\0';
            int at = word.Start+p+1;
            string id;
            int advance;
            if (c == '-') {
                if (result.Count == 0 || !Regular(result[^1].Id)) {
                    Column(at,"misplaced long mark");
                }
                id = "L";
                advance = 1;
            } else if (c == '\'') {
                Column(at,"misplaced apostrophe");
                return result;
            } else {
                MatchResult? syllable = Match(text,p,system);
                if (syllable is not null) {
                    id = syllable.Id;
                    advance = syllable.Length;
                } else if ((normalize || system == "WAPURO") && text[p..].StartsWith("xtu",StringComparison.Ordinal)) {
                    id = "Q";
                    advance = 3;
                } else if (c == 'n') {
                    id = "N";
                    advance = 1;
                    if (normalize) {
                        char third = p+2 < text.Length ? text[p+2] : '\0';
                        if (next == '\'' || next == 'n' && !"aiueoy'".Contains(third)) {
                            advance = 2;
                        }
                    } else if (system == "WAPURO") {
                        if (next == 'n') {
                            advance = 2;
                        }
                    } else if (next == '\'') {
                        advance = 2;
                    }
                } else if ((normalize || system == "TRADITIONAL") && c == 'm' && "bmp".Contains(next)) {
                    id = "N";
                    advance = 1;
                } else if (Letter(c) && !"aiueon".Contains(c) && c == next && Match(text,p+1,system) is not null) {
                    id = "Q";
                    advance = 1;
                } else if ((normalize || system == "HEPBURN" || system == "TRADITIONAL") && c == 't' &&
                    text[(p+1)..].StartsWith("ch",StringComparison.Ordinal) && Match(text,p+1,system) is not null) {
                    id = "Q";
                    advance = 1;
                } else {
                    Column(at,"unknown syllable");
                    return result;
                }
            }
            result.Add(new Mora(id,at));
            p += advance;
        }
        return result;
    }
    static List<Word> Scan(string text) => Regex.Matches(text,"[A-Za-z'-]+")
        .Select(match => new Word(match.Value,match.Index,0,new List<Mora>())).ToList();
    static int Pattern(string text) {
        char[] letters = text.Where(Letter).ToArray();
        if (letters.All(c => c >= 'a' && c <= 'z')) {
            return 0;
        }
        if (text[0] >= 'A' && text[0] <= 'Z' && letters.Skip(1).All(c => c >= 'a' && c <= 'z')) {
            return 1;
        }
        if (letters.Length >= 2 && letters.All(c => c >= 'A' && c <= 'Z')) {
            return 2;
        }
        return -1;
    }
    LongInfo GetLongInfo(List<Mora> morae) {
        bool[] paired = new bool[morae.Count], elements = new bool[morae.Count];
        char[] vowels = new char[morae.Count];
        for (int i = 0; i < morae.Count; i++) {
            if (morae[i].Id == "L") {
                elements[i] = true;
                vowels[i] = Last(morae[i-1].Id);
            }
        }
        int p = 0;
        while (p+1 < morae.Count) {
            string a = morae[p].Id, b = morae[p+1].Id;
            char v = Last(a);
            if (Regular(a) && Vowel(b) && (v == Last(b) || v == 'o' && b == "u" || v == 'e' && b == "i")) {
                paired[p+1] = true;
                if (v == 'o' && (b == "o" || b == "u") || v == 'u' && b == "u") {
                    elements[p+1] = true;
                    vowels[p+1] = v;
                }
                p += 2;
            } else {
                p++;
            }
        }
        return new LongInfo(paired,elements,vowels);
    }
    List<string> Parts(Word word, string system, string longMode) {
        LongInfo info = GetLongInfo(word.Morae);
        var result = new List<string>();
        for (int i = 0; i < word.Morae.Count; i++) {
            Mora mora = word.Morae[i];
            string id = mora.Id, nextId = i+1 < word.Morae.Count ? word.Morae[i+1].Id : "";
            string next = Regular(nextId) ? Spelling(system,nextId) : "";
            string part;
            if (info.Elements[i]) {
                char v = info.Vowels[i];
                part = longMode switch {
                    "KEEP" => id == "L" ? "-" : Spelling(system,id),
                    "DROP" => "",
                    "PASSPORT" => v == 'o' && !Begins(next,"aiueo") ? "h" : "",
                    "HYPHEN" => "-",
                    _ => v.ToString()
                };
            } else if (Regular(id)) {
                part = Spelling(system,id);
            } else if (id == "N") {
                if (system == "WAPURO") {
                    part = nextId == "N" || Begins(next,"aiueoyn") ? "nn" : "n";
                } else if (system == "TRADITIONAL" && Begins(next,"bmp")) {
                    part = "m";
                } else {
                    part = Begins(next,"aiueoy") ? "n'" : "n";
                }
            } else {
                if (next.Length > 0 && !Begins(next,"aiueon")) {
                    part = (system is "HEPBURN" or "TRADITIONAL") && next.StartsWith("ch",StringComparison.Ordinal) ? "t" : next[..1];
                } else if (system == "WAPURO") {
                    part = "xtu";
                } else {
                    Column(mora.Column,"small tsu cannot be written");
                    return result;
                }
            }
            result.Add(part);
        }
        return result;
    }
    string Write(Word word, string system, string longMode, string caseMode) {
        string result = string.Concat(Parts(word,system,longMode));
        int pattern = caseMode == "KEEP" ? word.Pattern : caseMode == "LOWER" ? 0 : caseMode == "TITLE" ? 1 : 2;
        if (pattern == 1) {
            result = result[..1].ToUpperInvariant()+result[1..];
        }
        if (pattern == 2) {
            result = result.ToUpperInvariant();
        }
        return result;
    }
    string Canonical(Word word, string system) => Write(word,system,"KEEP","KEEP");
    static List<string> Ids(Word word) => word.Morae.Select(m => m.Id).ToList();
    List<string> Loose(Word word) {
        LongInfo info = GetLongInfo(word.Morae);
        return word.Morae.Where((_,i) => !info.Elements[i]).Select(m => m.Id).ToList();
    }
    List<Element> Elements(Word word) {
        var result = new List<Element>();
        foreach (Mora mora in word.Morae) {
            string id = mora.Id;
            if (id == "L") {
                continue;
            }
            if (id == "N") {
                result.Add(new Element("N",0,0));
            } else if (id == "Q") {
                result.Add(new Element("tu",0,1));
            } else {
                Meta meta = metadata[id];
                if (meta.Contracted) {
                    result.Add(new Element(Devoice(meta.Row[..1]+"i"),Voice(meta.Row),0));
                    result.Add(new Element("y"+Last(id),0,1));
                } else {
                    result.Add(new Element(Devoice(id),Voice(meta.Row),0));
                }
            }
        }
        return result;
    }
    static int Compare(List<int> a, List<int> b) {
        for (int i = 0; i < Math.Min(a.Count,b.Count); i++) {
            if (a[i] != b[i]) {
                return a[i].CompareTo(b[i]);
            }
        }
        return a.Count.CompareTo(b.Count);
    }
    List<Word> Sorted(List<Word> words) {
        var ranks = (orderSetting == "GOJUON" ? Gojuon : Iroha).Split(' ')
            .Select((name,index) => (name,index)).ToDictionary(p => p.name,p => p.index,StringComparer.Ordinal);
        var result = words.ToList();
        result.Sort((a,b) => {
            var first = Elements(a);
            var second = Elements(b);
            List<int>[] left = { first.Select(e => ranks[e.Base]).ToList(),first.Select(e => e.Voice).ToList(),
                first.Select(e => e.Size).ToList(),a.Morae.Select(m => m.Id == "L" ? 1 : 0).ToList() };
            List<int>[] right = { second.Select(e => ranks[e.Base]).ToList(),second.Select(e => e.Voice).ToList(),
                second.Select(e => e.Size).ToList(),b.Morae.Select(m => m.Id == "L" ? 1 : 0).ToList() };
            for (int i = 0; i < 4; i++) {
                int comparison = Compare(left[i],right[i]);
                if (comparison != 0) {
                    return comparison;
                }
            }
            return a.Start.CompareTo(b.Start);
        });
        return result;
    }
    List<string> PatternMorae(string pattern, string system) {
        if (!Regex.IsMatch(pattern,@"\A[a-z'?*\-]+\z")) {
            Fail("invalid pattern");
        }
        var result = new List<string>();
        int start = 0;
        try {
            for (int i = 0; i <= pattern.Length; i++) {
                if (i == pattern.Length || pattern[i] == '?' || pattern[i] == '*') {
                    if (i > start) {
                        var part = new Word(pattern[start..i],0,0,new List<Mora>());
                        result.AddRange(Parse(part,system).Select(m => m.Id));
                    }
                    if (i < pattern.Length) {
                        result.Add(pattern[i].ToString());
                    }
                    start = i+1;
                }
            }
        } catch (Problem) {
            Fail("invalid pattern");
        }
        return result;
    }
    static bool Matches(List<string> pattern, List<string> word) {
        bool[] dp = new bool[word.Count+1];
        dp[0] = true;
        foreach (string token in pattern) {
            bool[] next = new bool[word.Count+1];
            next[0] = token == "*" && dp[0];
            for (int j = 1; j <= word.Count; j++) {
                next[j] = token == "*" ? dp[j] || next[j-1] : dp[j-1] && (token == "?" || token == word[j-1]);
            }
            dp = next;
        }
        return dp[word.Count];
    }
    string Detect(List<Word> words) {
        var result = new List<string>();
        foreach (string system in Systems) {
            string verdict = "canonical";
            try {
                var parsed = words.Select(w => w with { Morae = Parse(w,system) }).ToList();
                foreach (Word word in parsed) {
                    if (word.Text != Canonical(word,system)) {
                        verdict = "readable";
                    }
                }
            } catch (Problem) {
                verdict = "error";
            }
            result.Add(system+"="+verdict);
        }
        return string.Join(" ",result);
    }
    string Execute(string line) {
        string command = line.Split(new[] { ' ' },2,StringSplitOptions.None)[0];
        var counts = new Dictionary<string,int>(StringComparer.Ordinal) {
            ["CONVERT"] = 2, ["NORMALIZE"] = 0, ["REVERSE"] = 1, ["VALID"] = 1,
            ["DETECT"] = 0, ["DIFF"] = 2, ["SAME"] = 2, ["MORAE"] = 1, ["SYLLABLES"] = 1,
            ["ROW"] = 1, ["STATS"] = 1, ["SORT"] = 1, ["INDEX"] = 1, ["FIND"] = 2,
            ["HAIKU"] = 1, ["KAIBUN"] = 1, ["SHIRITORI"] = 1
        };
        if (!counts.ContainsKey(command) && command is not "SET" and not "TABLE") {
            Fail("unknown command "+command);
        }
        if (command is "SET" or "TABLE") {
            string[] tokens = line.Split(' ');
            if (tokens.Length < 3) {
                Fail("missing argument");
            }
            if (tokens.Length > 3) {
                Fail("too many arguments");
            }
            if (command == "SET") {
                string[] allowed = tokens[1] switch {
                    "LONG" => new[] { "KEEP","DROP","PASSPORT","HYPHEN","DOUBLE" },
                    "CASE" => new[] { "KEEP","LOWER","UPPER","TITLE" },
                    "ORDER" => new[] { "GOJUON","IROHA" },
                    _ => throw new Problem("unknown option "+tokens[1])
                };
                if (!allowed.Contains(tokens[2])) {
                    Fail("unknown value "+tokens[2]);
                }
                if (tokens[1] == "LONG") {
                    longSetting = tokens[2];
                }
                if (tokens[1] == "CASE") {
                    caseSetting = tokens[2];
                }
                if (tokens[1] == "ORDER") {
                    orderSetting = tokens[2];
                }
                return tokens[1]+"="+tokens[2];
            }
            if (!Systems.Contains(tokens[1])) {
                Fail("unknown system "+tokens[1]);
            }
            if (!Rows.Contains(tokens[2])) {
                Fail("unknown row "+tokens[2]);
            }
            return string.Join(" ",table.Where(m => m.Row == tokens[2]).Select(m => Spelling(tokens[1],m.Id)));
        }
        int fixedArgs = counts[command];
        string[] chunks = line.Split(new[] { ' ' },fixedArgs+2,StringSplitOptions.None);
        if (chunks.Length < fixedArgs+2) {
            Fail("missing argument");
        }
        string[] arguments = chunks.Skip(1).Take(fixedArgs).ToArray();
        string text = chunks[fixedArgs+1];
        int systemCount = command is "NORMALIZE" or "DETECT" ? 0 : command is "CONVERT" or "DIFF" or "SAME" ? 2 : 1;
        for (int i = 0; i < systemCount; i++) {
            if (!Systems.Contains(arguments[i])) {
                Fail("unknown system "+arguments[i]);
            }
        }
        var searchPattern = command == "FIND" ? PatternMorae(arguments[1],arguments[0]) : new List<string>();
        bool slash = command is "SAME" or "HAIKU";
        for (int i = 0; i < text.Length; i++) {
            char c = text[i];
            if (!Letter(c) && c != '\'' && c != '-' && !" 0123456789.,!?;:()\"".Contains(c) && !(slash && c == '/')) {
                Column(i+1,"invalid character");
            }
        }
        string[] poem = text.Split('/');
        if (command == "SAME" && (poem.Length != 2 || Scan(poem[0]).Count == 0 || Scan(poem[1]).Count == 0)) {
            Fail("expected two texts");
        }
        if (command == "HAIKU") {
            if (poem.Length != 3 && poem.Length != 5) {
                Fail("expected 3 or 5 lines");
            }
            foreach (string part in poem) {
                if (Scan(part).Count == 0) {
                    Fail("expected 3 or 5 lines");
                }
            }
        }
        var words = Scan(text);
        if (words.Count == 0) {
            Fail("no words");
        }
        for (int i = 0; i < words.Count; i++) {
            int pattern = Pattern(words[i].Text);
            if (pattern < 0) {
                Column(words[i].Start+1,"mixed case");
            }
            words[i] = words[i] with { Pattern = pattern };
        }
        if (command == "DETECT") {
            return Detect(words);
        }
        for (int i = 0; i < words.Count; i++) {
            Word word = words[i];
            string source = command == "NORMALIZE" ? "ANY" : command == "SAME" && word.Start > text.IndexOf('/') ? arguments[1] : arguments[0];
            words[i] = word with { Morae = Parse(word,source) };
        }
        string system = command == "NORMALIZE" ? "HEPBURN" : arguments[0];
        switch (command) {
            case "CONVERT":
            case "NORMALIZE":
            case "REVERSE": {
                string target = command == "CONVERT" ? arguments[1] : system;
                var result = new StringBuilder();
                int cursor = 0;
                foreach (Word word in words) {
                    result.Append(text[cursor..word.Start]);
                    Word written = word;
                    if (command == "REVERSE") {
                        var reversed = new List<Mora>();
                        for (int i = 0; i < word.Morae.Count; i++) {
                            Mora mora = word.Morae[i];
                            string id = mora.Id == "L" ? Last(word.Morae[i-1].Id).ToString() : mora.Id;
                            reversed.Add(new Mora(id,mora.Column));
                        }
                        reversed.Reverse();
                        written = word with { Morae = reversed };
                    }
                    result.Append(Write(written,target,longSetting,caseSetting));
                    cursor = word.Start+word.Text.Length;
                }
                result.Append(text[cursor..]);
                return result.ToString();
            }
            case "VALID": {
                foreach (Word word in words) {
                    string expected = Canonical(word,system);
                    if (word.Text != expected) {
                        int i = 0;
                        while (i < Math.Min(word.Text.Length,expected.Length) && word.Text[i] == expected[i]) {
                            i++;
                        }
                        return $"INVALID col {word.Start+i+1}: expected {expected}";
                    }
                }
                return "VALID";
            }
            case "DIFF": {
                var changes = new List<string>();
                foreach (Word word in words) {
                    string a = Write(word,system,longSetting,caseSetting);
                    string b = Write(word,arguments[1],longSetting,caseSetting);
                    if (a != b) {
                        changes.Add(a+">"+b);
                    }
                }
                return $"{changes.Count} of {words.Count}"+(changes.Count == 0 ? "" : ": "+string.Join(" ",changes));
            }
            case "SAME": {
                var left = words.Where(w => w.Start < text.IndexOf('/')).ToList();
                var right = words.Where(w => w.Start > text.IndexOf('/')).ToList();
                bool exact = true;
                for (int i = 0; i < Math.Min(left.Count,right.Count); i++) {
                    if (!Loose(left[i]).SequenceEqual(Loose(right[i]))) {
                        return $"DIFFERENT at word {i+1}";
                    }
                    if (!Ids(left[i]).SequenceEqual(Ids(right[i]))) {
                        exact = false;
                    }
                }
                if (left.Count != right.Count) {
                    return $"DIFFERENT at word {Math.Min(left.Count,right.Count)+1}";
                }
                return exact ? "EXACT" : "LOOSE";
            }
            case "MORAE": {
                var result = new List<string>();
                int count = 0;
                foreach (Word word in words) {
                    var pieces = word.Morae.Select(m => Regular(m.Id) ? Spelling(system,m.Id) : m.Id == "L" ? "-" : m.Id).ToList();
                    count += pieces.Count;
                    result.Add(string.Join(".",pieces));
                }
                return $"{count}: {string.Join(" ",result)}";
            }
            case "SYLLABLES": {
                var result = new List<string>();
                int count = 0;
                foreach (Word word in words) {
                    var pieces = Parts(word,system,"KEEP");
                    var syllables = new List<string>();
                    LongInfo info = GetLongInfo(word.Morae);
                    for (int i = 0; i < pieces.Count; i++) {
                        if (i == 0 || Regular(word.Morae[i].Id) && !info.Paired[i]) {
                            syllables.Add(pieces[i]);
                        } else {
                            syllables[^1] += pieces[i];
                        }
                    }
                    count += syllables.Count;
                    result.Add(string.Join(".",syllables));
                }
                return $"{count}: {string.Join(" ",result)}";
            }
            case "ROW": {
                var result = new List<string>();
                foreach (Word word in words) {
                    foreach (Mora mora in word.Morae) {
                        result.Add(metadata.TryGetValue(mora.Id,out Meta? meta) ?
                            $"{Spelling(system,meta.Id)}: {meta.Row} {meta.Dan}" : (mora.Id == "L" ? "-" : mora.Id)+": special");
                    }
                }
                return string.Join(", ",result);
            }
            case "STATS": {
                var rowCounts = new Dictionary<string,int>(StringComparer.Ordinal);
                int count = 0, voiced = 0, semivoiced = 0, contracted = 0, n = 0, q = 0, l = 0;
                foreach (Word word in words) {
                    foreach (Mora mora in word.Morae) {
                        count++;
                        if (!metadata.TryGetValue(mora.Id,out Meta? meta)) {
                            if (mora.Id == "N") {
                                n++;
                            }
                            if (mora.Id == "Q") {
                                q++;
                            }
                            if (mora.Id == "L") {
                                l++;
                            }
                        } else {
                            string row = BaseRow(meta.Row);
                            rowCounts[row] = rowCounts.GetValueOrDefault(row)+1;
                            if (Voice(meta.Row) == 1) {
                                voiced++;
                            }
                            if (Voice(meta.Row) == 2) {
                                semivoiced++;
                            }
                            if (meta.Contracted) {
                                contracted++;
                            }
                        }
                    }
                }
                var result = new List<string> { $"morae={count}" };
                foreach (string row in Rows.Take(10)) {
                    if (rowCounts.ContainsKey(row)) {
                        result.Add($"{row}={rowCounts[row]}");
                    }
                }
                result.AddRange(new[] { $"voiced={voiced}",$"semivoiced={semivoiced}",$"contracted={contracted}",$"N={n}",$"Q={q}",$"L={l}" });
                return string.Join(" ",result);
            }
            case "SORT":
            case "INDEX": {
                var sorted = Sorted(words);
                if (command == "SORT") {
                    return string.Join(" ",sorted.Select(w => w.Text));
                }
                var groups = new List<string>();
                var group = new List<string>();
                string previous = "";
                foreach (Word word in sorted) {
                    string baseKana = Elements(word)[0].Base;
                    string heading = orderSetting == "IROHA" || baseKana == "N" ? baseKana : metadata[baseKana].Row;
                    if (heading != previous && group.Count > 0) {
                        groups.Add(previous+": "+string.Join(" ",group));
                        group.Clear();
                    }
                    previous = heading;
                    group.Add(word.Text);
                }
                groups.Add(previous+": "+string.Join(" ",group));
                return string.Join("; ",groups);
            }
            case "FIND": {
                var found = words.Where(w => Matches(searchPattern,Ids(w))).Select(w => w.Text).ToList();
                return $"{found.Count} of {words.Count}"+(found.Count == 0 ? "" : ": "+string.Join(" ",found));
            }
            case "HAIKU": {
                int[] totals = new int[poem.Length];
                foreach (Word word in words) {
                    totals[text[..word.Start].Count(c => c == '/')] += word.Morae.Count;
                }
                int[] expected = poem.Length == 3 ? new[] { 5,7,5 } : new[] { 5,7,5,7,7 };
                return (totals.SequenceEqual(expected) ? "OK " : "NG ")+(poem.Length == 3 ? "haiku " : "tanka ")+string.Join("-",totals);
            }
            case "KAIBUN": {
                var bases = words.SelectMany(Elements).Select(e => e.Base).ToList();
                return (bases.SequenceEqual(bases.AsEnumerable().Reverse()) ? "YES " : "NO ")+string.Join(".",bases);
            }
            case "SHIRITORI": {
                var seen = new HashSet<string>(StringComparer.Ordinal);
                string previous = "";
                for (int i = 0; i < words.Count; i++) {
                    Word word = words[i];
                    var elements = Elements(word);
                    string head = elements[0].Base, tail = elements[^1].Base;
                    string prefix = $"NG {i+1}: {word.Text}";
                    if (i > 0 && head != previous) {
                        return prefix+" must start with "+Spelling(system,previous);
                    }
                    string key = string.Join(".",Ids(word));
                    if (seen.Contains(key)) {
                        return prefix+" is repeated";
                    }
                    if (tail == "N") {
                        return prefix+" ends with N";
                    }
                    seen.Add(key);
                    previous = tail;
                }
                return $"OK {words.Count}";
            }
            default: throw new InvalidOperationException("Unreachable command");
        }
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        int count = int.Parse(Console.ReadLine()!,CultureInfo.InvariantCulture);
        var converter = new Program();
        for (int i = 0; i < count; i++) {
            string line = Console.ReadLine()!;
            try {
                Console.WriteLine(converter.Execute(line));
            } catch (Problem problem) {
                Console.WriteLine("ERROR "+problem.Message);
            }
        }
    }
}
