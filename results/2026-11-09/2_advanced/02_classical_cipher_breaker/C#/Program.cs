#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

sealed class JobFault : Exception
{
    public JobFault(string reason) : base(reason) { }
}

sealed record Candidate(string Key, string Plaintext, int Score, int Order);

sealed record BreakOutcome(
    List<Candidate> Ranked,
    Candidate Choice,
    int Length,
    string Method,
    int Passes,
    int Changes,
    KasiskiData? Kasiski
);

static class Program
{
    private static readonly string[] Commands =
        { "ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY" };

    private static readonly HashSet<string> Ciphers = new(StringComparer.Ordinal)
        { "caesar", "affine", "vigenere", "autokey", "railfence", "columnar", "playfair" };

    private static readonly int[] AffineMultipliers =
        { 1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25 };

    private static readonly Dictionary<string, List<string>> Messages =
        new(StringComparer.Ordinal);

    private static readonly Dictionary<string, int[]> Totals =
        Commands.ToDictionary(command => command, command => new int[2], StringComparer.Ordinal);

    private static readonly List<string> ResultLines = new();
    private static readonly List<string> CandidateLines = new();
    private static readonly List<string> AnalysisLines = new();

    private static int[] Mono = Array.Empty<int>();
    private static int[,] Bi = new int[26, 26];

    private static bool ValidName(string value) =>
        Regex.IsMatch(value, @"\A[a-z0-9_]{1,16}\z");

    private static bool Digits(string value, int max) =>
        Regex.IsMatch(value, @"\A[0-9]{1," + max + @"}\z");

    private static void Fail(string reason) => throw new JobFault(reason);

    private static string Body(string name) => string.Join("\n", Messages[name]);

    private static string Letters(string name) => Scoring.Letters(Body(name));

    private static bool SubstitutionCipher(string cipher) =>
        cipher is "caesar" or "affine" or "vigenere" or "autokey";

    private static void ReadMessages(string path)
    {
        string? current = null;
        var lines = new List<string>();
        foreach (string line in File.ReadAllLines(path, Encoding.ASCII))
        {
            if (current == null)
            {
                if (line.Length == 0)
                    continue;
                current = line.Substring(8);
                lines = new List<string>();
            }
            else if (line == "END")
            {
                Messages.Add(current, lines);
                current = null;
            }
            else
            {
                lines.Add(line);
            }
        }
    }

    private static string NormalizeKey(string cipher, string original)
    {
        bool valid;
        switch (cipher)
        {
            case "caesar":
                valid = Digits(original, 2) && int.Parse(original) <= 25;
                return valid ? int.Parse(original).ToString() : throw new JobFault("bad key " + original);
            case "affine":
                string[] pair = original.Split(',');
                valid = pair.Length == 2 && Digits(pair[0], 2) && Digits(pair[1], 2)
                    && AffineMultipliers.Contains(int.Parse(pair[0])) && int.Parse(pair[1]) <= 25;
                return valid ? $"{int.Parse(pair[0])},{int.Parse(pair[1])}"
                    : throw new JobFault("bad key " + original);
            case "railfence":
                valid = Digits(original, 2) && int.Parse(original) is >= 2 and <= 20;
                return valid ? int.Parse(original).ToString() : throw new JobFault("bad key " + original);
            case "vigenere":
            case "autokey":
                valid = Regex.IsMatch(original, @"\A[A-Za-z]{1,20}\z");
                break;
            case "playfair":
                valid = Regex.IsMatch(original, @"\A[A-Za-z]{1,25}\z");
                break;
            case "columnar":
                valid = Regex.IsMatch(original, @"\A[A-Za-z0-9]{2,9}\z");
                break;
            default:
                valid = false;
                break;
        }
        if (!valid)
            throw new JobFault("bad key " + original);
        string normalized = original.ToUpperInvariant();
        return cipher == "playfair" ? normalized.Replace('J', 'I') : normalized;
    }

    private static Dictionary<string, (int Min, int Max, int Default)> OptionRules(string command, string cipher)
    {
        var options = new Dictionary<string, (int, int, int)>(StringComparer.Ordinal);
        if (command == "ANALYZE")
            options["MAXLEN"] = (2, 20, 10);
        if (command != "BREAK")
            return options;

        options["TOP"] = (1, 20, 5);
        if (cipher == "vigenere")
        {
            options["MAXLEN"] = (2, 20, 10);
            options["IOC"] = (1, 100000, 6000);
            options["KASISKI"] = (1, 100, 60);
            options["REFINE"] = (0, 10, 5);
        }
        else if (cipher == "autokey")
            options["MAXLEN"] = (1, 20, 8);
        else if (cipher == "railfence")
            options["MAXRAILS"] = (2, 20, 10);
        else if (cipher == "columnar")
            options["MAXLEN"] = (2, 6, 6);
        return options;
    }

