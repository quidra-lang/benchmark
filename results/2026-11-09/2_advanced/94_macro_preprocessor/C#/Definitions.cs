using System;
using System.Collections.Generic;
using System.Linq;
readonly record struct Position(string File, int Line) {
    public override string ToString() => $"{File}:{Line}";
}
sealed record Diagnostic(Position Position, string Kind, string Message);
sealed class PPError(string reason) : Exception(reason) {
    public string Reason {
        get;
    } = reason;
}
sealed class Macro(string name, List<string>? parameters, bool variadic, List<Token> replacement, Position position, bool main) {
    public string Name {
        get;
    } = name;
    public List<string>? Parameters {
        get;
    } = parameters;
    public bool Variadic {
        get;
    } = variadic;
    public List<Token> Replacement {
        get;
    } = replacement;
    public Position Position {
        get;
    } = position;
    public bool Main {
        get;
    } = main;
    public int Expanded {
        get;
        set;
    } public int Tested {
        get;
        set;
    }
    public string Signature => Parameters == null ? Name : Name + "(" + string.Join(", ", Parameters.Select((parameter, i) => Variadic && i == Parameters.Count - 1 ? "..." : parameter)) + ")";
    public string Definition => "#define " + Signature + (Replacement.Count == 0 ? "" : " " + Lexer.Render(Replacement));
    public bool Identical(Macro other) => (Parameters == null ? other.Parameters == null : other.Parameters != null && Parameters.SequenceEqual(other.Parameters)) && Variadic == other.Variadic && Replacement.Count == other.Replacement.Count && Replacement.Zip(other.Replacement).All(pair => pair.First.Text == pair.Second.Text && pair.First.Space == pair.Second.Space);
}
static class Definitions {
    public static bool Builtin(string name) => name is "__LINE__" or "__FILE__" or "__COUNTER__";
    public static string Name(List<Token> tokens, string directive) {
        if (tokens.Count == 0) throw new PPError($"no macro name given in #{directive} directive");
        Token token = tokens[0];
        if (token.Kind != "identifier") throw new PPError("macro names must be identifiers");
        if (token.Text == "defined") throw new PPError("\"defined\" cannot be used as a macro name");
        if (Builtin(token.Text)) throw new PPError($"cannot {(directive == "define" ? "redefine" : "undefine")} builtin macro \"{token.Text}\"");
        return token.Text;
    }
    public static Macro Parse(List<Token> tokens, Position position, bool main) {
        string name = Name(tokens, "define"), vaError = "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro";
        if (name == "__VA_ARGS__") throw new PPError(vaError);
        int i = 1;
        List<string>? parameters = null;
        bool variadic = false;
        if (tokens.Count > 1 && tokens[1].Text == "(" && !tokens[1].Space) {
            i = 2;
            List<string> names = new();
            if (i < tokens.Count && tokens[i].Text == ")") i++;
            else while (true) {
                if (i == tokens.Count) throw new PPError("missing ')' in macro parameter list");
                Token token = tokens[i];
                if (token.Text == "...") {
                    variadic = true;
                    names.Add("__VA_ARGS__");
                }
                else if (token.Kind == "identifier") {
                    if (token.Text == "__VA_ARGS__") throw new PPError(vaError);
                    if (names.Contains(token.Text)) throw new PPError($"duplicate macro parameter \"{token.Text}\"");
                    names.Add(token.Text);
                }
                else throw new PPError($"expected parameter name, found \"{token.Text}\"");
                i++;
                if (i == tokens.Count) throw new PPError("missing ')' in macro parameter list");
                if (tokens[i].Text == ")") {
                    i++;
                    break;
                } if (variadic) throw new PPError($"expected ')' after \"...\", found \"{tokens[i].Text}\"");
                if (tokens[i].Text != ",") throw new PPError($"expected ',' or ')', found \"{tokens[i].Text}\"");
                i++;
            }
            parameters = names;
        }
        List<Token> replacement = tokens.Skip(i).Select((token, k) => k == 0 ? token with {
            Space = false
        } : token).ToList();
        if (replacement.FirstOrDefault()?.Text == "##" || replacement.LastOrDefault()?.Text == "##") throw new PPError("'##' cannot appear at either end of a macro expansion");
        for (int k = 0; k < replacement.Count; k++) {
            Token token = replacement[k];
            if (token.Kind == "identifier" && token.Text == "__VA_ARGS__" && !variadic) throw new PPError(vaError);
            if (token.Text == "#" && parameters != null && (k + 1 == replacement.Count || replacement[k + 1].Kind != "identifier" || !parameters.Contains(replacement[k + 1].Text))) throw new PPError("'#' is not followed by a macro parameter");
        } return new(name, parameters, variadic, replacement, position, main);
    }
}
