using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public static class CnfIo {
    public static bool Matches(this string value,
                               string pattern) => Regex.IsMatch(value, "\\A(?:" + pattern + ")\\z");
    public sealed record Formula(int variables, List<int[]> clauses);
    public sealed class Invalid : Exception {
        public Invalid(string reason) : base(reason) {
        }
    }
    public static bool Number(string value) {
        return value.Matches("0|[1-9][0-9]{0,5}");
    }
    public static Formula Read(string name) {
        List<string> lines = File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII).ToList();
        bool header = false;
        int variables = 0, declared = 0;
        List<int[]> clauses = new();
        List<int> clause = new();
        for (int i = 0; i < lines.Count; i++) {
            string line = lines[i];
            if (line.StartsWith("c") || line.Trim().Length == 0)
                continue;
            string[] tokens = line.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (tokens[0].Equals("p")) {
                if (header)
                    throw new Invalid("duplicate header at line " + (i + 1));
                if (tokens.Length != 4 || !tokens[1].Equals("cnf") || !Number(tokens[2]) ||
                    !Number(tokens[3]))
                    throw new Invalid("bad header at line " + (i + 1));
                header = true;
                variables = int.Parse(tokens[2]);
                declared = int.Parse(tokens[3]);
            } else {
                if (!header)
                    throw new Invalid("missing header");
                foreach (string token in tokens) {
                    if (!token.Matches("0|-?[1-9][0-9]{0,5}"))
                        throw new Invalid("bad token " + token + " at line " + (i + 1));
                    int literal = int.Parse(token);
                    if (Math.Abs(literal) > variables)
                        throw new Invalid("literal out of range " + token + " at line " + (i + 1));
                    if (literal == 0) {
                        clauses.Add(clause.ToArray());
                        clause = new();
                    } else
                        clause.Add(literal);
                }
            }
        }
        if (!header)
            throw new Invalid("missing header");
        if (clause.Count != 0)
            throw new Invalid("unterminated clause");
        if (clauses.Count != declared)
            throw new Invalid("clause count mismatch header=" + declared + " found=" + clauses.Count);
        return new Formula(variables, clauses);
    }
    public static List<string> ModelLines(bool[] model) {
        List<string> tokens = new();
        for (int x = 1; x < model.Length; x++)
            tokens.Add(Convert.ToString(model[x] ? x : -x));
        tokens.Add("0");
        List<string> lines = new();
        for (int i = 0; i < tokens.Count; i += 10)
            lines.Add("v " + string.Join(" ", tokens.GetRange(i, Math.Min(i + 10, tokens.Count) - (i))));
        return lines;
    }
}
