using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Text.RegularExpressions;
sealed class ModelError(int line, string reason) : Exception(reason) {
    public int Line {
        get;
    } = line;
    public string Reason {
        get;
    } = reason;
}
sealed record Term(string Name, F Coefficient);
sealed record Constraint(int Line, string Name, List<Term> Terms, string Comparison, F Rhs);
sealed record BoundLine(int Line, string Name, string Kind, F? Lower, F? Upper);
sealed record Declaration(int Line, List<string> Names);
sealed class Parsed(string name) {
    public string Name {
        get;
    } = name;
    public bool Maximize {
        get;
        set;
    } public List<Term> Objective {
        get;
        set;
    } = new();
    public List<Constraint> Constraints {
        get;
    } = new();
    public List<BoundLine> Bounds {
        get;
    } = new();
    public List<Declaration> Integers {
        get;
    } = new();
    public List<Declaration> Binaries {
        get;
    } = new();
    public ModelError? Error {
        get;
        set;
    }
}
sealed record Params(int Level, int Limit, Dictionary<string, int> Levels, Dictionary<string, int> Limits);
static class LPParser {
    static bool Name(string word) => Regex.IsMatch(word, @"\A[a-z][a-z0-9_]*\z") && word is not ("bounds" or "integer" or "binary" or "free" or "inf");
    static List<Term>? Expression(List<string> words) {
        List<Term> terms = new();
        int i = 0;
        F sign = 1;
        if (words.FirstOrDefault() == "-") {
            i++;
            sign = -1;
        }
        while (i < words.Count) {
            F? coefficient = F.Read(words[i]);
            string variable;
            F value;
            if (coefficient.HasValue) {
                if (i + 1 >= words.Count || !Name(words[i + 1])) return null;
                variable = words[i + 1];
                value = coefficient.Value;
                i += 2;
            }
            else if (Name(words[i])) {
                variable = words[i++];
                value = 1;
            } else return null;
            terms.Add(new(variable, sign * value));
            if (i == words.Count) return terms;
            if (words[i] is not ("+" or "-")) return null;
            sign = words[i++] == "+" ? 1 : -1;
        }
        return null;
    }
    static (string Name, List<Term> Terms)? Named(List<string> words) {
        if (words.Count < 2 || !words[0].EndsWith(':')) return null;
        string name = words[0][..^1];
        if (!Name(name)) return null;
        List<Term>? terms = Expression(words.Skip(1).ToList());
        return terms == null ? null : (name, terms);
    }
    static Constraint? ConstraintLine(List<string> words, int line) {
        if (words.Count < 4 || words[^2] is not ("<=" or ">=" or "=")) return null;
        F? rhs = F.Read(words[^1], true);
        var named = Named(words.SkipLast(2).ToList());
        return !rhs.HasValue || named == null ? null : new(line, named.Value.Name, named.Value.Terms, words[^2], rhs.Value);
    }
    static BoundLine? Bound(List<string> words, int line) {
        if (words.Count == 2 && Name(words[0]) && words[1] == "free") return new(line, words[0], "both", null, null);
        if (words.Count == 3 && Name(words[0])) {
            F? value = F.Read(words[2], true);
            if (words[1] == ">=" && (value.HasValue || words[2] == "-inf")) return new(line, words[0], "lower", value, null);
            if (words[1] == "<=" && (value.HasValue || words[2] == "inf")) return new(line, words[0], "upper", null, value);
            if (words[1] == "=" && value.HasValue) return new(line, words[0], "both", value, value);
        }
        if (words.Count == 5 && words[1] == "<=" && words[3] == "<=" && Name(words[2])) {
            F? lower = F.Read(words[0], true), upper = F.Read(words[4], true);
            if ((lower.HasValue || words[0] == "-inf") && (upper.HasValue || words[4] == "inf")) return new(line, words[2], "both", lower, upper);
        } return null;
    }
    static Parsed Parse(string name, List<(int Line, string Text)> body, int end) {
        Parsed result = new(name);
        string state = "A";
        foreach (var (line, text) in body) {
            List<string> words = text.Split(' ').ToList();
            bool accepted = false;
            switch (state) {
                case "A": if (text is "maximize" or "minimize") {
                    result.Maximize = text == "maximize";
                    state = "B";
                    accepted = true;
                } break;
                case "B": {
                    var value = Named(words);
                    if (value.HasValue) {
                        result.Objective = value.Value.Terms;
                        state = "C";
                        accepted = true;
                    } break;
                }
                case "C": if (text == "subject to") {
                    state = "D";
                    accepted = true;
                } break;
                case "D": case "E": if (state == "E" && text is "bounds" or "integer" or "binary") {
                    state = text switch {
                        "bounds" => "F", "integer" => "G", _ => "H"
                    };
                    accepted = true;
                } else {
                    Constraint? value = ConstraintLine(words, line);
                    if (value != null) {
                        result.Constraints.Add(value);
                        state = "E";
                        accepted = true;
                    }
                } break;
                case "F": if (text is "integer" or "binary") {
                    state = text == "integer" ? "G" : "H";
                    accepted = true;
                } else {
                    BoundLine? value = Bound(words, line);
                    if (value != null) {
                        result.Bounds.Add(value);
                        accepted = true;
                    }
                } break;
                case "G": case "H": if (state == "G" && text == "binary") {
                    state = "H";
                    accepted = true;
                } else if (words.All(Name)) {
                    (state == "G" ? result.Integers : result.Binaries).Add(new(line, words));
                    accepted = true;
                } break;
            }
            if (!accepted) {
                result.Error = new(line, "syntax error");
                return result;
            }
        }
        if (state is "A" or "B" or "C" or "D") result.Error = new(end, "syntax error");
        return result;
    }
    public static List<Parsed> Read() {
        List<Parsed> result = new();
        string? name = null;
        List<(int, string)> body = new();
        string[] lines = File.ReadAllLines("input/models.lp");
        for (int i = 0; i < lines.Length; i++) {
            string text = lines[i];
            if (text.Length == 0 || text.StartsWith('#')) continue;
            if (name == null) {
                name = text.Split(' ')[1];
                body.Clear();
            } else if (text == "end") {
                result.Add(Parse(name, body, i + 1));
                name = null;
            } else body.Add((i + 1, text));
        } return result;
    }
    public static Params Settings() {
        string[] lines = File.ReadAllLines("input/params.txt");
        Dictionary<string, int> levels = new(), limits = new();
        foreach (string text in lines.Skip(2)) if (text.Length != 0) {
            string[] words = text.Split(' ');
            (words[0] == "log" ? levels : limits)[words[1]] = int.Parse(words[2]);
        } return new(int.Parse(lines[0].Split(' ')[1]), int.Parse(lines[1].Split(' ')[1]), levels, limits);
    }
}