    private static Dictionary<string, string> ParseOptions(string command, string cipher, IEnumerable<string> words)
    {
        var rules = OptionRules(command, cipher);
        var values = rules.ToDictionary(item => item.Key, item => item.Value.Default.ToString(),
            StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (string option in words)
        {
            int separator = option.IndexOf('=');
            string name = separator < 0 ? "" : option.Substring(0, separator);
            string value = separator < 0 ? "" : option.Substring(separator + 1);
            if (separator < 0 || !seen.Add(name))
                Fail("bad option " + option);
            if (name == "KEYS" && (command == "IDENTIFY" || (command == "BREAK" && cipher == "playfair")))
            {
                if (!ValidName(value))
                    Fail("bad option " + option);
                values[name] = value;
                continue;
            }
            if (!rules.TryGetValue(name, out var rule) || !Digits(value, 6))
                Fail("bad option " + option);
            int parsed = int.Parse(value);
            if (parsed < rule.Min || parsed > rule.Max)
                Fail("bad option " + option);
            values[name] = parsed.ToString();
        }
        if (command == "BREAK" && cipher == "playfair" && !values.ContainsKey("KEYS"))
            Fail("missing option KEYS");
        return values;
    }

    private static int Option(Dictionary<string, string> opts, string name) =>
        int.Parse(opts[name]);

    private static string Decrypt(string letters, string cipher, string key)
    {
        if (SubstitutionCipher(cipher))
            return Scoring.Letters(Substitution.Apply(letters, cipher, key, false));
        if (cipher == "railfence")
            return Transposition.RailFence(letters, int.Parse(key), false);
        if (cipher == "columnar")
            return Transposition.Columnar(letters, key, false);
        return Playfair.Apply(letters, key, false);
    }

    private static string Transform(string text, string cipher, string key, bool encrypt)
    {
        if (SubstitutionCipher(cipher))
            return Substitution.Apply(text, cipher, key, encrypt);
        string letters = Scoring.Letters(text);
        if (cipher == "railfence")
            return Transposition.RailFence(letters, int.Parse(key), encrypt);
        if (cipher == "columnar")
            return Transposition.Columnar(letters, key, encrypt);
        return Playfair.Apply(letters, key, encrypt);
    }

    private static List<string> KeyList(string name)
    {
        var keys = new List<string>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (Match match in Regex.Matches(Body(name), "[A-Za-z]+"))
        {
            string key = match.Value.ToUpperInvariant().Replace('J', 'I');
            if (seen.Add(key))
                keys.Add(key);
        }
        return keys;
    }

    private static IEnumerable<string> PermutationKeys(int length)
    {
        char[] digits = Enumerable.Range(1, length).Select(i => (char)('0' + i)).ToArray();
        foreach (string key in Permute(digits, 0))
            yield return key;
    }

    private static IEnumerable<string> Permute(char[] digits, int index)
    {
        if (index == digits.Length)
        {
            yield return new string(digits);
            yield break;
        }
        for (int next = index; next < digits.Length; next++)
        {
            (digits[index], digits[next]) = (digits[next], digits[index]);
            foreach (string key in Permute(digits, index + 1))
                yield return key;
            (digits[index], digits[next]) = (digits[next], digits[index]);
        }
    }

    private static string ColumnKey(string text, int length, bool autokey)
    {
        var key = new StringBuilder(length);
        for (int column = 0; column < length; column++)
        {
            string segment = Analysis.Column(text, length, column);
            int bestValue = 0;
            int bestScore = int.MinValue;
            for (int value = 0; value < 26; value++)
            {
                int score;
                if (!autokey)
                {
                    string decoded = Substitution.Apply(segment, "caesar", value.ToString(), false);
                    score = Scoring.Mono(decoded, Mono);
                }
                else
                {
                    int previous = value;
                    score = 0;
                    foreach (char c in segment)
                    {
                        previous = Substitution.Mod(Scoring.Value(c) - previous);
                        score += Mono[previous];
                    }
                }
                if (score > bestScore)
                {
                    bestScore = score;
                    bestValue = value;
                }
            }
            key.Append(Scoring.Letter(bestValue));
        }
        return key.ToString();
    }

    private static IEnumerable<string> CandidateKeys(
        string cipher, string text, Dictionary<string, string> options, List<string>? words)
    {
        if (cipher == "caesar")
        {
            for (int key = 0; key <= 25; key++)
                yield return key.ToString();
        }
        else if (cipher == "affine")
        {
            foreach (int a in AffineMultipliers)
                for (int b = 0; b <= 25; b++)
                    yield return $"{a},{b}";
        }
        else if (cipher == "railfence")
        {
            for (int rails = 2; rails <= Option(options, "MAXRAILS"); rails++)
                yield return rails.ToString();
        }
        else if (cipher == "columnar")
        {
            for (int length = 2; length <= Option(options, "MAXLEN"); length++)
                foreach (string key in PermutationKeys(length).OrderBy(value => value, StringComparer.Ordinal))
                    yield return key;
        }
        else if (cipher == "playfair")
        {
            foreach (string key in words!)
                yield return key;
        }
        else
        {
            for (int length = 1; length <= Option(options, "MAXLEN"); length++)
                yield return ColumnKey(text, length, cipher == "autokey");
        }
    }

    private static int Score(string cipher, string text)
    {
        return cipher is "caesar" or "affine"
            ? Scoring.Mono(text, Mono) : Scoring.Bi(text, Bi);
    }

    private static BreakOutcome Break(
        string cipher, string text, Dictionary<string, string> options, List<string>? words = null)
    {
        var candidates = new List<Candidate>();
        foreach (string key in CandidateKeys(cipher, text, options, words))
        {
            string plaintext = Decrypt(text, cipher, key);
            candidates.Add(new Candidate(key, plaintext, Score(cipher, plaintext), candidates.Count));
        }
        List<Candidate> ranked = candidates.OrderByDescending(c => c.Score)
            .ThenBy(c => c.Order).ToList();
        Candidate best = ranked[0];
        if (cipher != "vigenere")
            return new BreakOutcome(ranked, best, 0, "", 0, 0, null);

        int maxlen = Option(options, "MAXLEN");
        int threshold = Option(options, "IOC");
        KasiskiData kasiski = Analysis.Kasiski(text);
        int[] averages = Enumerable.Range(1, maxlen)
            .Select(length => Analysis.AverageIOC(text, length)).ToArray();
        int kasiskiLength = 0;
        for (int length = 2; length <= maxlen; length++)
            if (kasiski.Gaps.Length >= 1
                && 100 * kasiski.Count(length) >= Option(options, "KASISKI") * kasiski.Gaps.Length)
                kasiskiLength = length;

        int chosen = 0;
        string method;
        if (kasiskiLength != 0 && averages[kasiskiLength - 1] >= threshold)
        {
            chosen = kasiskiLength;
            method = "kasiski";
        }
        else
        {
            for (int length = 1; length <= maxlen; length++)
                if (averages[length - 1] >= threshold)
                {
                    chosen = length;
                    break;
                }
            if (chosen != 0)
                method = "ioc";
            else
            {
                chosen = 1;
                for (int length = 2; length <= maxlen; length++)
                    if (averages[length - 1] > averages[chosen - 1])
                        chosen = length;
                method = "maxioc";
            }
        }
        string keyText = candidates[chosen - 1].Key;
        int reference = Score(cipher, Decrypt(text, cipher, keyText));
        int passes = 0;
        int changes = 0;
        for (int attempt = 0; attempt < Option(options, "REFINE"); attempt++)
        {
            passes++;
            int changesThisPass = 0;
            for (int index = 0; index < keyText.Length; index++)
            {
                char winner = keyText[index];
                int high = reference;
                for (int value = 0; value < 26; value++)
                {
                    string trial = keyText.Substring(0, index) + Scoring.Letter(value)
                        + keyText.Substring(index + 1);
                    int score = Score(cipher, Decrypt(text, cipher, trial));
                    if (score > high)
                    {
                        high = score;
                        winner = Scoring.Letter(value);
                    }
                }
                if (high > reference)
                {
                    keyText = keyText.Substring(0, index) + winner + keyText.Substring(index + 1);
                    reference = high;
                    changes++;
                    changesThisPass++;
                }
            }
            if (changesThisPass == 0)
                break;
        }
        best = new Candidate(keyText, Decrypt(text, cipher, keyText), reference, -1);
        return new BreakOutcome(ranked, best, chosen, method, passes, changes, kasiski);
    }

    private static void WriteCandidateReport(
        int job, string cipher, string source, BreakOutcome broken, int top)
    {
        int trials = broken.Ranked.Count;
        int margin = trials > 1 ? broken.Ranked[0].Score - broken.Ranked[1].Score : 0;
        CandidateLines.Add($"JOB {job} BREAK {cipher} source={source} tried={trials} margin={margin}");
        for (int rank = 0; rank < Math.Min(top, trials); rank++)
        {
            Candidate candidate = broken.Ranked[rank];
            string preview = candidate.Plaintext.Substring(0, Math.Min(40, candidate.Plaintext.Length));
            CandidateLines.Add($"{rank + 1} {candidate.Key} {candidate.Score} {preview}");
        }
    }

    private static void WriteBreakAnalysis(int job, string cipher, string source,
        string text, Dictionary<string, string> options, BreakOutcome broken)
    {
        if (cipher == "vigenere")
        {
            AnalysisLines.Add($"JOB {job} BREAK vigenere source={source}");
            AnalysisLines.Add($"letters={text.Length}");
            AnalysisLines.AddRange(Analysis.PeriodTable(text, Option(options, "MAXLEN"), broken.Kasiski!));
            AnalysisLines.AddRange(Analysis.KasiskiTable(broken.Kasiski!));
            AnalysisLines.Add($"decision length={broken.Length} method={broken.Method}");
            AnalysisLines.Add($"refine passes={broken.Passes} changes={broken.Changes} key={broken.Choice.Key}");
        }
        else if (cipher == "playfair")
        {
            string t = text.Replace('J', 'I');
            string square = Playfair.Square(broken.Choice.Key);
            AnalysisLines.Add($"JOB {job} BREAK playfair source={source}");
            AnalysisLines.Add($"letters={t.Length}");
            int pairs = t.Length / 2;
            int distinct = Enumerable.Range(0, pairs).Select(i => t.Substring(i * 2, 2)).Distinct().Count();
            AnalysisLines.Add($"digraphs pairs={pairs} distinct={distinct}");
            AnalysisLines.Add("top " + Analysis.TopPairs(t, true));
            AnalysisLines.Add("square " + string.Join(" ", Enumerable.Range(0, 5)
                .Select(i => square.Substring(i * 5, 5))));
        }
    }

    private static string[] OutputText(string fullBody, string cipher, string key, bool encrypt)
    {
        string result = Transform(fullBody, cipher, key, encrypt);
        return SubstitutionCipher(cipher) ? result.Split('\n') : Scoring.Groups(result);
    }

    private static void SaveMessage(string? name, string[] lines)
    {
        if (name != null)
            Messages.Add(name, lines.ToList());
    }

    private static void EncryptDecrypt(int job, string command, string cipher,
        string key, string source, string? target)
    {
        string letters = Letters(source);
        if (letters.Length == 0)
            Fail("no letters");
        if (command == "DECRYPT" && cipher == "playfair" && !Playfair.Valid(letters))
            Fail("bad playfair text");
        string[] lines = OutputText(Body(source), cipher, key, command == "ENCRYPT");
        int outputLetters = lines.Sum(line => Scoring.Letters(line).Length);
        string heading = $"JOB {job} {command} {cipher} key={key} source={source} letters={outputLetters} lines={lines.Length}";
        if (target != null)
            heading += " as=" + target;
        ResultLines.Add(heading);
        ResultLines.AddRange(lines);
        SaveMessage(target, lines);
    }

    private static void BreakJob(int job, string cipher, string source,
        string? target, Dictionary<string, string> options)
    {
        string text = Letters(source);
        if (text.Length < 40)
            Fail("text too short");
        if (cipher == "playfair" && !Playfair.Valid(text))
            Fail("bad playfair text");
        List<string>? words = cipher == "playfair" ? KeyList(options["KEYS"]) : null;
        if (cipher == "playfair" && words!.Count == 0)
            Fail("empty key list");
        BreakOutcome broken = Break(cipher, text, options, words);
        Candidate winner = broken.Choice;
        string[] lines = OutputText(Body(source), cipher, winner.Key, false);
        string heading = $"JOB {job} BREAK {cipher} source={source} key={winner.Key} score={winner.Score} lines={lines.Length}";
        if (target != null)
            heading += " as=" + target;
        ResultLines.Add(heading);
        ResultLines.AddRange(lines);
        WriteCandidateReport(job, cipher, source, broken, Option(options, "TOP"));
        WriteBreakAnalysis(job, cipher, source, text, options, broken);
        SaveMessage(target, lines);
    }

    private static void AnalyzeJob(int job, string source, Dictionary<string, string> options)
    {
        string text = Letters(source);
        if (text.Length < 40)
            Fail("text too short");
        ResultLines.Add($"JOB {job} ANALYZE source={source} letters={text.Length}");
        AnalysisLines.AddRange(Analysis.Report($"{job} ANALYZE source={source}",
            text, Mono, Bi, Option(options, "MAXLEN")));
    }

    private static void CompareJob(int job, string leftName, string rightName)
    {
        string left = Letters(leftName);
        string right = Letters(rightName);
        int length = Math.Min(left.Length, right.Length);
        int first = length + 1;
        int count = 0;
        for (int i = 0; i < length; i++)
        {
            if (left[i] == right[i])
                continue;
            if (count == 0)
                first = i + 1;
            count++;
        }
        if (left == right)
            ResultLines.Add($"JOB {job} COMPARE {leftName} {rightName} equal letters={left.Length}");
        else
            ResultLines.Add($"JOB {job} COMPARE {leftName} {rightName} differ letters={left.Length},{right.Length} first={first} mismatches={count}");
    }

    private static void IdentifyJob(int job, string source, Dictionary<string, string> options)
    {
        string text = Letters(source);
        if (text.Length < 40)
            Fail("text too short");

        int ioc = Analysis.IOC(text);
        int mean = Scoring.Mono(text, Mono) / text.Length;
        int distinct = Analysis.Frequency(text).Count(n => n > 0);
        bool shape = !text.Contains('J') && Playfair.Valid(text);
        string family = shape ? "playfair" :
            ioc >= 5500 && mean >= 44 ? "transposition" :
            ioc >= 5500 ? "monoalphabetic" : "polyalphabetic";
        List<string>? keys = null;
        if (family == "playfair" && options.TryGetValue("KEYS", out string? keysName))
        {
            keys = KeyList(keysName);
            if (keys.Count == 0)
                Fail("empty key list");
        }
        string[] ciphers = family switch
        {
            "transposition" => new[] { "railfence", "columnar" },
            "monoalphabetic" => new[] { "affine" },
            "polyalphabetic" => new[] { "vigenere", "autokey" },
            _ => keys == null ? Array.Empty<string>() : new[] { "playfair" }
        };
        var tested = new List<(string Cipher, Candidate Winner)>();
        foreach (string cipher in ciphers)
        {
            Dictionary<string, string> defaults = ParseOptions("BREAK", cipher,
                cipher == "playfair" ? new[] { "KEYS=" + options["KEYS"] } : Array.Empty<string>());
            BreakOutcome outcome = Break(cipher, text, defaults, keys);
            tested.Add((cipher, outcome.Choice));
        }
        string heading = $"JOB {job} IDENTIFY source={source} family={family}";
        string chosenCipher = "";
        string chosenKey = "";
        Candidate? winner = null;
        foreach (var entry in tested)
        {
            if (winner != null && winner.Score >= entry.Winner.Score)
                continue;
            chosenCipher = entry.Cipher;
            chosenKey = entry.Winner.Key;
            winner = entry.Winner;
        }
        if (winner != null)
        {
            if (chosenCipher == "affine")
            {
                string[] parts = chosenKey.Split(',');
                if (parts[0] == "1")
                {
                    chosenCipher = "caesar";
                    chosenKey = parts[1];
                }
            }
            string[] lines = OutputText(Body(source), chosenCipher, chosenKey, false);
            heading += $" cipher={chosenCipher} key={chosenKey} score={winner.Score} lines={lines.Length}";
            ResultLines.Add(heading);
            ResultLines.AddRange(lines);
        }
        else
            ResultLines.Add(heading);

        AnalysisLines.Add($"JOB {job} IDENTIFY source={source}");
        AnalysisLines.Add($"letters={text.Length} ioc={ioc} mono_avg={mean} distinct={distinct} shape={(shape ? "yes" : "no")}");
        AnalysisLines.Add("family=" + family);
        foreach (var trial in tested)
            AnalysisLines.Add($"try {trial.Cipher} key={trial.Winner.Key} score={trial.Winner.Score}");
        if (winner != null)
            AnalysisLines.Add("choice " + chosenCipher);
    }

    private static void CheckReferences(string[] parts, string command,
        Dictionary<string, string> options)
    {
        string source = command is "ENCRYPT" or "DECRYPT" or "BREAK"
            ? parts[command == "BREAK" ? 2 : 3] : parts[1];
        if (!Messages.ContainsKey(source))
            Fail("unknown message " + source);
        if (options.TryGetValue("KEYS", out string? keys) && !Messages.ContainsKey(keys))
            Fail("unknown message " + keys);
        if (command == "COMPARE" && !Messages.ContainsKey(parts[2]))
            Fail("unknown message " + parts[2]);
    }

    private static void Execute(int number, string line)
    {
        string[] parts = line.Split(' ');
        string command = parts[0];
        if (!Commands.Contains(command))
            Fail("unknown command");

        string? target = null;
        if (command is "ENCRYPT" or "DECRYPT" or "BREAK"
            && parts.Length >= 5 && parts[^2] == "AS")
        {
            target = parts[^1];
            parts = parts.Take(parts.Length - 2).ToArray();
            if (!ValidName(target))
                Fail("bad syntax");
        }
        bool syntax = command switch
        {
            "ENCRYPT" or "DECRYPT" => parts.Length == 4,
            "BREAK" => parts.Length >= 3,
            "ANALYZE" or "IDENTIFY" => parts.Length is 2 or 3,
            "COMPARE" => parts.Length == 3,
            _ => false
        };
        if (!syntax)
            Fail("bad syntax");

        string cipher = command is "ENCRYPT" or "DECRYPT" or "BREAK" ? parts[1] : "";
        if (cipher != "" && !Ciphers.Contains(cipher))
            Fail("unknown cipher " + cipher);

        string key = command is "ENCRYPT" or "DECRYPT" ? NormalizeKey(cipher, parts[2]) : "";
        IEnumerable<string> optionWords = command == "BREAK" ? parts.Skip(3) :
            command is "ANALYZE" or "IDENTIFY" ? parts.Skip(2) : Array.Empty<string>();
        Dictionary<string, string> options = ParseOptions(command, cipher, optionWords);
        CheckReferences(parts, command, options);
        if (target != null && Messages.ContainsKey(target))
            Fail("duplicate message " + target);

        switch (command)
        {
            case "ENCRYPT":
            case "DECRYPT":
                EncryptDecrypt(number, command, cipher, key, parts[3], target);
                break;
            case "BREAK":
                BreakJob(number, cipher, parts[2], target, options);
                break;
            case "ANALYZE":
                AnalyzeJob(number, parts[1], options);
                break;
            case "COMPARE":
                CompareJob(number, parts[1], parts[2]);
                break;
            case "IDENTIFY":
                IdentifyJob(number, parts[1], options);
                break;
        }
    }

    private static void RunJobs(string path)
    {
        int jobs = 0, ok = 0, errors = 0;
        foreach (string text in File.ReadAllLines(path, Encoding.ASCII))
        {
            if (text.Length == 0 || text[0] == '#')
                continue;
            jobs++;
            string command = text.Split(' ')[0];
            bool recognized = Totals.ContainsKey(command);
            try
            {
                Execute(jobs, text);
                ok++;
                if (recognized)
                    Totals[command][0]++;
            }
            catch (JobFault error)
            {
                errors++;
                if (recognized)
                    Totals[command][1]++;
                ResultLines.Add($"JOB {jobs} ERROR {error.Message}");
            }
        }
        foreach (string command in Commands)
            ResultLines.Add($"TOTAL {command} ok={Totals[command][0]} errors={Totals[command][1]}");
        ResultLines.Add($"SUMMARY jobs={jobs} ok={ok} errors={errors} messages={Messages.Count}");
    }

    private static void WriteFile(string filename, List<string> lines)
    {
        string text = lines.Count == 0 ? "" : string.Join("\n", lines) + "\n";
        File.WriteAllText(Path.Combine("output", filename), text, Encoding.ASCII);
    }

    private static void Main()
    {
        (Mono, Bi) = Scoring.Read(Path.Combine("input", "weights.txt"));
        ReadMessages(Path.Combine("input", "messages.txt"));
        RunJobs(Path.Combine("input", "jobs.txt"));
        Directory.CreateDirectory("output");
        WriteFile("results.txt", ResultLines);
        WriteFile("candidates.txt", CandidateLines);
        WriteFile("analysis.txt", AnalysisLines);
    }
}
