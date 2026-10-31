using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
abstract record ReplacementItem {
    public sealed record Sequence(List<Token> Tokens) : ReplacementItem;
    public sealed record Paste(Token Token) : ReplacementItem;
}
sealed record Collected(List<List<Token>> Arguments, int Consumed, Token Closing);
sealed class Expander {
    public Dictionary<string, Macro> Table {
        get;
    } = new();
    public List<Diagnostic> Diagnostics {
        get;
    } = new();
    public Dictionary<string, int> Uses {
        get;
    } = new() {
        ["__COUNTER__"] = 0, ["__FILE__"] = 0, ["__LINE__"] = 0
    };
    int counter;
    public void Diagnostic(Position position, string kind, string message) => Diagnostics.Add(new(position, kind, message));
    void Error(Token token, string file, int offset, string message) => Diagnostic(new(file, token.Line + offset), "error", message);
    public List<Token> Expand(List<Token> tokens, string file, int offset) {
        List<Token> input = tokens.AsEnumerable().Reverse().ToList(), result = new();
        while (input.Count > 0) {
            Token token = input[^1];
            input.RemoveAt(input.Count - 1);
            if (token.Kind != "identifier" || token.Hide.Contains(token.Text)) {
                result.Add(token);
                continue;
            }
            if (Definitions.Builtin(token.Text)) {
                Uses[token.Text]++;
                string kind, text;
                switch (token.Text) {
                    case "__LINE__": kind = "number";
                    text = (token.Line + offset).ToString();
                    break;
                    case "__FILE__": kind = "string";
                    text = "\"" + file + "\"";
                    break;
                    default: kind = "number";
                    text = counter.ToString();
                    counter++;
                    break;
                } result.Add(new(kind, text, token.Line, token.Space));
                continue;
            }
            if (!Table.TryGetValue(token.Text, out Macro? definition)) {
                result.Add(token);
                continue;
            } HashSet<string> hide = new(token.Hide);
            List<List<Token>> arguments = new();
            if (definition.Parameters != null) {
                if (input.LastOrDefault()?.Text != "(") {
                    result.Add(token);
                    continue;
                } Collected? collected = Collect(definition, input, token, file, offset);
                if (collected == null) {
                    result.Add(token);
                    continue;
                } arguments = collected.Arguments;
                input.RemoveRange(input.Count - collected.Consumed, collected.Consumed);
                hide.IntersectWith(collected.Closing.Hide);
            }
            hide.Add(definition.Name);
            List<Token> replacement = Substitute(definition, arguments, token, hide, file, offset);
            definition.Expanded++;
            if (replacement.Count == 0 && token.Space && input.Count > 0) input[^1] = input[^1] with {
                Space = true
            };
            input.AddRange(replacement.AsEnumerable().Reverse());
        }
        return result;
    }
    Collected? Collect(Macro definition, List<Token> reversed, Token token, string file, int offset) {
        List<List<Token>> arguments = new() {
            new()
        };
        List<Token> separators = new();
        int depth = 0;
        (int Index, Token Token)? closing = null;
        List<Token> input = reversed.AsEnumerable().Reverse().ToList();
        for (int i = 1; i < input.Count; i++) {
            Token current = input[i];
            if (current.Text == ")" && depth == 0) {
                closing = (i, current);
                break;
            } if (current.Text == "," && depth == 0) {
                separators.Add(current);
                arguments.Add(new());
            } else {
                if (current.Text == "(") depth++;
                else if (current.Text == ")") depth--;
                arguments[^1].Add(current);
            }
        }
        if (closing == null) {
            Error(token, file, offset, $"unterminated argument list invoking macro \"{definition.Name}\"");
            return null;
        }
        int k = arguments.Count, n = definition.Parameters!.Count - (definition.Variadic ? 1 : 0);
        bool emptyZero = !definition.Variadic && n == 0 && k == 1 && arguments[0].Count == 0;
        string? message = !definition.Variadic && n == 0 && !emptyZero ? $"macro \"{definition.Name}\" passed {k} arguments, but takes just 0" : k < n ? $"macro \"{definition.Name}\" requires {n} arguments, but only {k} given" : k > n && !definition.Variadic ? $"macro \"{definition.Name}\" passed {k} arguments, but takes just {n}" : null;
        if (message != null) {
            Error(token, file, offset, message);
            return null;
        }
        if (definition.Variadic) {
            List<Token> variable = new();
            for (int i = n; i < k; i++) {
                if (i > n) variable.Add(separators[i - 1]);
                variable.AddRange(arguments[i]);
            } arguments = arguments.Take(n).ToList();
            arguments.Add(variable);
        } else if (emptyZero) arguments = new();
        return new(arguments, closing.Value.Index + 1, closing.Value.Token);
    }
    static Token Stringize(List<Token> tokens, Token template) {
        StringBuilder text = new();
        for (int i = 0; i < tokens.Count; i++) {
            Token token = tokens[i];
            if (i > 0 && token.Space) text.Append(' ');
            if (token.Kind is "string" or "character") {
                foreach (char c in token.Text) {
                    if (c is (char)92 or '"') text.Append((char)92);
                    text.Append(c);
                }
            } else text.Append(token.Text);
        } return new("string", "\"" + text + "\"", template.Line, template.Space);
    }
    List<Token> Paste(Token left, Token right, Token invocation, string file, int offset) {
        if (left.Kind == "placemarker") return new() {
            right with {
                Space = left.Space
            }
        };
        if (right.Kind == "placemarker") return new() {
            left
        };
        string text = left.Text + right.Text;
        string? kind = Lexer.Single(text);
        if (kind != null) return new() {
            new(kind, text, left.Line, left.Space, left.Hide.Intersect(right.Hide).ToHashSet())
        };
        Error(invocation, file, offset, $"pasting \"{left.Text}\" and \"{right.Text}\" does not give a valid preprocessing token");
        return new() {
            left, right with {
                Space = false
            }
        };
    }
    List<Token> Substitute(Macro definition, List<List<Token>> arguments, Token invocation, HashSet<string> hide, string file, int offset) {
        List<string> names = definition.Parameters ?? new();
        List<Token> replacement = definition.Replacement;
        Dictionary<int, List<Token>> expanded = new();
        List<ReplacementItem> items = new();
        int i = 0;
        while (i < replacement.Count) {
            Token token = replacement[i];
            if (token.Text == "#" && definition.Parameters != null) {
                int parameter = names.IndexOf(replacement[i + 1].Text);
                items.Add(new ReplacementItem.Sequence(new() {
                    Stringize(arguments[parameter], token)
                }));
                i += 2;
                continue;
            }
            if (token.Text == "##") items.Add(new ReplacementItem.Paste(token));
            else if (token.Kind == "identifier" && names.Contains(token.Text)) {
                int parameter = names.IndexOf(token.Text);
                bool raw = i > 0 && replacement[i - 1].Text == "##" || i + 1 < replacement.Count && replacement[i + 1].Text == "##";
                List<Token> sequence;
                if (raw) sequence = arguments[parameter];
                else {
                    if (!expanded.TryGetValue(parameter, out sequence!)) {
                        sequence = Expand(arguments[parameter], file, offset);
                        expanded[parameter] = sequence;
                    }
                } items.Add(new ReplacementItem.Sequence(sequence.Count == 0 ? new() {
                    new("placemarker", "", token.Line, token.Space)
                } : sequence.Select((value, k) => k == 0 ? value with {
                    Space = token.Space
                } : value).ToList()));
            }
            else items.Add(new ReplacementItem.Sequence(new() {
                token
            }));
            i++;
        }
        List<Token> output = new();
        i = 0;
        while (i < items.Count) {
            switch (items[i]) {
                case ReplacementItem.Sequence sequence: output.AddRange(sequence.Tokens);
                break;
                case ReplacementItem.Paste: {
                    Token left = output[^1];
                    output.RemoveAt(output.Count - 1);
                    List<Token> right = items[i + 1] switch {
                        ReplacementItem.Sequence rightSequence => rightSequence.Tokens, ReplacementItem.Paste paste => new() {
                            paste.Token
                        }, _ => throw new InvalidOperationException()
                    };
                    output.AddRange(Paste(left, right[0], invocation, file, offset));
                    output.AddRange(right.Skip(1));
                    i++;
                    break;
                }
            } i++;
        }
        List<Token> result = new();
        bool space = false;
        foreach (Token token in output) {
            if (token.Kind == "placemarker") {
                space |= token.Space;
                continue;
            } result.Add(token with {
                Line = invocation.Line, Space = token.Space || space, Hide = token.Hide.Union(hide).ToHashSet()
            });
            space = false;
        } if (result.Count > 0) result[0] = result[0] with {
            Space = invocation.Space
        };
        return result;
    }
}
