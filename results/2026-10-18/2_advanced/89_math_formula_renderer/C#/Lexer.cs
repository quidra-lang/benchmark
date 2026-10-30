global using System;
global using System.Collections.Generic;
global using System.Globalization;
global using System.IO;
global using System.Linq;
global using System.Text;
sealed record Token(string Kind, string Value, int Column);
sealed class FormulaError(int column, string reason) : Exception(reason)
{
    public int Column {
        get;
    } = column;
    public string Reason {
        get;
    } = reason;
}
static class Lexer
{
    public static readonly string[] Greek = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu", "xi", "pi", "rho", "sigma", "tau", "upsilon", "phi", "chi", "psi", "omega", "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega"];
    public static (string Text, int Type)? Symbol(string name)
    {
        if (Greek.Contains(name)) return (name, 0);
        return name switch
        {
            "cdot" => ("*", 2), "times" => ("x", 2), "pm" => ("+-", 2), "mp" => ("-+", 2),
            "leq" => ("<=", 3), "geq" => (">=", 3), "neq" => ("!=", 3), "approx" => ("~=", 3), "to" => ("->", 3),
            "infty" => ("oo", 0), "ldots" or "cdots" => ("...", 0), "quad" => ("  ", 0), "," => (" ", 0), "{" => ("{", 4), "}" => ("}", 5),
            "sin" or "cos" or "tan" or "log" or "ln" or "exp" or "det" or "lim" or "max" or "min" or "sum" or "prod" or "int" => (name, 1), _ => null
        };
    }
    public static bool Letter(char c) => c is >= 'A' and <= 'Z' or >= 'a' and <= 'z';
    public static bool CommandName(string text) => Symbol(text) is not null && text.Length > 0 && text.All(Letter);
    public static List<Token> Lex(string text)
    {
        List<Token> result = new();
        int i = 0;
        while (i < text.Length)
        {
            char c = text[i];
            int column = i + 1;
            string kind, value;
            if (c == ' ') {
                i++;
                continue;
            }
            else if (Letter(c))
            {
                int start = i++;
                while (i < text.Length && Letter(text[i])) i++;
                kind = "identifier";
                value = text[start..i];
            }
            else if (c is >= '0' and <= '9')
            {
                int start = i++;
                while (i < text.Length && text[i] is >= '0' and <= '9') i++;
                if (i + 1 < text.Length && text[i] == '.' && text[i + 1] is >= '0' and <= '9')
                {
                    i += 2;
                    while (i < text.Length && text[i] is >= '0' and <= '9') i++;
                }
                kind = "number";
                value = text[start..i];
            }
            else if ("+-*/=<>:()[],;.!|'".Contains(c)) {
                kind = "symbol";
                value = c.ToString();
                i++;
            }
            else if ("{}^_&".Contains(c)) {
                kind = c.ToString();
                value = kind;
                i++;
            }
            else if (c == '\\')
            {
                i++;
                if (i < text.Length && text[i] == '\\') {
                    i++;
                    kind = "newline";
                    value = "";
                }
                else if (i < text.Length && "{},".Contains(text[i])) {
                    kind = "command";
                    value = "\\" + text[i++];
                }
                else
                {
                    int start = i;
                    while (i < text.Length && Letter(text[i])) i++;
                    string name = text[start..i];
                    if (name.Length == 0) throw new FormulaError(column, "invalid command");
                    if (name is "text" or "begin" or "end" or "tag" or "label" or "eqref")
                    {
                        while (i < text.Length && text[i] == ' ') i++;
                        if (i == text.Length || text[i] != '{') throw new FormulaError(i + 1, "expected {");
                        int end = text.IndexOf('}', i + 1);
                        if (end < 0) throw new FormulaError(column, "unterminated argument");
                        value = text[(i + 1)..end];
                        i = end + 1;
                        kind = name;
                        if (name is "begin" or "end" && !new[] {
                            "matrix", "pmatrix", "bmatrix", "vmatrix", "cases"
                        }.Contains(value)) throw new FormulaError(column, $"unknown environment \"{value}\"");
                    }
                    else if (Symbol(name) is not null) {
                        kind = "command";
                        value = "\\" + name;
                    }
                    else if (name is "overline" or "hat" or "vec" or "dot" or "tilde" or "overbrace" or "underbrace") {
                        kind = "accent";
                        value = name;
                    }
                    else if (name is "frac" or "binom" or "overset" or "underset" or "sqrt" or "left" or "right") {
                        kind = name;
                        value = "";
                    }
                    else throw new FormulaError(column, "unknown command \\" + name);
                }
            }
            else throw new FormulaError(column, "invalid character " + c);
            result.Add(new Token(kind, value, column));
        }
        return result;
    }
}
